> **SUPERSEDED by `analysis/sensitivity.md`.**
> Kept as a record: it is where the S4 trap, picking the window that flatters the result, 
> was named *before* it could be walked into. The final table, and the N = 20 sample rule
> that removes the fragility, are in `sensitivity.md`. Do not cite the numbers here as current.

# Lookback sensitivity, preliminary, Stage 2

Captured during Stage 2. The full table is a Stage 4 deliverable; these are the first real numbers
and they carry a finding that matters more than the table will.

Produced **by the circuit**, not computed alongside it, `TestS5_LookbackSensitivity` in
`brevis/prover/circuits/directional_balance_s5_test.go`.

Address `0x51c72848c68a965f66fa7a88855f9f7784502a7f`, USDC/WETH 0.05% pool.

| lookback | swaps seen | directional balance |
|---|---|---|
| 20 blocks | 4 | **0 bps** |
| 40 blocks | 10 | **10,000 bps** |
| 80 blocks | 18 | **7,777 bps** |

## The finding

**The same address scores 0, then 10,000, then 7,777 as the window widens.** The judge's predicted
attack, *"change the lookback and the same address flips"*, is not hypothetical. It lands, hard,
at short windows.

## Why, and what it is not

This is **small-sample noise, not a defect in the metric**. At 20 blocks the address has made 4
swaps, all one direction; a single additional swap the other way would move it from 0 to 5,000. At
18 swaps the figure is far less jumpy. Balance over a handful of trades is simply not a measurement.

It is specifically **not** evidence that directional balance is the wrong claim. Adverse-selection
scoring would have the same small-sample problem *plus* a price series, a post-trade window, and a
threshold. Three more free parameters, each of which would need defending.

## The S4 trap this creates, named before it is walked into

There is now an obvious temptation: **pick the 80-block window because it produces the nicest
number.** That would be exactly the tuned constant the anti-goal blacklist forbids, chosen to make a signal
look clean rather than because it is right.

We do not do that. Two honest responses instead:

1. **The circuit already emits `total` and the attested block range** alongside the balance. A
   consumer can see the sample size and the window that produced any figure. Nothing is hidden
   inside a single number.
2. **Publish the sensitivity rather than argue about it.** A design that shows its own parameter
   dependence is more credible than one that presents a single confident figure, and no other
   entrant is likely to be discussing this at all.

## Consequence for Stage 3

Standing derived from a very short window is close to meaningless. Options, to be decided at Stage 3
and **not** by picking whichever looks best:

- have the registry record `(balance, total, window)` and let the hook's depth mapping account for
  sample size, or
- require a minimum observed swap count for standing to be recorded at all, defensible as a
  *validity condition* rather than a discriminator, but it is a constant and must be argued for
  openly, not slipped in.

Either way the choice gets stated on camera with these numbers next to it.
