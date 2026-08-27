"""Verify every README file:line pointer still resolves to the symbol named beside it.

The partner-integrations section with file+line pointers is a submission binary gate. `forge fmt`
reflows source files, so a pointer that was correct when written drifts silently — which is exactly
what happened after the Stage 5 formatting pass. This makes the gate machine-checked rather than
trusted.

A pointer matches if the symbol appears within two lines of the stated number, which tolerates
small edits without tolerating real drift.
"""
import io
import re
import sys

PATTERN = re.compile(r"`(src/[^`:]+\.sol):(\d+)`.*?`([A-Za-z_][A-Za-z0-9_]*)`")
TOLERANCE = 2

bad = []
checked = 0

for line in io.open("README.md", encoding="utf-8"):
    m = PATTERN.search(line)
    if not m:
        continue
    path, num, sym = m.group(1), int(m.group(2)), m.group(3)
    checked += 1
    try:
        rows = io.open(path, encoding="utf-8").read().split("\n")
    except OSError:
        bad.append("%s: file missing" % path)
        continue
    lo = max(0, num - 1 - TOLERANCE)
    hi = num + TOLERANCE
    window = "\n".join(rows[lo:hi])
    if sym not in window:
        bad.append("%s:%d does not contain '%s' within +/-%d lines" % (path, num, sym, TOLERANCE))

for b in bad:
    print("  " + b)
print("  checked %d pointers, %d stale" % (checked, len(bad)))
sys.exit(1 if bad else 0)
