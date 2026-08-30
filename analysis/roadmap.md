# Roadmap — remaining work

**Updated 2026-08-30. Stages 1–5 are complete. The mechanism is FROZEN.**

Everything left is documentation, video and submission. If a change would alter mechanism
behaviour it is out of scope — record it here instead of building it.

---

## Where things stand

| | |
|---|---|
| Repo | https://github.com/Manuel-dev01/tenure-hook — public, `main`, CI green |
| Tests | 56 passing, 0 failed, **0 skipped** under `forge test --isolate` |
| Gate | `bash scripts/gate.sh` → GATE PASS |

| stage | outcome |
|---|---|
| 1 — hook standalone | done. 15 tests, zero Brevis; submittable on its own with operator-set standing |
| 2 — directional-balance circuit | done. S5-verified against real mainnet swap logs |
| 3 — ZK registry wired | done. `_vkHash` enforced; N = 20 sample rule adopted |
| 3.5 — per-transaction depth meter | done. Closed the splitting hole |
| 4 — A/B evidence | done. Splitting buys nothing; LP-benefit claim declined |
| 5 — mainnet replay | done. Mechanism live but narrow |

## The one outstanding technical item

**The prover still runs the upstream example circuit**, not ours —
`brevis/prover/cmd/main.go` instantiates `&circuits.AppCircuit{}`, and `~/circuitOut` holds only the
example's digest.

So `DirectionalBalanceCircuit` has no proving key and **no vk hash**, and `setVkHash` cannot yet be
called with a real value for it. What *is* established: the ZK round trip works (T1a, *example*
circuit) and our circuit's computation is correct (S5, gnark test engine, real logs). The two have
never been joined.

Two acceptable resolutions, and only these:

1. **Wire it** — point `main.go` at `DirectionalBalanceCircuit` and regenerate setup. Fast, because
   the 3 GiB SRS is cached content-addressed; only key generation reruns.
2. **Disclose it** plainly in the README and on camera.

Doing neither is the only wrong answer.

---

## Stage 6 — README, architecture, limitations *(Aug 30)*

- [ ] Architecture section: credential → hook → registry, and where the depth curve lives.
- [ ] Partner integrations with **file:line** pointers (already machine-checked by
      `scripts/check_pointers.py`; keep it passing).
- [ ] **Limitations section**, covering all of:
      EIP-7702 block pinning · router-batched unsigned users sharing a per-transaction bucket ·
      cross-transaction splitting within a block · opening-leg blindness · the missing production
      vk hash · one-sided flow being 1.3% of volume.
- [ ] Clone instructions must say **`--recurse-submodules`** — `lib/*` are gitlinks and a plain
      clone will not build.
- [ ] Keep the Roundtrip falsification linked as a documented negative result.

**Done when:** every claim in the README is demonstrable and `gate.sh` passes.

## Stage 7 — video *(Aug 31 – Sep 1)*

- [ ] Script ≤ 5:00. **Lead with depth, never with history.**
- [ ] Cover the measured findings — especially that splitting buys nothing, that the mechanism is
      live but narrow (1.3% of volume), and that we decline the LP-benefit claim.
- [ ] Rehearse three answers: *why not a fee dial*, *why not a whitelist*, *why this metric*.
- [ ] **Human audio, no AI voice.** Dry-run the demo so recording is not also debugging.

## Stage 8 — checklist and submit *(Sep 2 – 3)*

- [ ] `analysis/submission-checklist.md`, line by line.
- [ ] Logged-out repo check in a private window; video plays logged out.
- [ ] Submit Sep 3 AM; verify the branch in the repo link.

---

## Cut order — fixed in advance, not decided under pressure

1. A/B harness refinements *(drop first)*
2. Operator-configurable sensitivity
3. Multi-window sensitivity → collapse to two windows
4. Staleness/refresh policy → fixed conservative constant
5. Sepolia deployment → local-only demo *(deployment is not required by the rules)*

**Never cut:** `_vkHash` validation · the fail-closed cases · README partner pointers · the
non-exclusion property. Those are binary gates or the pitch itself.

## Contingency — the Brevis gateway is still down

Demo degrades to: proof generated locally, verifier contract deployed, `setVkHash` set, verification
called with a pre-generated proof. **Say on camera that gateway submission was unavailable during
the build window.** A sponsor outage costs nothing when disclosed; hidden and noticed, it costs
Functionality.

## The remaining risk

**Framing drift.** Every artefact must lead with the entitlement. The RFH check found a
fee-discount-on-volume hook already in the directory — if Tenure is heard as that, the 30% is gone
regardless of how well the code works.
