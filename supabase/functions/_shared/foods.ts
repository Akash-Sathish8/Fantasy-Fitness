// Saving foods with the service role, and the shape the app receives.
//
// The database computes meal and recipe macros from these rows, so only the functions
// write them: USDA rows are shared by everyone, and an estimate from a photo scan
// belongs to the player who scanned it.

import type { SupabaseClient } from "npm:@supabase/supabase-js@2.118.0";
import type { NormalizedFood, Per100g, Portion } from "./usda.ts";

/** A food as the app decodes it (`FoodRow` in Services/Rows.swift). */
export interface FoodJson {
  id: string;
  source: "usda" | "estimate";
  name: string;
  detail: string;
  per_100g: Per100g;
  portions: Portion[];
}

export interface EstimateFood extends Per100g {
  name: string;
}

/** Upserts on fdc_id and returns one food per input, in the order given, with row ids. */
export async function saveUsdaFoods(
  db: SupabaseClient,
  foods: NormalizedFood[],
): Promise<FoodJson[]> {
  if (foods.length === 0) return [];
  const unique = [...new Map(foods.map((food) => [food.fdcId, food])).values()];
  const { data, error } = await db
    .from("foods")
    .upsert(
      unique.map((food) => ({
        source: "usda",
        fdc_id: food.fdcId,
        data_type: food.dataType,
        name: food.name,
        kcal_100g: food.kcal,
        protein_100g: food.protein,
        carbs_100g: food.carbs,
        fat_100g: food.fat,
        portions: food.portions,
      })),
      { onConflict: "fdc_id" },
    )
    .select("id, fdc_id");
  if (error) throw new Error(`Saving USDA foods failed: ${error.message}`);

  const ids = new Map(
    (data ?? []).map((row) => [row.fdc_id as number, row.id as string]),
  );
  return foods.map((food) => {
    const id = ids.get(food.fdcId);
    if (!id) {
      throw new Error(`Saved USDA food ${food.fdcId} came back without an id`);
    }
    return usdaJson(id, food);
  });
}

/** Inserts one player's photo estimates and returns them in the order given. */
export async function saveEstimateFoods(
  db: SupabaseClient,
  userId: string,
  estimates: EstimateFood[],
): Promise<FoodJson[]> {
  if (estimates.length === 0) return [];
  const rows = estimates.map((estimate) => ({
    id: crypto.randomUUID(),
    source: "estimate",
    name: estimate.name,
    kcal_100g: estimate.kcal,
    protein_100g: estimate.protein,
    carbs_100g: estimate.carbs,
    fat_100g: estimate.fat,
    created_by: userId,
  }));
  const { error } = await db.from("foods").insert(rows);
  if (error) throw new Error(`Saving estimated foods failed: ${error.message}`);
  return rows.map((row, index) => estimateJson(row.id, estimates[index]));
}

export function usdaJson(id: string, food: NormalizedFood): FoodJson {
  return {
    id,
    source: "usda",
    name: food.name,
    detail: food.dataType === "Survey (FNDDS)"
      ? "USDA, as eaten"
      : "USDA, ingredient",
    per_100g: {
      kcal: food.kcal,
      protein: food.protein,
      carbs: food.carbs,
      fat: food.fat,
    },
    portions: food.portions,
  };
}

export function estimateJson(id: string, food: EstimateFood): FoodJson {
  return {
    id,
    source: "estimate",
    name: food.name,
    detail: "Estimated from your photo",
    per_100g: {
      kcal: food.kcal,
      protein: food.protein,
      carbs: food.carbs,
      fat: food.fat,
    },
    portions: [],
  };
}
