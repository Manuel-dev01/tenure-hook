# Tenure

**Depth is the product. Every address pays the same fee; what you earn is how much of the book you
can reach.**

A Uniswap v4 hook where the fee is **identical for every address**, and proven on-chain history
determines **how much of the book you can take in a single swap**. Standing is proven with a Brevis
ZK circuit over historical chain data and presented by the trader as an EIP-712 credential.

Standing is an asset the trader holds, not a property the pool assigns. You are not sorted into a
bracket — you present a credential you earned.

> **Status: Stage 1 complete.** The hook works standalone with operator-set standing. Capability
> gates T1a and T2 have both passed. Nothing here prices anything, and no code path adjusts a fee
> based on standing — see the fee-parity rule, which forbids it outright.

---

## What this submission claims — and what it does not

> The mechanism gates atomic depth by proven directional balance, **the gate binds**, and **it
> cannot be split around**. Restraint costs fee income proportionally. **We do not claim to improve
> LP outcome**, because a closed sandbox cannot know where price goes after the informed flow, and
> any reference price we chose would determine the sign of the result.

The three-arm A/B in [`analysis/lp-outcome.md`](analysis/lp-outcome.md) establishes the first two
together:

| comparison | what it proves |
|---|---|
| arm A vs arm B | the cap **binds** — informed take falls 80.00 → 5.00 |
| arm B vs arm C | the cap **cannot be routed around** — the split attack realises byte-identical volume, fees and inventory |

That pairing is the point. Two weeks earlier this repository's predecessor died because the
mechanism did not do what its pitch said (see [the falsification](analysis/roundtrip-negative-result.md)).
This is the opposite outcome, measured against the one attack that would have made the cap cosmetic.

**On the benefit claim.** Valuing the arms at a single reference price flips the sign of the result:
tranching looks harmful at P = 0.98 and beneficial at P = 1.02. Valuing at the unconstrained arm's
own final price is worse than arbitrary — it is biased toward that arm by construction. So no LP
value figure is reported, and the sensitivity is published instead.

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
| Depth enforcement at swap time | `src/TenureHook.sol:235` — `_beforeSwap` |
| Per-transaction depth meter | `src/TenureHook.sol:317` — `_consumedDepth` / `_setConsumedDepth` |
| Continuous depth curve (no cliffs) | `src/TenureHook.sol:192` — `depthFractionBps` |
| Credential binding struct | `src/TenureHook.sol:101` — `DepthCredential` |
| Anti-whitelist floor | `src/TenureHook.sol:51` — `BASE_DEPTH_BPS` |
| Fee neutrality, structural | `src/TenureHook.sol:148` — `beforeSwapReturnDelta: false` |
| Stage 1 tests (15) | [`test/TenureHookTest.t.sol`](test/TenureHookTest.t.sol) |

**Forgery is a no-op, not an attack.** A forged signature recovers to the *forger's own* address, so
they simply get their own standing rather than the victim's. There is nothing to steal: the
credential names no beneficiary a thief could redirect. Asserted in
`test_ForgedSignatureGetsForgersStanding`.

### Depth is metered per transaction, not per swap

A per-swap cap alone would be cosmetic: sign several credentials, split one large take into N
cap-sized swaps in a single transaction, pay almost nothing extra. Standing would gate nothing.

So consumed depth accumulates in **hook-local transient storage** across every leg of a transaction
and is checked against the standing-derived entitlement. Consumption is keyed to the **recovered
trader**, not the credential, so minting more signatures cannot raise the ceiling.

**Per-transaction is the principled boundary, not the cheap one.** Atomicity is what makes a large
take harmful. A trader splitting across blocks is exposed to price movement and other flow in
between — that is ordinary trading, not extraction. What the hook gates is the atomic grab.

**Unsigned swaps are metered too — anonymity is not an exemption.** Were they exempt, the cheapest
route to the whole book would be to sign nothing and split at base depth, making standing strictly
*worse* than no standing and running the mechanism backwards. Asserted in
`test_Meter_UnsignedSplittingRevertsAtBaseCap`.

#### Limitations, stated plainly

- **Unsigned swaps batched by one router share a per-transaction bucket.** Any of those users can
  sign a zero-standing credential — free, permissionless, no standing needed — and be metered
  separately. Asserted in `test_Meter_ZeroStandingCredentialGetsItsOwnBucket`.
- **Splitting across separate transactions in the same block still evades the cap.** It costs gas
  per transaction and gives up atomicity, which makes it a materially weaker attack, but it is real.

### Standing is undefined below 20 swaps

