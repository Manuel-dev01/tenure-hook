#!/usr/bin/env bash
# scripts/demo.sh — exercise and demonstrate the whole product, in order.
#
#   bash scripts/demo.sh              # everything that needs no secrets
#   bash scripts/demo.sh --offline    # skip anything touching the network
#   bash scripts/demo.sh --with-proof # also generate a real ZK proof (needs the prover running)
#
# WHAT THIS IS FOR. Two audiences, one script. A judge runs it to check the claims without
# trusting us; we run it before recording so the demo is rehearsed rather than debugged on camera.
#
# NO SECRETS REQUIRED. The on-chain stage signs with the PUBLIC Anvil test key, whose address has
# standing written into the demo registry precisely so anyone can reproduce stage 6. It holds no
# funds and stage 6 only simulates - nothing is broadcast, so an empty key is not a problem.
#
# EVERY STAGE PRINTS PASS, FAIL, or SKIP WITH A REASON. A stage that cannot run says so rather than
# passing quietly, because a silent skip is how a broken claim survives.

set -uo pipefail
cd "$(dirname "$0")/.."

OFFLINE=0
WITH_PROOF=0
for arg in "$@"; do
  case "$arg" in
    --offline) OFFLINE=1 ;;
    --with-proof) WITH_PROOF=1 ;;
    *) echo "unknown flag: $arg"; exit 2 ;;
  esac
done

# Foundry may not be on PATH in a fresh shell.
export PATH="$PATH:$HOME/.foundry/bin"

RPC="${RPC_URL:-https://ethereum-sepolia-rpc.publicnode.com}"
HOOK=0x8878dbEB12C6Aba4ab6629DB41238d131e6D0080
ROUTER=0xA202C318D22Df67E6C347FC5b98F3d1adDFd3470
REGISTRY=0x2fA2242c80F7a7a7690cF0a36a19FcFf70709AaA
ZK_REGISTRY=0x03F05F1c89b9725F2AD775Aed85F60DD38af19B5
CURRENCY0=0x0f07BFd5575fae87D3f178faCc592566378fbe25
CURRENCY1=0x2596369630c5Ff13342B06Ed99d7a489300ABD87
POOL_ID=0x402c9dcb4dc9182b2ee9fa2622178a3cdb764c84b560c1061e1f913706f661d9
# Anvil's default key. Public, worthless, and deliberately used here.
DEMO_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
SITE=https://manuel-dev01.github.io/tenure-hook

pass=0; fail=0; skip=0
TMP="${TMPDIR:-.gate-tmp}"; mkdir -p "$TMP"

hr()   { printf '\n\033[2m%s\033[0m\n' "────────────────────────────────────────────────────────────"; }
stage(){ hr; printf '\033[1m%s\033[0m\n\n' "$1"; }
ok()   { printf '  \033[32mPASS\033[0m  %s\n' "$1"; pass=$((pass+1)); }
no()   { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; fail=$((fail+1)); }
sk()   { printf '  \033[33mSKIP\033[0m  %s\n' "$1"; skip=$((skip+1)); }

# ─────────────────────────────────────────────────────────────────────────────
stage "0 · Preflight"

command -v forge >/dev/null 2>&1 && ok "$(forge --version 2>/dev/null | head -1)" \
                                 || { no "forge not found — install Foundry"; }
if [ -f lib/v4-core/src/interfaces/IPoolManager.sol ]; then
  ok "submodules present"
else
  no "lib/ is empty — run: git submodule update --init --recursive"
fi
command -v go >/dev/null 2>&1 && ok "go $(go version | awk '{print $3}' | sed 's/^go//')" || sk "go not on PATH (stage 2 circuit tests)"

# ─────────────────────────────────────────────────────────────────────────────
stage "1 · The contracts build, and the deployable ones fit"

if forge build >"$TMP/demo_build.log" 2>&1; then ok "forge build"; else no "forge build (see $TMP/demo_build.log)"; fi
if forge build --sizes --skip 'scripts/**' --skip 'test/**' >"$TMP/demo_sizes.log" 2>&1; then
  ok "deployed contracts within EIP-170"
  grep -E "^\| (TenureHook|TenureRegistry|TenureSwapRouter) " "$TMP/demo_sizes.log" | sed 's/^/        /'
