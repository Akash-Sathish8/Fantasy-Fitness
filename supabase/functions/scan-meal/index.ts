// scan-meal: lists the foods in a meal photo so the player can review and log them.
//
// POST raw JPEG bytes (Content-Type: image/jpeg, at most 3 MB; the app sends ≤1280 px).
// → {"is_food": true, "meal_name": "...", "scans_left": 17,
//    "items": [{"label": "Grilled chicken", "grams": 150, "food": {...food-search shape}}]}
//
// Each scan costs an API call, so begin_meal_scan enforces a per-player daily cap and a
// game-wide one before the photo goes anywhere. The photo is never stored or logged.
//
// Settings: ANTHROPIC_API_KEY, USDA_API_KEY, SCAN_MODEL (default claude-haiku-5-5),
// SCAN_DAILY_CAP (20 per player per 24 h), SCAN_GLOBAL_DAILY_CAP (1,000 per 24 h).

import Anthropic from "npm:@anthropic-ai/sdk@1.3.0";
import type { SupabaseClient } from "npm:@supabase/supabase-js@2.118.0";
import { admin, requireUser } from "../_shared/auth.ts";
import {
  type EstimateFood,
  type FoodJson,
  saveEstimateFoods,
  saveUsdaFoods,
} from "../_shared/foods.ts";
import {
  errorResponse,
  HttpError,
  intEnv,
  json,
  readBody,
} from "../_shared/http.ts";
import { MATCH_CANDIDATES, pickCandidate } from "../_shared/match.ts";
import {
  analyzePhoto,
  DEFAULT_SCAN_MODEL,
  mealName,
  sanitizeItems,
  type ScannedItem,
} from "../_shared/scan.ts";
import {
  type NormalizedFood,
  normalizeUsda,
  searchUsda,
} from "../_shared/usda.ts";

const MAX_PHOTO_BYTES = 3_000_000;

// A scan usually takes 2–5 s. One attempt of at most 25 s, plus USDA's 5 s, stays inside
// the 45 s the app waits. No automatic retries: the SDK would wait as long as the API's
// retry-after asks, past what the app waits; the app offers Try again instead.
const anthropic = new Anthropic({
  apiKey: Deno.env.get("ANTHROPIC_API_KEY"),
  maxRetries: 0,
  timeout: 25_000,
});

// "failed" counts toward no cap (see begin_meal_scan); every other status does.
type ScanStatus = "ok" | "not_food" | "refused" | "rejected" | "failed";

interface ScanRecord {
  status: ScanStatus;
  model?: string;
  input_tokens?: number;
  output_tokens?: number;
  item_count?: number;
}

Deno.serve(async (req) => {
  const startedAt = Date.now();
  try {
    if (req.method !== "POST") {
      throw new HttpError(405, "method_not_allowed", "Use POST.");
    }
    const userId = await requireUser(req);

    const photo = await readBody(
      req,
      MAX_PHOTO_BYTES,
      () =>
        new HttpError(
          413,
          "image_too_large",
          "That photo is too large. Try taking it again.",
        ),
    );
    if (
      !(photo.length > 3 && photo[0] === 0xff && photo[1] === 0xd8 &&
        photo[2] === 0xff)
    ) {
      throw new HttpError(
        415,
        "not_jpeg",
        "That photo couldn't be read. Try another one.",
      );
    }

    const db = admin();
    const userCap = intEnv("SCAN_DAILY_CAP", 20);
    const { data: gate, error: gateError } = await db.rpc("begin_meal_scan", {
      p_user: userId,
      p_user_cap: userCap,
      p_global_cap: intEnv("SCAN_GLOBAL_DAILY_CAP", 1000),
    });
    if (gateError) {
      throw new Error(`begin_meal_scan failed: ${gateError.message}`);
    }
    if (!gate.allowed) {
      throw gate.reason === "player"
        ? new HttpError(
          429,
          "scan_limit",
          `You've used today's ${userCap} plate scans. Search for foods instead; scans come back over the next day.`,
        )
        : new HttpError(
          503,
          "scan_resting",
          "Plate scans are resting for today. Search for foods instead.",
        );
    }
    const scanId = gate.scan_id as string;
    const scansLeft = Math.max(0, userCap - (gate.used as number));
    const finish = (record: ScanRecord) =>
      recordScan(db, scanId, { ...record, latency_ms: Date.now() - startedAt });

    const model = Deno.env.get("SCAN_MODEL") || DEFAULT_SCAN_MODEL;
    let analysis;
    try {
      analysis = await analyzePhoto(anthropic, photo, model);
    } catch (error) {
      const failure = scanFailure(error);
      await finish({ status: failure.status, model });
      throw failure.error;
    }
    const usage = {
      model: analysis.model,
      input_tokens: analysis.inputTokens,
      output_tokens: analysis.outputTokens,
    };

    if (analysis.stopReason === "refusal") {
      await finish({ status: "refused", ...usage });
      throw new HttpError(
        422,
        "scan_refused",
        "That photo couldn't be read as a meal. Try another, or search for foods.",
      );
    }
    if (!analysis.result) {
      await finish({ status: "failed", ...usage });
      throw new HttpError(
        502,
        "scan_failed",
        "Couldn't read that plate. Try again, or search for foods.",
      );
    }

    const items = analysis.result.is_food ? sanitizeItems(analysis.result) : [];
    if (items.length === 0) {
      await finish({ status: "not_food", ...usage, item_count: 0 });
      return json({
        is_food: false,
        meal_name: "",
        scans_left: scansLeft,
        items: [],
      });
    }

    let foods;
    try {
      foods = await resolveFoods(db, userId, items);
    } catch (error) {
      await finish({ status: "failed", ...usage, item_count: items.length });
      throw error;
    }
    await finish({ status: "ok", ...usage, item_count: items.length });
    return json({
      is_food: true,
      meal_name: mealName(analysis.result, items),
      scans_left: scansLeft,
      items: items.map((item, index) => ({
        label: item.label,
        grams: item.grams,
        food: foods[index],
      })),
    });
  } catch (error) {
    return errorResponse(error);
  }
});

