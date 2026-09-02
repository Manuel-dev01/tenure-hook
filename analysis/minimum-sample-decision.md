# Decision: standing is undefined below N swaps. N = 20.

**Recorded 2026-08-25, BEFORE running any numbers at any N.** That ordering is the whole point: a
sample size chosen after seeing which value flatters the result is a tuned constant, which
the anti-goal blacklist forbids. This one is derived from the metric's own arithmetic.

---

## The rule

> Standing is **undefined** below N swaps. The window is whatever block range contains N.

An address with fewer than N observed swaps does not get a low score. It gets **no standing**, and
falls to base depth alongside every unsigned swapper. Nothing is excluded, nothing is penalised.
Standing must be earned across a volume of interactions, not caught in a lucky window.

## Why this replaces fixed lookback windows

Stage 2 measured the same address at 0 / 10,000 / 7,777 bps across 20 / 40 / 80-block windows. That
is small-sample noise, and a fixed window does not fix it. It just picks which noise to show.

The sample rule **removes the last free parameter**. There is no lookback to choose. What remains is
a threshold on *evidence sufficiency*, how much data before we will say anything at all, which is
categorically different from a threshold on the metric. It does not separate good traders from bad;
it separates "measured" from "not yet measured".

## Deriving N without looking at data

Balance is `2·min(buys, sells) / total`. For a near-balanced address, adding one more swap moves it
by roughly:

```
Δ ≈ 10000 / (N + 1)  bps
```

Requiring that **one additional swap cannot move standing by more than 500 bps** (5 percentage
points) gives:

```
10000 / (N + 1) ≤ 500   →   N ≥ 19
```

**N = 20.**

Two independent constraints agree with it:

- The circuit's `MaxSwaps` budget is 32, so N must fit inside a single proof. 20 leaves headroom.
- At N = 20 the standard error of a proportion at p = 0.5 is ≈ 0.11, so the figure is meaningful to
  roughly the nearest 1,000 bps, which is the resolution the depth curve actually needs, since
  depth moves continuously and small differences do not produce cliffs.

If N had come out at 4 or at 400 this document would say so. The derivation is stated so it can be
checked, and so that changing N later is visibly a change of argument rather than a quiet retune.

## Consequences

- **The hook must see `total`, not just the balance.** The circuit already emits it. The registry
  stores it, and the hook grants base depth whenever `total < MIN_STANDING_SWAPS`.
- **The sensitivity table still ships.** Stage 4 publishes the 20/40/80 spread *and* this rule, and
  says on camera that the spread is why the rule exists. Conceding the attack is stronger than
  pre-empting it.
- **No lookback constant appears anywhere in the circuit or the hook.** The attested block range is
  an output, reported for audit, never an input we chose.

## What would falsify this choice

If a meaningful share of real addresses never reach 20 swaps on a single pool, then standing is
unreachable in practice and the mechanism serves nobody. Stage 4 measures that distribution and
reports it, whatever it shows.
