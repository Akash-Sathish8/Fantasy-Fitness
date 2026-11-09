import { assertEquals } from "jsr:@std/assert@1.0.13";
import { pickCandidate } from "./match.ts";
import { normalizeUsda, type UsdaFood } from "./usda.ts";

const candidates = (name: string) =>
  (JSON.parse(
    Deno.readTextFileSync(new URL(`./testdata/${name}`, import.meta.url)),
  ).foods as UsdaFood[])
    .map(normalizeUsda)
    .filter((food) => food !== null);

Deno.test("skips USDA's dehydrated-banana top hit for a raw banana", () => {
  const pick = pickCandidate(
    { kcal: 89, protein: 1.1, carbs: 22.8, fat: 0.3 },
    candidates("usda_banana.json"),
  );
  assertEquals(pick?.fdcId, 173944);
  assertEquals(pick?.name, "Bananas, raw");
});

Deno.test("picks the closest grilled chicken, not the first", () => {
  const pick = pickCandidate(
    { kcal: 165, protein: 31, carbs: 0, fat: 3.6 },
    candidates("usda_chicken.json"),
  );
  assertEquals(pick?.fdcId, 2705968); // 176 kcal, 29.62 g protein; the top hit is 202 kcal with sauce
});

Deno.test("returns null when nothing is close to the estimate", () => {
  assertEquals(
    pickCandidate(
      { kcal: 500, protein: 1, carbs: 22, fat: 0.3 },
      candidates("usda_banana.json"),
    ),
    null,
  );
  assertEquals(
    pickCandidate({ kcal: 89, protein: 1, carbs: 23, fat: 0 }, []),
    null,
  );
});

Deno.test("protein has to be close too", () => {
  const chicken = candidates("usda_chicken.json");
  // Right calories, but far too little protein for any of these chickens.
  assertEquals(
    pickCandidate({ kcal: 180, protein: 5, carbs: 30, fat: 4 }, chicken),
    null,
  );
});

Deno.test("only the first 10 results are considered", () => {
  const far = { kcal: 900, protein: 0, carbs: 0, fat: 100 };
  const list = Array.from({ length: 12 }, (_, i) => ({ ...far, fdcId: i }));
  list[11] = { kcal: 100, protein: 10, carbs: 10, fat: 2, fdcId: 11 };
  assertEquals(
    pickCandidate({ kcal: 100, protein: 10, carbs: 10, fat: 2 }, list),
    null,
  );
});
