# LP outcome A/B, what the sandbox can and cannot show

Produced by `test/LPOutcomeTest.t.sol`. Three arms, identical traffic, identical starting state via
snapshot/revert. Pool 0.30%, LP position 1e22 liquidity over ticks ±60000.

The informed trader has one-sided history (balance 0 bps, 40 samples) so reaches only base depth.
Retail has two-sided history (10,000 bps) so is never capped.

## Result

| arm | informed volume | fee income from it | LP token0 | LP token1 |
|---|---|---|---|---|
| **A** no tranching | 80.00 | 0.240 | 9590.05 | 9415.08 |
| **B** tranching | 5.00 | 0.015 | 9515.05 | 9489.11 |
| **C** tranching + split attack | **5.00** | **0.015** | **9515.05** | **9489.11** |

## Finding 1, splitting buys nothing

**Arms B and C are byte-identical on every measured quantity.** The informed trader attempting to
split an 80-unit take into cap-sized pieces inside one transaction realises exactly the same 5 units
as the trader who does not bother.

That is the Stage 3.5 per-transaction meter doing its job, measured rather than asserted. Before that
meter, arm C would have converged to arm A and the cap would have been cosmetic.

Asserted, not eyeballed: `assertEq(C.informedVolume, B.informedVolume)`.

## Finding 2, tranching restrains the take, and costs fees, proportionally

Tranching cut the informed take from 80 to 5 units, a 16× reduction, and cut LP fee income from
that flow by exactly the same factor, 0.240 → 0.015. Fees are linear in volume, so **the restraint
and the cost are the same number seen from two sides.** There is no free lunch here and we do not
present one.

## What this harness deliberately does NOT report

**No single "LP value" figure.** Producing one requires valuing every arm at one reference price,
and the *sign of the answer flips with that choice*:

| assumed price of token1 in token0 | arm B − arm A |
|---|---|
| 0.98 | −2.58 |
| 1.00 | −1.00 |
| 1.01 | −0.21 |
| **1.02** | **+0.58** |

Valuing at arm A's own final price is worse than arbitrary. It is **biased toward A by
construction**, since A's inventory is exactly what that price implies.

Picking whichever price makes tranching look good would be precisely the tuned constant
the anti-goal blacklist forbids. So the number is not reported. **Whether tranching helps an LP depends on
where the price actually goes after the informed flow, and that is not knowable in a closed
sandbox.** It is measurable against real market data, which is Stage 5's fork-replay.

This is the same discipline as the lookback result: publish the parameter dependence instead of
hiding inside one confident figure.

## S5. The harness has no adversary, so it was mutated

The A/B has no revert to catch a mistake, making it the piece most likely to be green for the wrong
reason. Two mutations, both asserted in the suite:

- **`test_S5_HarnessCollapsesWhenTranchingDisabled`**, with tranching off on both sides, the arms
  must be identical in volume, both token balances, and final price. If they are not, the harness is
  measuring traffic ordering or fee accrual rather than the mechanism, and every number above is
  void.
- **`test_S5_NoDifferenceWhenNobodyIsCapped`**, give the informed trader full standing so the
  tranche never binds; tranching must then make no difference at all.

Both pass.

## A modelling correction worth recording

The first run compared arms unfairly: arm B's trader abandoned the trade when denied (0 volume)
while arm C's fell back to a cap-sized swap. That made splitting look productive, arm C appeared to
realise 5 units against arm B's 0.

Both arms now model the same rational trader: **denied the full size, take what you can.** The two
arms then differ *only* in whether splitting is attempted, which is the variable under test.

## Honest scope

This sandbox establishes that the meter works and quantifies the fee cost. It does **not** establish
that tranching improves LP outcomes. That claim requires real subsequent prices and is not made
until Stage 5 produces them, or not made at all, if Stage 5 does not support it.
