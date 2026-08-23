# Roundtrip

A Uniswap v4 hook that reads the PoolManager's transient flash-accounting state at
`beforeSwap` and classifies the composite operation the swap is a leg of — structurally,
while it is still executing, rather than inferring toxicity from statistics after the fact.

**Status: Milestone 0.** The foundational assumption is under test and has not yet been
confirmed. Nothing here prices anything. See `CLAUDE.md` §2 for the go/no-go gate.

## Pinned dependencies

Both are git submodules, pinned to exact commits:

| Dependency | Pin | Commit |
|---|---|---|
| `uniswap/v4-core` | tag `v4.0.0` | `e50237c43811bd9b526eff40f26772152a42daba` |
| `uniswap/v4-periphery` | `main` | `dce236d4e2057422d0791d9a973a58765eb46f65` |
| `foundry-rs/forge-std` | tag `v1.16.2` | `bf647bd6046f2f7da30d0c2bf435e5c76a780c1b` |

Compiled with solc `0.8.26`, `evm_version = "cancun"` — EIP-1153 transient storage is
load-bearing for this project, not incidental.

## Attribution

Slot derivations for the PoolManager's transient state are **imported** from v4-core
(BUSL-1.1), never transcribed — see `src/libraries/TransientDeltaReader.sol`. Test
scaffolding derives from `v4-core/test/utils/Deployers.sol` and
`v4-periphery/test/shared/HookMiner.sol`.
