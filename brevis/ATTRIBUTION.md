# Attribution

The contents of this directory are derived from
[`brevis-network/brevis-quickstart-ts`](https://github.com/brevis-network/brevis-quickstart-ts),
cloned 2026-08-23 for UHI10.

The upstream licence is preserved in `LICENSE`.

## Why it is vendored rather than submoduled

Milestone 0 (T1 in the go/no-go gate) uses the upstream example circuit unmodified, to answer one
question: **does the Brevis proof round-trip close end-to-end on testnet?** Vendoring keeps the
exact code that answered that gate visible in this repository's history.

## What is ours vs theirs

Every file authored for Tenure carries a header saying so. Nothing in this directory is claimed as
original work unless its header says otherwise, per the UHI10 binary gate on uncredited code.

**Ours:**

| File | What it is |
|---|---|
| `prover/circuits/directional_balance.go` | the production circuit: directional balance from swap logs only |
| `prover/circuits/directional_balance_s5_test.go` | its test, checking circuit output against a figure computed outside the circuit |
| `app/src/prove_standing.ts` | builds the proof request, proves locally, verifies the decoded output |
| `app/src/test_gateway.ts` | the gateway diagnostic that traced the stale-SDK rejection |
| `app/src/chain_scoped_request.ts` | sets `src_chain_id`, which brevis-sdk-typescript 1.3.1 never does |
| `prover/cmd/main.go` | **modified**, not authored: see the changes table below |
| `prover/go.mod`, `go.sum` | **modified**: SDK bump and restated replace directives |

**Upstream's, unmodified:** `prover/circuits/circuit.go` and `circuit_test.go` (the example circuit,
retained because it closed the T1 round-trip gate), `app/src/index.ts`, `prover/Makefile`,
`prover/configs/`, `LICENSE`, `README.md`, and the app's config and lockfiles.

**An earlier version of this section was written in the future tense** ("the Tenure standing circuit,
when written, ... will be marked accordingly") and was never updated once the circuit existed. Under
its own rule, five files we wrote read as upstream's because they carried no header. Corrected
2026-09-03: the headers were added and the table above replaces the promise.

---

## Our changes to upstream code

| File | Change | Date |
|---|---|---|
| `prover/cmd/main.go` | `RpcURL` swapped from `https://eth.llamarpc.com` (origin returning Cloudflare 521, aborting prover startup after a successful setup) to `https://ethereum-rpc.publicnode.com`, verified responding to `eth_blockNumber`. Marked inline with a `TENURE CHANGE` comment. | 2026-08-25 |
| `prover/cmd/main.go` | RPC moved again to `https://eth.drpc.org`, because the pinned proving range needs an archive endpoint. See the endpoint table below. | 2026-08-30 |
| `prover/cmd/main.go` | Instantiates `DirectionalBalanceCircuit` instead of the upstream example, and adapts to the v0.3.33 API: source RPC moves into `prover.SourceChainConfigs`, `Serve` takes an explicit REST port. | 2026-09-02 |
| `prover/go.mod`, `go.sum` | `brevis-sdk` v0.3.12 to v0.3.33, with `gnark` and `go-ethereum` replace directives restated. | 2026-09-02 |

Everything else under `brevis/` remains upstream's, unmodified.

---

## RPC endpoints, which one serves which purpose, and why

`prover/cmd/main.go` has been changed twice for two *different* reasons. Recording both so the
endpoint is not "corrected" back by someone who remembers only one of them.

| endpoint | verdict |
|---|---|
| `https://eth.llamarpc.com` | **upstream default. Do not restore.** Returned Cloudflare **521** and aborted prover startup *after* a successful setup. The error names its own `zone` as `eth.llamarpc.com`, which reads exactly like a Brevis outage and is not one. |
| `https://ethereum-rpc.publicnode.com` | fixed the 521, and is fine for **recent** blocks. **Not archive-capable**, answers `cannot get mpt key ... not found` for the pinned historical range. |
| `https://eth.drpc.org` | **current setting.** Archive-capable; serves receipts and MPT keys for the pinned pre-Pectra range. |

The trap: the publicnode change was *correct for the 521* and *wrong for historical proving*. A fix
being right for one bug and wrong for a later use is precisely what gets rediscovered painfully.
The proving range is historical by necessity (EIP-7702, see `analysis/pinned-proving-range.md`), so
**the prover's RPC must be archive-capable.**

## SDK version, ours, and why it is not upstream's default

The quickstart template ships `brevis-sdk v0.3.12`. We run **v0.3.33**, and restate its `replace`
directives (`gnark => brevis-network/gnark v0.1.0`, `go-ethereum => celer-network/go-ethereum`) in
`prover/go.mod`, because a replace in a dependency's go.mod is ignored by the go tool.

This is not a gratuitous bump. Brevis document 0.3.17 as the minimum supported version, *"It is not
backward-compatible"*, and below it the gateway rejects every query, because older SDKs hard-code
per-chain dummy input commitments that Brevis has since rotated. The full trace is in
`analysis/brevis-gateway-diagnosis.md`.

`app/src/chain_scoped_request.ts` is ours: brevis-sdk-typescript 1.3.1 never sets `src_chain_id`,
which v0.3.33 requires.

## What is not in this repository

`brevis/contracts/`, the quickstart's Hardhat project, is **not tracked here**. It is upstream
scaffolding for deploying *their* example contract, Tenure does not use it, and it carried
upstream's own Sepolia deployment records, which would have read as ours. It is available in the
[upstream repository](https://github.com/brevis-network/brevis-quickstart-ts).

The one file Tenure needs from it is vendored at `src/lib/BrevisAppZkOnly.sol`, unmodified except
for the pragma and a provenance comment, so the Foundry build does not depend on a Hardhat
dependency tree. That file names its origin in its own header.
