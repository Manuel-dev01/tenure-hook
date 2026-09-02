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
import sys

SKIP_DIRS = {".git", "lib", "node_modules", "out", "cache", "broadcast", ".gate-tmp"}
PATTERN = re.compile(r"\]\((\.{0,2}/?[A-Za-z0-9_./-]+\.(?:md|sol|go|ts|json|py|sh|html))\)")

bad = []
checked = 0

for root, dirs, files in os.walk("."):
    dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
    for name in files:
        if not name.endswith(".md"):
            continue
        path = os.path.join(root, name)
        text = io.open(path, encoding="utf-8", errors="ignore").read()
        for m in PATTERN.finditer(text):
            checked += 1
            target = os.path.normpath(os.path.join(root, m.group(1)))
            if not os.path.exists(target):
                bad.append("%s -> %s" % (path.replace(os.sep, "/"), m.group(1)))

for b in sorted(set(bad)):
    print("  " + b)
print("  checked %d relative links, %d dangling" % (checked, len(set(bad))))
sys.exit(1 if bad else 0)
