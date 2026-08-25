#!/usr/bin/env bash
# scripts/gate.sh — run at every stage gate. Exit 0 = proceed.
#
# Usage:  ./scripts/gate.sh          # infers stage from the repo
#         STAGE=3 ./scripts/gate.sh  # force a stage
#
# Stage-dependent checks are SKIPPED (not deleted, not weakened) before the stage
# that makes them meaningful, and become hard failures from that stage onward.
set -uo pipefail
cd "$(dirname "$0")/.."

fail=0
check()  { if [ "$1" -ne 0 ]; then echo "  FAIL: $2"; fail=1; else echo "  ok:   $2"; fi; }
skip()   { echo "  skip: $2 (stage $STAGE < $1)"; }

# Temp dir: /tmp is not reliable across the shells this repo is built in.
TMP="${TMPDIR:-.gate-tmp}"; mkdir -p "$TMP"

# ---- stage inference ---------------------------------------------------------
# 1 = hook standalone, 2 = circuit, 3 = wired on-chain, 4 = evidence, 5 = freeze
if [ -z "${STAGE:-}" ]; then
  STAGE=1
  [ -f brevis/prover/circuits/directional_balance.go ] && STAGE=2
  grep -rqs 'handleProofResult' src/ && STAGE=3
  [ -f analysis/sensitivity.md ] && STAGE=4
fi
echo "== stage $STAGE =="

echo "== 1. tests =="
# --isolate is required: without it the Roundtrip cross-transaction test skips
# rather than running, so a bare `forge test` under-reports coverage.
forge test --isolate >"$TMP/gate_test.log" 2>&1
check $? "forge test --isolate green (see $TMP/gate_test.log)"

# A skipped test is not a passing test. Catch silent skips.
if grep -qE '[1-9][0-9]* skipped' "$TMP/gate_test.log" 2>/dev/null; then
  echo "  FAIL: tests were skipped — a skip is not a pass"; fail=1
else
  echo "  ok:   no skipped tests"
fi

echo "== 2. fee parity (disqualifying if violated) =="
# No banned identifiers anywhere in src/. These are how loyalty-pricing framing
# creeps in through variable names even when the mechanism is correct.
grep -rniE '\b(discount|tier|loyalty|rebate|bonus|feeDiscount|reducedFee|vip|reward)\b' src/ >"$TMP/gate_banned.log" 2>/dev/null
[ ! -s "$TMP/gate_banned.log" ]; check $? "no banned identifiers in src/"

# Nothing may write to a dynamic-fee path. Standing changes depth, never price.
grep -rnE 'LPFeeLibrary|updateDynamicLPFee|OVERRIDE_FEE|setLPFee' src/ >"$TMP/gate_fee.log" 2>/dev/null
[ ! -s "$TMP/gate_fee.log" ]; check $? "no dynamic-fee machinery in src/"

# The hook must not hold the permission to alter execution economics. This is
# stronger than the greps above: without the flag it CANNOT move the fee, whatever
# code exists. Checked as source truth, then proven by the test below.
grep -q 'beforeSwapReturnDelta: false' src/TenureHook.sol 2>/dev/null
check $? "hook declares beforeSwapReturnDelta: false"

# A test must actively prove parity, not merely fail to violate it.
grep -rq 'test_FeeParity' test/; check $? "test_FeeParity_* exists"
forge test --match-test test_FeeParity >/dev/null 2>&1
check $? "test_FeeParity_* passes"

echo "== 3. identity soundness =="
# EIP-712 replay and expiry must be tested, not assumed. Meaningful from stage 1.
if [ "$STAGE" -ge 1 ]; then
  grep -rq 'test_Replay' test/; check $? "replay-attempt test exists"
  grep -rq 'test_Expired' test/; check $? "expired-deadline test exists"
  forge test --match-test 'test_Replay|test_Expired' >/dev/null 2>&1
  check $? "replay + expiry tests pass"
else
  skip 1 "EIP-712 replay/expiry tests"
fi

echo "== 4. submission gates =="
grep -qi 'partner integration' README.md 2>/dev/null
check $? "README has partner integrations section"
# file:line pointers, e.g. src/TenureHook.sol:142
grep -qE '\.sol:[0-9]+' README.md 2>/dev/null
check $? "README has file:line pointers"

# setVkHash is security-critical but only exists once the registry is wired.
# An unset vkHash accepts proofs from ANY circuit, so from stage 3 this is hard.
if [ "$STAGE" -ge 3 ]; then
  grep -rq 'setVkHash' scripts/ src/ 2>/dev/null
  check $? "setVkHash present in deploy path (stage 3+)"
else
  skip 3 "setVkHash in deploy path"
fi

echo "== 5. scope =="
# Anything from CLAUDE.md §5 'not building' that would show up as a file.
ls src/ 2>/dev/null | grep -iE 'governance|token|frontend|oracle|ml|score' >"$TMP/gate_scope.log"
[ ! -s "$TMP/gate_scope.log" ]; check $? "no out-of-scope modules in src/"

# Stage 2 claim discipline: directional balance uses swap logs only. If a price
# series appears in the circuit, the claim has drifted back to adverse-selection
# scoring and must stop.
if [ "$STAGE" -ge 2 ]; then
  # Strip // comments first: the circuit's own docs explain WHY it uses no price data, and
  # matching those words in prose would be a false positive. What matters is executable code.
  find brevis/prover/circuits -name '*.go' -not -name '*_test.go' -print0 2>/dev/null     | xargs -0 -r sed 's://.*::'     | grep -niE 'price|oracle|twap|sqrtPrice' >"$TMP/gate_price.log" 2>/dev/null
  [ ! -s "$TMP/gate_price.log" ]; check $? "circuit uses no price data (claim has not drifted)"
else
  skip 2 "circuit price-drift check"
fi

echo
if [ "$fail" -eq 0 ]; then echo "GATE PASS"; else echo "GATE FAIL — fix before proceeding"; fi
exit $fail
