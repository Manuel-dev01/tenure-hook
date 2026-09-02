# Submission checklist. Sep 2/3

**Updated 2026-08-30.** Three checks that were manual are now machine-enforced, in both
`scripts/gate.sh` and CI. Run `bash scripts/gate.sh` first; it covers everything marked *(auto)*.
The manual wording is kept so the check survives the script being wrong.

## Automated, `bash scripts/gate.sh` must exit 0

- [ ] *(auto)* `forge fmt --check` clean
- [ ] *(auto)* `forge test --isolate`, **0 failed and 0 skipped.** A skip is not a pass; without
      `--isolate` the cross-transaction tests silently skip
- [ ] *(auto)* `scripts/check_pointers.py`, every README `file:line` pointer resolves to the symbol
      named beside it. `forge fmt` reflows sources and drifts these silently
- [ ] *(auto)* no banned identifiers in `src/`
- [ ] *(auto)* no dynamic-fee machinery in `src/`
- [ ] *(auto)* hook declares `beforeSwapReturnDelta: false`
- [ ] *(auto)* circuit contains no price/oracle reference
- [ ] CI green on the pushed commit, **open the Actions tab and look.** This was ticked from
      memory while `main` had been red for four consecutive commits: `forge build --sizes` was
      failing because the demo harness exceeds EIP-170, which is expected for a contract that is
      never deployed and was never scoped out. A claim about CI is checkable in one click by
      anyone, including a judge.

Line items, not runbook steps. Each is something that can be silently skipped in a rush and cost
either the submission or a question on stage. Tick nothing from memory.

---

## Security

**Deployment is NOT required by the rules, and as of Sep 2 nothing is deployed.** The reason is no
longer technical: as of 2026-09-02 the Brevis gateway **accepts** our query and returns a query key
(`analysis/brevis-gateway-diagnosis.md`). What remains is the on-chain leg, deploy the registry,
`setVkHash`, pay `BrevisRequest.sendRequest`, receive the callback. Pick a path and tick the
matching block. Do not leave the deployed-only items unticked and unexplained; an empty checkbox
reads as an omission.

### Path A, not deployed (current default)

- [ ] The README and video state plainly that **the gateway accepts the query but no proof has
      landed on-chain**, because the paid `sendRequest` leg was not run. Proofs are generated and
      verified locally.
      *Do NOT say this is an outage, and do NOT say the circuit needs registering with Brevis.
      Both were written into this repo previously and both were false; the real cause was a stale
      `brevis-sdk` pin, now fixed.*
- [ ] `scripts/Deploy.s.sol` demonstrates the correct `setVkHash` sequence *including the readback*,
      so the security property is legible in code even though no deployment exists.
- [ ] `TenureRegistryTest` covers `_vkHash` rejection and callback authorisation. The guarantees
      are test-backed rather than deployment-backed. Say which, do not imply the other.

### Path B, if a deployment happens before submission

- [ ] **`setVkHash` has been called and `vkHash()` reads back
      `0x0230047e074d6b8c19ab6714303a3c84412e6dc7a6d540835925f1e08e6f94b8`.**
      *This value changed on 2026-09-02 with the brevis-sdk v0.3.33 upgrade. The old
      `0x028f783f…` is dead and would reject every real proof.*
      `vkHash` initialises to `bytes32(0)`. `handleProofResult` does
      `require(vkHash == _vkHash, "invalid vk")`, with `vkHash` unset, that check accepts **only**
      a zero hash, and a misconfiguration means proofs from an arbitrary circuit could drive our
      callback. There is a published audit finding against exactly this pattern.
      **Read it back from the contract. Do not trust the deploy log.**
- [ ] Registry rejects a callback from any address other than the Brevis request contract.
- [ ] Fail-closed tests re-run against the *deployed* configuration, not just locally.

## The fee-parity constraint, the 30% criterion

- [ ] **No code path adjusts a fee based on standing.** Grep the final tree for `getFee`,
      `lpFeeOverride`, `dynamicFee` and confirm every hit is either absent or provably constant.
- [ ] **Banned identifiers absent:** `discount`, `tier`, `loyalty`, `reward`, `vip`.
      `tier` is doubly banned, a prior directory project (`SwapNFT`) already pairs "tier" with a
      fee discount, so the word actively maps us onto the pattern we are avoiding.
