# Roadmap — Aug 25 to Sep 3

Nine days. **Feature freeze is Sep 1 at 12:00**, which is the real deadline; Sep 3 is only
submission. So there are **seven working days**, not nine.

Every day below names a **done condition** — something checkable, not "work on X". Anything without
a done condition is not a plan, it is a hope.

---

## Status entering the roadmap

| | |
|---|---|
| **T1a** | **PASS** — proof generated and verified against vk, twice |
| **T2** | **PASS** — 10/10, all fail-closed cases |
| **T1b** | blocked on a Brevis gateway outage. **Not a gate.** Contingency below |
| Trusted setup | paid, permanent, cached |
| Circuit claim | **decided** — directional balance |
| Progress Update 1 | **NOT FILED — 2 days late** |

---

## The critical path

```
circuit  ->  registry  ->  hook wiring  ->  Sepolia data  ->  demo  ->  video
```

Everything off that line is cuttable. The cut order is fixed in advance, below, so it is not
decided under pressure on Aug 31.

---

## Aug 25 — today

- [ ] **File Progress Update 1.** Two days late. Twenty minutes, no technical component, and the
      substance is now stronger: a cleared capability gate rather than a pending one.
- [ ] Confirm directional balance is not in Brevis's ineligible-metric list.
- [ ] Sketch the circuit's data access: which swap-log fields, how many receipts, which pool.

**Done when:** the update is filed and the circuit's input shape is written down.

## Aug 26 — circuit, and the last switch point

- [ ] Implement the directional-balance circuit in Go, replacing `prover/circuits/circuit.go`.
- [ ] Regenerate keys — seconds, and **no SRS re-download** (content-addressed cache).
- [ ] Record the new `vkHash`.
- [ ] Prove against real mainnet swap data for one address.

**Done when:** a proof verifies for a real address with a real directional-balance output.

> **This is the last honest switch point.** Vigil needs six days and would have five. Past ~Aug 28
> switching is worse than narrowing (§2). If the circuit is not proving by end of Aug 26, narrow its
> claim — do not change projects.

## Aug 27 — registry and hook

- [ ] `TenureRegistry`: `handleProofResult` with **`_vkHash` validated** against the expected hash.
- [ ] Decode circuit output to `(address, balance, window)`; store standing with a timestamp.
- [ ] Promote `TenureGateProbe` into `src/TenureHook.sol` on OZ `uniswap-hooks` `BaseHook`, reading
      the real registry instead of the stub.
- [ ] Staleness policy: standing older than N blocks reverts to base depth.

**Done when:** a Foundry test drives registry → hook → capped swap, and all T2 fail-closed cases
still pass against the real registry.

## Aug 28 — Sepolia

- [ ] **Generate Sepolia trading history early** (§2) — a fresh pool has nothing to prove against.
- [ ] Deploy registry + mined hook; initialise pool; add liquidity.
- [ ] `setVkHash`, then **read `vkHash()` back** to confirm (checklist item, not a deploy-log trust).

**Done when:** a Sepolia pool exists with the hook attached and real history behind it.

## Aug 29 — end to end + sensitivity

- [ ] Full path: prove → callback → registry → signed credential → capped swap on Sepolia.
- [ ] **Sensitivity harness**: directional balance across 2–3 lookback windows, published as a
      table. This is the answer to the strongest attack on the design.

**Done when:** the sensitivity table exists and the end-to-end path has run once.

## Aug 30 — hardening and README

- [ ] README: architecture, one-liner leading with the entitlement, partner integrations with
      **file + line** pointers verified after any refactor.
- [ ] Full suite green: `forge test --isolate`.
- [ ] Buffer for whatever slipped.

**Done when:** README is complete and every claim in it is demonstrable.

## Aug 31 — video preparation

- [ ] Script the ≤5:00 video. Lead with depth, never with history.
- [ ] Rehearse the three answers: *why not a fee dial*, *why not a whitelist*, *why this metric*.
- [ ] Dry-run the demo path so recording is not also debugging.

## Sep 1 — 12:00 FEATURE FREEZE

- [ ] Nothing new after noon. **Record video** (human audio, no AI voice).

## Sep 2 — verification

- [ ] `analysis/submission-checklist.md`, line by line.
- [ ] Logged-out repo check in a private window. Video plays logged out.

## Sep 3 (AM) — submit

- [ ] Submit, verify branch in the repo link.

---

## Cut order — decided now, not under pressure

Cut from the bottom **before** compressing anything above it:

1. A/B harness showing LP outcomes *(should-have, drop first)*
2. Operator-configurable sensitivity *(should-have)*
3. Multi-window sensitivity → collapse to two windows *(keep at least two)*
4. Staleness/refresh policy → fixed conservative constant
5. Sepolia deployment → local-only demo *(deployment is not required by the rules)*

**Never cut:** `_vkHash` validation, the four fail-closed cases, the README partner pointers, the
non-exclusion property. Those are either binary gates or the pitch itself.

## Contingency — if the Brevis gateway stays down

Demo degrades to: proof generated locally, verifier contract deployed, `setVkHash` set, verification
called with a pre-generated proof. **Say on camera that gateway submission was unavailable during
the build window.** No judge penalises a sponsor outage, and deployment is not required by the rules.

## The two risks that actually threaten this

1. **Circuit design time.** Compute is seconds; deciding what to prove and shaping mainnet swap data
   is the real cost, and T1 provides no benchmark for it. This is why Aug 26 is a hard checkpoint.
2. **Framing drift.** Every artefact must lead with the entitlement. The RFH check found a
   fee-discount-on-volume hook already in the directory — if Tenure is heard as that, the 30% is
   gone regardless of how well the code works.
