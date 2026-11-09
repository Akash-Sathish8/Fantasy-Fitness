import { assertEquals } from "jsr:@std/assert@1.0.13";
import { normalizeUsda, type UsdaFood } from "./usda.ts";

const fixture = (name: string): UsdaFood[] =>
  JSON.parse(
    Deno.readTextFileSync(new URL(`./testdata/${name}`, import.meta.url)),
  ).foods;

const chicken = fixture("usda_chicken.json");
const bananas = fixture("usda_banana.json");
const byId = (foods: UsdaFood[], id: number) =>
  structuredClone(foods.find((food) => food.fdcId === id)!);
const without = (food: UsdaFood, ...numbers: string[]): UsdaFood => ({
  ...food,
  foodNutrients: food.foodNutrients!.filter((n) =>
    !numbers.includes(n.nutrientNumber!)
  ),
});

Deno.test("reads per-100 g values and portions from a Survey food", () => {
  const food = normalizeUsda(byId(chicken, 2705968))!;
  assertEquals(food.fdcId, 2705968);
  assertEquals(
    food.name,
    "Chicken breast, grilled without sauce, skin not eaten",
  );
  assertEquals(food.dataType, "Survey (FNDDS)");
  assertEquals([food.kcal, food.protein, food.carbs, food.fat], [
    176,
    29.62,
    0,
    5.45,
  ]);
  assertEquals(food.portions[0], { label: "1 medium breast", grams: 120 });
});

Deno.test("drops 'Quantity not specified' and keeps at most 8 portions", () => {
  for (const raw of chicken) {
    const food = normalizeUsda(raw)!;
    assertEquals(
      food.portions.some((p) => /quantity not specified/i.test(p.label)),
      false,
    );
    assertEquals(food.portions.length <= 8, true);
  }
});

Deno.test("SR Legacy foods have no portions in search results", () => {
  const food = normalizeUsda(byId(bananas, 173944))!;
  assertEquals([food.name, food.kcal, food.protein, food.carbs, food.fat], [
    "Bananas, raw",
    89,
    1.09,
    22.8,
    0.33,
  ]);
  assertEquals(food.portions, []);
});

Deno.test("energy falls back to kJ, then Atwater kcal, then 4/4/9", () => {
  const raw = byId(bananas, 173944);
  assertEquals(normalizeUsda(without(raw, "208"))!.kcal, 88.7); // 371 kJ / 4.184
  const atwater = without(raw, "208", "268");
  atwater.foodNutrients!.push({
    nutrientNumber: "958",
    unitName: "KCAL",
    value: 92,
  });
  assertEquals(normalizeUsda(atwater)!.kcal, 92);
  assertEquals(normalizeUsda(without(raw, "208", "268"))!.kcal, 98.5); // 4×1.09 + 4×22.8 + 9×0.33
});

Deno.test("returns null without any energy or macro data", () => {
  assertEquals(
    normalizeUsda({ fdcId: 1, description: "Water", foodNutrients: [] }),
    null,
  );
  assertEquals(
    normalizeUsda({
      fdcId: 1,
      description: " ",
      foodNutrients: [{ nutrientNumber: "208", value: 1 }],
    }),
    null,
  );
});

Deno.test("clamps values to the foods table's limits", () => {
  const food = normalizeUsda({
    fdcId: 7,
    description: "Odd data",
    foodNutrients: [
      { nutrientNumber: "208", value: 1200 },
      { nutrientNumber: "203", value: 140 },
      { nutrientNumber: "204", value: -3 },
      { nutrientNumber: "205", value: 12.345 },
    ],
    foodMeasures: [
      { disseminationText: "1 cup", gramWeight: 240 },
      { disseminationText: "1 Cup", gramWeight: 240 },
      { disseminationText: "bad", gramWeight: 0 },
    ],
  })!;
  assertEquals([food.kcal, food.protein, food.carbs, food.fat], [
    900,
    100,
    12.35,
    0,
  ]);
  assertEquals(food.portions, [{ label: "1 cup", grams: 240 }]);
});