/**
 * One food per item: the closest USDA match when there is one, otherwise the model's
 * estimate saved for this player. A failed USDA search just means using the estimate.
 */
async function resolveFoods(
  db: SupabaseClient,
  userId: string,
  items: ScannedItem[],
): Promise<FoodJson[]> {
  const searches = await Promise.allSettled(
    items.map((item) => searchUsda(item.query, MATCH_CANDIDATES)),
  );
  const matches: (NormalizedFood | null)[] = searches.map((search, index) => {
    if (search.status === "rejected") return null;
    const candidates = search.value.map(normalizeUsda).filter((food) =>
      food !== null
    );
    return pickCandidate(items[index].estimate, candidates);
  });

  const matched = matches.filter((match) => match !== null);
  const usda = await saveUsdaFoods(db, matched);
  const usdaByFdcId = new Map(
    matched.map((match, index) => [match.fdcId, usda[index]]),
  );

  const unmatched = items.flatMap((_, index) => matches[index] ? [] : [index]);
  const estimates = await saveEstimateFoods(
    db,
    userId,
    unmatched.map((index): EstimateFood => ({
      name: items[index].label,
      ...items[index].estimate,
    })),
  );
  const estimateByIndex = new Map(
    unmatched.map((itemIndex, i) => [itemIndex, estimates[i]]),
  );

  return items.map((_, index) => {
    const match = matches[index];
    return match ? usdaByFdcId.get(match.fdcId)! : estimateByIndex.get(index)!;
  });
}

async function recordScan(
  db: SupabaseClient,
  scanId: string,
  record: ScanRecord & { latency_ms: number },
) {
  const { error } = await db.from("meal_scans").update(record).eq("id", scanId);
  if (error) console.error(`Recording scan ${scanId} failed: ${error.message}`);
}

/**
 * What a failed Claude call means for the player. Busy, down or unreachable: "failed",
 * which costs no scan, and the app offers Try again. The API turning the photo down
 * (400, e.g. bytes that only start like a JPEG): "rejected", which counts, so junk
 * uploads can't spend the game-wide budget.
 */
function scanFailure(
  error: unknown,
): { status: "failed" | "rejected"; error: HttpError } {
  if (
    error instanceof Anthropic.RateLimitError ||
    error instanceof Anthropic.InternalServerError ||
    error instanceof Anthropic.APIConnectionError
  ) {
    return {
      status: "failed",
      error: new HttpError(
        503,
        "scan_busy",
        "The plate reader is busy. Try again in a moment, or search for foods.",
      ),
    };
  }
  if (error instanceof Anthropic.BadRequestError) {
    console.error(`Claude API error ${error.status}: ${error.message}`);
    return {
      status: "rejected",
      error: new HttpError(
        422,
        "photo_rejected",
        "That photo couldn't be read. Try another one.",
      ),
    };
  }
  if (error instanceof Anthropic.APIError) {
    console.error(`Claude API error ${error.status}: ${error.message}`);
  } else {
    console.error(
      error instanceof Error
        ? `${error.name}: ${error.message}`
        : "Unknown scan error",
    );
  }
  return {
    status: "failed",
    error: new HttpError(
      502,
      "scan_failed",
      "Couldn't read that plate. Try again, or search for foods.",
    ),
  };
}
