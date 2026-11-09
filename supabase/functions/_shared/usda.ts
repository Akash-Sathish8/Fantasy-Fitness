// USDA FoodData Central search, and turning its results into the per-100 g values the
// foods table stores. API guide: https://fdc.nal.usda.gov/api-guide
//
// Only generic foods are searched: Foundation and SR Legacy (ingredients) and Survey
// (FNDDS) (foods as eaten, which also carry household portions like "1 medium breast").
// Branded foods are left out; their names are noisy and they're better found by barcode.

import { HttpError } from "./http.ts";

const SEARCH_URL = "https://api.nal.usda.gov/fdc/v1/foods/search";
const DATA_TYPES = ["Foundation", "SR Legacy", "Survey (FNDDS)"];

interface UsdaNutrient {
  nutrientNumber?: string;
  unitName?: string;
  value?: number;
}

interface UsdaMeasure {
  disseminationText?: string;
  gramWeight?: number;
}

export interface UsdaFood {
  fdcId: number;
  description: string;
  dataType?: string;
  foodNutrients?: UsdaNutrient[];
  foodMeasures?: UsdaMeasure[];
}

export interface Portion {
  label: string;
  grams: number;
}

/** Per 100 g, rounded the way the foods table stores it. */
export interface Per100g {
  kcal: number;
  protein: number;
  carbs: number;
  fat: number;
}

export interface NormalizedFood extends Per100g {
  fdcId: number;
  name: string;
  dataType: string;
  portions: Portion[];
}

let warnedDemoKey = false;

export async function searchUsda(
  query: string,
  pageSize: number,
): Promise<UsdaFood[]> {
  let key = Deno.env.get("USDA_API_KEY");
  if (!key) {
    if (!warnedDemoKey) {
      console.warn(
        "USDA_API_KEY is not set; using DEMO_KEY, which allows very few requests",
      );
    }
    warnedDemoKey = true;
    key = "DEMO_KEY";
  }

  let response: Response;
  try {
    // The key goes in the query string, so never log this URL or a fetch error message.
    response = await fetch(`${SEARCH_URL}?api_key=${encodeURIComponent(key)}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ query, dataType: DATA_TYPES, pageSize }),
      signal: AbortSignal.timeout(5000),
    });
  } catch {
    throw new HttpError(
      503,
      "usda_unavailable",
      "The food database didn't answer. Try again.",
    );
  }
  if (response.status === 429) {
    throw new HttpError(
      503,
      "usda_busy",
      "The food database is busy. Try again in a minute.",
    );
  }
  if (!response.ok) {
    await response.body?.cancel();
    throw new HttpError(
      502,
      "usda_unavailable",
      "The food database had a problem. Try again.",
    );
  }
  const body = await response.json() as { foods?: UsdaFood[] };
  return Array.isArray(body.foods) ? body.foods : [];
}

/**
 * Per-100 g nutrition from a search result, or null when USDA has no energy or macro
 * data for it. Energy falls back from kcal (208) to the Atwater kcal values (958, 957),
 * then kJ (268), then 4/4/9 kcal per gram of protein/carbs/fat.
 */
export function normalizeUsda(raw: UsdaFood): NormalizedFood | null {
  const value = (number: string) => {
    const hit = raw.foodNutrients?.find((n) =>
      n.nutrientNumber === number && typeof n.value === "number"
    );
    return hit?.value;
  };

  const protein = value("203");
  const fat = value("204");
  const carbs = value("205") ?? value("205.2");
  let kcal = value("208") ?? value("958") ?? value("957");
  if (kcal === undefined) {
    const kilojoules = value("268");
    if (kilojoules !== undefined) kcal = kilojoules / 4.184;
  }
  if (
    kcal === undefined &&
    (protein !== undefined || carbs !== undefined || fat !== undefined)
  ) {
    kcal = 4 * (protein ?? 0) + 4 * (carbs ?? 0) + 9 * (fat ?? 0);
  }
  const name = raw.description?.trim().slice(0, 200);
  if (kcal === undefined || !name || !Number.isInteger(raw.fdcId)) return null;

  return {
    fdcId: raw.fdcId,
    name,
    dataType: raw.dataType ?? "",
    ...clampPer100g({
      kcal,
      protein: protein ?? 0,
      carbs: carbs ?? 0,
      fat: fat ?? 0,
    }),
    portions: portionsFrom(raw.foodMeasures ?? []),
  };
}

/** Keeps values inside the foods table's checks: kcal to 0.1, grams to 0.01. */
export function clampPer100g(values: Per100g): Per100g {
  const clamp = (n: number, max: number) =>
    Math.min(Math.max(Number.isFinite(n) ? n : 0, 0), max);
  return {
    kcal: round(clamp(values.kcal, 900), 1),
    protein: round(clamp(values.protein, 100), 2),
    carbs: round(clamp(values.carbs, 100), 2),
    fat: round(clamp(values.fat, 100), 2),
  };
}

function portionsFrom(measures: UsdaMeasure[]): Portion[] {
  const seen = new Set<string>();
  const portions: Portion[] = [];
  for (const measure of measures) {
    const label = measure.disseminationText?.trim().slice(0, 60);
    const grams = measure.gramWeight;
    if (!label || typeof grams !== "number" || !(grams > 0) || grams > 5000) {
      continue;
    }
    if (/quantity not specified/i.test(label)) continue;
    const key = label.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    portions.push({ label, grams: round(grams, 1) });
    if (portions.length === 8) break;
  }
  return portions;
}

function round(value: number, places: number): number {
  const factor = 10 ** places;
  return Math.round(value * factor) / factor;
}
