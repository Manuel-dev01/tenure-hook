// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// TENURE — STAGE 4. LP outcome A/B. MEASUREMENT ONLY, no mechanism changes.
//
// Three arms, identical traffic, identical starting state (snapshot/revert):
//
//   A  no tranching                      — the baseline
//   B  tranching, honest traffic         — the mechanism as it ships
//   C  tranching + the split attack      — does splitting buy anything?
//
// Arm C is the point. After the Stage 3.5 per-transaction meter it should converge to B, not A.
// If it converges to A instead, the meter does not work and that is the headline.
//
// HONESTY NOTE. Tranching reduces adverse fills AND reduces fee income. The net may be negative.
// This harness reports fees, inventory and net separately so a small or unfavourable result is
// visible rather than buried in one number.
//
// Derived from Uniswap v4-core test scaffolding (BUSL-1.1).

import {Test, console} from "forge-std/Test.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {FullMath} from "v4-core/src/libraries/FullMath.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {HookMiner} from "v4-periphery/test/shared/HookMiner.sol";

import {TenureHook} from "../src/TenureHook.sol";
import {OperatorStandingRegistry} from "../src/OperatorStandingRegistry.sol";
import {IStandingRegistry} from "../src/interfaces/IStandingRegistry.sol";
import {CompositeRouter} from "./routers/CompositeRouter.sol";

