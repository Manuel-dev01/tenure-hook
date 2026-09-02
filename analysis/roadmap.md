# Roadmap, remaining work

**Updated 2026-08-30. Stages 1–5 are complete. The mechanism is FROZEN.**

Everything left is documentation, video and submission. If a change would alter mechanism
behaviour it is out of scope, record it here instead of building it.

---

## Where things stand

| | |
|---|---|
| Repo | https://github.com/Manuel-dev01/tenure-hook, public, `main`. **CI was RED from Aug 31 to Sep 2** (unscoped `forge build --sizes` failing on the demo harness) while these notes claimed green; fixed, verify the badge rather than trusting this row |
| Tests | 56 passing, 0 failed, **0 skipped** under `forge test --isolate` |
| Gate | `bash scripts/gate.sh` → GATE PASS |

| stage | outcome |
|---|---|
| 1, hook standalone | done. 15 tests, zero Brevis; submittable on its own with operator-set standing |
| 2, directional-balance circuit | done. S5-verified against real mainnet swap logs |
| 3. ZK registry wired | done. `_vkHash` enforced; N = 20 sample rule adopted |
| 3.5, per-transaction depth meter | done. Closed the splitting hole |
| 4. A/B evidence | done. Splitting buys nothing; LP-benefit claim declined |
| 5, mainnet replay | done. Mechanism live but narrow |

## The outstanding technical item. RESOLVED 2026-08-30

The prover now runs `DirectionalBalanceCircuit`. It has a proving key and a real vk hash:

```
circuit digest 0x0d0d4ebe86cc9ec341bc9b98d94d52bc9b7bfbe67be97ae75a3e71e8f5cd8baa
vk hash        0x0230047e074d6b8c19ab6714303a3c84412e6dc7a6d540835925f1e08e6f94b8
constraints    1,601,003        brevis-sdk v0.3.33
```

**Superseded, do not deploy with these:** under brevis-sdk v0.3.12 the digest was `0x871ee235…`,
the vk hash `0x028f783f…`, constraints 1,583,108. The v0.3.33 upgrade changed the constraint
system, so the old hash would reject every real proof.

Two real proofs generated and verified against real mainnet swap logs from the pinned range, 
a balanced trader (9375 bps) and a one-sided one (0 bps), both matching figures computed
independently from the logs. Full record in `analysis/production-circuit-proof.md`.

**Consequence for Stage 6:** the README can claim the full path rather than disclose a gap.
**Gateway submission now works** (2026-09-02): the blocker was a stale `brevis-sdk` pin, not
registration and not an outage. See `brevis-gateway-diagnosis.md`. What remains untested is the
on-chain leg, pay `sendRequest`, receive the callback.

---

## Stage 6. README, architecture, limitations *(Aug 30)*

- [ ] Architecture section: credential → hook → registry, and where the depth curve lives.
- [ ] Partner integrations with **file:line** pointers (already machine-checked by
      `scripts/check_pointers.py`; keep it passing).
- [ ] **Limitations section**, covering all of:
      EIP-7702 block pinning · router-batched unsigned users sharing a per-transaction bucket ·
      cross-transaction splitting within a block · opening-leg blindness · the on-chain callback
      leg untested (the gateway accepts the query; no proof has landed on a chain).
- [ ] **Impact section leads with volume-weighted mean accessible depth (6721 bps / 67.2%)**, not
      the 1.3% one-sided figure. State the nuance: the 8.8% held near the floor is one-sided actors
      *plus* addresses not yet measurable.
- [ ] **State the two-fixture proof design as evidence**: 17/15 -> 9375 bps and 29/0 -> 0 bps,
      expectations computed from raw logs independently, script exits non-zero on mismatch. A
      verifying proof only shows the circuit ran; two fixtures differing in the predicted direction
      is what makes it evidence. Same S5 logic as the min->max mutation.
- [ ] **Write `scripts/Demo.s.sol`. It does not exist yet.** Must use PRE-GENERATED proofs and show
      verification plus decoded output. Proving takes ~100s, so nothing may prove live on camera.
- [ ] Clone instructions must say **`--recurse-submodules`**, `lib/*` are gitlinks and a plain
      clone will not build.
- [ ] Keep the Roundtrip falsification linked as a documented negative result.

**Done when:** every claim in the README is demonstrable and `gate.sh` passes.

## Stage 7, video *(Aug 31 – Sep 1)*

- [ ] Script ≤ 5:00. **Lead with depth, never with history.**
- [ ] Cover the measured findings, especially that splitting buys nothing, that the mechanism is
      live but narrow (1.3% of volume), and that we decline the LP-benefit claim.
- [ ] Rehearse three answers: *why not a fee dial*, *why not a whitelist*, *why this metric*.
- [ ] **Human audio, no AI voice.** Dry-run the demo so recording is not also debugging.

## Stage 8, checklist and submit *(Sep 2 – 3)*

- [ ] `analysis/submission-checklist.md`, line by line.
- [ ] Logged-out repo check in a private window; video plays logged out.
- [ ] Submit Sep 3 AM; verify the branch in the repo link.

---

## Cut order, fixed in advance, not decided under pressure

1. A/B harness refinements *(drop first)*
2. Operator-configurable sensitivity
3. Multi-window sensitivity → collapse to two windows
4. Staleness/refresh policy → fixed conservative constant
5. Sepolia deployment → local-only demo *(deployment is not required by the rules)*

**Never cut:** `_vkHash` validation · the fail-closed cases · README partner pointers · the
non-exclusion property. Those are binary gates or the pitch itself.

## Contingency, the on-chain callback does not land

The gateway accepts our query as of 2026-09-02. If the paid `sendRequest` leg is not completed or
does not fulfil, the demo is unchanged: proofs are generated locally and verified against the vk,
and the registry's `_vkHash` check is exercised with a pre-generated proof.

**On camera, say only what was measured:** the gateway accepts the query and returns a query key;
the on-chain leg was not run. Do NOT call anything an outage, and do NOT say the circuit needs
registering. Both were written here previously and both were false. See
`brevis-gateway-diagnosis.md`.

## The remaining risk

**Framing drift.** Every artefact must lead with the entitlement. The RFH check found a
fee-discount-on-volume hook already in the directory, if Tenure is heard as that, the 30% is gone
regardless of how well the code works.
