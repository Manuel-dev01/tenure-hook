# Architecture

How Tenure is put together, and why each piece is shaped the way it is.

**Contents**

1. [The one-sentence model](#the-one-sentence-model)
2. [Components](#components)
3. [The two flows](#the-two-flows)
4. [The depth curve](#the-depth-curve)
5. [Identity: why a signature and not a router](#identity-why-a-signature-and-not-a-router)
6. [The per-transaction meter](#the-per-transaction-meter)
7. [The circuit](#the-circuit)
8. [Trust models behind one interface](#trust-models-behind-one-interface)
9. [Uniswap v4 constraints that shaped the design](#uniswap-v4-constraints-that-shaped-the-design)
10. [Key code pointers](#key-code-pointers)
11. [What each file is for](#what-each-file-is-for)

---

## The one-sentence model

Every address pays the same fee. Proven trading history decides how much of the book that address
can take in a single transaction.

Nothing in the system adjusts a price. The hook's deployed address does not even hold the
permission to do so, which is checked below.

---

## Components

```
                     off chain                          on chain
  ┌────────────────────────────┐        ┌──────────────────────────────────────┐
  │  Uniswap v3 Swap logs      │        │                                      │
  │  (real mainnet history)    │        │   IStandingRegistry                  │
  │            │               │        │   ┌────────────────┐                 │
  │            ▼               │        │   │ TenureRegistry │  ZK callback    │
  │  DirectionalBalanceCircuit │───────▶│   └────────────────┘                 │
  │  (gnark, 1,601,003         │ proof  │   ┌────────────────────────────┐     │
  │   constraints)             │        │   │ OperatorStandingRegistry   │     │
  │            │               │        │   └────────────────────────────┘     │
  │            ▼               │        │            │  standingOf(address)    │
  │  proof + verifying key     │        │            ▼                         │
  └────────────────────────────┘        │       TenureHook                     │
                                        │       beforeSwap only                │
  ┌────────────────────────────┐        │            ▲                         │
  │  trader's wallet           │        │            │ hookData                │
  │  signs an EIP-712          │───────▶│    TenureSwapRouter ───▶ PoolManager │
  │  DepthCredential           │        │    (one unlock, N legs)              │
  └────────────────────────────┘        └──────────────────────────────────────┘
```

| Component | File | Role |
|---|---|---|
| Hook | [`src/TenureHook.sol`](src/TenureHook.sol) | Enforces the depth ceiling in `beforeSwap`. Holds no fee power. |
| Standing interface | [`src/interfaces/IStandingRegistry.sol`](src/interfaces/IStandingRegistry.sol) | The single question the hook asks: `standingOf(address)`. |
| ZK registry | [`src/TenureRegistry.sol`](src/TenureRegistry.sol) | Receives a Brevis callback, validates the verifying-key hash, records standing. |
| Operator registry | [`src/OperatorStandingRegistry.sol`](src/OperatorStandingRegistry.sol) | Same interface, operator-written. The second trust model. |
| Router | [`src/TenureSwapRouter.sol`](src/TenureSwapRouter.sol) | Carries `hookData` and holds one `unlock` across several legs. |
| Circuit | [`brevis/prover/circuits/directional_balance.go`](brevis/prover/circuits/directional_balance.go) | Proves directional balance over real swap logs. |
| Demo ERC20 | [`src/DemoERC20.sol`](src/DemoERC20.sol) | Testnet-only token so the Sepolia pool has something to trade. |

---

## The two flows

### Flow 1: earning standing (asynchronous, off chain first)

Brevis proving cannot happen inside `beforeSwap`. A proof takes between 57 and 176 seconds, and a
swap has one block. So standing is **attested first and consumed later**, never proven at swap time.

```
1. collect an address's Swap logs from one pool
2. prove directional balance in the circuit           (57-176s)
3. verify the proof against the verifying key
4. deliver on chain, and the registry records standing
5. the hook reads the cached figure at swap time      (one SLOAD)
```

Step 4 is the step that is **not live**. See [Trust models](#trust-models-behind-one-interface).

### Flow 2: spending depth (synchronous, one transaction)

```
trader signs DepthCredential(locker, poolId, maxSize, nonce, deadline)
        │
        ▼
router.swap(poolKey, legs)          hookData = abi.encode(credential, signature)
        │
        ▼
PoolManager.unlock  ──▶  swap leg 1  ──▶  TenureHook.beforeSwap
                                            ├─ recover the signer from the signature
                                            ├─ check locker, poolId, nonce, deadline
                                            ├─ entitled = tranche × depthFractionBps(standing)
                                            ├─ allowed  = min(signed maxSize, entitled)
                                            ├─ revert ExceedsDepthAllowance if requested > allowed
                                            ├─ revert DepthExhaustedThisTx if the meter is spent
                                            └─ add requested to the transient meter
                     ──▶  swap leg 2  ──▶  same hook, meter already partly consumed
        │
        ▼
settle both currencies against the swapper
```

---

## The depth curve

```solidity
function depthFractionBps(uint256 standing) public pure returns (uint256) {
    if (standing >= FULL_DEPTH_STANDING) return BPS;
    return BASE_DEPTH_BPS + ((BPS - BASE_DEPTH_BPS) * standing) / FULL_DEPTH_STANDING;
}
```

| Constant | Value | Why |
|---|---|---|
| `BASE_DEPTH_BPS` | 500 (5%) | **Deliberately non-zero.** This constant is the anti-whitelist property: an address with no standing at all still reaches 5% of the tranche. The mechanism caps size; it never denies access. |
| `FULL_DEPTH_STANDING` | 10,000 | Standing at which the whole tranche is reachable. |
| `BPS` | 10,000 | Basis-point scale. |

Linear, monotonic, continuous. No brackets, no cliffs, nothing tuned. A trader one basis point
better off gets a slightly larger allowance, never a step change.

The **depth tranche** is per pool and operator-set, in input-token units. Zero means unconfigured,
and an unconfigured pool is unrestricted.

---

## Identity: why a signature and not a router

`beforeSwap` receives `sender`, which is the **locker**, meaning whichever contract opened the
`unlock`. It is never the trader's address. Uniswap's `IMsgSender.msgSender()` exists, but it is
**self-reported by the router**, so a malicious router could name any high-standing address.

So the trader signs an EIP-712 credential and the hook recovers the signer from it:

```solidity
struct DepthCredential {
    address locker;    // binds to one router, so a credential cannot be lifted elsewhere
    bytes32 poolId;    // binds to one pool
    uint256 maxSize;   // the trader's own ceiling for this swap
    uint256 nonce;     // single use
    uint256 deadline;  // expires
}
```

Every field is load-bearing. Drop `locker` and a credential works through any router; drop `poolId`
and standing proven on one pool spends on another; drop `nonce` and it replays.

A router allowlist was considered and **permanently rejected**. Trusting `msgSender()` from an
allowlist would make the trust boundary the router, so standing proven cryptographically would then
be gated behind an admin-maintained list. That is a whitelist with extra steps, and it is visible in
the code.

---

## The per-transaction meter

Without a meter the cap is cosmetic. A trader signs several credentials and splits one large take
into cap-sized pieces inside a single transaction, at almost no extra cost.

The hook therefore accumulates consumption in **EIP-1153 transient storage**, keyed to the
**recovered trader**, and checks it against the entitlement rather than against the signed cap:

```solidity
uint256 consumed = _consumedDepth(trader);
if (consumed + requested > entitled) {
    revert DepthExhaustedThisTx(requested, entitled - consumed);
}
_setConsumedDepth(trader, consumed + requested);
```

Two consequences worth stating plainly:

**Unsigned swaps are metered too**, against `address(0)`. Exempting them would make signing strictly
worse than not signing, because the cheapest route to the whole book would be to stay anonymous and
split. The mechanism would run backwards. This is asserted by
`test_Meter_UnsignedSplittingRevertsAtBaseCap`.

**Cross-transaction splitting within a block still evades the cap.** Transient storage is
transaction-scoped, so it clears between transactions. This costs gas and gives up atomicity, and it
is disclosed rather than hidden.

---

## The circuit

[`brevis/prover/circuits/directional_balance.go`](brevis/prover/circuits/directional_balance.go)
proves one thing:

```
directional balance = 2 × min(buys, sells) / total,  in basis points
```

Counts only. **No price series, no post-trade window, no oracle.** That restriction is machine
enforced: `scripts/gate.sh` fails if price data appears in the circuit, so the claim cannot drift
back into adverse-selection scoring.

| Property | Value |
|---|---|
| Receipt budget | 32 (`MaxSwaps`) |
| Constraints | 1,601,003 |
| Verifying-key hash | `0x0230047e074d6b8c19ab6714303a3c84412e6dc7a6d540835925f1e08e6f94b8` |
| SDK | `brevis-sdk v0.3.33` |

The circuit emits the observed block range, so the window is attested rather than claimed.

**Minimum sample.** Below 20 observed swaps, standing is *undefined* rather than zero. `N = 20` was
solved for, not chosen: one extra trade should not move the metric more than the depth curve can
resolve, which gives `10000/(N+1) <= 500`, so `N >= 19`. It also fits the 32-receipt budget. The
derivation was written down before any numbers were run.

---

## Trust models behind one interface

`TenureHook` reads `IStandingRegistry` and does not care how standing was established. Two
implementations exist:

| | `TenureRegistry` | `OperatorStandingRegistry` |
|---|---|---|
| Written by | a Brevis ZK callback | the operator |
| Validates | the verifying-key hash, so a proof from another circuit is rejected | operator authority |
| Live on Sepolia | deployed and configured, holds nothing | **in use** |

`expectedVkHash` starts at zero and every callback reverts until an operator sets it. An unset
registry accepts nothing rather than accepting everything, which is the opposite of the published
audit finding this pattern is known for.

**What is live today.** The circuit proves standing and the proof verifies against its verifying
key. No proof has been delivered on chain, so the hook currently points at the operator registry.
The figure it holds is not invented: 9,375 bps over 32 swaps is the balanced fixture's real circuit
output, reproducible with `npm run prove -- balanced`. The full record is in
[`analysis/brevis-gateway-diagnosis.md`](analysis/brevis-gateway-diagnosis.md).

Being able to swap the address and keep the interface is the point of the split, not an excuse for
it. The app names which registry it is reading, on every screen.

---

## Uniswap v4 constraints that shaped the design

These are verified against the pinned v4-core, and each one changed a decision.

| Constraint | Consequence |
|---|---|
| `beforeSwap` fires **before** `_accountPoolBalanceDelta` (`PoolManager.sol:200` vs `:224`) | A hook sees a state prefix, never the current leg. This falsified the predecessor project outright. The design works with the prefix rather than around it. |
| `IMsgSender.msgSender()` is self-reported | Identity comes from an EIP-712 signature instead. |
| `sender` in `beforeSwap` is the locker | The credential binds to the locker, not to an EOA. |
| Transient storage is transaction-scoped | The meter is per transaction, and cross-transaction splitting is disclosed. |
| Return deltas need the matching permission bit mined into the address | The hook's address is mined **without** `BEFORE_SWAP_RETURNS_DELTA`, so it cannot alter execution economics whatever code it contains. The deployed address ends `0080`. |
| Flash accounting is strict | The router settles every currency it touches, or the unlock reverts. |
| `PoolSwapTest` opens its own unlock per swap | It cannot demonstrate the meter, so `TenureSwapRouter` holds one unlock across legs. |

That last row is why a purpose-built router exists. With a per-swap router, a multi-leg route
collapses into separate transactions and the meter never binds, so the splitting demonstration would
silently prove nothing.

---

## Key code pointers

Line numbers, so a reviewer can go straight to the thing being claimed. These are machine checked by
`scripts/check_pointers.py` on every CI run, because `forge fmt` reflows source files and a pointer
that was correct when written drifts silently.

| What | Where |
|---|---|
| Depth enforcement at swap time | `src/TenureHook.sol:235`, `_beforeSwap` |
| Continuous depth curve, no cliffs | `src/TenureHook.sol:192`, `depthFractionBps` |
| Per-transaction depth meter | `src/TenureHook.sol:317`, `_consumedDepth` |
| Credential binding struct | `src/TenureHook.sol:101`, `DepthCredential` |
| Anti-whitelist floor | `src/TenureHook.sol:51`, `BASE_DEPTH_BPS` |
| Fee neutrality, structural | `src/TenureHook.sol:148`, `beforeSwapReturnDelta` |
| Permission set, beforeSwap only | `src/TenureHook.sol:136`, `getHookPermissions` |
| ZK callback with vk-hash validation | `src/TenureRegistry.sol:83`, `handleProofResult` |
| The one question the hook asks | `src/interfaces/IStandingRegistry.sol:16`, `standingOf` |

---

## What each file is for

```
src/
  TenureHook.sol              the mechanism: beforeSwap, the depth curve, the meter
  TenureRegistry.sol          ZK-attested standing, validates the verifying-key hash
  OperatorStandingRegistry.sol  operator-written standing, same interface
  TenureSwapRouter.sol        one unlock, N legs, carries hookData, custodies nothing
  DemoERC20.sol               testnet-only token for the Sepolia pool
  interfaces/IStandingRegistry.sol   standingOf(address)
  lib/BrevisAppZkOnly.sol     Brevis callback base

brevis/
  prover/circuits/directional_balance.go   the production circuit
  prover/cmd/main.go                       prover service, brevis-sdk v0.3.33
  app/src/prove_standing.ts                generate and self-verify a proof
  app/src/test_gateway.ts                  gateway probe

scripts/
  Deploy.s.sol       hook + ZK registry, sets the vk hash and reads it back
  DeployDemo.s.sol   tokens, pool, liquidity, router, operator registry
  VerifyDemo.s.sol   asserts four behaviours against the deployed contracts
  Demo.s.sol         the whole mechanism offline, for recording
  demo.sh            one command that exercises everything
  gate.sh            the claim gate, run at every stage
  check_pointers.py  verifies README file:line pointers still resolve

docs/                the landing page and app served by GitHub Pages
analysis/            evidence, decisions and negative results
```
