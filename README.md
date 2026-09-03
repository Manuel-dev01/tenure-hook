# Tenure

**A submission to the fair flow frontier: a Uniswap v4 hook where every address pays the same fee,
and proven trading history decides how much of the book you can take in a single transaction.**

Standing is an asset the trader holds, not a property the pool assigns. You are not sorted into a
bracket. You present a credential you earned.

Uniswap Hook Incubator 10 submission. Live on Sepolia, with a front end you can open and swap
through.

| | |
|---|---|
| **App** | https://manuel-dev01.github.io/tenure-hook/app.html |
| **Landing** | https://manuel-dev01.github.io/tenure-hook/ |
| **Run everything** | `bash scripts/demo.sh` |
| **Tests** | 44 passing, 0 skipped |

---

## Contents

[Quick start](#quick-start) · [What is live](#what-is-live) · [What this claims, and what it does
not](#what-this-claims-and-what-it-does-not) · [Impact](#impact-measured-on-15804-real-mainnet-swaps)
· [Limitations](#limitations) · [Partner integrations](#partner-integrations) ·
[Documentation map](#documentation-map) · [Running the tests](#running-the-tests)

**Deeper reading:** [ARCHITECTURE.md](ARCHITECTURE.md) for the design and why each piece is shaped
the way it is. [DEMO.md](DEMO.md) for how to run and verify every claim yourself.

---

## How it works

**1. Prove your history.** A Brevis ZK circuit reads real Uniswap `Swap` logs and proves one number:
directional balance, `2 × min(buys, sells) / total`, in basis points. Counts only. No price series,
no post-trade window, no oracle. That restriction is machine enforced by `scripts/gate.sh`.

**2. Standing is recorded** in a registry the hook reads. Proving takes 57 to 176 seconds, so it
cannot happen inside `beforeSwap`. Standing is attested first and consumed later, never proven at
swap time.

**3. You sign a credential.** An EIP-712 `DepthCredential` binding the router, the pool, a maximum
size, a nonce and a deadline. `beforeSwap` receives the locker, never your address, and
`msgSender()` is self-reported by the router, so identity comes from a signature you control.

**4. The pool caps your size, never your access.** Accessible depth runs linearly from **5%** of the
pool's tranche at zero standing to **100%** at full standing. Continuous and monotonic, with no
brackets and no cliffs.

**5. Splitting buys nothing.** Depth is metered per transaction in transient storage, keyed to the
recovered signer, so signing several credentials and splitting one large take into cap-sized pieces
reverts. Unsigned swaps are metered too, because exempting them would make signing strictly worse
than not signing and the mechanism would run backwards.

---


## Quick start

```bash
git clone --recurse-submodules https://github.com/Manuel-dev01/tenure-hook
cd tenure-hook
bash scripts/demo.sh
```

One command exercises the whole project: build, 44 tests, the circuit's arithmetic, the claim gate,
the offline mechanism demo, the live Sepolia contracts, and the front end. 19 checks, about 90
seconds, and it needs **no secret of ours**. The on-chain stage signs with Anvil's public default
key, whose address has standing written into the demo registry so a stranger can reproduce it.

Every stage prints PASS, FAIL, or SKIP **with a reason**. A stage that cannot run says so rather
than passing quietly.

**`--recurse-submodules` is required.** `lib/*` are gitlinks and a plain clone will not build. If
you already cloned without it: `git submodule update --init --recursive`.

Just the tests:

```bash
forge test --isolate
```

Full walkthrough, including how to swap in the browser: **[DEMO.md](DEMO.md)**.

---

## What is live

A demonstration pool guarded by the hook, on Sepolia, and a UI that talks to it.

| | |
|---|---|
| Hook | [`0x8878dbEB12C6Aba4ab6629DB41238d131e6D0080`](https://sepolia.etherscan.io/address/0x8878dbEB12C6Aba4ab6629DB41238d131e6D0080) |
| Router | [`0xA202C318D22Df67E6C347FC5b98F3d1adDFd3470`](https://sepolia.etherscan.io/address/0xA202C318D22Df67E6C347FC5b98F3d1adDFd3470) |
| Standing registry | [`0x2fA2242c80F7a7a7690cF0a36a19FcFf70709AaA`](https://sepolia.etherscan.io/address/0x2fA2242c80F7a7a7690cF0a36a19FcFf70709AaA) |
| ZK registry | [`0x03F05F1c89b9725F2AD775Aed85F60DD38af19B5`](https://sepolia.etherscan.io/address/0x03F05F1c89b9725F2AD775Aed85F60DD38af19B5) |
| Pool | `tETH / tUSD`, fee 0.30%, tranche 250,000 |

**The hook address ends `0080`.** That is the permission bitmap, mined into the address with
CREATE2: `beforeSwap` and nothing else, with no `BEFORE_SWAP_RETURNS_DELTA`. The hook does not
decline to change your fee. It cannot.

Four behaviours are asserted against those deployed contracts, matched by **error selector** rather
than by "it reverted", because a swap can fail for a dozen reasons unrelated to depth:

```
forge script scripts/VerifyDemo.s.sol --rpc-url $RPC_URL

1. swap at half the allowance   OK
2. over the allowance           reverted ExceedsDepthAllowance
3. split across legs in one tx  reverted DepthExhaustedThisTx
4. unsigned swap at base depth  OK, nobody is excluded
```

(3) is the splitting attack and (4) is the anti-whitelist property. Those are the two properties
most easily lost in a refactor, so they are asserted on chain rather than assumed.

**What is not live: delivery, and only delivery.** The Brevis gateway is holding a finished, correct
result for our paid query. It decodes through the deployed registry's own `decodeOutput`, so you can
check it without trusting us:

```bash
RPC=https://ethereum-sepolia-rpc.publicnode.com
REG=0x03F05F1c89b9725F2AD775Aed85F60DD38af19B5
OUT=0x308c6fbd6a14881af333649f17f2fde9cd75e2a60000001d0000000001425c5c000000000142a8ad

cast call $REG \
  'decodeOutput(bytes)(address,uint16,uint16,uint64,uint64)' \
  $OUT --rpc-url $RPC

0x308C6fbD6a14881Af333649f17f2FdE9cd75e2a6   # trader
0                                            # balanceBps
29                                           # swapCount
21126236                                     # fromBlock
21145773                                     # toBlock
```

`OUT` is the `circuit_output` field of the gateway's `GetQueryStatus` response for the query we paid
for on Sepolia, and it matches the one-sided fixture's hand-computed expectation exactly. The proof
is generated and the output is correct. What has not happened is Brevis submitting the aggregated
proof on chain, so `brevisCallback` never fired.

**This is not specific to the chain we chose.** Every BrevisRequest deployment Brevis documents was
surveyed: Arbitrum, both Sepolia deployments, Optimism and BSC Testnet, plus BrevisProof on Arbitrum
and Sepolia. All are unpaused with active provers registered. All show zero events over windows of
up to 4,000,000 blocks, except ours, which shows exactly one: our own payment. The table, the
control that makes an empty result mean empty, and the two limits on that claim are in
[`analysis/brevis-gateway-diagnosis.md`](analysis/brevis-gateway-diagnosis.md).

Because delivery is outstanding, standing in the app is written by the operator registry, the second
trust model behind the same interface. The figure it holds is not invented either: 9,375 bps over 32
swaps is the *balanced* fixture's real circuit output, reproducible with `npm run prove -- balanced`.
The app names which registry it reads, on every screen.

If the callback ever fires it will record **0 bps for `0x308c6fbd...`**, the one-sided fixture, not
9,375 for the balanced one. Two different fixtures, two different addresses, and the paid query is
the one-sided one. Full record, including a measurement error we made and retracted:
[`analysis/brevis-gateway-diagnosis.md`](analysis/brevis-gateway-diagnosis.md).

---


## What this claims, and what it does not

> The mechanism gates atomic depth by proven directional balance, **the gate binds**, and **it
> cannot be split around**. Restraint costs fee income proportionally. **We do not claim to improve
> LP outcome**, because a closed sandbox cannot know where price goes after the informed flow, and
> any reference price we chose would determine the sign of the result.

The three-arm A/B in [`analysis/lp-outcome.md`](analysis/lp-outcome.md) establishes the first two
together:

| comparison | what it proves |
|---|---|
| arm A vs arm B | the cap **binds**. Informed take falls from 80.00 to 5.00. |
| arm B vs arm C | the cap **cannot be routed around**. The split attack realises byte-identical volume, fees and inventory. |

That pairing is the point. A cap that binds but can be routed around is cosmetic, so both halves
are measured, and the second is measured against the one attack that would defeat it.

**On the benefit claim.** Valuing the arms at a single reference price flips the sign of the result:
tranching looks harmful at P = 0.98 and beneficial at P = 1.02. Valuing at the unconstrained arm's
own final price is worse than arbitrary, because it is biased toward that arm by construction. So no
LP value figure is reported, and the sensitivity is published instead.

---

## Impact, measured on 15,804 real mainnet swaps

Replayed against the pinned range on the USDC/WETH 0.05% pool
([`analysis/mainnet-replay.md`](analysis/mainnet-replay.md)). Every figure is counted from logs.
None requires a counterfactual.

| measure | value |
|---|---|
| **volume-weighted mean accessible depth** | **6721 bps, 67.2% of the tranche** |
| swap-weighted mean accessible depth | 5984 bps, 59.8% |
| floor (no standing) | 500 bps |

**The average dollar on this pool moves at roughly two-thirds of the tranche, while the average
address sits near the floor.** Depth tracks proven behaviour, not headcount. That gap is the
mechanism doing its job.

### Who the restraint actually falls on, including people we did not aim at

8.8% of volume sits in the lowest depth band. That is not one population, and the distinction
matters:

| group | share of volume | is this the target? |
|---|---|---|
| measured, and one-sided | 1.3% | **yes** |
| not enough history to be measured | about 7.5% | **no** |

The second group's only characteristic is being new to this pool. They are **not excluded**. They
trade at base depth like every unsigned swapper, and standing is permissionlessly acquirable by
trading two-sidedly. But they pay part of the cost of a mechanism aimed at someone else, and that is
the honest price of requiring evidence before granting depth.

**This compounds with tranche sizing.** An operator who sets the tranche too low pushes more
ordinary flow into that same floor. At a 500,000 USDC tranche, base depth blocks **20.8%** of
long-tail swaps. Below that it gets worse: **28.5%** at 250,000 and **42.5%** at 100,000. The median
long-tail swap is 3,563 USDC. The two caveats are one point. The cost of the mechanism lands partly
on people it is not aimed at, and a badly sized tranche makes that worse.

---

## Limitations

Every one we know of, stated here rather than left to be found.

| Limitation | Detail |
|---|---|
| **No proof has landed on chain** | Every step we own works: the circuit proves standing, the proof verifies against its verifying key, the gateway accepts the query, the fee is paid on Sepolia, and the gateway holds a correct decodable result for it. Brevis never submitted the aggregated proof, so the callback never fired and standing in the app is operator-written. No BrevisRequest deployment we could reach shows any fulfilment traffic, so this is not specific to the chain we chose. [Record](analysis/brevis-gateway-diagnosis.md). |
| **Proof fixtures use a historical block range** | `brevis-sdk v0.3.12` could not build receipt proofs for blocks containing EIP-7702 transactions, so the fixtures are cut from a pinned pre-Pectra range anchored at block 21,146,236. v0.3.33 pins a go-ethereum fork that does parse type 4, so the constraint is probably lifted, but the fixtures were never re-cut and we do not claim it is fixed. [Detail](analysis/pinned-proving-range.md). |
| **Cross-transaction splitting still evades the cap** | Transient storage is transaction-scoped, so it clears between transactions. This costs gas and gives up atomicity. |
| **Router-batched unsigned users share one bucket** | Any of them can sign a zero-standing credential, which is free and permissionless, to isolate themselves. |
| **Opening-leg blindness** | `beforeSwap` fires before delta accounting, so the hook never sees the first leg of a composite operation. This is a v4 property, not a defect in the hook. |
| **No LP outcome claim** | See [above](#what-this-claims-and-what-it-does-not). |
| **One address holds standing on the demo pool** | A fresh wallet gets base depth, which is the correct behaviour and is what the app shows. |

---

## Partner integrations

**Brevis is the one partner integration, and it is running code.** The circuit is written and
compiles to 1,601,003 constraints. It proves standing from real Ethereum mainnet swap logs, and the
proof verifies against its verifying key. The verifying-key hash is set on the deployed Sepolia
registry, which enforces it on every callback. Two fixtures were proved and each matched a figure
computed from the raw logs outside the circuit. What is not complete is the last leg, Brevis
delivering the aggregated proof on chain. Detail, with transaction hashes:
[`analysis/brevis-gateway-diagnosis.md`](analysis/brevis-gateway-diagnosis.md).

| Partner | Where | What it does |
|---|---|---|
| **Brevis** | [`brevis/prover/circuits/directional_balance.go`](brevis/prover/circuits/directional_balance.go) | the production circuit, proving directional balance from swap logs only |
| **Brevis** | [`brevis/prover/cmd/main.go`](brevis/prover/cmd/main.go) | prover service, instantiates the production circuit |
| **Brevis** | [`brevis/app/src/prove_standing.ts`](brevis/app/src/prove_standing.ts) | builds the proof request, proves locally, verifies the decoded output |
| **Brevis** | [`brevis/app/src/chain_scoped_request.ts`](brevis/app/src/chain_scoped_request.ts) | scopes the query to a source chain, which the TypeScript SDK never sets |
| **Brevis** | `src/TenureRegistry.sol:83` | `handleProofResult`, the ZK callback, with `_vkHash` validated |
| **Brevis** | `src/lib/BrevisAppZkOnly.sol:9` | vendored `BrevisAppZkOnly` callback base |

What each of those does, in order, and where the flow stops:

```
directional_balance.go   circuit over mainnet swap logs        written, 1,601,003 constraints
prove_standing.ts        prove locally, verify against the vk   two fixtures, both match
chain_scoped_request.ts  submit to the Brevis gateway           accepted, query key returned
BrevisRequest.sendRequest pay for fulfilment on Sepolia         paid, tx 0xd5f1a81b, fee 0
Brevis gateway            hold the finished result               QS_PAID, output correct and decodable
TenureRegistry.sol:83    brevisCallback records standing        never fired
```

The registry is deployed with the verifying-key hash enforced, so it is ready for that callback.
`expectedVkHash` starts at zero and every callback reverts until it is set, which makes an unset key
fail closed rather than accept a proof from any circuit.

### Dependencies

Not partners, listed separately so the table above is not padded.

| Dependency | Where | What it does |
|---|---|---|
| **Uniswap v4** | `src/TenureHook.sol:235` | `_beforeSwap` enforcing the depth entitlement |
| **Uniswap v4** | `src/TenureHook.sol:136` | `getHookPermissions`, beforeSwap only, no fee power |
| **OpenZeppelin** | `src/TenureHook.sol:37` | `uniswap-hooks` v1.0.0 `BaseHook` |

Uniswap v4 is the base protocol this is built on rather than an integration, and OpenZeppelin is a
library dependency. Neither is a UHI10 sponsor.

These `file:line` pointers are **machine checked** on every CI run by `scripts/check_pointers.py`,
because `forge fmt` reflows source files and a pointer that was correct when written drifts
silently.

Attribution for vendored upstream code, and which files are ours versus upstream's:
[`brevis/ATTRIBUTION.md`](brevis/ATTRIBUTION.md). The circuit, the prover entrypoint's configuration
and the proving script are ours. The surrounding scaffolding is upstream's quickstart.

---

## Documentation map

| Document | What it is for |
|---|---|
| [ARCHITECTURE.md](ARCHITECTURE.md) | the design, the two flows, and the v4 constraints that shaped them |
| [DEMO.md](DEMO.md) | run and verify every claim yourself |
| [VERIFY.md](VERIFY.md) | the verification protocol used at every stage of the build |
| [`analysis/mainnet-replay.md`](analysis/mainnet-replay.md) | the impact figures, on 15,804 real swaps |
| [`analysis/lp-outcome.md`](analysis/lp-outcome.md) | the three-arm A/B, and why no LP value figure is reported |
| [`analysis/sensitivity.md`](analysis/sensitivity.md) | the reference-price sensitivity that made us decline the claim |
| [`analysis/production-circuit-proof.md`](analysis/production-circuit-proof.md) | the circuit's real outputs, both fixtures |
| [`analysis/brevis-gateway-diagnosis.md`](analysis/brevis-gateway-diagnosis.md) | what is and is not live in the ZK path, and two wrong explanations we published first |
| [`analysis/minimum-sample-decision.md`](analysis/minimum-sample-decision.md) | why N = 20, derived before any numbers were run |
| [`analysis/pinned-proving-range.md`](analysis/pinned-proving-range.md) | why the fixtures use a historical block range |
| [`brevis/ATTRIBUTION.md`](brevis/ATTRIBUTION.md) | what is ours and what is upstream's |

---

## Running the tests

```bash
forge test --isolate
```

44 tests across four suites, zero skipped.

| Suite | Tests | What it proves |
|---|---|---|
| `TenureHookTest` | 21 | the depth entitlement, credential binding, fee neutrality, and the per-transaction meter |
| `TenureRegistryTest` | 10 | `_vkHash` validation and the minimum-sample rule |
| `TenureIdentityTest` | 10 | identity binding and all fail-closed cases |
| `LPOutcomeTest` | 3 | the three-arm A/B and its own mutation checks |

`--isolate` is required for the cross-transaction meter tests. Without it they skip loudly rather
than passing vacuously, and the gate treats a skip as a failure.

### Pinned dependencies

| Dependency | Pin | Commit |
|---|---|---|
| `uniswap/v4-core` | tag `v4.0.0` | `e50237c43811bd9b526eff40f26772152a42daba` |
| `uniswap/v4-periphery` | `main` | `dce236d4e2057422d0791d9a973a58765eb46f65` |
| `foundry-rs/forge-std` | tag `v1.16.2` | `bf647bd6046f2f7da30d0c2bf435e5c76a780c1b` |
| `OpenZeppelin/uniswap-hooks` | tag `v1.0.0` | `1db96464698ee567521bd2dd65833ff1e1864ac7` |
| `brevis-network/brevis-sdk` | `v0.3.33` | Brevis document 0.3.17 as the minimum supported version |

`uniswap-hooks` is pinned to v1.0.0 rather than latest, because v1.2.x imports `SwapParams` from
`v4-core/src/types/PoolOperation.sol`, which does not exist in our pinned v4-core `v4.0.0`.

solc `0.8.26`, `evm_version = "cancun"`.

### Attribution

Test scaffolding derives from `v4-core/test/utils/Deployers.sol` and
`v4-periphery/test/shared/HookMiner.sol`. The transient-delta reader in `test/probe/` **imports**
v4-core's slot derivations rather than transcribing them. Brevis code under `brevis/` is upstream's.
See [`brevis/ATTRIBUTION.md`](brevis/ATTRIBUTION.md).
