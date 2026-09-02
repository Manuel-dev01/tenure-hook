# Demo runbook — testing and showing the whole product

**One command does all of it:**

```bash
bash scripts/demo.sh
```

19 checks across 8 stages, ~90 seconds. Every stage prints **PASS**, **FAIL**, or **SKIP with a
reason** — a stage that cannot run says so rather than passing quietly, because a silent skip is how
a broken claim survives.

| flag | effect |
|---|---|
| *(none)* | everything that needs no secrets, including live Sepolia reads |
| `--offline` | skip anything touching the network — 10 passed, 3 skipped |
| `--with-proof` | also generate a real ZK proof (needs the prover on `:33247`, ~2 min) |

**It requires no secret of ours.** Stage 6 signs with Anvil's public default key, whose address has
standing written into the demo registry precisely so a stranger can reproduce it. The key holds
nothing and stage 6 only simulates — nothing is broadcast.

Exit code is non-zero if anything failed, so it can gate a recording session: **do not record until
it is green.**

---

## What each stage is actually proving

### 0 · Preflight
Foundry present, **submodules present**, Go present. The submodule check exists because `lib/*` are
gitlinks and a plain `git clone` produces a repo that cannot build — the single most likely way a
judge's first command fails.

### 1 · The contracts build, and the deployable ones fit
`forge build`, then an EIP-170 size check **scoped to `src/`**. The scoping is deliberate: the demo
harness in `scripts/` embeds a whole PoolManager so it can run offline, which puts it far over the
limit and is fine because it is never deployed. Running the unscoped check is what turned CI red for
four commits.

### 2 · The test suite, and the circuit's arithmetic
56 Solidity tests under `--isolate`, and it **fails if any test skipped** — a skip is not a pass, and
without `--isolate` the cross-transaction tests skip rather than run.

Then `go test ./...`, which covers the circuit's arithmetic against a figure computed *outside* the
circuit. This is gated because it once panicked silently through an SDK upgrade while every Foundry
check stayed green.

### 3 · The claim gate
`scripts/gate.sh`: fee parity (no banned identifiers, no dynamic-fee machinery, `beforeSwapReturnDelta:
false`), identity soundness (replay and expiry), scope, and that every README `file:line` pointer
still resolves.

### 4 · The mechanism, end to end, offline
Two traders, same pool, same fee, same 60-unit swap. **One fills, one is capped.** Then the split
attack reverts. Deterministic, no network — this is the narrative spine.

### 5 · A real ZK proof over real mainnet swap logs
Off by default because it needs the prover running. The expected figure is computed from raw logs
**not by the circuit**, and the script exits non-zero on mismatch — so it is a check, not a printout.

### 6 · The deployed contracts on Sepolia
Four configuration reads, then the four behavioural assertions:

```
1. swap at half the allowance   OK
2. over the allowance           reverted ExceedsDepthAllowance
3. split across legs in one tx  reverted DepthExhaustedThisTx
4. unsigned swap at base depth  OK - nobody is excluded
```

**Matched by error selector, not by "it reverted".** A swap can fail for a dozen reasons unrelated to
depth — a bad approval, no liquidity, a price limit — and a check that only tested for failure would
pass for every one of them and prove nothing.

One configuration read is worth pointing at: the hook's address **ends `0080`**. That is
`BEFORE_SWAP` and nothing else. Fee parity is enforced by the deployed address itself, so the hook
cannot alter execution economics whatever its code says.

### 7 · The front end
Three HTTP 200s, and then a check that the app still carries the **operator-written** disclosure. If
that banner ever disappears the script fails with *"do not demo it in this state"*, because the app
would then be implying a ZK delivery that has not happened.

---

## Showing it to a person

Roughly 6 minutes if you talk over it. Order matters — lead with the outcome, then the machinery.

**1. The one-liner.** *"Every address pays the same fee. What you earn is how much of the book you
can reach in one transaction."*

**2. Run `bash scripts/demo.sh`** and talk over stage 4 while it scrolls: two traders, same
everything, one fills and one is capped.

**3. Stop on stage 6.** This is the strongest moment — it is a live public testnet, not a test
harness, and the failures are named by the hook's own errors.

**4. Open the app**, https://manuel-dev01.github.io/tenure-hook/app.html. Connect a wallet and let it
*read*: standing, the depth curve, the allowance. **Do not execute a swap in front of an audience** —
it needs a wallet popup, gas and a confirmation wait, any of which can stall, and stage 6 already
proved the property more rigorously.

**5. Say what is not true**, before being asked:

> *"The ZK path isn't fully live. The circuit proves standing and the proof verifies, but Brevis'
> on-chain delivery service is retired — we paid the fee, the query reached QS_PAID, and their
> aggregation never ran. So standing in the app is operator-written, and the app says so in a banner
> rather than letting you find out."*

That beat is worth more than any of the green checks. Everyone demos what works.

---

## If something is red

| stage | symptom | fix |
|---|---|---|
| 0 | `lib/ is empty` | `git submodule update --init --recursive` |
| 0 | `forge not found` | install Foundry, or `export PATH=$PATH:$HOME/.foundry/bin` |
| 2 | tests skipped | you dropped `--isolate`; the gate treats a skip as a failure |
| 5 | prover not listening | `cd brevis/prover && go run ./cmd/main.go` — first run does a ~3 min setup |
| 6 | on-chain reads fail | public RPC rate limit; set `RPC_URL` to your own endpoint |
| 6 | tranche unset | someone re-deployed the hook without `setDepthTranche`; the hook enforces nothing at tranche 0 |
| 7 | disclosure missing | **stop.** Do not demo or record until the banner is restored |

## Reproducing the deployment from scratch

Not needed to evaluate anything above, but the path exists:

```bash
cp .env.example .env          # add PRIVATE_KEY, fund it on Sepolia
forge script scripts/Deploy.s.sol     --rpc-url $RPC_URL --broadcast   # hook + ZK registry
HOOK=<hook> forge script scripts/DeployDemo.s.sol --rpc-url $RPC_URL --broadcast   # pool, router, tokens
forge script scripts/VerifyDemo.s.sol --rpc-url $RPC_URL                # assert the four behaviours
```

`Deploy.s.sol` sets the circuit's vk hash **and reads it back**, because a deploy log is not
evidence. Total cost on Sepolia was about 0.016 ETH.
