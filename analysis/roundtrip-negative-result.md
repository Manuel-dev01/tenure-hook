# Roundtrip: a falsified hypothesis

**Status: dead. Falsified 2026-08-23, one day after starting.**
**Result: the observation surface works. The classification built on it cannot.**

This document exists because the negative result is worth more than the code that produced it.
Everything below is reproducible from this repository.

---

## The hypothesis

> A Uniswap v4 hook can read the PoolManager's outstanding currency deltas at `beforeSwap` and
> price the swap on **what the composite operation structurally is**, rather than inferring
> toxicity from statistics after the fact.

The claimed wedge: *"It doesn't infer that a trade was arbitrage. It observes the shape of the
operation as it runs."*

Three questions gated the build. Q2 was the go/no-go; Q3 was the experiment.

---

## Q1, hook-local transient storage. PASS

Hook-local `tstore`/`tload` persists across legs within one `unlock` and is cleared between
transactions.

| Test | Result |
|---|---|
| `test_Q1_TransientPersistsAcrossLegsInOneTx` | leg 0 to leg 1, `sawPriorTouch` false to true |
| `test_Q1_TransientClearedBetweenTxs` | both transactions start clean (requires `--isolate`) |

**Consequence worth stating plainly:** transient storage is transaction-scoped, so
**cross-transaction sandwiches are structurally invisible** to any hook built this way. Not hard, 
invisible. This was a known design boundary, and it is now verified rather than assumed.

---

## Q2, reading PoolManager transient state via `exttload`. PASS

A hook **can** read the PoolManager's flash-accounting deltas mid-swap, from outside the
PoolManager, using `IExttload`.

Verified against a **hand-calculated** value rather than a plausible-looking one.
`manager.take(A, 1_000_000)` accounts a delta of exactly `-1_000_000` to the caller, so the
expected reading is known before the test runs:

```
nonzeroDeltaCount : 1
delta in A        : -1000000     <- exact, not merely "non-zero"
locker            : the router, NOT the EOA
```

Ambiguity was closed deliberately. `exttload` on a wrong slot returns zero rather than reverting,
so "zero" and "wrong slot" are indistinguishable unless you force the issue:
`test_Q2_WrongSlotReadsZeroSoRightSlotIsNotGarbage` shows a target that never locked reads `0`
while the correct slot reads the known value.

Slot derivations were **imported** from v4-core, never transcribed, 
`NonzeroDeltaCount.NONZERO_DELTA_COUNT_SLOT` and `CurrencyDelta._computeSlot` are both `internal`
and usable by import, which binds them to the pinned submodule at compile time and removes the
transcription failure mode entirely.

**Q2 is a real, clean capability.** It is not carried into the successor project. It lives here.

---

## The instrument, and why it nearly produced a false negative

v4-core's `PoolSwapTest` calls `manager.unlock()` **once per swap and fully settles before
returning**. Every scenario built from stock routers therefore reads `nonzeroDeltaCount == 0` at
the hook boundary, every traffic type looks identical.

Had the experiment been run with stock tooling it would have reported "no separation" for a
**tooling** reason rather than a real one: a false negative that kills a live hypothesis while
leaving no trace that it was ever alive. `ActionsRouter` batches inside one unlock but has no
`SWAP` action, so it cannot build multi-leg routes either.

`test/routers/CompositeRouter.sol` was written to close this: one router, one `unlock`, an ordered
script of operations. All scenarios run through it, so any difference in signature is attributable
to the shape of the operation rather than to router idiosyncrasy.

Because that router authors the traffic it then measures, a **control** gates every number below
(`test_Q3_0_Control_RouterProducesHandCalculatedDelta`): the router must reproduce a delta computed
by hand, exactly, before any scenario is recorded.

---

## Q3, the experiment. FAIL

**The predicate under test**, stated so it could be falsified:

> At `beforeSwap`, does the locker already hold a non-zero delta of **opposing sign** in this
> swap's **output** currency?

A swap always credits the locker in the output currency, so the opposing sign is a debt: the locker
already owes the very currency this leg will pay them, i.e. the operation is closing a cycle.
Strictly boolean, no threshold, no magnitude, no tuning constant.

### The five signatures

| # | Scenario | nonzero deltas | delta in A | delta in B | delta in OUT | Predicate |
|---|---|---|---|---|---|---|
|, | **control** (hand-calculated) | 1 | −1,000,000 | 0 | −1,000,000 | true |
| 1 | single-hop retail | 0 | 0 | 0 | 0 | false |
| 2 | multi-hop A to B to C | 2 | +998501997253744881 *(B)* | 0 *(C)* | 0 | false |
| 3 | zap then add liquidity | 0 | 0 | 0 | 0 | false |
| **4** | **cyclic arb, closing leg** | **2** | **−1000000000000000000** | **+998501997253744881** | **−1000000000000000000** | **true** |
| **5** | **third-party batch settlement** | **2** | **−1000000000000000000** | **+998501997253744881** | **−1000000000000000000** | **true** |
| 5b | batch, no cycle closed | 2 | +998501997253744881 | 0 | 0 | false |