Directional balance over a handful of trades is noise: at four swaps a single extra trade moves it
5,000 bps. Rather than choose a lookback window that flatters the result, an address below **20
observed swaps has no standing** and receives base depth alongside every unsigned swapper. N was
derived from the metric's own arithmetic — one further swap must not move balance by more than 500
bps, so `10000/(N+1) ≤ 500` — and **recorded before any numbers were run at any N**
([`analysis/minimum-sample-decision.md`](analysis/minimum-sample-decision.md)).

This removes the last free parameter: there is no lookback to pick, only a threshold on evidence
sufficiency, which separates *measured* from *not yet measured* rather than good traders from bad.

### Known limitation: proofs run against a historical block range

`brevis-sdk v0.3.12` cannot build receipt proofs for blocks containing **EIP-7702 (type 4)**
transactions, which are present in current mainnet blocks. Measured, not assumed: the failing range
carried 12 type-4 transactions, the pinned range zero. Blob transactions are *not* the problem — they
appear in the working range too.

Proofs are therefore generated against a pinned pre-Pectra range, anchored at block **21,146,236**.
See [`analysis/pinned-proving-range.md`](analysis/pinned-proving-range.md).

---

## Milestone 0 gates

| Gate | Question | Status |
|---|---|---|
| **T1a** | Does local Brevis proving work — compile, key-gen, prove, verify? | **PASS** |
| **T1b** | Does gateway submission reach Sepolia? | blocked by a Brevis-side gateway outage. **Not a gate** — deployment is not required by the rules |
| **T2** | Can the hook bind a swap to a trader unforgeably, and fail closed? | **PASS** — 10/10 |

T1a evidence: circuit 857,942 constraints, setup 13.6s, vk hash
`0x1cb76a97800eca38048ce06ba3199638113b0218e56ed9c9b212fbedbd8a79fc`, proof generated **and verified
against the vk** twice (the prover's `prove()` returns an error rather than a proof if verification
fails, so proof output *is* verification).

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
| missing `hookData` | *(probe only)* `MissingCredential` — the production `TenureHook` instead grants **base depth**, see Architecture |
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
| **Brevis** | `src/TenureRegistry.sol:83` | `handleProofResult` — ZK callback, `_vkHash` validated |
| **Brevis** | `src/lib/BrevisAppZkOnly.sol:9` | vendored `BrevisAppZkOnly` callback base |
| **Uniswap v4** | `src/TenureHook.sol:235` | `_beforeSwap` enforcing the depth entitlement |
| **Uniswap v4** | `src/TenureHook.sol:136` | `getHookPermissions` — beforeSwap only, no fee power |
| **OpenZeppelin** | `src/TenureHook.sol:37` | `uniswap-hooks` v1.0.0 `BaseHook` |

Attribution for vendored upstream code: [`brevis/ATTRIBUTION.md`](brevis/ATTRIBUTION.md). At the T1
gate, everything under `brevis/` is upstream's example code, unmodified.

---

## Running the tests

```bash
forge test --isolate
```

47 tests across four suites.

| Suite | Tests | What it proves |
|---|---|---|
| `TenureHookTest` | 15 | Stage 1 — the depth entitlement, credential binding, fee neutrality |
| `TenureRegistryTest` | 10 | Stage 3 — `_vkHash` validation and the minimum-sample rule |
| `TenureIdentityTest` | 10 | T2 — identity binding and all fail-closed cases |
| `DiscriminatorTest` | 12 | the Roundtrip falsification, still reproducible |

`--isolate` is required for the cross-transaction half of the Roundtrip Q1 test; without it that
one test skips loudly rather than passing vacuously.

## Pinned dependencies

| Dependency | Pin | Commit |
|---|---|---|
| `uniswap/v4-core` | tag `v4.0.0` | `e50237c43811bd9b526eff40f26772152a42daba` |
| `uniswap/v4-periphery` | `main` | `dce236d4e2057422d0791d9a973a58765eb46f65` |
| `foundry-rs/forge-std` | tag `v1.16.2` | `bf647bd6046f2f7da30d0c2bf435e5c76a780c1b` |
| `OpenZeppelin/uniswap-hooks` | tag `v1.0.0` | `1db96464698ee567521bd2dd65833ff1e1864ac7` |

`uniswap-hooks` is pinned to v1.0.0 rather than latest: v1.2.x imports `SwapParams` from
`v4-core/src/types/PoolOperation.sol`, which does not exist in our pinned v4-core `v4.0.0`.

solc `0.8.26`, `evm_version = "cancun"`.

## Attribution

Test scaffolding derives from `v4-core/test/utils/Deployers.sol` and
`v4-periphery/test/shared/HookMiner.sol`. The transient-delta reader in `test/probe/` **imports**
v4-core's slot derivations rather than transcribing them. Brevis code under `brevis/` is upstream's;
see `brevis/ATTRIBUTION.md`.
