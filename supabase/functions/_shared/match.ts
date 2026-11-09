// Matching a food the photo model named to a USDA search result.
//
// USDA's ranking is noisy: "banana" puts dehydrated banana (346 kcal per 100 g) above
// raw banana (89). The model also gives its own per-100 g estimate, so a result is only
// accepted when it's close to that estimate; otherwise the estimate is used.

import type { Per100g } from "./usda.ts";

/** How many search results are considered, in USDA's order. */
export const MATCH_CANDIDATES = 10;

/**
 * The closest candidate within tolerance of the estimate (kcal within 40 kcal or 30%,
 * protein within 6 g or 40%), or null. Ties keep USDA's order.
 */
export function pickCandidate<T extends Per100g>(
  estimate: Per100g,
  candidates: T[],
): T | null {
  const kcalTolerance = Math.max(40, 0.3 * estimate.kcal);
  const proteinTolerance = Math.max(6, 0.4 * estimate.protein);
  let best: T | null = null;
  let bestScore = Number.POSITIVE_INFINITY;

  for (const candidate of candidates.slice(0, MATCH_CANDIDATES)) {
    const kcalGap = Math.abs(candidate.kcal - estimate.kcal);
    const proteinGap = Math.abs(candidate.protein - estimate.protein);
    if (kcalGap > kcalTolerance || proteinGap > proteinTolerance) continue;
    const score = kcalGap / Math.max(estimate.kcal, 50) +
      proteinGap / Math.max(estimate.protein, 5);
    if (score < bestScore) {
      best = candidate;
      bestScore = score;
    }
  }
  return best;
}
