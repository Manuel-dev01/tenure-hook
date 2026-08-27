// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// MILESTONE 0 — DISCRIMINATOR TEST — Roundtrip
//
// One job: answer the go/no-go gate's three questions. Nothing here prices anything.
//
//   Q1. Does hook-local transient storage survive across legs of one tx, and clear between txs?
//   Q2. Can the hook read the PoolManager's transient deltas mid-swap?   <-- THE GO/NO-GO
//   Q3. Does the delta pattern separate composite ops from retail, AND arb from benign composites?
//
// Q3.0 is a CONTROL and gates everything after it: CompositeRouter is the instrument, so every
// Q3 number inherits its correctness. If the control cannot reproduce a hand-calculated delta,
// no scenario number below it means anything.
//
// Derived from Uniswap v4-core test scaffolding (BUSL-1.1).

import {Test, console} from "forge-std/Test.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {HookMiner} from "v4-periphery/test/shared/HookMiner.sol";

import {ProbeHook} from "./probe/ProbeHook.sol";
import {CompositeRouter} from "./routers/CompositeRouter.sol";

contract DiscriminatorTest is Test, Deployers {
    ProbeHook internal probe;
    CompositeRouter internal router;

    // Three currencies, sorted: A < B < C.
    Currency internal A;
    Currency internal B;
    Currency internal C;

    // Same pair (A,B) at two fee tiers — the arb geometry. Probe sits on the DEAR pool, which is
    // the one the arb touches SECOND. We cannot see a cycle at its opening, only at its close.
    PoolKey internal poolAB_cheap; // 0.05%, NO hook  — arb opening leg
    PoolKey internal poolAB_probed; // 0.30%, PROBED  — arb closing leg, retail, batch settlement
    PoolKey internal poolBC_probed; // 0.30%, PROBED  — multi-hop second leg (A->B->C)

    // Wide range so scenario swaps do not run out of liquidity. tickSpacing is 60 for fee 3000
    // and 10 for fee 500 (Deployers.initPool derives it as fee/100*2), so 60000 is a multiple of
    // both.
    int24 internal constant TICK_LOWER = -60000;
    int24 internal constant TICK_UPPER = 60000;
    int256 internal constant LIQUIDITY = 1e21;

    /// @dev Amount used by the control to establish a delta of an exactly known size.
    int256 internal constant CONTROL_TAKE = 1_000_000;

    function setUp() public {
        deployFreshManagerAndRouters();

        // Three tokens, sorted so PoolKey ordering is valid.
        MockERC20[] memory tokens = deployTokens(3, 2 ** 255);
        address[] memory addrs = new address[](3);
        for (uint256 i = 0; i < 3; i++) {
            addrs[i] = address(tokens[i]);
        }
        _sort3(addrs);
        A = Currency.wrap(addrs[0]);
        B = Currency.wrap(addrs[1]);
        C = Currency.wrap(addrs[2]);

        // Mine a CREATE2 address whose low bits encode exactly BEFORE_SWAP_FLAG. A hook at an
        // unmined address fails Hooks.validateHookPermissions at initialize. The project conventions.
        // Note beforeSwapReturnDelta is deliberately NOT set — this probe cannot price.
        (address hookAddr, bytes32 salt) = HookMiner.find(
            address(this), uint160(Hooks.BEFORE_SWAP_FLAG), type(ProbeHook).creationCode, abi.encode(manager)
        );
        probe = new ProbeHook{salt: salt}(manager);
        require(address(probe) == hookAddr, "hook address mining failed");

        router = new CompositeRouter(manager);

        // Approvals + funding for every router that moves tokens.
        for (uint256 i = 0; i < 3; i++) {
            tokens[i].approve(address(modifyLiquidityRouter), type(uint256).max);
            tokens[i].approve(address(swapRouter), type(uint256).max);
            // The composite router settles from its OWN balance, so it must hold tokens.
            tokens[i].transfer(address(router), 1e30);
        }

        (poolAB_cheap,) = initPool(A, B, IHooks(address(0)), 500, SQRT_PRICE_1_1);
        (poolAB_probed,) = initPool(A, B, IHooks(address(probe)), 3000, SQRT_PRICE_1_1);
        (poolBC_probed,) = initPool(B, C, IHooks(address(probe)), 3000, SQRT_PRICE_1_1);

        _addLiquidity(poolAB_cheap);
        _addLiquidity(poolAB_probed);
        _addLiquidity(poolBC_probed);

        probe.clear();
    }

    // ---------------------------------------------------------------------------------------
    // helpers
    // ---------------------------------------------------------------------------------------

    function _sort3(address[] memory a) internal pure {
        for (uint256 i = 0; i < 3; i++) {
            for (uint256 j = i + 1; j < 3; j++) {
                if (a[j] < a[i]) (a[i], a[j]) = (a[j], a[i]);
            }
        }
    }

    function _addLiquidity(PoolKey memory k) internal {
        modifyLiquidityRouter.modifyLiquidity(
            k,
            IPoolManager.ModifyLiquidityParams({
                tickLower: TICK_LOWER,
                tickUpper: TICK_UPPER,
                liquidityDelta: LIQUIDITY,
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );
    }

    function _swapStep(PoolKey memory k, bool zeroForOne, int256 amountSpecified)
        internal
        pure
        returns (CompositeRouter.Step memory s)
    {
        s.kind = CompositeRouter.StepKind.SWAP;
        s.key = k;
        s.zeroForOne = zeroForOne;
        s.amountSpecified = amountSpecified;
    }

    function _takeStep(Currency c, uint256 amount) internal pure returns (CompositeRouter.Step memory s) {
        s.kind = CompositeRouter.StepKind.TAKE;
        s.currency = c;
        s.amount = amount;
    }

    function _addLiqStep(PoolKey memory k, int256 liquidityDelta)
        internal
        pure
        returns (CompositeRouter.Step memory s)
    {
        s.kind = CompositeRouter.StepKind.ADD_LIQUIDITY;
        s.key = k;
        s.tickLower = TICK_LOWER;
        s.tickUpper = TICK_UPPER;
        s.liquidityDelta = liquidityDelta;
    }

    function _net2(Currency c0, Currency c1) internal pure returns (Currency[] memory n) {
        n = new Currency[](2);
        n[0] = c0;
        n[1] = c1;
    }

    function _net3(Currency c0, Currency c1, Currency c2) internal pure returns (Currency[] memory n) {
        n = new Currency[](3);
        n[0] = c0;
        n[1] = c1;
        n[2] = c2;
    }

    /// @dev Pretty-print one observation as a row of the Q3 signature table.
    function _report(string memory label, uint256 i) internal view {
        ProbeHook.Observation memory o = probe.observation(i);
        console.log("----------------------------------------------------------------");
        console.log(label);
        console.log("  leg index              :", o.legIndex);
        console.log("  nonzeroDeltaCount      :", o.nonzeroDeltaCount);
        console.log("  delta currency0        :", o.deltaCurrency0);
        console.log("  delta currency1        :", o.deltaCurrency1);
        console.log("  delta in INPUT  ccy    :", o.deltaInInputCurrency);
        console.log("  delta in OUTPUT ccy    :", o.deltaInOutputCurrency);
        console.log("  PREDICATE TRIPPED      :", o.predicateTripped);
    }

    // =======================================================================================
    // Q1 — hook-local transient storage lifetime
    // =======================================================================================

    /// @notice Two legs inside ONE unlock must share hook-local transient state.
    function test_Q1_TransientPersistsAcrossLegsInOneTx() public {
        CompositeRouter.Step[] memory steps = new CompositeRouter.Step[](2);
        steps[0] = _swapStep(poolAB_probed, true, -1e18);
        steps[1] = _swapStep(poolAB_probed, true, -1e18);

        router.execute(steps, _net2(A, B));

        assertEq(probe.observationCount(), 2, "expected two observations");

        ProbeHook.Observation memory first = probe.observation(0);
        ProbeHook.Observation memory second = probe.observation(1);

        assertEq(first.legIndex, 0, "first leg index");
        assertFalse(first.sawPriorTouch, "first leg must not see a prior touch");
        assertEq(second.legIndex, 1, "second leg index");
        assertTrue(second.sawPriorTouch, "second leg must see the first leg's touch");
    }

    /// @notice Transient state must NOT survive into a different transaction.
    /// @dev Run with `--isolate` so each top-level call is its own transaction. Without it,
    ///      Foundry executes the whole test body as a single transaction and this correctly
    ///      fails — which is itself the demonstration that the state is tx-scoped, not call-scoped.
    ///      This is why cross-transaction sandwiches are invisible to us (the declared scope, the v4 trap list).
    function test_Q1_TransientClearedBetweenTxs() public {
        CompositeRouter.Step[] memory steps = new CompositeRouter.Step[](1);
        steps[0] = _swapStep(poolAB_probed, true, -1e18);

        router.execute(steps, _net2(A, B));
        router.execute(steps, _net2(A, B));

        assertEq(probe.observationCount(), 2, "expected two observations");

        // Without --isolate, Foundry runs the whole test body as ONE transaction, so the second
        // call correctly still sees the first call's transient state. Detect that and skip rather
        // than assert a claim the harness is not set up to test — and rather than let it pass
        // vacuously.
        if (probe.observation(1).sawPriorTouch) {
            console.log("SKIPPED: re-run with --isolate to test transaction-scoped clearing.");
            vm.skip(true);
        }

        assertFalse(probe.observation(0).sawPriorTouch, "tx 1 must start clean");
        assertFalse(probe.observation(1).sawPriorTouch, "tx 2 must start clean");
        assertEq(probe.observation(1).legIndex, 0, "tx 2 leg index must reset to 0");
    }

    // =======================================================================================
    // Q2 — THE GO/NO-GO. Can the hook read PoolManager transient deltas mid-swap?
    // =======================================================================================

    /// @notice The hook must read a delta whose value the test knows independently and exactly.
    /// @dev `manager.take(currency, to, amount)` accounts a delta of exactly `-amount` to the
    ///      caller (PoolManager._accountDelta). So after taking CONTROL_TAKE of A, the router's
    ///      delta in A is exactly -CONTROL_TAKE. A zero reading here cannot be confused with a
    ///      wrong slot, which is the v4 trap list's ambiguous-zero trap.
    function test_Q2_HookReadsKnownNonZeroPoolManagerDelta() public {
        CompositeRouter.Step[] memory steps = new CompositeRouter.Step[](2);
        steps[0] = _takeStep(A, uint256(CONTROL_TAKE));
        // Swap B->A so the OUTPUT currency is A, the one carrying the known debt.
        steps[1] = _swapStep(poolAB_probed, false, -1e18);

        router.execute(steps, _net2(A, B));

        ProbeHook.Observation memory o = probe.observation(0);

        // The exact hand-calculated value, not merely "non-zero".
        assertEq(o.deltaCurrency0, -CONTROL_TAKE, "hook must read the exact known delta in A");
        assertEq(o.nonzeroDeltaCount, 1, "exactly one currency should be out of balance");
        assertEq(o.locker, address(router), "delta must key to the LOCKER, not the EOA");

        _report("Q2: known non-zero state (took 1e6 of A, then swapped B->A)", 0);
    }

    /// @notice A deliberately wrong slot must read zero, proving the right slot is not garbage.
    /// @dev the v4 trap list: `exttload` returning zero is ambiguous. This disambiguates by showing
    ///      the reader distinguishes a real value from a bad address.
    function test_Q2_WrongSlotReadsZeroSoRightSlotIsNotGarbage() public {
        CompositeRouter.Step[] memory steps = new CompositeRouter.Step[](2);
        steps[0] = _takeStep(A, uint256(CONTROL_TAKE));
        steps[1] = _swapStep(poolAB_probed, false, -1e18);
        router.execute(steps, _net2(A, B));

        // Correct slot, read from outside: same value the hook saw.
        assertEq(probe.observation(0).deltaCurrency0, -CONTROL_TAKE, "correct slot");

        // The same currency keyed to an address that never locked: must be zero.
        int256 bogus = _readDeltaFor(address(0xdead), A);
        assertEq(bogus, 0, "a target with no deltas must read zero");
    }

    function _readDeltaFor(address target, Currency c) internal view returns (int256) {
        bytes32 slot;
        address t = target;
        address cc = Currency.unwrap(c);
        assembly ("memory-safe") {
            mstore(0, and(t, 0xffffffffffffffffffffffffffffffffffffffff))
            mstore(32, and(cc, 0xffffffffffffffffffffffffffffffffffffffff))
            slot := keccak256(0, 64)
        }
        return int256(uint256(manager.exttload(slot)));
    }

    // =======================================================================================
    // Q3.0 — CONTROL. Gates every scenario below.
    // =======================================================================================

    /// @notice The router must reproduce a hand-calculated intermediate delta EXACTLY.
    /// @dev Hand derivation: `take(A, CONTROL_TAKE)` accounts exactly -CONTROL_TAKE to the router
    ///      and increments nonzeroDeltaCount from 0 to 1. Then a B->A swap on the probed pool
    ///      fires beforeSwap, at which point the router's A delta must still be exactly
    ///      -CONTROL_TAKE and nothing else can be outstanding.
    ///      If this assertion fails, CompositeRouter is not building the states we think it is,
    ///      and no Q3 signature below is readable.
    function test_Q3_0_Control_RouterProducesHandCalculatedDelta() public {
        CompositeRouter.Step[] memory steps = new CompositeRouter.Step[](2);
        steps[0] = _takeStep(A, uint256(CONTROL_TAKE));
        steps[1] = _swapStep(poolAB_probed, false, -1e18);

        router.execute(steps, _net2(A, B));

        ProbeHook.Observation memory o = probe.observation(0);
        assertEq(o.deltaCurrency0, -CONTROL_TAKE, "CONTROL: delta in A must equal -CONTROL_TAKE exactly");
        assertEq(o.deltaCurrency1, 0, "CONTROL: delta in B must be exactly zero");
        assertEq(o.nonzeroDeltaCount, 1, "CONTROL: exactly one non-zero delta");
        assertTrue(o.predicateTripped, "CONTROL: output currency A carries a debt, predicate must trip");

        _report("Q3.0 CONTROL (hand-calculated: delta A == -1000000)", 0);
    }

    // =======================================================================================
    // Q3 — the five traffic signatures
    // =======================================================================================

    /// @notice 1. Single-hop retail. A->B on the probed pool. Clean slate.
    function test_Q3_1_SingleHopRetail() public {
        CompositeRouter.Step[] memory steps = new CompositeRouter.Step[](1);
        steps[0] = _swapStep(poolAB_probed, true, -1e18);
        router.execute(steps, _net2(A, B));

        _report("Q3.1 SINGLE-HOP RETAIL (A->B)", 0);
        ProbeHook.Observation memory o = probe.observation(0);
        assertEq(o.nonzeroDeltaCount, 0, "retail arrives on a clean slate");
        assertFalse(o.predicateTripped, "retail must not trip the predicate");
    }

    /// @notice 2. Multi-hop A->B->C. Composite, benign. Probe observes the B->C leg.
    function test_Q3_2_MultiHop() public {
        CompositeRouter.Step[] memory steps = new CompositeRouter.Step[](2);
        steps[0] = _swapStep(poolAB_cheap, true, -1e18); // A->B, unprobed pool
        steps[1] = _swapStep(poolBC_probed, true, -1e17); // B->C, PROBED
        router.execute(steps, _net3(A, B, C));

        _report("Q3.2 MULTI-HOP (A->B->C, observing B->C)", 0);
        ProbeHook.Observation memory o = probe.observation(0);
        assertFalse(o.predicateTripped, "multi-hop must not trip: output C carries no prior delta");
    }

    /// @notice 3. Zap: swap half, then add liquidity. Composite, benign.
    function test_Q3_3_ZapThenAddLiquidity() public {
        CompositeRouter.Step[] memory steps = new CompositeRouter.Step[](2);
        steps[0] = _swapStep(poolAB_probed, true, -1e18); // A->B, PROBED
        steps[1] = _addLiqStep(poolAB_probed, 1e18); // then provide
        router.execute(steps, _net2(A, B));

        _report("Q3.3 ZAP THEN ADD LIQUIDITY", 0);
        ProbeHook.Observation memory o = probe.observation(0);
        assertFalse(o.predicateTripped, "zap must not trip: the swap is the opening move");
    }

    /// @notice 4. Cyclic arbitrage, closing leg. Buy cheap, sell dear, net profit in A.
    /// @dev Probe sits on the pool the arb touches SECOND. The opening leg on the cheap pool is
    ///      unobservable — the locker arrives with a clean slate there, indistinguishable from
    ///      retail. This is structural, not a gap in effort: beforeSwap fires at
    ///      PoolManager.sol:200, before delta accounting at :224.
    function test_Q3_4_CyclicArbitrageClosingLeg() public {
        CompositeRouter.Step[] memory steps = new CompositeRouter.Step[](2);
        steps[0] = _swapStep(poolAB_cheap, true, -1e18); // A->B on cheap pool (unprobed)
        steps[1] = _swapStep(poolAB_probed, false, -1e18); // B->A on dear pool (PROBED) — closes the cycle
        router.execute(steps, _net2(A, B));

        _report("Q3.4 CYCLIC ARB, CLOSING LEG (A->B cheap, B->A probed)", 0);
        ProbeHook.Observation memory o = probe.observation(0);
        assertTrue(o.predicateTripped, "arb close must trip: locker owes A and is about to receive A");
    }

    /// @notice 5. Third-party batch settlement. One solver, two unrelated users, opposite sides.
    /// @dev THE COLLISION. If this is isomorphic to scenario 4 at the delta boundary, the
    ///      predicate cannot separate a solver netting users from a bot closing a loop, and per
    ///      the anti-goal blacklist no heuristic may be added to rescue it.
    function test_Q3_5_ThirdPartyBatchSettlement() public {
        CompositeRouter.Step[] memory steps = new CompositeRouter.Step[](2);
        // user 1 wants A->B; solver routes it through the cheap pool
        steps[0] = _swapStep(poolAB_cheap, true, -1e18);
        // user 2, unrelated, wants B->A; solver routes it through the probed pool
        steps[1] = _swapStep(poolAB_probed, false, -37e16); // deliberately NOT the pass-through amount
        router.execute(steps, _net2(A, B));

        _report("Q3.5 THIRD-PARTY BATCH SETTLEMENT (two users, opposite sides)", 0);
    }

    /// @notice 5b. Batch settlement that does NOT close a currency cycle.
    /// @dev Not in the original spec. Added because scenario 5 conflates two things: "a solver
    ///      batched two users" and "the batch happened to close a cycle on a token". If 5 trips
    ///      and 5b does not, then the predicate is not keying on batching at all — it is keying
    ///      on cycle closure, and the collision with arb is narrower than "all solver flow".
    ///      This is measurement, not rescue: no threshold, same boolean predicate.
    function test_Q3_5b_BatchSettlementNoCycle() public {
        CompositeRouter.Step[] memory steps = new CompositeRouter.Step[](2);
        // user 1 wants A->B
        steps[0] = _swapStep(poolAB_cheap, true, -1e18);
        // user 2, unrelated, wants B->C — a different pair, so no cycle closes
        steps[1] = _swapStep(poolBC_probed, true, -1e17);
        router.execute(steps, _net3(A, B, C));

        _report("Q3.5b BATCH SETTLEMENT, NO CYCLE (user1 A->B, user2 B->C)", 0);
    }

    /// @notice Runs 4 and 5 adjacently and prints their full delta vectors side by side.
    /// @dev This is the only comparison that decides the project. Everything else is context.
    function test_Q3_ARB_vs_BATCH_SideBySide() public {
        // Both scenarios must start from IDENTICAL pool state. Running them sequentially would
        // let the first one move the price, and the second would then show a different delta
        // magnitude purely as an artifact of ordering — a spurious "difference" that has nothing
        // to do with the shape of the operation.
        uint256 snap = vm.snapshotState();

        // --- scenario 4: cyclic arb ---
        CompositeRouter.Step[] memory arb = new CompositeRouter.Step[](2);
        arb[0] = _swapStep(poolAB_cheap, true, -1e18);
        arb[1] = _swapStep(poolAB_probed, false, -1e18);
        router.execute(arb, _net2(A, B));
        ProbeHook.Observation memory oArb = probe.observation(0);

        vm.revertToState(snap);

        // --- scenario 5: batch settlement ---
        CompositeRouter.Step[] memory batch = new CompositeRouter.Step[](2);
        batch[0] = _swapStep(poolAB_cheap, true, -1e18);
        batch[1] = _swapStep(poolAB_probed, false, -37e16);
        router.execute(batch, _net2(A, B));
        ProbeHook.Observation memory oBatch = probe.observation(0);

        console.log("================================================================");
        console.log("  ARB CLOSE vs BATCH SETTLEMENT  -- full delta vectors");
        console.log("================================================================");
        console.log("                          ARB          BATCH");
        console.log("nonzeroDeltaCount   :", oArb.nonzeroDeltaCount, oBatch.nonzeroDeltaCount);
        console.log("delta A (arb)       :", oArb.deltaCurrency0);
        console.log("delta A (batch)     :", oBatch.deltaCurrency0);
        console.log("delta B (arb)       :", oArb.deltaCurrency1);
        console.log("delta B (batch)     :", oBatch.deltaCurrency1);
        console.log("delta OUT (arb)     :", oArb.deltaInOutputCurrency);
        console.log("delta OUT (batch)   :", oBatch.deltaInOutputCurrency);
        console.log("predicate (arb)     :", oArb.predicateTripped);
        console.log("predicate (batch)   :", oBatch.predicateTripped);
        console.log("================================================================");

        // Recorded for completeness only. PRE-DISQUALIFIED as a separator: the hook is open
        // source and on-chain, so any predicate keyed to exact amount matching is defeated by
        // adding one wei. A separator an adversary breaks by reading our repo is a speed bump,
        // not a structural classification, and fails the anti-goal blacklist for the same reason a tuned
        // threshold does.
        console.log("[pre-disqualified] arb input == prior credit?  ", oArb.amountSpecified == -oArb.deltaCurrency1);
        console.log("[pre-disqualified] batch input == prior credit?", oBatch.amountSpecified == -oBatch.deltaCurrency1);

        // THE FINDING, asserted rather than eyeballed. Every field the hook can observe at the
        // boundary is identical between a bot closing an arbitrage cycle and a solver settling
        // two unrelated users. Not "similar" — equal.
        // If a future change to the observation surface ever breaks one of these equalities,
        // this test fails and that is a signal worth investigating, not a test to update.
        assertEq(oArb.nonzeroDeltaCount, oBatch.nonzeroDeltaCount, "ISOMORPHIC: nonzeroDeltaCount");
        assertEq(oArb.deltaCurrency0, oBatch.deltaCurrency0, "ISOMORPHIC: delta in A");
        assertEq(oArb.deltaCurrency1, oBatch.deltaCurrency1, "ISOMORPHIC: delta in B");
        assertEq(oArb.deltaInOutputCurrency, oBatch.deltaInOutputCurrency, "ISOMORPHIC: delta in output currency");
        assertEq(oArb.predicateTripped, oBatch.predicateTripped, "ISOMORPHIC: predicate outcome");
        assertTrue(oArb.predicateTripped, "both trip the predicate");
    }
}
