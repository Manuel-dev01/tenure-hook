# Running and verifying Tenure

Everything here can be checked without trusting us. Nothing in this file requires a key of ours, and
the on-chain stage signs with a public test key so you can reproduce it yourself.

**Contents**

1. [One command](#one-command)
2. [What each stage proves](#what-each-stage-proves)
3. [Try it in the browser](#try-it-in-the-browser)
4. [Check the contracts yourself](#check-the-contracts-yourself)
5. [Generate a real ZK proof](#generate-a-real-zk-proof)
6. [Redeploy from scratch](#redeploy-from-scratch)
7. [Troubleshooting](#troubleshooting)

---

## One command

```bash
git clone --recurse-submodules https://github.com/Manuel-dev01/tenure-hook
cd tenure-hook
bash scripts/demo.sh
```

19 checks across 8 stages, about 90 seconds. Every stage prints **PASS**, **FAIL**, or **SKIP with a
reason**. A stage that cannot run says so rather than passing quietly, because a silent skip is how a
broken claim survives.

| flag | effect |
|---|---|
| *(none)* | everything that needs no secrets, including live Sepolia reads |
| `--offline` | skips anything touching the network: 10 passed, 3 skipped |
| `--with-proof` | also generates a real ZK proof, which needs the prover running |

`--recurse-submodules` is required. `lib/*` are gitlinks and a plain clone will not build. If you
already cloned without it, run `git submodule update --init --recursive`.

Expected tail:

```
SUMMARY   19 passed · 0 failed · 1 skipped
```

The exit code is non-zero if anything failed.

---

## What each stage proves

**0. Preflight.** Foundry present, submodules present, Go present. The submodule check exists
because a plain `git clone` produces a repo that cannot build, which is the most likely way a first
command fails.

**1. Build and contract sizes.** `forge build`, then an EIP-170 size check scoped to `src/`. The
scoping is deliberate: the demo harness in `scripts/` embeds a whole PoolManager so it can run
offline, which puts it far over the limit and is fine because it is never deployed.

**2. Tests.** 44 Solidity tests under `--isolate`, and the stage fails if any test **skipped**. A
skip is not a pass, and without `--isolate` the cross-transaction tests skip rather than run. Then
`go test ./...`, which covers the circuit's arithmetic against a figure computed outside the circuit.

**3. The claim gate.** `scripts/gate.sh` checks fee parity (no banned identifiers, no dynamic-fee
machinery, `beforeSwapReturnDelta: false`), identity soundness (replay and expiry), scope, and that
every README `file:line` pointer still resolves.

**4. The mechanism, offline.** Two traders, same pool, same fee, same 60-unit swap. One fills, one is
capped. Then the split attack reverts. Deterministic, no network.

**5. A real ZK proof.** Off by default because it needs the prover running. The expected figure is
computed from raw logs and not by the circuit, and the script exits non-zero on mismatch, so it is a
check rather than a printout.

**6. The deployed contracts.** Four configuration reads, then the four behavioural assertions below.

**7. The front end.** Three HTTP 200s, plus a check that the app still carries its trust-model
disclosure. If that disappears the stage fails with "do not demo it in this state", because the app
would then be implying a delivery that has not happened.

---

## Try it in the browser

| | |
|---|---|
| Landing | https://manuel-dev01.github.io/tenure-hook/ |
| App | https://manuel-dev01.github.io/tenure-hook/app.html |

The app is readable with no wallet installed. Every figure on it is read live from Sepolia.

To swap, connect a wallet on **Sepolia** and press **Get demo tokens**, which mints 500,000 test
tokens to you. Then use the three preset buttons, which size themselves from whatever your address
can actually take:

| preset | what happens |
|---|---|
| **fills** | the swap executes |
| **exceeds the cap** | reverts with `ExceedsDepthAllowance`, named in the panel |
| **exhausts the meter** | splits into two legs, each inside the cap, and the second reverts `DepthExhaustedThisTx` |

The presets exist because those amounts depend on your standing. A fresh wallet has base depth
(12,500) while a wallet with standing recorded has more, so a fixed number could only ever work for
one of them.

**Swap unsigned** presents no credential at all. It still executes, at base depth, which is the
anti-whitelist property: the mechanism caps size and never denies access. Note that unsigned swaps
recover `address(0)`, so they are capped at base depth no matter whose wallet is connected.

Reverts are simulated before anything is broadcast, so being rejected costs a signature and no gas.

---

## Check the contracts yourself

| | |
|---|---|
| Hook | [`0x8878dbEB12C6Aba4ab6629DB41238d131e6D0080`](https://sepolia.etherscan.io/address/0x8878dbEB12C6Aba4ab6629DB41238d131e6D0080) |
| Router | [`0xA202C318D22Df67E6C347FC5b98F3d1adDFd3470`](https://sepolia.etherscan.io/address/0xA202C318D22Df67E6C347FC5b98F3d1adDFd3470) |
| Standing registry | [`0x2fA2242c80F7a7a7690cF0a36a19FcFf70709AaA`](https://sepolia.etherscan.io/address/0x2fA2242c80F7a7a7690cF0a36a19FcFf70709AaA) |
| ZK registry | [`0x03F05F1c89b9725F2AD775Aed85F60DD38af19B5`](https://sepolia.etherscan.io/address/0x03F05F1c89b9725F2AD775Aed85F60DD38af19B5) |
| Pool | `tETH / tUSD`, fee 0.30%, tranche 250,000 |

**The hook address ends `0080`.** That is the permission bitmap, mined into the address with CREATE2:
`beforeSwap` and nothing else, with no `BEFORE_SWAP_RETURNS_DELTA`. Fee parity is enforced by the
address itself, so the hook cannot alter execution economics whatever code it contains.

Four behaviours are asserted against those deployed contracts:

```bash
forge script scripts/VerifyDemo.s.sol --rpc-url https://ethereum-sepolia-rpc.publicnode.com

1. swap at half the allowance   OK
2. over the allowance           reverted ExceedsDepthAllowance
3. split across legs in one tx  reverted DepthExhaustedThisTx
4. unsigned swap at base depth  OK, nobody is excluded
```

Each is matched by the specific **error selector**, not by "something reverted". A swap can fail for
a dozen reasons unrelated to depth, and a check that only tested for failure would pass for every one
of them.

This needs no key of ours. It signs with Anvil's public default key, whose address has standing
written into the demo registry precisely so a stranger can reproduce it. The key holds nothing and
the script only simulates.

Read the configuration directly if you prefer:

```bash
RPC=https://ethereum-sepolia-rpc.publicnode.com
HOOK=0x8878dbEB12C6Aba4ab6629DB41238d131e6D0080

cast call $HOOK 'registry()(address)' --rpc-url $RPC
cast call $HOOK 'BASE_DEPTH_BPS()(uint256)' --rpc-url $RPC
cast call $HOOK 'depthFractionBps(uint256)(uint256)' 9375 --rpc-url $RPC
```

---

## Generate a real ZK proof

```bash
cd brevis/prover && go run ./cmd/main.go     # first run does a one-time setup
cd brevis/app && npm install
npm run prove -- balanced                     # 17 buys / 15 sells -> 9375 bps
npm run prove -- onesided                     # 29 buys / 0 sells  -> 0 bps
```

Two fixtures, not one. A verifying proof only shows the circuit ran; two fixtures differing in the
predicted direction is what makes it evidence. Both expected figures are computed from raw logs
independently of the circuit, and the script exits non-zero on mismatch.

The first prover start downloads a 3 GiB trusted setup and generates keys, which takes a few
minutes. It is content-addressed and cached, so restarts are fast.

---

## Redeploy from scratch

Not needed to evaluate anything above, but the path exists.

```bash
cp .env.example .env      # add PRIVATE_KEY, fund it with Sepolia ETH

forge script scripts/Deploy.s.sol --rpc-url $RPC_URL --broadcast
HOOK=<hook address> forge script scripts/DeployDemo.s.sol --rpc-url $RPC_URL --broadcast
forge script scripts/VerifyDemo.s.sol --rpc-url $RPC_URL
```

`Deploy.s.sol` sets the circuit's verifying-key hash **and reads it back**, because a deploy log is
not evidence. `expectedVkHash` starts at zero and every callback reverts until it is set, so setting
it wrong is worse than not deploying. Total cost on Sepolia was about 0.016 ETH.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `lib/ is empty` | `git submodule update --init --recursive`. **`--recursive` is not optional:** `remappings.txt` maps `solmate/` into `lib/v4-core/lib/solmate`, a submodule of v4-core, so a non-recursive init builds `src/` but fails the tests. |
| `Source "lib/v4-core/lib/solmate/..." not found` | Same cause. The nested submodule was not fetched. |
| Windows: `Filename too long` during clone | Clone to a short path such as `C:\src`. The recursive fetch nests to `lib/uniswap-hooks/lib/v4-core/lib/forge-std/...`, which exceeds the 260-character limit from a deep directory. Reproduced; it is a Windows path limit, not a repository problem. `git config --global core.longpaths true` also works. |
| Downloaded as a ZIP rather than cloned | The ZIP has no `lib/`, so nothing builds. Clone instead. The claim gate degrades gracefully outside git and says so, rather than failing on `git ls-files`. |
| `forge not found` | Install Foundry, or `export PATH=$PATH:$HOME/.foundry/bin` |
| Tests reported as skipped | You dropped `--isolate`. The gate treats a skip as a failure. |
| Prover not listening on :33247 | `cd brevis/prover && go run ./cmd/main.go`. The first run does a setup of a few minutes. |
| On-chain reads fail | Public RPC rate limit. Set `RPC_URL` to your own endpoint. |
| App shows "Could not load the app" | The RPC or `deployments.json` could not be read. Reload, or check the network. |
| Swap says "Token approval missing" | Retry. The app requests an approval before the swap. |
| Swap says "Not enough demo tokens" | Press **Get demo tokens** on the Standing tab. |
