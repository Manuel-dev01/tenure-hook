# T1 runbook — Brevis round-trip

State as of 2026-08-25. The 3 GiB trusted setup is **downloaded and verified**; everything below is
what remains. Steps 1–3 need no credentials. Step 4 needs a funded Sepolia key.

---

## Done

| Item | State |
|---|---|
| KZG SRS ignition file | **verified** — `~/kzgsrs/kzg_srs_100800000_bn254_MAIN_IGNITION`, 3,225,600,164 bytes, md5 `2abd249241a7fe883379db93530365f8` |
| Go module deps | downloaded |
| `brevis/app` npm deps | installed |
| `brevis/contracts` npm deps | installed, `npx hardhat compile` succeeds (6 contracts) |
| Circuit | compiles — 857,948 constraints |

## Not done

| Item | Blocker |
|---|---|
| Proving/verifying keys | **memory** — see below |
| Local proof generation | needs keys |
| Gateway submission | needs a proof |
| On-chain callback | needs a funded Sepolia key |

---

## The memory blocker

`prover.NewService` → `readOrSetup` → `sdk.Setup` → `srs.NewSRS` does two expensive things:

1. `validateFile` reads the **entire 3 GiB into a `bytes.Buffer`** to MD5 it
   (`brevis-sdk/sdk/srs/srs.go`).
2. `UnsafeReadFrom` parses **all 100.8M G1 points** into memory. At 32 bytes/point on disk
   decompressing to ~64 bytes affine, that is **~6.4 GB** — estimated from the file's
   bytes-per-point ratio, not measured.

Then gnark generates proving/verifying keys for 857,948 constraints on top of that.

Estimated peak **7–10 GB**. Last observed: **0.9 GB available**, 32.8 / 43.8 GB committed. It would
not hard-fail — there is pagefile headroom — but it would thrash for hours and may hit the commit
limit.

**Cheapest fix: reboot before running step 1.** Top processes are all small (~0.3 GB each), so the
usage is spread across many processes and closing a few apps will not recover enough.

---

## Steps

### 1. Generate keys and start the prover
```bash
cd brevis/prover
go run ./cmd/main.go
```
(`make start` in the Makefile wraps exactly this; `make` is not installed on this machine.)

Watch for `size system 857948` then key generation. It listens on **:33247** when ready.

**This is the long, memory-hungry step and it is one-time.** Setup is cached content-addressed at
`~/circuitOut/0x{circuit-digest}/{pk,vk}`, and `readOrSetup` checks that cache *before* touching the
SRS. So a restart is near-instant, and replacing this circuit with Tenure's real one regenerates
keys but **never re-downloads the SRS**.

### 2. Generate a proof
```bash
cd brevis/app
npm run start 0x8a7fc50330533cd0adbf71e1cfb51b1b6bbe2170b4ce65c02678cf08c8b17737
```
That tx hash is upstream's example: a mainnet USDC transfer ≥ 500 USDC. The circuit proves
`(blockNum, account, volume)`. Source chain is mainnet (1), destination Sepolia (11155111).

### 3. Gateway submission
Handled by the same script — `Prover('localhost:33247')` proves locally, then
`Brevis('appsdkv3.brevis.network:443')` submits. **No partner key required.**

### 4. On-chain callback — NEEDS A FUNDED SEPOLIA KEY
```bash
cd brevis/contracts
cp .env.template .env        # then fill in PRIVATE_KEY and SEPOLIA_ENDPOINT yourself
npx hardhat deploy --network sepolia --tags TokenTransferZkOnly
```
Then, before submitting a proof with a callback address:

- read the circuit's `vkHash` from the prover's setup output
- call `setVkHash(vkHash)` on the deployed contract

**This is security-critical, not a formality.** `TokenTransferZkOnly.handleProofResult` does
`require(vkHash == _vkHash, "invalid vk")`. Its `vkHash` starts at zero — leaving it unset means
any proof from any circuit would be accepted. A published audit finding against this exact pattern
records ignoring `_vkHash` as an exploitable bug.

---

## T1 passes when

A `TransferAmountAttested` event is emitted on Sepolia by our deployed contract, carrying our
circuit's output, with `vkHash` set and matching.

Not before. A locally generated proof is **not** the gate — the round trip is.

## If it does not close by Aug 26

Per the go/no-go gate the hard switch is **Aug 28 EOD**, and Vigil needs six days. Treat end of Aug 26
as the real decision point rather than running the clock to the 28th.
