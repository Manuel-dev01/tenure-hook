# Attribution

The contents of this directory are derived from
[`brevis-network/brevis-quickstart-ts`](https://github.com/brevis-network/brevis-quickstart-ts),
cloned 2026-08-23 for UHI10.

The upstream licence is preserved in `LICENSE`.

## Why it is vendored rather than submoduled

Milestone 0 (T1 in `CLAUDE.md` §2) uses the upstream example circuit unmodified, to answer one
question: **does the Brevis proof round-trip close end-to-end on testnet?** Vendoring keeps the
exact code that answered that gate visible in this repository's history.

## What is ours vs theirs

At the time of the T1 gate, **everything here is upstream's**. Any file authored for Tenure carries
a header saying so. The Tenure standing circuit, when written, replaces
`prover/circuits/circuit.go` and will be marked accordingly.

Per the UHI10 binary gate on uncredited code: nothing in this directory is claimed as original work
unless its header says otherwise.