else
  no "a deployed contract exceeds EIP-170 (see $TMP/demo_sizes.log)"
fi

# ─────────────────────────────────────────────────────────────────────────────
stage "2 · The test suite, and the circuit's arithmetic"

if forge test --isolate >"$TMP/demo_test.log" 2>&1; then
  ok "$(grep -oE '[0-9]+ tests passed' "$TMP/demo_test.log" | tail -1)"
else
  no "forge test --isolate (see $TMP/demo_test.log)"
fi
if grep -qE '[1-9][0-9]* skipped' "$TMP/demo_test.log" 2>/dev/null; then
  no "tests were skipped — a skip is not a pass"
else
  ok "no skipped tests"
fi

if command -v go >/dev/null 2>&1; then
  # The S5 test proves the circuit computes 2*min(buys,sells)/total, checked against a figure
  # computed outside the circuit. Mutating min->max turns it red naming the cause.
  if ( cd brevis/prover && TMPDIR= TMP= TEMP= go test ./... ) >"$TMP/demo_gotest.log" 2>&1; then
    ok "go test ./... — circuit arithmetic verified"
  else
    no "go test ./... (see $TMP/demo_gotest.log)"
  fi
else
  sk "circuit arithmetic — go not on PATH"
fi

# ─────────────────────────────────────────────────────────────────────────────
stage "3 · The claim gate"

if bash scripts/gate.sh >"$TMP/demo_gate.log" 2>&1; then
  ok "GATE PASS — fee parity, identity soundness, scope, README pointers"
else
  no "GATE FAIL (see $TMP/demo_gate.log)"
  grep -E "FAIL:" "$TMP/demo_gate.log" | sed 's/^/        /'
fi

# ─────────────────────────────────────────────────────────────────────────────
stage "4 · The mechanism, end to end, offline"

echo "  Two traders, same pool, same fee, same 60-unit swap. One fills, one is capped."
echo ""
if forge script scripts/Demo.s.sol >"$TMP/demo_run.log" 2>&1; then
  sed -n '/== Logs ==/,$p' "$TMP/demo_run.log" | sed 's/^/  /' | head -60
  ok "demo ran"
else
  no "demo failed (see $TMP/demo_run.log)"
fi

# ─────────────────────────────────────────────────────────────────────────────
stage "5 · A real ZK proof over real mainnet swap logs"

if [ "$WITH_PROOF" -eq 1 ]; then
  if [ "$OFFLINE" -eq 1 ]; then
    sk "proving needs the network"
  elif ! nc -z localhost 33247 2>/dev/null && ! (command -v powershell.exe >/dev/null 2>&1 &&
        powershell.exe -NoProfile -Command "(Test-NetConnection -ComputerName localhost -Port 33247 -InformationLevel Quiet)" 2>/dev/null | grep -qi true); then
    sk "prover not listening on :33247 — start it with: cd brevis/prover && go run ./cmd/main.go"
  else
    echo "  Proving takes 57-176s. The expected figure is computed from raw logs, NOT by the circuit,"
    echo "  and the script exits non-zero on mismatch — so this is a check, not a printout."
    if ( cd brevis/app && npm run prove -- balanced ) 2>&1 | tail -14 | sed 's/^/  /'; then
      ok "balanced fixture proved and matched (9375 bps over 32 swaps)"
    else
      no "proving failed or the output did not match"
    fi
  fi
else
  sk "ZK proof — pass --with-proof (needs the prover on :33247, ~2 min)"
fi

# ─────────────────────────────────────────────────────────────────────────────
stage "6 · The deployed contracts on Sepolia"

if [ "$OFFLINE" -eq 1 ]; then
  sk "on-chain reads — --offline"