Rows 2 and 5b observe the B/C pool, so the positional columns hold B and C.

### Rows 4 and 5 are isomorphic

Not similar. **Byte-identical on every field the hook can observe.** This is asserted in
`test_Q3_ARB_vs_BATCH_SideBySide`, not eyeballed off a log, if a future change ever separates
them, that test fails.

The two scenarios were given **deliberately different** second-leg amounts (`-1e18` vs `-37e16`)
and the observables still matched exactly.

A bot closing an arbitrage cycle and a solver settling two unrelated users are the same thing at
this boundary.

---

## The general result. This is the part that matters

The isomorphism is not a coincidence of chosen parameters. It follows from where the hook sits.

`beforeSwap` fires at [`PoolManager.sol:200`](../lib/v4-core/src/PoolManager.sol#L200). Delta
accounting happens at [`:224`](../lib/v4-core/src/PoolManager.sol#L224), *after* the swap executes:

```solidity
(amountToSwap, beforeSwapDelta, lpFeeOverride) = key.hooks.beforeSwap(key, params, hookData);  // :200
swapDelta = _swap(pool, id, ...);                                                              // :204
...
_accountPoolBalanceDelta(key, swapDelta, msg.sender);                                          // :224
```

Therefore:

> **A hook never observes an operation. It observes a state prefix, and infers an operation from it.**

The predicate cannot distinguish *"closing a loop"* from *"holding an opposing delta and about to
do something else entirely"*, **at the instant it fires, those are the same state.** The collision
set is not "solvers", and it is not enumerable: it is *every operation sharing a prefix with a
toxic one*. No amount of additional scenario design closes that, because the missing information
does not exist yet at the moment the decision must be made.

This also generalises past the specific predicate. Any classifier reading only PoolManager
transient state at `beforeSwap` is classifying a prefix.

### Why that kills the wedge specifically

The pitch was *observes structure during execution, rather than inferring it afterwards*. What the
code actually does is infer an operation from a partial state. That is inference with a fresher
input, which is the pattern the project was defined against.

A separator was **not** attempted via intent, calldata shape, or router identity. Those are
heuristics, and a heuristic layered on a structural observation is a fee dial wearing a costume.

### The one result that cuts the other way

Scenario 5b, a batch that does **not** close a currency cycle, does not trip the predicate. So
the predicate is not flagging "solver flow" broadly; it flags **cycle closure** specifically, which
is a narrower and more defensible category than expected. It was weighed and did not change the
outcome, because the prefix problem above is not bounded by the solver/arb distinction.

---

## Disqualified before it could tempt anyone

The one axis on which rows 4 and 5 could be separated is **exact amount matching**, an arbitrage
bot passes through the credit it just received, whereas two unrelated users' amounts are
independent.

This was ruled out **on principle, before the number was looked at**: the hook is open source and
on-chain, so any separator keyed to exact amounts is defeated by adding one wei. A predicate an
adversary breaks by reading the repository is a speed bump, not a structural classification. It is
still measured and printed by the test, and never adopted.

---

## Reproducing

```bash
forge test --match-contract Discriminator --isolate -vv
```

12 tests. `--isolate` is required for the cross-transaction half of Q1; without it that test skips
loudly rather than passing vacuously.

| File | Role |
|---|---|
| [`test/DiscriminatorTest.t.sol`](../test/DiscriminatorTest.t.sol) | Q1, Q2, control, five scenarios |
| [`test/probe/ProbeHook.sol`](../test/probe/ProbeHook.sol) | observation-only hook; prices nothing |
| [`test/probe/TransientDeltaReader.sol`](../test/probe/TransientDeltaReader.sol) | slot derivations, imported from v4-core |
| [`test/routers/CompositeRouter.sol`](../test/routers/CompositeRouter.sol) | multi-leg single-unlock instrument |

---

## What was kept

Two verified facts, carried into the v4 trap list as v4 traps:

1. **`beforeSwap` fires before `_accountPoolBalanceDelta`.** A hook never sees the current leg's
   own accounting. Verified at PoolManager.sol:200 vs :224.
2. **Deltas key to the locker, not the EOA**, `_accountPoolBalanceDelta(key, swapDelta, msg.sender)`.

The timeline was the point. The failure mode was never "Q3 fails". It was "Q3 fails on Aug 30".
