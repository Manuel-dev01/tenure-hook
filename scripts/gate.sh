#!/usr/bin/env bash
# scripts/gate.sh, run at every stage gate. Exit 0 = proceed.
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
# Absolute form, for the one check below that runs from a different directory.
GATE_LOG_DIR="$(cd "$TMP" && pwd)"

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
  echo "  FAIL: tests were skipped, a skip is not a pass"; fail=1
else
  echo "  ok:   no skipped tests"
fi

# The circuit's arithmetic evidence lives in a GO test, not a Solidity one, and this gate used to
# miss it entirely: the brevis-sdk v0.3.12 -> v0.3.33 upgrade made TestS5_BalancedVersusOneSided
# panic, and every Foundry check above stayed green. The README cites that test, so it is gated.
#
# Not added to CI: it needs Go plus a reachable Brevis gateway, and a network-flaky red badge the
# night before a submission is worse than a check that runs here. Skipped, loudly, if Go is absent.
if [ "$STAGE" -ge 2 ]; then
  if command -v go >/dev/null 2>&1; then
    # TMPDIR is relative here, and the go toolchain resolves it against ITS OWN working
    # directory - so after the cd it looks for brevis/prover/.gate-tmp and dies before running a
    # single test. Clear it and let go use the system default.
    # -v so a t.Skip is visible: without it `go test` prints nothing for a skipped test and the
    # package still reports ok, so an unexercised assertion would be recorded here as a pass.
    ( cd brevis/prover && TMPDIR= TMP= TEMP= go test -v ./... ) >"$GATE_LOG_DIR/gate_gotest.log" 2>&1
    rc=$?
    if [ $rc -ne 0 ]; then
      echo "  FAIL: go test ./... in brevis/prover (see $TMP/gate_gotest.log)"; fail=1
    elif grep -q -- "--- SKIP: TestS5" "$GATE_LOG_DIR/gate_gotest.log"; then
      echo "  skip: circuit arithmetic SKIPPED (gateway unreachable), not verified (see $TMP/gate_gotest.log)"
    else
      echo "  ok:   go test ./... green in brevis/prover"
    fi
  else
    echo "  skip: go test, go not on PATH (the S5 circuit evidence is NOT verified)"
  fi
else
  skip 2 "go test (circuit evidence)"
fi

# CI runs a build and a size check; the gate did not, so a red CI badge could sit on main
# undetected. It did, for four commits. Same two commands, same scoping.
forge build >"$TMP/gate_build.log" 2>&1
check $? "forge build clean (see $TMP/gate_build.log)"
forge build --sizes --skip 'scripts/**' --skip 'test/**' >"$TMP/gate_sizes.log" 2>&1
check $? "deployed contracts within EIP-170 (see $TMP/gate_sizes.log)"

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

# ...and they must still RESOLVE. forge fmt reflows files, so a pointer that was
# correct when written drifts silently. This is a binary gate, so it is verified
# rather than trusted.
python scripts/check_pointers.py >"$TMP/gate_ptr.log" 2>&1
check $? "doc file:line pointers still resolve, all documents (see $TMP/gate_ptr.log)"

# setVkHash is security-critical but only exists once the registry is wired.
# An unset vkHash accepts proofs from ANY circuit, so from stage 3 this is hard.
if [ "$STAGE" -ge 3 ]; then
  grep -rq 'setVkHash' scripts/ src/ 2>/dev/null
  check $? "setVkHash present in deploy path (stage 3+)"
else
  skip 3 "setVkHash in deploy path"
fi

echo "== 5. scope =="
# Anything from the declared scope 'not building' that would show up as a file.
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
if [ "$fail" -eq 0 ]; then echo "GATE PASS"; else echo "GATE FAIL, fix before proceeding"; fi
exit $fail
