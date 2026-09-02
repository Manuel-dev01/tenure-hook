# VERIFY.md: self-audit at every stage gate

Run this yourself at the end of every stage. Do not proceed to the next stage, and do not ask for review, until every item passes. Escalate only what §4 lists.

---

## 1. Mechanical gate

```bash
./scripts/gate.sh
```

Must exit 0. It checks: tests green, no fee varies by address, no banned identifiers, fee-parity test exists and passes, README partner section present with file:line pointers, no files outside the declared scope.

If it fails, fix it. A failing gate is never a reason to escalate. Only a fix that would change the mechanism is.

---

## 2. The five failure shapes

Every error caught in this project so far is one of these five. Answer all five in writing at each gate, in your report. "No" is not an answer. Name the specific place you looked.

**S1. Am I trusting something self-reported?**
*Precedent: `msgSender()` is a claim, not an identity; a malicious router names any address.*
Where does this stage take an input on faith that the sender controls? Is it authenticated, or merely stated?

**S2. Am I accepting a report instead of checking a result?**
*Precedent: "the SDK returned no error" is not verification. Tail-only checksums passed damaged files.*
What am I treating as confirmed because something told me so, rather than because I checked the artifact?

**S3. Am I inferring an operation from partial state?**
*Precedent: `beforeSwap` sees a state prefix, not an operation. Adverse-selection scoring is the same move one layer out: inferring intent from what happens afterwards.*
Does any logic conclude "X is happening" from evidence that is also consistent with Y?

**S4. Am I about to tune a number to make a weak signal look clean?**
*Precedent: the exactness falsifier; thresholds on continuous scores.*
Is there a constant in this stage whose value I chose to make results look better? If yes, it is a heuristic. The anti-goal blacklist forbids it. Say "fuzzy" and stop.

**S5. Does this assertion pass for the reason it claims?**
*Precedent: a tail-only checksum passed files damaged mid-file. A bare-selector `expectRevert` would have passed on the wrong error. "The SDK returned no error" was treated as verification. `vm.expectRevert` was silently consumed by a `hashCredential` call inside the argument list, so five tests failed while the code was correct.*
S1–S4 are about trusting the wrong **evidence**. S5 is different: the evidence is real, the check is green, and it is green for a reason other than the one it names.
**A green test is not evidence until you have made it fail on purpose.** For anything load-bearing, break the thing it tests and confirm the failure message names the right cause. If breaking the subject does not turn the test red, the test was never watching it.

---

## 2b. Stage 7: the video is unpatchable

**Every number spoken or shown in the video is re-derived from the artifact that produced it, never
copied from the README or from an earlier script draft.**

This is S2 wearing documentation clothes. Two live examples, both caught only by re-reading the
source:

- the README cited the **example** circuit's 857,942 constraints and vk hash `0x1cb76a97...` as
  though they were the production circuit's
- it claimed everything under `brevis/` was "upstream's example code, unmodified". That became false once the
  circuit was wired, and false about *code provenance* in a submission where uncredited code is a
  disqualifying gate

Both were errors of copying forward rather than looking. The README can be corrected after
submission. **The video cannot.**

Re-derive from: `forge script scripts/Demo.s.sol` for mechanism numbers, the prover log for circuit
digest / vk hash / constraints, `analysis/mainnet-replay.md` for replay figures.

---

## 3. Framing check

Read the diff. Then answer:

- Does any code path make a **fee** depend on the address? (If yes: stop. This is disqualifying, not a bug.)
- Could a tired judge reading this code call it loyalty pricing? Name what in the code refutes that.
- Does the one-liner still describe what the code does? *"Depth is the product. Every address pays the same fee; what you earn is how much of the book you can reach."*
- Is anything in the declared scope's "not building" list now in the repo?

---

## 4. Escalate ONLY these

Everything else, decide yourself and report at the gate.

1. A fix would change the mechanism's shape.
2. The one-liner or framing needs to change.
3. A stage misses its date.
4. Any pressure to make a fee vary by address.
5. S4 fires: a real "fuzzy" verdict.
6. The **Sep 3 submission** looks threatened, or Stage 7 (video) cannot be recorded in time.
7. Anything would require a **mechanism change**. The code is frozen as of Aug 30.

**Not escalations:** failing tests, infra outages, dependency problems, refactors, scope reductions inside a stage, anything the gate script catches. Fix and report.

---

## 5. Gate report format

Keep it short:

```
STAGE n. PASS / BLOCKED
gate.sh: exit 0
S1: <where I looked, what I found>
S2: <same>
S3: <same>
S4: <same>
S5: <what I broke on purpose, and the failure it produced>
Framing: fee-parity holds, per <the test that proves it>
Scope: nothing added from §5
Next: <stage n+1 start>
```