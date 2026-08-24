# Progress Update 1 — UHI10

**Submit to:** tally.so/r/3ER2yL
**Due:** Aug 24, 2026
**Status:** ready to file. T2 passed; T1 is mid-flight and its status is stated honestly below.

---

## What I set out to build

**Roundtrip** — a Uniswap v4 hook that reads the PoolManager's outstanding currency deltas from
transient storage at `beforeSwap` and classifies the composite operation a swap is a leg of, so it
could price on what the operation structurally *is* rather than on statistical guesses about
toxicity.

I gated the whole project on one unverified assumption and refused to write hook logic until it was
answered.

## What happened

**I falsified it in a day, and I am pivoting.**

Two of the three gating questions passed:

- A hook **can** read PoolManager transient deltas mid-swap via `exttload`. Verified against a
  hand-calculated value (exactly `-1000000`), not a plausible-looking one, with a wrong-slot control
  proving a zero reading is unambiguous.
- Hook-local transient storage behaves as EIP-1153 specifies — persists across legs of one
  transaction, cleared between transactions. Which also confirms cross-transaction sandwiches are
  structurally invisible to this design.

The third question failed, and the way it failed is the interesting part.

**Cyclic arbitrage and third-party batch settlement are byte-identical at the hook boundary.** Not
similar — identical on every observable field, with deliberately different swap amounts. That
equality is asserted in the test suite rather than eyeballed.

## The underlying reason, which generalises

`beforeSwap` fires at `PoolManager.sol:200`. Delta accounting happens at `:224`, *after* the swap
executes. So:

> **A hook never observes an operation. It observes a state prefix, and infers an operation from it.**

At the instant the hook fires, "closing an arbitrage loop" and "holding an opposing delta and about
to do something else" are the *same state*. The collision set isn't solvers, and it isn't
enumerable — it's every operation sharing a prefix with a toxic one. No additional scenario design
closes that, because the distinguishing information does not exist yet at the moment the decision
must be made.

That kills the idea specifically. My pitch was "observes structure during execution rather than
inferring it afterwards." What the code actually does is infer from a partial state — inference
with a fresher input, which is the pattern I had defined the project against.

I did not try to rescue it with calldata shape, router identity, or intent heuristics. A heuristic
layered on a structural observation is just a fee dial with a better story.

The full write-up, with the five-scenario table and reproduction instructions, is in
`analysis/roundtrip-negative-result.md`. The tests still run.

## What I am building instead

**Tenure.**

> **Depth is the product. Every address pays the same fee; what you earn is how much of the book
> you can reach.**

A pool where the fee is identical for every address, and proven on-chain history determines how
much of the book you can take in a single swap. Standing is proven with a Brevis ZK circuit and
presented by the trader as an EIP-712 credential — it is an asset the trader holds, not a property
the pool assigns.

No code path adjusts a fee based on standing. The thing that varies is accessible depth.

Milestone 0 for Tenure is the same shape that just worked: capability gates with a hard date and a
named fallback. Hard switch date Aug 28; fallback is a Reactive-based hook.

### T2 — identity binding. PASSED.

`beforeSwap` receives the router, never the trader, and v4-periphery's `IMsgSender.msgSender()` is
**self-reported** — a malicious router could name any high-standing address and take the largest
size. Self-reported identity is not identity, and a mechanism granting entitlements on an
unauthenticated claim has no mechanism at all.

The trader instead signs an EIP-712 credential binding locker, pool, max size, nonce and deadline.
The hook recovers the signer and reads *that* address's standing. Eight negative cases each have
their own test and all revert: forged signature, garbage signature, missing credential, replayed
nonce, expired deadline, wrong locker, wrong pool, and exceeding the signed size. Signature
malleability is rejected too, since a malleable signature is a second valid credential for the same
nonce.

An address with zero standing still receives a non-zero depth allowance. Nobody is excluded — the
mechanism caps size, it never denies access.

### T1 — Brevis round-trip. In progress, with a measured blocker.

The circuit compiles (857,948 constraints). The gate is currently blocked on one-time local setup:
the Brevis SDK requires the full gnark KZG ignition file, **3.0 GiB**, and MD5-checks it against a
hardcoded digest, so it cannot be truncated to the ~1M points the circuit actually uses. Measured
throughput is ~350 KiB/s aggregate across eight parallel range requests, roughly 1.8x a single
stream, which puts the ceiling at the local link rather than at the source.

This is a setup cost, not a capability failure, and it resolves well inside the Aug 28 switch date.
Stating it because a milestone that is "nearly done" on the day it is due is worth reporting
precisely rather than optimistically.

## What I would tell another team

Gate your project on its riskiest assumption and put a date on it. Roundtrip's failure mode was
never "the idea doesn't work" — it was "the idea doesn't work, discovered on Aug 30."

One concrete trap worth passing on: v4-core's `PoolSwapTest` opens its own `unlock` per swap and
settles before returning, so every multi-leg scenario built from stock routers looks identical at
the hook boundary. Testing with it would have told me "no signal" for a tooling reason rather than a
real one — a false negative that kills a live idea and leaves no trace it was ever alive. I had to
write a single-unlock router before the experiment could say anything at all, and gate it on a
control that reproduced a hand-calculated delta.

## Days remaining

10. Ahead of where I would be if I had found this on Aug 30.
