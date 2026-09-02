# The production circuit, proven end to end

> **SUPERSEDED IN PART, 2026-09-02.** Every figure below has been re-measured against
> **brevis-sdk v0.3.33**; the table now carries the new numbers. The figures originally recorded
> here were produced under v0.3.12, whose vk hash was
> `0x028f783f8de9ae97f93c69536bcc9227fc91cdbd809bef15a8b1a1f2414e3b0b` at 1,583,108 constraints.
> **Do not use that value for `setVkHash`.** Why the SDK moved, and what it unblocked, is in
> `brevis-gateway-diagnosis.md`. Both fixtures reproduce their expected figures exactly under the
> new SDK, which is the point of re-running them rather than assuming.

**2026-08-30.** The gap recorded in the roadmap, *"the ZK round trip is proven with the example
circuit, our circuit's computation is proven by test engine, and the two have never been joined"*, 
**is closed.** They are now joined.

## What runs

`brevis/prover/cmd/main.go` instantiates `&circuits.DirectionalBalanceCircuit{}`. The upstream
example (`circuits.AppCircuit`, a USDC-transfer proof) is retained in `circuits/circuit.go` for
reference, and its setup stays cached, so the T1a gate evidence remains reproducible.

| | production circuit | example circuit (T1a) |
|---|---|---|
| constraints | **1,601,003** | 857,942 |
| public / secret | 6 / 1091 | 6 / 1089 |
| Lagrange size | 2²¹ = 2,097,152 | 2²⁰ = 1,048,576 |
| setup time | **2 m 42.7 s** (cold SRS load) | 13.6 s |
| proving key | 134,252,200 bytes | 67,143,336 bytes |
| circuit digest | `0x0d0d4ebe86cc9ec341bc9b98d94d52bc9b7bfbe67be97ae75a3e71e8f5cd8baa` | `0x0e299aa2…` |
| **vk hash** | **`0x0230047e074d6b8c19ab6714303a3c84412e6dc7a6d540835925f1e08e6f94b8`** | `0x1cb76a97…` |

**That vk hash is the value `setVkHash` takes.** Until now there was none, so the registry's
`_vkHash` check could not be configured for the real circuit.

The constraint count roughly doubling is the expected shape: this circuit runs per-receipt
provenance assertions (pool match, shared log position, topic/data discipline, trader match) plus
filter/count/reduce across 32 receipts, where the example checked a single transfer.

## Two real proofs

Receipts are genuine Uniswap V3 `Swap` logs from the **pinned pre-Pectra range**
(see `pinned-proving-range.md`), pool USDC/WETH 0.05%.

| fixture | trader | buys / sells | expected | **circuit output** | swaps | attested window | prove time |
|---|---|---|---|---|---|---|---|
| balanced | `0x0f4a1d7f…77eca3` | 17 / 15 | 9375 bps | **9375 bps** | 32 | 21126338–21144863 | 176.0 s |
| one-sided | `0x308c6fbd…d75e2a6` | 29 / 0 | 0 bps | **0 bps** | 29 | 21126236–21145773 | 56.8 s |

Proof size 936 bytes in both cases.

**The expected values were computed from raw logs, independently of the circuit.** A verifying proof
is not evidence the circuit computed the right thing. That is the S5 rule, so
`brevis/app/src/prove_standing.ts` compares the decoded output against the hand-derived figure and
exits non-zero on any mismatch. The pair differing in the expected direction (9375 against 0) is
what makes this evidence rather than one data point.

Reproduce:

```bash
cd brevis/prover && go run ./cmd/main.go      # serves :33247, keys load from cache
cd brevis/app    && npm run prove -- balanced
                    npm run prove -- onesided
```

## Three things this surfaced

**1. Receipt indices are mandatory.** `ProofRequest.addReceipt(data, index)`, the index looks
optional in TypeScript, but the prover always pins by it (`sdk/prover/server.go:241`). Omitting it
sends `index: 0` for every receipt and the second one panics with *"an element already pinned at
index 0"*. Any multi-receipt proof must pass distinct indices.

**2. The prover needs an ARCHIVE RPC.** The pinned range is historical, and a non-archive endpoint
answers `cannot get mpt key ... not found` when the SDK fetches receipts and MPT keys. `main.go` now
points at `https://eth.drpc.org`; `publicnode` refuses archive requests without a token.

**3. Custom inputs are how the circuit is parameterised.** `PoolAddress` and `Trader` are struct
fields on the circuit, supplied per proof as JSON and reflected onto it by the prover
(`sdk/prover/assign.go`). Build values with the exported `asUint248`; the `CustomInput` class itself
is declared but **not exported**, and `setCustomInput` takes a plain object it stringifies itself.

## Honest scope

This is **local proving and local verification**. Gateway submission to Sepolia remains blocked by
the gateway declining our unregistered app circuit (measured: `invalid app circuit ... dummy input commitment`), and is not a gate, deployment is not required by
the rules. What is now demonstrated is that the production circuit generates a real, verifying
proof from real mainnet data and outputs exactly the standing figure derived independently from the
logs.

Proving takes ~100 s for 29–32 receipts at 1.58M constraints. If that ever needs reducing, the
honest lever is the `MaxSwaps` receipt budget, not the circuit's logic, and that is a mechanism
parameter, so it would be a disclosure rather than a change.