- [ ] README and video **lead with the entitlement, never with the history.**
- [ ] The non-exclusion property is stated out loud on camera: an address with zero standing still
      receives a non-zero depth allowance. With 40 KYC/allowlist projects in the directory, the
      "whitelist with extra steps" objection arrives pre-loaded and must be pre-empted.
      See `analysis/rfh-collision-check.md`.

## Binary gates, fail one and we are not scored

- [ ] Public repo, correct branch, link works **logged out** (check in a private window).
- [ ] Demo video **≤ 5:00**.
- [ ] **Human audio, no AI voice.**
- [ ] Valid v4 hook interface.
- [ ] All code written in the build window, commit history is the evidence.
- [ ] README lists partner integrations **with file + line pointers**, and the lines are correct
      after any final refactor.
- [ ] Tests or a frontend. We ship **both**. The gate is met by the tests
      (`forge test --isolate` green, 56 passing); the `docs/` UI is presentation on top.
      *Say it that way round. A UI that breaks on the day would not endanger the gate, and
      claiming it as the gate would make it do so.*
- [ ] No uncredited copied code. `brevis/ATTRIBUTION.md` current; v4-core/periphery derivations
      credited in file headers.

## Disclosures, every one of these must appear in the README AND on camera

- [ ] **EIP-7702 block pinning.** `brevis-sdk v0.3.12` could not parse type-4 transactions, so the
      fixtures use a historical range (anchor 21146236). Blob txs are *not* the cause; type 4 alone
      is. v0.3.33 pins a geth fork that does parse type 4, so this is probably lifted, but the
      fixtures were never re-cut, so **do not claim it is fixed**.
- [ ] ~~The production circuit has no vk hash~~ **RESOLVED.** Circuit is wired; vk hash is
      `0x0230047e074d6b8c19ab6714303a3c84412e6dc7a6d540835925f1e08e6f94b8`. **This is the value
      `setVkHash` takes**, read `vkHash()` back after deploying to confirm.
      *Superseded value: `0x028f783f…` (brevis-sdk v0.3.12). Dead, see
      `analysis/brevis-gateway-diagnosis.md`.*
- [ ] **Router-batched unsigned users share one per-transaction bucket.** Escapable free by signing
      a zero-standing credential.
- [ ] **Cross-transaction splitting within a block still evades the cap.**
- [ ] **Opening-leg blindness**, the hook never sees the first leg of a composite operation.
- [ ] **One-sided flow is 1.3% of volume** on the replayed pool. The mechanism is live but narrow.
- [ ] **Tranche sizing has a real cost.** At a 500,000 USDC tranche, base depth blocks about a
      fifth (20.8%) of long-tail swaps, **below that, more**: 28.5% at 250,000, 42.5% at 100,000.
      Median long-tail swap is 3,563 USDC.
      *Do not say "below 500,000 … a fifth". That understates our own cost, and it is the phrasing
      a judge with the repo open would check.*
- [ ] **Gateway submission works.** It failed for a week and we published two wrong explanations
      before tracing it: `0x127d5d80...` in `invalid app circuit chain 1 dummy input commitment
      0x127d5d80...` was a **string constant in our own pinned SDK** (`brevis-sdk@v0.3.12
      common/const.go:3`), not an identifier Brevis assigned us. v0.3.17+ fetches the value from
      the gateway; Brevis document 0.3.17 as the minimum. Upgrading to v0.3.33 fixed it.
      **Never call it an outage and never say the circuit needed registering.**
- [ ] **The on-chain leg is untested and must be described as such.** The gateway accepting a query
      proves routing, not fulfilment. Say "no proof has landed on any chain", not "the ZK path is
      live end to end".

## Claims discipline

- [ ] Every capability claimed in the README or video is demonstrable. Functionality is graded
      against our own stated scope, so an unshipped promise is a free deduction.
- [ ] The Roundtrip falsification is presented as a deliberate result, not an apology.
      `analysis/roundtrip-negative-result.md` reproduces from a clean checkout.
- [ ] Anything narrowed late is narrowed **in the claim**, not left overclaimed in prose.
- [ ] **We do NOT claim to improve LP outcome anywhere.** Any reference price would determine the
      sign of the result. The sensitivity is published as the reason.
- [ ] Clone instructions say **`--recurse-submodules`**, `lib/*` are gitlinks and a plain clone
      will not build.
