# Lookback sensitivity, and why the sample rule removes it

Produced by the circuit, not computed alongside it:
`TestS5_LookbackSensitivity` in `brevis/prover/circuits/directional_balance_s5_test.go`.

Address `0x51c72848c68a965f66fa7a88855f9f7784502a7f`, USDC/WETH 0.05% pool.

## The attack this answers

> *"Brevis proves the history is real; it doesn't prove your metric is the right one. Change the
> lookback and the same address flips."*

It does flip. We are not going to argue with that. We measured it.

## The naive version is fragile

| lookback | swaps seen | directional balance |
|---|---|---|
| 20 blocks | 4 | **0 bps** |
| 40 blocks | 10 | **10,000 bps** |
| 80 blocks | 18 | **7,777 bps** |

The same address scores 0, then perfectly balanced, then 7,777, purely by moving the window. At 4
swaps a single additional trade moves the figure by 5,000 bps. **Balance over a handful of trades is
not a measurement.**

## The sample rule removes it

Standing is **undefined below 20 swaps**. The window is whatever block range contains 20, see
`analysis/minimum-sample-decision.md`, written and committed before these numbers were produced.

| approach | 20 blk | 40 blk | 80 blk |
|---|---|---|---|
| naive fixed window | 0 bps | 10,000 bps | 7,777 bps |
| **N = 20 sample rule** | *no standing* | *no standing* | **7,777 bps** |

An address with 4 swaps does not score 0. It has **no standing at all**, and falls to base depth
alongside every unsigned swapper. The noisy regime is not smoothed or clipped; it is declared out of
scope.

## Why this is not just a threshold in disguise

The rule removes the last free parameter rather than adding one. There is no lookback to choose:
the window is a *consequence* of the sample requirement. N is a threshold on **evidence
sufficiency**, not on the metric. It does not say "balanced enough", it says "measured enough".

The circuit still emits `total` and the attested block range alongside the balance, so a verifier
can always see the sample size and window behind any figure. Nothing is hidden inside one number.
