// Static event-planning recommendations.
//
// All numbers are CONSERVATIVE RANGES based on rule-of-thumb sourcing from
// event-catering literature, food-truck owner forums, and PT genset rental
// pricelists. They are intentionally simple in PR 1; the real advisor in
// PR 2 will tighten these with input from our own truck owners and let users
// scale up/down. For now, surface ranges + caveats — never a single number.
//
// Sources consulted (rule-of-thumb; not formal citations):
//   - Roaming Hunger blog: "How many food trucks for a wedding"
//   - Mobile Cuisine: typical truck throughput 80-120 covers/hour
//   - PT genset rental tables (Generac, Atlas Copco): kVA per kitchen draw
//   - On-site catering checklists (water + waste per food station)

export type EventPlan = {
  /** Recommended truck count as [min, max]; max==min for very small events. */
  trucks: { min: number; max: number };
  /** Combined kVA draw across recommended trucks (range). */
  kva: { min: number; max: number };
  /** Suggested standalone genset size, if no mains hookup. */
  gensetKva: number;
  /** Litres of water on site, total. */
  waterLiters: { min: number; max: number };
  /** Square metres of clear ground for trucks + queueing. */
  areaM2: { min: number; max: number };
  /** Waste: number of 240L general bins + grease drums. */
  waste: { bins240l: number; greaseDrums: number };
};

/**
 * Compute a planning sketch for an event with `pax` guests.
 *
 * Heuristic (aligned with wizard's auto-suggest at ~150 pax/truck mid):
 *   - upper bound = 1 truck per 200 guests (snack / cocktail-only scenario)
 *   - lower bound = 1 truck per 120 guests (full-meal scenario)
 *   - ~150 sits in the middle and matches the wizard's slider auto-fill
 *   - cap at 8 (events bigger than ~1600 pax need bespoke planning;
 *     surface the cap with a caveat in the UI)
 *   - kVA per truck: 4-8 (running draw, not peak start surge)
 *   - genset sizing: 1.5× the upper-bound kVA, rounded up to a common rental size
 *     (10, 15, 20, 25, 40, 60, 100)
 *   - water per truck: 200-400L
 *   - footprint per truck: ~18 m² (truck + service zone) + ~6 m²/truck queueing
 *   - waste: 1 bin per 2 trucks (min 1), 1 grease drum per truck
 *
 * The `min/max` outputs are intentionally wide so the UI can present a range.
 */
export function recommendForEvent(pax: number): EventPlan {
  const safePax = Number.isFinite(pax) && pax > 0 ? Math.floor(pax) : 100;

  const trucksLower = Math.max(1, Math.ceil(safePax / 200));
  const trucksUpper = Math.max(trucksLower, Math.ceil(safePax / 120));
  const trucksMin = Math.min(trucksLower, 8);
  const trucksMax = Math.min(trucksUpper, 8);

  const kvaMin = trucksMin * 4;
  const kvaMax = trucksMax * 8;

  const gensetKva = roundUpToCommonGenset(Math.ceil(kvaMax * 1.5));

  const waterMin = trucksMin * 200;
  const waterMax = trucksMax * 400;

  const areaMin = trucksMin * 18 + trucksMin * 6;
  const areaMax = trucksMax * 18 + trucksMax * 6;

  return {
    trucks: { min: trucksMin, max: trucksMax },
    kva:    { min: kvaMin, max: kvaMax },
    gensetKva,
    waterLiters: { min: waterMin, max: waterMax },
    areaM2:      { min: areaMin, max: areaMax },
    waste: {
      bins240l: Math.max(1, Math.ceil(trucksMax / 2)),
      greaseDrums: trucksMax,
    },
  };
}

const COMMON_GENSET_KVA = [10, 15, 20, 25, 40, 60, 100, 150, 200];
function roundUpToCommonGenset(kva: number): number {
  for (const size of COMMON_GENSET_KVA) {
    if (size >= kva) return size;
  }
  return COMMON_GENSET_KVA[COMMON_GENSET_KVA.length - 1];
}
