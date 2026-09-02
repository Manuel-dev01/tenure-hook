"""Verify every documented file:line pointer still resolves to the symbol named beside it.

The partner-integrations section with file+line pointers is a submission binary gate. `forge fmt`
reflows source files, so a pointer that was correct when written drifts silently, which is exactly
what happened after the Stage 5 formatting pass. This makes the gate machine-checked rather than
trusted.

Every document that carries pointers is scanned, not just the README. When the architecture notes
moved out of README.md into ARCHITECTURE.md, their pointers left the checked set and could have
drifted unnoticed; a checker that only knows about one file quietly stops covering the docs as they
grow.

A pointer matches if the symbol appears within two lines of the stated number, which tolerates small
edits without tolerating real drift.
"""
import io
import os
import re
import sys

DOCS = ["README.md", "ARCHITECTURE.md", "DEMO.md"]
PATTERN = re.compile(r"`(src/[^`:]+\.sol):(\d+)`.*?`([A-Za-z_][A-Za-z0-9_]*)`")
TOLERANCE = 2

bad = []
checked = 0

for doc in DOCS:
    if not os.path.exists(doc):
        bad.append("%s: document missing" % doc)
        continue
    for line in io.open(doc, encoding="utf-8"):
        m = PATTERN.search(line)
        if not m:
            continue
        path, num, sym = m.group(1), int(m.group(2)), m.group(3)
        checked += 1
        try:
            rows = io.open(path, encoding="utf-8").read().split("\n")
        except OSError:
            bad.append("%s -> %s: file missing" % (doc, path))
            continue
        lo = max(0, num - 1 - TOLERANCE)
        hi = num + TOLERANCE
        window = "\n".join(rows[lo:hi])
        if sym not in window:
            bad.append(
                "%s -> %s:%d does not contain '%s' within +/-%d lines"
                % (doc, path, num, sym, TOLERANCE)
            )

for b in bad:
    print("  " + b)
print("  checked %d pointers across %d documents, %d stale" % (checked, len(DOCS), len(bad)))
sys.exit(1 if bad else 0)
