// food-search: looks up foods on USDA FoodData Central for the Tavern.
//
// POST {"query": "chicken breast", "limit": 15}
// → {"foods": [{"id", "source": "usda", "name", "detail", "per_100g": {...}, "portions": [...]}]}
//
// Every result is saved to the foods table, so the id can go straight into a recipe or
// a logged plate; the database computes macros from that row, not from the app.

import { admin, requireUser } from "../_shared/auth.ts";
import { saveUsdaFoods } from "../_shared/foods.ts";
import { errorResponse, HttpError, json } from "../_shared/http.ts";
import { normalizeUsda, searchUsda } from "../_shared/usda.ts";

Deno.serve(async (req) => {
  try {
    if (req.method !== "POST") {
      throw new HttpError(405, "method_not_allowed", "Use POST.");
    }
    await requireUser(req);

    const body = await req.json().catch(() => ({})) as {
      query?: unknown;
      limit?: unknown;
    };
    const query = typeof body.query === "string" ? body.query.trim() : "";
    if (query.length < 2 || query.length > 80) {
      throw new HttpError(
        400,
        "bad_query",
        "Type between 2 and 80 letters to search.",
      );
    }
    const limit = typeof body.limit === "number" && Number.isInteger(body.limit)
      ? Math.min(Math.max(body.limit, 1), 25)
      : 15;

    const found = (await searchUsda(query, limit))
      .map(normalizeUsda)
      .filter((food) => food !== null);
    return json({ foods: await saveUsdaFoods(admin(), found) });
  } catch (error) {
    return errorResponse(error);
  }
});
