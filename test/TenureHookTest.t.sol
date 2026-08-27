// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// TENURE — STAGE 1. The hook, standing alone. Zero Brevis.
//
// This suite must prove the hook is submittable on its own: if the circuit never lands, standing is
// written by the pool operator and this is still a valid, complete submission.
//
// Four required behaviours, per the Stage 1 brief:
//   1. cap enforced
//   2. replayed nonce reverts
//   3. expired deadline reverts
//   4. an unsigned swap gets BASE depth — not a revert
//
// (4) is the one that matters most for the pitch. Presenting a credential is how a trader claims
// MORE than base depth, never how they gain entry. Nobody is excluded.
//
// Derived from Uniswap v4-core test scaffolding (BUSL-1.1).

import {Test} from "forge-std/Test.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {CustomRevert} from "v4-core/src/libraries/CustomRevert.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {HookMiner} from "v4-periphery/test/shared/HookMiner.sol";

import {TenureHook} from "../src/TenureHook.sol";
import {OperatorStandingRegistry} from "../src/OperatorStandingRegistry.sol";
import {IStandingRegistry} from "../src/interfaces/IStandingRegistry.sol";
import {CompositeRouter} from "./routers/CompositeRouter.sol";

contract TenureHookTest is Test, Deployers {
    using PoolIdLibrary for PoolKey;

    TenureHook internal hook;
    OperatorStandingRegistry internal registry;
    CompositeRouter internal router;

    PoolKey internal pool;
    bytes32 internal poolIdBytes;

    address internal operator = address(this);

    uint256 internal traderKey = 0xA11CE;
    uint256 internal eveKey = 0xE4E;
    address internal trader;
    address internal eve;

    int24 internal constant TICK_LOWER = -60000;
    int24 internal constant TICK_UPPER = 60000;
    int256 internal constant LIQUIDITY = 1e21;

    /// @dev The pool's depth tranche: the most any single swap may consume.
    uint256 internal constant TRANCHE = 100e18;

    /// @dev Base is 500bps of the tranche = 5e18. This is the anti-whitelist floor.
    uint256 internal constant BASE_ALLOWED = 5e18;

    function setUp() public {
        deployFreshManagerAndRouters();

        trader = vm.addr(traderKey);
        eve = vm.addr(eveKey);

        MockERC20[] memory tokens = deployTokens(2, 2 ** 255);
        (Currency c0, Currency c1) = address(tokens[0]) < address(tokens[1])
            ? (Currency.wrap(address(tokens[0])), Currency.wrap(address(tokens[1])))
            : (Currency.wrap(address(tokens[1])), Currency.wrap(address(tokens[0])));

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

        for (uint256 i = 0; i < 2; i++) {
            tokens[i].approve(address(modifyLiquidityRouter), type(uint256).max);
            tokens[i].transfer(address(router), 1e30);
        }

        (pool,) = initPool(c0, c1, IHooks(address(hook)), 3000, SQRT_PRICE_1_1);
        poolIdBytes = PoolId.unwrap(pool.toId());

        modifyLiquidityRouter.modifyLiquidity(
            pool,
            IPoolManager.ModifyLiquidityParams({
                tickLower: TICK_LOWER, tickUpper: TICK_UPPER, liquidityDelta: LIQUIDITY, salt: bytes32(0)
            }),
            ZERO_BYTES
        );

        hook.setDepthTranche(pool, TRANCHE);
    }

    // ---------------------------------------------------------------------------------------
    // helpers
    // ---------------------------------------------------------------------------------------

    function _credential(uint256 maxSize, uint256 nonce, uint256 deadline)
        internal
        view
        returns (TenureHook.DepthCredential memory c)
    {
        c = TenureHook.DepthCredential({
            locker: address(router), poolId: poolIdBytes, maxSize: maxSize, nonce: nonce, deadline: deadline
        });
    }

    function _sign(uint256 pk, TenureHook.DepthCredential memory c) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, hook.hashCredential(c));
        return abi.encodePacked(r, s, v);
    }

    function _swap(int256 amountSpecified, bytes memory hookData) internal {
        CompositeRouter.Step[] memory steps = new CompositeRouter.Step[](1);
        steps[0].kind = CompositeRouter.StepKind.SWAP;
        steps[0].key = pool;
        steps[0].zeroForOne = true;
        steps[0].amountSpecified = amountSpecified;
        steps[0].hookData = hookData;

        Currency[] memory net = new Currency[](2);
        net[0] = pool.currency0;
        net[1] = pool.currency1;

        router.execute(steps, net);
    }

    /// @dev Execute several swaps in ONE transaction (one unlock), each with its own hookData.
    ///      This is the split attack: without a per-transaction meter, N cap-sized swaps take N
    ///      times the cap at near-zero extra cost.
    function _swapMany(int256[] memory amounts, bytes[] memory datas) internal {
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
        router.execute(steps, net);
    }

    /// @dev v4 wraps hook reverts in `CustomRevert.WrappedError`; asserting the bare selector would
    ///      pass on the wrong error. This rebuilds the wrapper so each test pins its exact failure.
    function _expectHookRevert(bytes memory innerError) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                CustomRevert.WrappedError.selector,
                address(hook),
                IHooks.beforeSwap.selector,
                innerError,
                abi.encodeWithSelector(Hooks.HookCallFailed.selector)
            )
        );
    }

    // =======================================================================================
    // 4. Unsigned swap gets BASE depth — nobody is excluded
    // =======================================================================================

    /// @notice A swap presenting no credential at all still executes, at base depth.
    /// @dev THE ANTI-WHITELIST PROPERTY. If this test ever becomes a revert, Tenure has turned into
    ///      an allowlist and the pitch is dead.
    function test_UnsignedSwapGetsBaseDepth() public {
        _swap(-int256(BASE_ALLOWED), "");
        assertEq(hook.maxSwapSize(pool, address(0)), BASE_ALLOWED, "base depth is 5% of tranche");
    }

    /// @notice An unsigned swap above base depth is capped.
    function test_UnsignedSwapAboveBaseDepthReverts() public {
        _expectHookRevert(
            abi.encodeWithSelector(TenureHook.ExceedsDepthAllowance.selector, BASE_ALLOWED + 1, BASE_ALLOWED)
        );
        _swap(-int256(BASE_ALLOWED + 1), "");
    }

    /// @notice Base depth is non-zero for every address, including one with no standing.
    function test_NobodyIsExcluded() public view {
        assertEq(hook.depthFractionBps(0), 500, "zero standing still reaches 5% of the tranche");
        assertGt(hook.maxSwapSize(pool, eve), 0, "no address may be denied access outright");
    }

    // =======================================================================================
    // 1. Cap enforced, and standing raises it continuously
    // =======================================================================================

    /// @notice Standing raises accessible depth, and a credential unlocks it.
    function test_StandingRaisesAccessibleDepth() public {
        registry.setStanding(trader, uint16(hook.FULL_DEPTH_STANDING()), 20);
        assertEq(hook.maxSwapSize(pool, trader), TRANCHE, "full standing reaches the whole tranche");

        TenureHook.DepthCredential memory c = _credential(TRANCHE, 1, block.timestamp + 1 hours);
        _swap(-int256(TRANCHE), abi.encode(c, _sign(traderKey, c)));

        assertTrue(hook.nonceUsed(trader, 1), "nonce consumed on success");
    }

    /// @notice A swap above the trader's earned depth reverts, even with a valid credential.
    function test_CapEnforcedAboveStanding() public {
        registry.setStanding(trader, 5000, 20); // half way => 5250bps => 52.5e18
        uint256 allowed = hook.maxSwapSize(pool, trader);
        assertEq(allowed, 52.5e18, "linear interpolation, no cliff");

        TenureHook.DepthCredential memory c = _credential(TRANCHE, 1, block.timestamp + 1 hours);
        // Sign BEFORE arming expectRevert: _sign calls hook.hashCredential(), an external call
        // that would otherwise consume the expectation and pass for the wrong reason.
        bytes memory data = abi.encode(c, _sign(traderKey, c));
        _expectHookRevert(abi.encodeWithSelector(TenureHook.ExceedsDepthAllowance.selector, allowed + 1, allowed));
        _swap(-int256(allowed + 1), data);
    }

    /// @notice Depth is continuous and monotonic — no brackets to be sorted into.
    function test_DepthIsContinuousAndMonotonic() public view {
        uint256 prev = hook.depthFractionBps(0);
        assertEq(prev, hook.BASE_DEPTH_BPS(), "starts at base");
        for (uint256 s = 500; s <= 12_000; s += 500) {
            uint256 cur = hook.depthFractionBps(s);
            assertGe(cur, prev, "monotonic");
            assertLe(cur - prev, 600, "no cliff between adjacent standings");
            prev = cur;
        }
        assertEq(hook.depthFractionBps(hook.FULL_DEPTH_STANDING()), hook.BPS(), "caps at 100%");
        assertEq(hook.depthFractionBps(type(uint128).max), hook.BPS(), "never exceeds 100%");
    }

    /// @notice A credential cannot be stretched past the size the trader signed for.
    function test_CannotExceedSignedMaxSize() public {
        registry.setStanding(trader, uint16(hook.FULL_DEPTH_STANDING()), 20);
        TenureHook.DepthCredential memory c = _credential(10e18, 1, block.timestamp + 1 hours);
        bytes memory data = abi.encode(c, _sign(traderKey, c));
        _expectHookRevert(abi.encodeWithSelector(TenureHook.ExceedsDepthAllowance.selector, 20e18, 10e18));
        _swap(-int256(20e18), data);
    }

    // =======================================================================================
    // 2 & 3. Replay and expiry
    // =======================================================================================

    /// @notice A credential is single-use.
    function test_ReplayedNonceReverts() public {
        registry.setStanding(trader, uint16(hook.FULL_DEPTH_STANDING()), 20);
        TenureHook.DepthCredential memory c = _credential(TRANCHE, 7, block.timestamp + 1 hours);
        bytes memory data = abi.encode(c, _sign(traderKey, c));

        _swap(-int256(10e18), data);
        assertTrue(hook.nonceUsed(trader, 7), "nonce consumed");

        _expectHookRevert(abi.encodeWithSelector(TenureHook.ReplayedNonce.selector));
        _swap(-int256(10e18), data);
    }

    /// @notice An expired credential reverts. A replayable signature is a cap that never expires.
    function test_ExpiredDeadlineReverts() public {
        registry.setStanding(trader, uint16(hook.FULL_DEPTH_STANDING()), 20);
        TenureHook.DepthCredential memory c = _credential(TRANCHE, 1, block.timestamp + 1 hours);
        bytes memory data = abi.encode(c, _sign(traderKey, c));

        vm.warp(block.timestamp + 2 hours);

        _expectHookRevert(abi.encodeWithSelector(TenureHook.ExpiredCredential.selector));
        _swap(-int256(10e18), data);
    }

    // =======================================================================================
    // Forgery — the credential must be unforgeable and unliftable
    // =======================================================================================

    /// @notice Eve signing the trader's credential gets EVE's standing, not the trader's.
    function test_ForgedSignatureGetsForgersStanding() public {
        registry.setStanding(trader, uint16(hook.FULL_DEPTH_STANDING()), 20);
        TenureHook.DepthCredential memory c = _credential(TRANCHE, 1, block.timestamp + 1 hours);
        bytes memory data = abi.encode(c, _sign(eveKey, c));

        _expectHookRevert(abi.encodeWithSelector(TenureHook.ExceedsDepthAllowance.selector, TRANCHE, BASE_ALLOWED));
        _swap(-int256(TRANCHE), data);
    }

    /// @notice A malformed signature reverts rather than resolving to a usable address.
    function test_GarbageSignatureReverts() public {
        TenureHook.DepthCredential memory c = _credential(TRANCHE, 1, block.timestamp + 1 hours);
        _expectHookRevert(abi.encodeWithSelector(TenureHook.InvalidSignature.selector));
        _swap(-int256(1e18), abi.encode(c, new bytes(65)));
    }

    /// @notice A credential signed for another router cannot be used through this one.
    function test_WrongLockerReverts() public {
        TenureHook.DepthCredential memory c = _credential(TRANCHE, 1, block.timestamp + 1 hours);
        c.locker = address(0xBEEF);
        bytes memory data = abi.encode(c, _sign(traderKey, c));
        _expectHookRevert(abi.encodeWithSelector(TenureHook.WrongLocker.selector));
        _swap(-int256(1e18), data);
    }

    /// @notice A credential signed for another pool cannot be used on this one.
    function test_WrongPoolReverts() public {
        TenureHook.DepthCredential memory c = _credential(TRANCHE, 1, block.timestamp + 1 hours);
        c.poolId = bytes32(uint256(0xDEAD));
        bytes memory data = abi.encode(c, _sign(traderKey, c));
        _expectHookRevert(abi.encodeWithSelector(TenureHook.WrongPool.selector));
        _swap(-int256(1e18), data);
    }

    // =======================================================================================
    // The fee-parity rule — the fee is identical for every address
    // =======================================================================================

    /// @notice The hook holds no fee permission, so it cannot alter execution economics at all.
    /// @dev Fee neutrality is enforced by the mined address, not merely by policy. If
    ///      beforeSwapReturnDelta were ever set, this test fails and the fee-parity rule has been violated.
    function test_FeeParity_HookHoldsNoFeePermission() public view {
        Hooks.Permissions memory p = hook.getHookPermissions();
        assertFalse(p.beforeSwapReturnDelta, "hook must not be able to return a swap delta");
        assertFalse(p.afterSwapReturnDelta, "hook must not be able to return a swap delta");

        uint160 bits = uint160(address(hook)) & 0x3FFF;
        assertEq(bits & uint160(Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG), 0, "address must not encode fee power");
        assertEq(bits & uint160(Hooks.BEFORE_SWAP_FLAG), uint160(Hooks.BEFORE_SWAP_FLAG), "beforeSwap only");
    }

    /// @notice Two addresses with different standing are quoted the same fee.
    /// @dev Standing changes accessible depth and nothing else.
    function test_FeeParity_StandingDoesNotChangeFee() public {
        registry.setStanding(trader, uint16(hook.FULL_DEPTH_STANDING()), 20);
        registry.setStanding(eve, 0, 20);

        // Same pool, same fee tier, regardless of who is swapping.
        assertEq(pool.fee, 3000, "fee is a property of the pool, not the trader");
        assertGt(hook.maxSwapSize(pool, trader), hook.maxSwapSize(pool, eve), "only depth differs");
    }

    // =======================================================================================
    // STAGE 3.5 — the per-transaction depth meter
    //
    // Without this, the cap is cosmetic: sign several credentials, split one large take into N
    // cap-sized swaps in one transaction, pay almost nothing extra. "Depth is the product" would
    // gate nothing at all.
    // =======================================================================================

    /// @notice Credentialed splitting reverts once the cumulative entitlement is crossed.
    /// @dev THE ATTACK THIS STAGE EXISTS TO STOP.
    function test_Meter_CredentialedSplittingRevertsAtCap() public {
        registry.setStanding(trader, 5000, 20); // entitled = 52.5e18
        uint256 entitled = hook.maxSwapSize(pool, trader);
        assertEq(entitled, 52.5e18, "entitlement");

        // Three swaps of 20e18 = 60e18 > 52.5e18. The third must fail.
        int256[] memory amounts = new int256[](3);
        bytes[] memory datas = new bytes[](3);
        for (uint256 i = 0; i < 3; i++) {
            amounts[i] = -int256(20e18);
            TenureHook.DepthCredential memory c = _credential(entitled, i + 1, block.timestamp + 1 hours);
            datas[i] = abi.encode(c, _sign(traderKey, c));
        }

        // consumed 40e18, remaining 12.5e18, requesting 20e18
        _expectHookRevert(
            abi.encodeWithSelector(TenureHook.DepthExhaustedThisTx.selector, uint256(20e18), uint256(12.5e18))
        );
        _swapMany(amounts, datas);
    }

    /// @notice Multiple credentials from one trader do not stack the ceiling.
    /// @dev Consumption is keyed to the recovered trader, not the credential, and checked against
    ///      the standing entitlement — so minting more signatures buys nothing.
    function test_Meter_TwoCredentialsDoNotStack() public {
        registry.setStanding(trader, 0, 20); // base only: 5e18
        uint256 entitled = hook.maxSwapSize(pool, trader);
        assertEq(entitled, BASE_ALLOWED, "base entitlement");

        int256[] memory amounts = new int256[](2);
        bytes[] memory datas = new bytes[](2);
        for (uint256 i = 0; i < 2; i++) {
            amounts[i] = -int256(BASE_ALLOWED);
            // Each credential authorises the full base amount, with a distinct nonce.
            TenureHook.DepthCredential memory c = _credential(BASE_ALLOWED, i + 1, block.timestamp + 1 hours);
            datas[i] = abi.encode(c, _sign(traderKey, c));
        }

        _expectHookRevert(abi.encodeWithSelector(TenureHook.DepthExhaustedThisTx.selector, BASE_ALLOWED, uint256(0)));
        _swapMany(amounts, datas);
    }

    /// @notice Unsigned swaps are metered too. Anonymity is not an exemption.
    /// @dev If unsigned swaps were exempt, the cheapest route to the whole book would be to sign
    ///      NOTHING and split at base depth — making standing strictly worse than no standing and
    ///      running the mechanism backwards. This test makes that defect impossible to reintroduce
    ///      silently.
    function test_Meter_UnsignedSplittingRevertsAtBaseCap() public {
        int256[] memory amounts = new int256[](2);
        bytes[] memory datas = new bytes[](2);
        amounts[0] = -int256(BASE_ALLOWED);
        amounts[1] = -int256(BASE_ALLOWED);
        datas[0] = "";
        datas[1] = "";

        _expectHookRevert(abi.encodeWithSelector(TenureHook.DepthExhaustedThisTx.selector, BASE_ALLOWED, uint256(0)));
        _swapMany(amounts, datas);
    }

    /// @notice A zero-standing signer is valid, gets base depth, and carries their own bucket.
    /// @dev The permissionless escape: a user a router would otherwise batch into a shared
    ///      anonymous bucket can sign for free and be metered separately. No standing required.
    function test_Meter_ZeroStandingCredentialGetsItsOwnBucket() public {
        // eve has no standing recorded at all.
        assertEq(hook.standingOf(eve), 0, "no standing");

        // An unsigned swap consumes the anonymous bucket...
        int256[] memory amounts = new int256[](2);
        bytes[] memory datas = new bytes[](2);
        amounts[0] = -int256(BASE_ALLOWED);
        datas[0] = "";
        // ...and eve, signing with zero standing, still gets a full base allowance of her own.
        amounts[1] = -int256(BASE_ALLOWED);
        TenureHook.DepthCredential memory c = _credential(BASE_ALLOWED, 1, block.timestamp + 1 hours);
        datas[1] = abi.encode(c, _sign(eveKey, c));

        _swapMany(amounts, datas); // must NOT revert

        assertEq(hook.consumedDepthThisTx(address(0)), 0, "accumulator cleared after the tx");
    }

    /// @notice The meter clears between transactions.
    /// @dev Q1's cross-transaction property, applied here. Requires --isolate; gate.sh enforces it.
    function test_Meter_ClearsBetweenTransactions() public {
        registry.setStanding(trader, 0, 20);

        TenureHook.DepthCredential memory c1 = _credential(BASE_ALLOWED, 1, block.timestamp + 1 hours);
        _swap(-int256(BASE_ALLOWED), abi.encode(c1, _sign(traderKey, c1)));

        // A second transaction gets a fresh allowance rather than a spent one.
        TenureHook.DepthCredential memory c2 = _credential(BASE_ALLOWED, 2, block.timestamp + 1 hours);
        _swap(-int256(BASE_ALLOWED), abi.encode(c2, _sign(traderKey, c2)));
    }

    /// @notice Swapping within the entitlement is never restricted by the meter.
    /// @dev The meter must bind only at the ceiling, not shave allowance off honest use.
    function test_Meter_DoesNotRestrictWithinEntitlement() public {
        registry.setStanding(trader, uint16(hook.FULL_DEPTH_STANDING()), 20); // full tranche

        int256[] memory amounts = new int256[](3);
        bytes[] memory datas = new bytes[](3);
        for (uint256 i = 0; i < 3; i++) {
            amounts[i] = -int256(30e18); // 90e18 total, under the 100e18 tranche
            TenureHook.DepthCredential memory c = _credential(TRANCHE, i + 1, block.timestamp + 1 hours);
            datas[i] = abi.encode(c, _sign(traderKey, c));
        }
        _swapMany(amounts, datas); // must NOT revert
    }
}
