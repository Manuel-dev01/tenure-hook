# Tenure

**Depth is the product. Every address pays the same fee; what you earn is how much of the book you
can reach.**

A Uniswap v4 hook where the fee is **identical for every address**, and proven on-chain history
determines **how much of the book you can take in a single swap**. Standing is proven with a Brevis
ZK circuit over historical chain data and presented by the trader as an EIP-712 credential.

Standing is an asset the trader holds, not a property the pool assigns. You are not sorted into a
bracket — you present a credential you earned.

> **Status: Milestone 0.** Gate T2 has passed. Gate T1 is in progress. Nothing here prices anything,
> and no code path adjusts a fee based on standing — see `CLAUDE.md` §X, which forbids it outright.

---

## Repository history, stated plainly

This repository began as **Roundtrip**, a different hook that was **falsified on 2026-08-23**, one
day after starting. That negative result is kept here deliberately rather than deleted:

**[`analysis/roundtrip-negative-result.md`](analysis/roundtrip-negative-result.md)**

The short version: a hook can read the PoolManager's transient deltas mid-swap (verified), but it
cannot classify operations from them, because `beforeSwap` fires at `PoolManager.sol:200` while
delta accounting happens at `:224`. **A hook never observes an operation — it observes a state
prefix and infers an operation from it.** Cyclic arbitrage and third-party batch settlement are
byte-identical at that boundary. The tests still run and still prove it.

Tenure is the successor. Roundtrip's capability is **not** carried into it.

---

## Architecture

```
                  Stage 1 (built)                    Stage 3 (wiring)
  ┌──────────┐                                    ┌──────────────────┐
  │  trader  │ ── EIP-712 DepthCredential ──┐     │  Brevis circuit  │
  └──────────┘    (locker, poolId,          │     │ directional bal. │
                   maxSize, nonce,          │     └────────┬─────────┘
                   deadline)                │              │ proof
                                            ▼              ▼
  ┌──────────┐    swap + hookData    ┌─────────────────────────────┐
  │  router  │ ────────────────────► │        TenureHook           │
  └──────────┘                       │  recovers signer            │
                                     │  reads standingOf[trader]   │
                                     │  caps size to depth share   │
                                     │  NEVER touches the fee      │
                                     └─────────────────────────────┘
```

**The entitlement.** Each pool has a **depth tranche** — the most any single swap may consume.
Standing determines what *fraction* of that tranche a trader can take, rising linearly from 5% at
zero standing to 100% at full standing. Continuous and monotonic: no brackets, no cliffs, nothing
to tune.

**Why a signature and not `msgSender()`.** `beforeSwap` receives the locker (router), never the
trader. v4-periphery exposes `IMsgSender.msgSender()` but it is **self-reported** — a malicious
router could name any high-standing address. Self-reported identity is not identity, so the trader
signs an EIP-712 credential binding `(locker, poolId, maxSize, nonce, deadline)` and the hook reads
the *recovered* signer's standing. Standing is an asset the trader presents, not a property the
pool assigns.

**Fee neutrality is structural, not policy.** The hook's mined address deliberately omits
`BEFORE_SWAP_RETURNS_DELTA`, so it *cannot* alter execution economics even if code were added
trying to. Asserted in `test_HookHoldsNoFeePermission`.

**Nobody is excluded.** A swap presenting no credential at all still executes, at base depth. A
credential is how a trader claims *more* than base, never how they gain entry. Asserted in
`test_UnsignedSwapGetsBaseDepth` and `test_NobodyIsExcluded`.

| Concern | Where |
|---|---|
| Depth entitlement + EIP-712 recovery | [`src/TenureHook.sol`](src/TenureHook.sol) |
| Continuous depth curve | `TenureHook.depthFractionBps` |
| Credential binding | `TenureHook.DepthCredential` |
| Stage 1 tests (15) | [`test/TenureHookTest.t.sol`](test/TenureHookTest.t.sol) |

---

## Milestone 0 gates

| Gate | Question | Status |
|---|---|---|
| **T1** | Does a Brevis proof round-trip close end-to-end on testnet? | in progress |
| **T2** | Can the hook bind a swap to a trader unforgeably, and fail closed? | **PASS** — 10/10 |

### T2 — the identity gate

`beforeSwap` receives the locker (router), never the trader. v4-periphery's `IMsgSender.msgSender()`
exists for this but is **self-reported**, so a malicious router could name any high-standing address
and take the largest size. Self-reported identity is not identity.

The trader instead signs an EIP-712 `DepthCredential` binding `(locker, poolId, maxSize, nonce,
deadline)`. The hook recovers the signer and reads *that* address's standing.

Every negative case has its own test, and all revert:

| Case | Error |
|---|---|
| forged signature | recovers a different address, whose standing is lower |
| garbage signature | `InvalidSignature` |
| missing `hookData` | `MissingCredential` |
| replayed nonce | `ReplayedNonce` |
| expired deadline | `ExpiredCredential` |
| wrong locker | `WrongLocker` |
| wrong pool | `WrongPool` |
| over signed `maxSize` | `ExceedsDepthAllowance` |

Nobody is excluded: an address with zero standing still receives a non-zero depth allowance. That
is the anti-whitelist property, and it is asserted in `test_T2_StandingChangesDepthOnly`.

---

## Partner integrations

| Partner | Where | What it does |
|---|---|---|
| **Brevis** | [`brevis/prover/circuits/circuit.go`](brevis/prover/circuits/circuit.go) | app circuit proving historical chain activity |
| **Brevis** | [`brevis/app/src/index.ts`](brevis/app/src/index.ts) | proof request, local proving, gateway submission to Sepolia |
| **Brevis** | [`brevis/contracts/`](brevis/contracts/) | `BrevisApp` callback receiver |
| **Uniswap v4** | [`test/gate/TenureGateProbe.sol:beforeSwap`](test/gate/TenureGateProbe.sol) | the hook enforcing depth allowance |

Attribution for vendored upstream code: [`brevis/ATTRIBUTION.md`](brevis/ATTRIBUTION.md). At the T1
gate, everything under `brevis/` is upstream's example code, unmodified.

---

## Running the tests

```bash
forge test --isolate
```

22 tests across two suites.

| Suite | What it proves |
|---|---|
| `TenureIdentityTest` | T2 — identity binding and all fail-closed cases |
| `DiscriminatorTest` | the Roundtrip falsification, still reproducible |

`--isolate` is required for the cross-transaction half of the Roundtrip Q1 test; without it that
one test skips loudly rather than passing vacuously.

## Pinned dependencies

| Dependency | Pin | Commit |
|---|---|---|
| `uniswap/v4-core` | tag `v4.0.0` | `e50237c43811bd9b526eff40f26772152a42daba` |
| `uniswap/v4-periphery` | `main` | `dce236d4e2057422d0791d9a973a58765eb46f65` |
| `foundry-rs/forge-std` | tag `v1.16.2` | `bf647bd6046f2f7da30d0c2bf435e5c76a780c1b` |

solc `0.8.26`, `evm_version = "cancun"`.

## Attribution

Test scaffolding derives from `v4-core/test/utils/Deployers.sol` and
`v4-periphery/test/shared/HookMiner.sol`. The transient-delta reader in `test/probe/` **imports**
v4-core's slot derivations rather than transcribing them. Brevis code under `brevis/` is upstream's;
see `brevis/ATTRIBUTION.md`.
