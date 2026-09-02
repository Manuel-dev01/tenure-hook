# T1 runbook — Brevis round-trip

**Updated 2026-08-30. T1a PASSED — this runbook is now largely a record, not a to-do list.**

The 3 GiB trusted setup is downloaded and verified, keys were generated in 13.6 seconds, and a proof
was generated and verified against the vk twice. What remains is the on-chain callback, blocked on a
the gateway rejecting our unregistered app circuit (see below) and a funded Sepolia key.

**Important scope note:** everything below was done with the **upstream example circuit**, which is
what closed the T1a round-trip gate. The production circuit `DirectionalBalanceCircuit` was wired
separately on Aug 30 and has its own keys, vk hash and verified proofs — see
`analysis/production-circuit-proof.md`.

---

## Done

| Item | State |
|---|---|
| KZG SRS ignition file | **verified** — `~/kzgsrs/kzg_srs_100800000_bn254_MAIN_IGNITION`, 3,225,600,164 bytes, md5 `2abd249241a7fe883379db93530365f8` |
| Go module deps | downloaded |
| `brevis/app` npm deps | installed |
| `brevis/contracts` npm deps | installed, `npx hardhat compile` succeeds (6 contracts) |
| Circuit (example) | compiles — 857,942 constraints |
| **Setup / keys** | **DONE — 13.6s.** pk 67,143,336 bytes, vk 34,368 bytes, cached content-addressed |
| **Local proof generation** | **DONE — generated and verified against the vk, twice** |
| **vk hash (example circuit)** | `0x1cb76a97800eca38048ce06ba3199638113b0218e56ed9c9b212fbedbd8a79fc` |

## Not done

| Item | Blocker |
|---|---|
| Gateway submission | **Not wired — our gap, not Brevis's.** The gateway is reachable and rejects the query: `invalid app circuit chain 1 dummy input commitment 0x127d5d80...`. Brevis routes only registered app circuits and we did not complete that onboarding. An earlier `RST_STREAM` against the upstream EXAMPLE circuit was a separate, possibly transient failure; the two were conflated. **Not a gate.** |
| On-chain callback | the gateway rejection above, plus a funded Sepolia key |
| ~~Production circuit setup~~ | **DONE Aug 30** — `cmd/main.go` now runs `DirectionalBalanceCircuit`; vk hash `0x028f783f…4e3b0b` |

---

## The memory blocker — RESOLVED

> **Resolved 2026-08-25 by a reboot.** Peak RSS was **4.78 GB**, not the 7–10 GB estimated below;
> the estimate was high. Setup then completed in 13.6 seconds. Kept for the record because the
> reasoning about `validateFile` and `UnsafeReadFrom` is still accurate, and because setup is
> content-addressed — swapping in a new circuit regenerates keys but never re-downloads the SRS.

### Original analysis

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

## Historical note

The switch-to-Vigil decision this section once described is **closed**. T1a passed on Aug 25 and
Vigil was abandoned. Nothing here should be read as a live decision.
