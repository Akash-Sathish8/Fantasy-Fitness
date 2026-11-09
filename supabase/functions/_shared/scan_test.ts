import { assertAlmostEquals, assertEquals } from "jsr:@std/assert@1.0.13";
import {
  mealName,
  parseScan,
  roundGrams,
  sanitizeItems,
  type ScanResult,
} from "./scan.ts";

type Item = ScanResult["items"][number];

const item = (overrides: Partial<Item> = {}): Item => ({
  name: "Grilled chicken",
  usda_query: "chicken breast grilled",
  grams: 150,
  kcal_per_100g: 165,
  protein_per_100g: 31,
  carbs_per_100g: 0,
  fat_per_100g: 3.6,
  ...overrides,
});

const scan = (items: Item[], meal_name = "Chicken plate"): ScanResult => ({
  is_food: true,
  meal_name,
  items,
});

Deno.test("keeps good items as they are", () => {
  const [chicken] = sanitizeItems(scan([item()]));
  assertEquals(chicken, {
    label: "Grilled chicken",
    query: "chicken breast grilled",
    grams: 150,
    estimate: { kcal: 165, protein: 31, carbs: 0, fat: 3.6 },
  });
});

Deno.test("drops nameless and weightless items and keeps at most 12", () => {
  assertEquals(
    sanitizeItems(
      scan([
        item({ name: "  " }),
        item({ grams: 0 }),
        item({ grams: Number.NaN }),
      ]),
    ),
    [],
  );
  assertEquals(
    sanitizeItems(scan(Array.from({ length: 15 }, () => item()))).length,
    12,
  );
});

Deno.test("rounds grams to whole grams under 10 g, then to 5 g, within 1 to 2,000", () => {
  assertEquals([
    roundGrams(7.4),
    roundGrams(0.2),
    roundGrams(152),
    roundGrams(158),
    roundGrams(3000),
  ], [7, 1, 150, 160, 2000]);
});

Deno.test("raises calories that are far below what the macros add up to", () => {
  const [fixed] = sanitizeItems(
    scan([item({ kcal_per_100g: 50, protein_per_100g: 30, fat_per_100g: 10 })]),
  );
  assertEquals(fixed.estimate.kcal, 210); // 4×30 + 9×10
});

Deno.test("leaves energy above the macros alone (alcohol)", () => {
  const [wine] = sanitizeItems(scan([item({
    name: "Red wine",
    kcal_per_100g: 83,
    protein_per_100g: 0.07,
    carbs_per_100g: 2.7,
    fat_per_100g: 0,
  })]));
  assertEquals(wine.estimate.kcal, 83);
});

Deno.test("scales macros down when they add up to more than 100 g per 100 g", () => {
  const [odd] = sanitizeItems(
    scan([
      item({
        kcal_per_100g: 800,
        protein_per_100g: 80,
        carbs_per_100g: 50,
        fat_per_100g: 20,
      }),
    ]),
  );
  assertAlmostEquals(
    odd.estimate.protein + odd.estimate.carbs + odd.estimate.fat,
    100,
    0.02,
  );
  assertEquals(odd.estimate.protein, 53.33);
});

Deno.test("clamps negative and huge values", () => {
  const [odd] = sanitizeItems(
    scan([
      item({
        kcal_per_100g: 5000,
        protein_per_100g: -4,
        carbs_per_100g: 0,
        fat_per_100g: 0,
      }),
    ]),
  );
  assertEquals(odd.estimate, { kcal: 900, protein: 0, carbs: 0, fat: 0 });
});

Deno.test("searches by the name when the model left the USDA query empty", () => {
  assertEquals(
    sanitizeItems(scan([item({ usda_query: " " })]))[0].query,
    "Grilled chicken",
  );
});

Deno.test("names the meal from its first foods when the model didn't", () => {
  const two = scan([item(), item({ name: "White rice" })], "");
  assertEquals(
    mealName(two, sanitizeItems(two)),
    "Grilled chicken and White rice",
  );
  const three = scan([
    item(),
    item({ name: "White rice" }),
    item({ name: "Broccoli" }),
  ], " ");
  assertEquals(
    mealName(three, sanitizeItems(three)),
    "Grilled chicken, White rice and more",
  );
  assertEquals(
    mealName(scan([item()]), sanitizeItems(scan([item()]))),
    "Chicken plate",
  );
});

Deno.test("reads the model's JSON and rejects anything else", () => {
  const reply = { is_food: true, meal_name: "Chicken plate", items: [item()] };
  assertEquals(parseScan(JSON.stringify(reply)), reply);
  assertEquals(parseScan("I can't help with that photo."), null);
  assertEquals(parseScan('{"is_food": true, "meal_name": "Cut off'), null);
  assertEquals(parseScan(JSON.stringify({ is_food: "yes", items: [] })), null);
});
