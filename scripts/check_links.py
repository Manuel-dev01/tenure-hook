"""Verify every relative link in the documentation points at a file that exists.

Untracking a document turns every citation of it into a dead end, and a dead link in a submission
reads as carelessness about everything else. This caught `brevis/README.md` still pointing into the
upstream Hardhat project after that project was removed from the repository.

Links are resolved against the directory of the file that contains them, not the working directory,
because `analysis/foo.md` legitimately links `../test/Bar.t.sol`.

Only relative links are checked. External URLs are not fetched: a network round trip would make the
gate flaky, and a 404 on someone else's site is not a defect in this repository.
"""
import io
import os
import re
import subprocess
import sys

PATTERN = re.compile(r"\]\((\.{0,2}/?[A-Za-z0-9_./-]+\.(?:md|sol|go|ts|json|py|sh|html))\)")


def tracked_markdown():
    """Only what ships. Untracked working notes may legitimately reference files that were removed
    from the repository, and failing the gate on those would punish keeping local notes."""
    out = subprocess.run(["git", "ls-files", "*.md"], capture_output=True, text=True)
    if out.returncode != 0:
        raise SystemExit("  git ls-files failed; run this inside the repository")
    return [p for p in out.stdout.splitlines() if p.strip()]


bad = []
checked = 0

for path in tracked_markdown():
    root = os.path.dirname(path) or "."
    text = io.open(path, encoding="utf-8", errors="ignore").read()
    for m in PATTERN.finditer(text):
        checked += 1
        target = os.path.normpath(os.path.join(root, m.group(1)))
        # A link must point at something that SHIPS, not merely something on this disk.
        if not os.path.exists(target):
            bad.append("%s -> %s  (missing)" % (path, m.group(1)))
        elif os.path.isfile(target):
            chk = subprocess.run(["git", "ls-files", "--error-unmatch", target],
                                 capture_output=True, text=True)
            if chk.returncode != 0:
                bad.append("%s -> %s  (exists locally but is NOT tracked)" % (path, m.group(1)))

for b in sorted(set(bad)):
    print("  " + b)
print("  checked %d relative links, %d dangling" % (checked, len(set(bad))))
sys.exit(1 if bad else 0)