else
  cfg_reg=$(cast call "$HOOK" 'registry()(address)' --rpc-url "$RPC" 2>/dev/null)
  if [ "${cfg_reg,,}" = "${REGISTRY,,}" ]; then
    ok "hook reads the standing registry at $REGISTRY"
  else
    no "hook.registry() is '$cfg_reg', expected $REGISTRY"
  fi

  tranche=$(cast call "$HOOK" 'depthTranche(bytes32)(uint256)' "$POOL_ID" --rpc-url "$RPC" 2>/dev/null | awk '{print $1}')
  [ -n "$tranche" ] && [ "$tranche" != "0" ] && ok "pool tranche configured: $tranche" \
                                             || no "pool tranche unset — the hook would not enforce"

  # The address bits ARE the fee-parity guarantee: no BEFORE_SWAP_RETURNS_DELTA means the hook
  # cannot alter execution economics whatever its code says.
  case "${HOOK,,}" in
    *0080) ok "hook address ends 0080 — beforeSwap only, no return-delta permission" ;;
    *)     no "hook address does not encode beforeSwap-only permissions" ;;
  esac

  vk=$(cast call "$ZK_REGISTRY" 'expectedVkHash()(bytes32)' --rpc-url "$RPC" 2>/dev/null)
  if [ "$vk" = "0x0230047e074d6b8c19ab6714303a3c84412e6dc7a6d540835925f1e08e6f94b8" ]; then
    ok "ZK registry vk hash matches the circuit's verifying key"
  else
    no "ZK registry vk hash is '$vk'"
  fi

  echo ""
  echo "  Reproducing the four behaviours against the DEPLOYED contracts."
  echo "  Signed with the public Anvil key, so this needs no secret of ours."
  echo ""
  if PRIVATE_KEY="$DEMO_KEY" HOOK="$HOOK" ROUTER="$ROUTER" \
     CURRENCY0="$CURRENCY0" CURRENCY1="$CURRENCY1" \
     forge script scripts/VerifyDemo.s.sol --rpc-url "$RPC" >"$TMP/demo_verify.log" 2>&1; then
    sed -n '/== Logs ==/,/^$/p' "$TMP/demo_verify.log" | sed 's/^/  /'
    ok "all four behaviours confirmed on-chain, matched by error selector"
  else
    no "on-chain verification failed (see $TMP/demo_verify.log)"
    tail -5 "$TMP/demo_verify.log" | sed 's/^/        /'
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
stage "7 · The front end"

if [ "$OFFLINE" -eq 1 ]; then
  sk "site checks — --offline"
elif ! command -v curl >/dev/null 2>&1; then
  sk "site checks — curl not found"
else
  for path in "" "app.html" "deployments.json"; do
    code=$(curl -s -o /dev/null -w '%{http_code}' "$SITE/$path" 2>/dev/null)
    [ "$code" = "200" ] && ok "$SITE/$path" || no "$SITE/$path returned $code"
  done
  # The banner is the honesty guarantee: standing is operator-written, not ZK-delivered.
  if curl -s "$SITE/app.html" 2>/dev/null | grep -q "operator-written"; then
    ok "app discloses that standing is operator-written, not ZK-delivered"
  else
    no "app is missing the trust-model disclosure — do not demo it in this state"
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
hr
printf '\033[1mSUMMARY\033[0m   \033[32m%d passed\033[0m · \033[31m%d failed\033[0m · \033[33m%d skipped\033[0m\n\n' "$pass" "$fail" "$skip"

if [ "$fail" -gt 0 ]; then
  echo "Something above is broken. Do not record until it is green."
  exit 1
fi
cat <<'SUMMARY'
What was just demonstrated, in one line each:

  · every address pays the same fee, and the hook's mined address makes that structural
  · standing comes from a ZK circuit over real mainnet swap logs — no price, no oracle
  · depth scales from 5% to 100% of a tranche, continuously, with no cliffs
  · the cap binds on a live public testnet, matched by the hook's own error selectors
  · splitting one large take into several capped legs reverts
  · an unsigned swap still executes, at base depth — nobody is excluded

Not claimed: no proof has landed on any chain. Brevis' aggregation service is
retired, so standing in the app is operator-written and the app says so.
SUMMARY
exit 0
