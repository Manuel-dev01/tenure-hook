# Submission checklist — Sep 2/3

**Updated 2026-08-30.** Three checks that were manual are now machine-enforced, in both
`scripts/gate.sh` and CI. Run `bash scripts/gate.sh` first; it covers everything marked *(auto)*.
The manual wording is kept so the check survives the script being wrong.

## Automated — `bash scripts/gate.sh` must exit 0

- [ ] *(auto)* `forge fmt --check` clean
- [ ] *(auto)* `forge test --isolate` — **0 failed and 0 skipped.** A skip is not a pass; without
      `--isolate` the cross-transaction tests silently skip
- [ ] *(auto)* `scripts/check_pointers.py` — every README `file:line` pointer resolves to the symbol
      named beside it. `forge fmt` reflows sources and drifts these silently
- [ ] *(auto)* no banned identifiers in `src/`
- [ ] *(auto)* no dynamic-fee machinery in `src/`
- [ ] *(auto)* hook declares `beforeSwapReturnDelta: false`
- [ ] *(auto)* circuit contains no price/oracle reference
- [ ] CI green on the pushed commit

Line items, not runbook steps. Each is something that can be silently skipped in a rush and cost
either the submission or a question on stage. Tick nothing from memory.

---

## Security — must be verified on the deployed contract

- [ ] **`setVkHash` has been called and returns the circuit's real vk hash.**
      `vkHash` initialises to `bytes32(0)`. `handleProofResult` does
      `require(vkHash == _vkHash, "invalid vk")` — with `vkHash` unset that check passes **only**
      for a zero hash, and any misconfiguration here means proofs from an arbitrary circuit could
      drive our callback. There is a published audit finding against exactly this pattern.
      Verify by reading `vkHash()` back from the deployed contract, not by trusting the deploy log.
- [ ] Registry rejects a callback from any address other than the Brevis request contract.
- [ ] Fail-closed tests all still pass against the *deployed* configuration, not just locally.

## The fee-parity constraint — the 30% criterion

- [ ] **No code path adjusts a fee based on standing.** Grep the final tree for `getFee`,
      `lpFeeOverride`, `dynamicFee` and confirm every hit is either absent or provably constant.
- [ ] **Banned identifiers absent:** `discount`, `tier`, `loyalty`, `reward`, `vip`.
      `tier` is doubly banned — a prior directory project (`SwapNFT`) already pairs "tier" with a
      fee discount, so the word actively maps us onto the pattern we are avoiding.
- [ ] README and video **lead with the entitlement, never with the history.**
- [ ] The non-exclusion property is stated out loud on camera: an address with zero standing still
      receives a non-zero depth allowance. With 40 KYC/allowlist projects in the directory, the
      "whitelist with extra steps" objection arrives pre-loaded and must be pre-empted.
      See `analysis/rfh-collision-check.md`.

## Binary gates — fail one and we are not scored

- [ ] Public repo, correct branch, link works **logged out** (check in a private window).
- [ ] Demo video **≤ 5:00**.
- [ ] **Human audio, no AI voice.**
- [ ] Valid v4 hook interface.
- [ ] All code written in the build window — commit history is the evidence.
- [ ] README lists partner integrations **with file + line pointers**, and the lines are correct
      after any final refactor.
- [ ] Tests or a frontend — we ship tests. `forge test --isolate` green.
- [ ] No uncredited copied code. `brevis/ATTRIBUTION.md` current; v4-core/periphery derivations
      credited in file headers.

## Disclosures — every one of these must appear in the README AND on camera

- [ ] **EIP-7702 block pinning.** `brevis-sdk v0.3.12` cannot parse type-4 transactions, so proofs
      use a historical range (anchor 21146236). Blob txs are *not* the cause; type 4 alone is.
- [ ] **The production circuit has no vk hash yet** — the prover entrypoint still runs the upstream
      example circuit. Either wire it or say so.
- [ ] **Router-batched unsigned users share one per-transaction bucket.** Escapable free by signing
      a zero-standing credential.
- [ ] **Cross-transaction splitting within a block still evades the cap.**
- [ ] **Opening-leg blindness** — the hook never sees the first leg of a composite operation.
- [ ] **One-sided flow is 1.3% of volume** on the replayed pool. The mechanism is live but narrow.
- [ ] **Tranche sizing has a real cost.** Below ~500,000 USDC, base depth caps a fifth of ordinary
      retail flow. Median long-tail swap is 3,563 USDC.
- [ ] **Gateway submission was unavailable** during the build window (Brevis-side outage).

## Claims discipline

- [ ] Every capability claimed in the README or video is demonstrable. Functionality is graded
      against our own stated scope, so an unshipped promise is a free deduction.
- [ ] The Roundtrip falsification is presented as a deliberate result, not an apology.
      `analysis/roundtrip-negative-result.md` reproduces from a clean checkout.
- [ ] Anything narrowed late is narrowed **in the claim**, not left overclaimed in prose.
- [ ] **We do NOT claim to improve LP outcome anywhere.** Any reference price would determine the
      sign of the result. The sensitivity is published as the reason.
- [ ] Clone instructions say **`--recurse-submodules`** — `lib/*` are gitlinks and a plain clone
      will not build.
