# Decision: what the circuit proves

**Date:** 2026-08-25 · **Decision: directional balance.** Adverse-selection scoring is rejected.

---

## The two candidates

**A, adverse-selection score.** Estimate how much the address's flow costs LPs, from price
movement after each swap. Requires a price series, a post-trade window, and a threshold.

**B, directional balance.** Over a lookback window, what fraction of this address's swaps on this
pool were in each direction. Computable from swap logs alone.

## Decision: B

### 1. B describes; A infers. That distinction already killed one project this week.

Roundtrip died because it **inferred an operation from a state prefix**. Adverse-selection scoring
infers *intent* from *subsequent price movement*, the same move, one layer out. Directional balance
is a property of the address's own realised history: no inference about why they traded, no claim
about what happened after.

The lesson of `analysis/roundtrip-negative-result.md` is not "transient storage was the wrong
mechanism". It is **stop inferring things the data does not contain.**

### 2. The originality budget is in the wrong place

`analysis/rfh-collision-check.md` established that across 660 directory projects, **depth-as-
entitlement is unoccupied** while Brevis-plus-reputation already exists (Reputation Hook, UHI2). The
30% comes from the entitlement, not the metric. Making the metric more exotic buys no originality
and costs defensibility.

A is more original-sounding. That is exactly why it is a trap.

### 3. The judge's attack lands on A and glances off B

> *"Brevis proves the history is real; it doesn't prove your metric is the right one. Change the
> lookback and the same address flips."*

Against **A** this is devastating. The lookback is one of *three* free parameters, alongside the
price series and the threshold, and every one is a modelling choice to defend on stage.

Against **B** the lookback is the *only* free parameter, and it is answered by showing the
sensitivity rather than arguing about it.

### 4. Anti-goal compliance

A requires a threshold on a continuous modelled score, a tuned heuristic, which the anti-goal blacklist bans outright.
B maps balance to depth **continuously and monotonically, with no cliff**, so there is no threshold
to tune and no bracket to fall into.

---

## What we claim, stated narrowly

> **The circuit proves what fraction of an address's swaps on this pool went in each direction over
> a given window. The pool prices accessible depth on that balance.**

We do **not** claim to detect toxicity, adverse selection, or intent. Under-claim in prose;
Functionality is graded against our own stated scope.

## The honest weakness, and why it is survivable

**An address can manufacture two-sidedness by round-tripping.** True, and it must be said on camera.

But every round trip pays the pool fee. So standing has a **real, non-zero acquisition cost**, paid
to LPs. The attack on the mechanism *is* the mechanism working: you pay liquidity providers to earn
depth. That is a better answer than any anti-gaming heuristic would be, and it strengthens the
anti-whitelist defence, standing is permissionlessly acquirable, at a price everyone pays equally.

## Required: sensitivity, not a single number

Compute directional balance across **two or three lookback windows** and publish how standing moves
between them. Nobody else in that room will be discussing parameter sensitivity at all, and it
converts the strongest attack on the design into a slide we chose to make.

## Ineligibility check

Directional balance is a **count ratio over swap direction**, not volume, so it stays clear of
Brevis's ineligible-metric category. Confirm against Brevis docs before implementing.