contract LPOutcomeTest is Test, Deployers {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    TenureHook internal hook;
    OperatorStandingRegistry internal registry;
    CompositeRouter internal router;

    PoolKey internal pool;
    bytes32 internal poolIdBytes;
    MockERC20 internal token0;
    MockERC20 internal token1;

    address internal operator = address(this);

    // The informed trader: one-sided history, so low standing, so a small depth share.
    uint256 internal informedKey = 0x1F0;
    address internal informed;
    // Retail: two-sided history, high standing.
    uint256 internal retailKey = 0xBEEF01;
    address internal retail;

    int24 internal constant TICK_LOWER = -60000;
    int24 internal constant TICK_UPPER = 60000;
    int256 internal constant LIQUIDITY = 1e22;

    uint256 internal constant TRANCHE = 100e18;

    /// @dev The size the informed trader wants to take atomically.
    int256 internal constant INFORMED_TARGET = 80e18;
    /// @dev Retail clip size, small relative to the tranche.
    int256 internal constant RETAIL_CLIP = 2e18;

    struct Arm {
        uint256 informedVolume; // informed size actually executed
        uint256 lp0; // token0 returned to the LP on exit (principal + fees)
        uint256 lp1; // token1 returned
        uint160 finalSqrtPrice;
    }

    function setUp() public {
        deployFreshManagerAndRouters();

        informed = vm.addr(informedKey);
        retail = vm.addr(retailKey);

        MockERC20[] memory tokens = deployTokens(2, 2 ** 255);
        (token0, token1) = address(tokens[0]) < address(tokens[1])
            ? (tokens[0], tokens[1])
            : (tokens[1], tokens[0]);

        registry = new OperatorStandingRegistry(operator);

        (address hookAddr, bytes32 salt) = HookMiner.find(
            address(this),
            uint160(Hooks.BEFORE_SWAP_FLAG),
            type(TenureHook).creationCode,
            abi.encode(manager, operator, IStandingRegistry(address(registry)))
        );
        hook = new TenureHook{salt: salt}(manager, operator, IStandingRegistry(address(registry)));
        require(address(hook) == hookAddr, "hook address mining failed");

        router = new CompositeRouter(manager);

        token0.approve(address(modifyLiquidityRouter), type(uint256).max);
        token1.approve(address(modifyLiquidityRouter), type(uint256).max);
        token0.transfer(address(router), 1e30);
        token1.transfer(address(router), 1e30);

        (pool,) = initPool(
            Currency.wrap(address(token0)), Currency.wrap(address(token1)), IHooks(address(hook)), 3000, SQRT_PRICE_1_1
        );
        poolIdBytes = PoolId.unwrap(pool.toId());

        _addLiquidity();

        // Standing: informed is one-sided (balance 0), retail is two-sided (balance 10000).
        // Both have enough samples for standing to be defined.
        registry.setStanding(informed, 0, 40);
        registry.setStanding(retail, 10_000, 40);
    }

    // ---------------------------------------------------------------------------------------
    // helpers
    // ---------------------------------------------------------------------------------------

    function _addLiquidity() internal {
        modifyLiquidityRouter.modifyLiquidity(
            pool,
            IPoolManager.ModifyLiquidityParams({
                tickLower: TICK_LOWER,
                tickUpper: TICK_UPPER,
                liquidityDelta: LIQUIDITY,
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );
    }

    function _credential(uint256 maxSize, uint256 nonce) internal view returns (TenureHook.DepthCredential memory c) {
        c = TenureHook.DepthCredential({
            locker: address(router),
            poolId: poolIdBytes,
            maxSize: maxSize,
            nonce: nonce,
            deadline: block.timestamp + 1 hours
        });
    }

    function _sign(uint256 pk, TenureHook.DepthCredential memory c) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, hook.hashCredential(c));
        return abi.encodePacked(r, s, v);
    }

    /// @dev Attempt one swap in its own transaction. Returns the size actually executed.
    ///      A denied swap is not a test failure — it is the mechanism working, and the trader
    ///      simply does not get that fill.
    function _try(int256 amount, bytes memory data) internal returns (uint256 executed) {
        CompositeRouter.Step[] memory steps = new CompositeRouter.Step[](1);
        steps[0].kind = CompositeRouter.StepKind.SWAP;
        steps[0].key = pool;
        steps[0].zeroForOne = true;
        steps[0].amountSpecified = amount;
        steps[0].hookData = data;

        Currency[] memory net = new Currency[](2);
        net[0] = pool.currency0;
        net[1] = pool.currency1;

        try router.execute(steps, net) {
            return amount < 0 ? uint256(-amount) : uint256(amount);
        } catch {
            return 0;
        }
    }

    /// @dev Attempt N swaps inside ONE transaction — the split attack.
    function _trySplit(int256[] memory amounts, bytes[] memory datas) internal returns (uint256 executed) {
        CompositeRouter.Step[] memory steps = new CompositeRouter.Step[](amounts.length);
        for (uint256 i = 0; i < amounts.length; i++) {
            steps[i].kind = CompositeRouter.StepKind.SWAP;
            steps[i].key = pool;
            steps[i].zeroForOne = true;
            steps[i].amountSpecified = amounts[i];
            steps[i].hookData = datas[i];
        }
        Currency[] memory net = new Currency[](2);
        net[0] = pool.currency0;
        net[1] = pool.currency1;

        try router.execute(steps, net) {
            for (uint256 i = 0; i < amounts.length; i++) {
                executed += uint256(-amounts[i]);
            }
        } catch {
            executed = 0;
        }
    }

    /// @dev Two-sided retail flow. Small clips, both directions, so it is genuinely two-sided.
    function _retailFlow() internal {
        for (uint256 i = 0; i < 4; i++) {
            TenureHook.DepthCredential memory c = _credential(TRANCHE, 100 + i);
            _try(-RETAIL_CLIP, abi.encode(c, _sign(retailKey, c)));
        }
    }

    /// @dev Close the LP position and report what came back (principal + fees).
    function _exitLP() internal returns (uint256 got0, uint256 got1) {
        uint256 b0 = token0.balanceOf(address(this));
        uint256 b1 = token1.balanceOf(address(this));
        modifyLiquidityRouter.modifyLiquidity(
            pool,
            IPoolManager.ModifyLiquidityParams({
                tickLower: TICK_LOWER,
                tickUpper: TICK_UPPER,
                liquidityDelta: -LIQUIDITY,
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );
        got0 = token0.balanceOf(address(this)) - b0;
        got1 = token1.balanceOf(address(this)) - b1;
    }

    /// @dev Fee income from the informed flow at the pool's 0.30% tier. Assumption-free: it is a
    ///      fixed fraction of realised volume, independent of any price path.
    function _fees(uint256 volume) internal pure returns (uint256) {
        return (volume * 3000) / 1_000_000;
    }

    /// @dev Value an LP's holdings in token0 terms at a given price.
    ///      Using ONE reference price across all arms is what makes them comparable: each arm ends
    ///      at a different price, so valuing each at its own price would compare different worlds.
    function _valueAt(uint256 amt0, uint256 amt1, uint160 sqrtPriceX96) internal pure returns (uint256) {
        // price(token1 in token0) = (sqrtP / 2^96)^2
        uint256 priceX96 = FullMath.mulDiv(uint256(sqrtPriceX96), uint256(sqrtPriceX96), 1 << 96);
        return amt0 + FullMath.mulDiv(amt1, priceX96, 1 << 96);
    }

    // ---------------------------------------------------------------------------------------
    // the arms
    // ---------------------------------------------------------------------------------------

    /// @param tranche 0 disables tranching entirely
    /// @param split   whether the informed trader attempts the split attack
    function _runArm(uint256 tranche, bool split) internal returns (Arm memory a) {
        if (tranche > 0) hook.setDepthTranche(pool, tranche);

        if (!split) {
            TenureHook.DepthCredential memory c = _credential(uint256(INFORMED_TARGET), 1);
            a.informedVolume = _try(-INFORMED_TARGET, abi.encode(c, _sign(informedKey, c)));
            // A rational trader denied the full size takes what they CAN, rather than giving up.
            // Modelling arm B as abandoning the trade while arm C falls back would compare two
            // different traders and make the split arm look artificially productive.
            if (a.informedVolume == 0 && tranche > 0) {
                uint256 cap0 = hook.maxSwapSize(pool, informed);
                TenureHook.DepthCredential memory cf = _credential(cap0, 998);
                a.informedVolume = _try(-int256(cap0), abi.encode(cf, _sign(informedKey, cf)));
            }
        } else {
            // Split the same target into cap-sized pieces inside one transaction.
            uint256 cap = hook.maxSwapSize(pool, informed);
            uint256 pieces = (uint256(INFORMED_TARGET) + cap - 1) / cap;
            int256[] memory amounts = new int256[](pieces);
            bytes[] memory datas = new bytes[](pieces);
            for (uint256 i = 0; i < pieces; i++) {
                amounts[i] = -int256(cap);
                TenureHook.DepthCredential memory c = _credential(cap, i + 1);
                datas[i] = abi.encode(c, _sign(informedKey, c));
            }
            a.informedVolume = _trySplit(amounts, datas);
            // A blocked split still leaves the honest single-swap route open.
            if (a.informedVolume == 0) {
                TenureHook.DepthCredential memory c2 = _credential(cap, 999);
                a.informedVolume = _try(-int256(cap), abi.encode(c2, _sign(informedKey, c2)));
            }
        }

        _retailFlow();

        (a.finalSqrtPrice,,,) = manager.getSlot0(pool.toId());
        (a.lp0, a.lp1) = _exitLP();
    }

    // =======================================================================================
    // THE MEASUREMENT
    // =======================================================================================

    function test_LPOutcome_ThreeArms() public {
        uint256 snap = vm.snapshotState();

        Arm memory A = _runArm(0, false);
        vm.revertToState(snap);
        snap = vm.snapshotState();

        Arm memory B = _runArm(TRANCHE, false);
        vm.revertToState(snap);
        snap = vm.snapshotState();

        Arm memory C = _runArm(TRANCHE, true);
        vm.revertToState(snap);

        // NO SINGLE "LP VALUE" NUMBER IS REPORTED, deliberately.
        //
        // Valuing every arm at one reference price requires assuming where the true price ends up,
        // and the SIGN of the result flips with that assumption: measured at P = 0.98 tranching
        // looks harmful, at P = 1.02 it looks beneficial. Picking the flattering price would be
        // precisely the tuned constant the anti-goal blacklist forbids.
        //
        // So this harness reports only what is assumption-free: realised volume, fee income, and
        // the raw inventory each arm leaves behind. Whether tranching HELPS the LP depends on
        // subsequent real prices, and that is measurable only against real market data — which is
        // Stage 5's fork-replay, not this sandbox.
        console.log("======== LP OUTCOME (assumption-free quantities only) ========");
        console.log("arm A  no tranching      informed volume:", A.informedVolume);
        console.log("       fees earned (1e18):", _fees(A.informedVolume));
        console.log("       lp token0:", A.lp0);
        console.log("       lp token1:", A.lp1);
        console.log("arm B  tranching         informed volume:", B.informedVolume);
        console.log("       fees earned (1e18):", _fees(B.informedVolume));
        console.log("       lp token0:", B.lp0);
        console.log("       lp token1:", B.lp1);
        console.log("arm C  tranching+split   informed volume:", C.informedVolume);
        console.log("       fees earned (1e18):", _fees(C.informedVolume));
        console.log("       lp token0:", C.lp0);
        console.log("       lp token1:", C.lp1);
        console.log("=============================================================");
        console.log("LP value is NOT reported: its sign depends on an assumed price. See");
        console.log("analysis/lp-outcome.md. Benefit is measured in Stage 5 on real data.");

        // --- the finding that matters: splitting must buy nothing ---
        assertEq(C.informedVolume, B.informedVolume, "SPLIT ATTACK: arm C must realise no more volume than arm B");
        assertLt(B.informedVolume, A.informedVolume, "tranching must actually restrain the informed take");
    }

    // =======================================================================================
    // S5 — the harness is the piece most likely to be green for the wrong reason.
    // It has no adversary and no revert to catch a mistake, so it gets mutated deliberately.
    // =======================================================================================

    /// @notice With tranching disabled on BOTH sides, the arms must be identical.
    /// @dev If they are not, the harness is measuring traffic ordering, fee accrual or rounding
    ///      rather than the mechanism — and every number it produces is void.
    function test_S5_HarnessCollapsesWhenTranchingDisabled() public {
        uint256 snap = vm.snapshotState();
        Arm memory X = _runArm(0, false);
        vm.revertToState(snap);
        snap = vm.snapshotState();
        Arm memory Y = _runArm(0, false);
        vm.revertToState(snap);

        assertEq(X.informedVolume, Y.informedVolume, "S5: identical arms must realise identical volume");
        assertEq(X.lp0, Y.lp0, "S5: identical arms must leave identical token0");
        assertEq(X.lp1, Y.lp1, "S5: identical arms must leave identical token1");
        assertEq(X.finalSqrtPrice, Y.finalSqrtPrice, "S5: identical arms must end at the same price");
    }

    /// @notice When nobody is capped, tranching must make no difference.
    /// @dev Gives the informed trader full standing, so the tranche never binds. Any residual
    ///      difference is harness artefact, not mechanism.
    function test_S5_NoDifferenceWhenNobodyIsCapped() public {
        registry.setStanding(informed, 10_000, 40);

        uint256 snap = vm.snapshotState();
        Arm memory noTranche = _runArm(0, false);
        vm.revertToState(snap);
        snap = vm.snapshotState();
        Arm memory withTranche = _runArm(TRANCHE, false);
        vm.revertToState(snap);

        assertEq(
            noTranche.informedVolume, withTranche.informedVolume, "S5: uncapped trader must be unaffected by tranching"
        );
        assertEq(noTranche.lp0, withTranche.lp0, "S5: uncapped traffic must leave LP identical (token0)");
        assertEq(noTranche.lp1, withTranche.lp1, "S5: uncapped traffic must leave LP identical (token1)");
    }
}
