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

At the time of the T1 gate, **everything here is upstream's**. Any file authored for Tenure carries
a header saying so. The Tenure standing circuit, when written, replaces
`prover/circuits/circuit.go` and will be marked accordingly.

Per the UHI10 binary gate on uncredited code: nothing in this directory is claimed as original work
unless its header says otherwise.

---

## Our changes to upstream code

| File | Change | Date |
|---|---|---|
| `prover/cmd/main.go` | `RpcURL` swapped from `https://eth.llamarpc.com` (origin returning Cloudflare 521, aborting prover startup after a successful setup) to `https://ethereum-rpc.publicnode.com`, verified responding to `eth_blockNumber`. Marked inline with a `TENURE CHANGE` comment. | 2026-08-25 |

Everything else under `brevis/` remains upstream's, unmodified.

---

## RPC endpoints — which one serves which purpose, and why

`prover/cmd/main.go` has been changed twice for two *different* reasons. Recording both so the
endpoint is not "corrected" back by someone who remembers only one of them.

| endpoint | verdict |
|---|---|
| `https://eth.llamarpc.com` | **upstream default. Do not restore.** Returned Cloudflare **521** and aborted prover startup *after* a successful setup. The error names its own `zone` as `eth.llamarpc.com`, which reads exactly like a Brevis outage and is not one. |
| `https://ethereum-rpc.publicnode.com` | fixed the 521, and is fine for **recent** blocks. **Not archive-capable** — answers `cannot get mpt key ... not found` for the pinned historical range. |
| `https://eth.drpc.org` | **current setting.** Archive-capable; serves receipts and MPT keys for the pinned pre-Pectra range. |

The trap: the publicnode change was *correct for the 521* and *wrong for historical proving*. A fix
being right for one bug and wrong for a later use is precisely what gets rediscovered painfully.
The proving range is historical by necessity (EIP-7702, see `analysis/pinned-proving-range.md`), so
**the prover's RPC must be archive-capable.**
