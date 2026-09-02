// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// TENURE MILESTONE 0 — T2: THE IDENTITY GATE
//
// One question: can the hook bind a swap to a trader UNFORGEABLY, and does it fail closed when it
// cannot?
//
// This gate exists because of one failure class: the hook cannot trust what it is told. Tenure would
// die the same way if it trusted a router to name the trader: `IMsgSender.msgSender()` is
// self-reported, and a mechanism granting larger size caps on an unauthenticated claim has no
// mechanism at all.
//
// The happy path is not the test. The four fail-closed cases are the test.
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

import {TenureGateProbe, StandingRegistryStub} from "./gate/TenureGateProbe.sol";
import {CompositeRouter} from "./routers/CompositeRouter.sol";

contract TenureIdentityTest is Test, Deployers {
    using PoolIdLibrary for PoolKey;

    TenureGateProbe internal gate;
    StandingRegistryStub internal registry;
    CompositeRouter internal router;

    PoolKey internal gatedPool;
    bytes32 internal gatedPoolId;

    // The trader who has standing, and the adversary who does not.
    uint256 internal traderKey = 0xA11CE;
    uint256 internal eveKey = 0xE4E;
    address internal trader;
    address internal eve;

    int24 internal constant TICK_LOWER = -60000;
    int24 internal constant TICK_UPPER = 60000;
    int256 internal constant LIQUIDITY = 1e21;

    /// @dev Standing 4 => allowance 1e18 + 4*5e17 = 3e18. Chosen so the boundary is exact.
    uint256 internal constant TRADER_STANDING = 4;
    uint256 internal constant EXPECTED_ALLOWANCE = 3e18;

    function setUp() public {
        deployFreshManagerAndRouters();

        trader = vm.addr(traderKey);
        eve = vm.addr(eveKey);

        MockERC20[] memory tokens = deployTokens(2, 2 ** 255);
        (Currency c0, Currency c1) = address(tokens[0]) < address(tokens[1])
            ? (Currency.wrap(address(tokens[0])), Currency.wrap(address(tokens[1])))
            : (Currency.wrap(address(tokens[1])), Currency.wrap(address(tokens[0])));

        registry = new StandingRegistryStub();

        (address hookAddr, bytes32 salt) = HookMiner.find(
            address(this), uint160(Hooks.BEFORE_SWAP_FLAG), type(TenureGateProbe).creationCode, abi.encode(registry)
        );
        gate = new TenureGateProbe{salt: salt}(registry);
        require(address(gate) == hookAddr, "hook address mining failed");

        router = new CompositeRouter(manager);

        for (uint256 i = 0; i < 2; i++) {
            tokens[i].approve(address(modifyLiquidityRouter), type(uint256).max);
            tokens[i].transfer(address(router), 1e30);
        }

        (gatedPool,) = initPool(c0, c1, IHooks(address(gate)), 3000, SQRT_PRICE_1_1);
        gatedPoolId = PoolId.unwrap(gatedPool.toId());

        modifyLiquidityRouter.modifyLiquidity(
            gatedPool,
            IPoolManager.ModifyLiquidityParams({
                tickLower: TICK_LOWER, tickUpper: TICK_UPPER, liquidityDelta: LIQUIDITY, salt: bytes32(0)
            }),
            ZERO_BYTES
        );

        registry.setStanding(trader, TRADER_STANDING);
    }

    // ---------------------------------------------------------------------------------------
    // helpers
    // ---------------------------------------------------------------------------------------

    function _credential(uint256 maxSize, uint256 nonce, uint256 deadline)
        internal
        view
        returns (TenureGateProbe.DepthCredential memory c)
    {
        c = TenureGateProbe.DepthCredential({
            locker: address(router), poolId: gatedPoolId, maxSize: maxSize, nonce: nonce, deadline: deadline
        });
    }

    function _sign(uint256 pk, TenureGateProbe.DepthCredential memory c) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, gate.hashCredential(c));
        return abi.encodePacked(r, s, v);
    }

    function _swap(int256 amountSpecified, bytes memory hookData) internal {
        CompositeRouter.Step[] memory steps = new CompositeRouter.Step[](1);
        steps[0].kind = CompositeRouter.StepKind.SWAP;
        steps[0].key = gatedPool;
        steps[0].zeroForOne = true;
        steps[0].amountSpecified = amountSpecified;
        steps[0].hookData = hookData;

        Currency[] memory net = new Currency[](2);
        net[0] = gatedPool.currency0;
        net[1] = gatedPool.currency1;

        router.execute(steps, net);
    }

    /// @dev v4 wraps any hook revert in `CustomRevert.WrappedError`, so asserting on the bare
    ///      selector would silently pass on the wrong error. This rebuilds the exact wrapper so
    ///      each test still pins the *specific* failure it is claiming to prove.
    function _expectHookRevert(bytes memory innerError) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                CustomRevert.WrappedError.selector,
                address(gate),
                IHooks.beforeSwap.selector,
                innerError,
                abi.encodeWithSelector(Hooks.HookCallFailed.selector)
            )
        );
    }

    // =======================================================================================
    // The happy path — necessary, but not what this gate is testing.
    // =======================================================================================

    /// @notice A validly signed credential lets the trader consume up to their earned allowance.
    function test_T2_ValidCredentialPermitsSwapWithinAllowance() public {
        TenureGateProbe.DepthCredential memory c = _credential(EXPECTED_ALLOWANCE, 1, block.timestamp + 1 hours);
        _swap(-int256(EXPECTED_ALLOWANCE), abi.encode(c, _sign(traderKey, c)));

        assertTrue(gate.nonceUsed(trader, 1), "nonce must be consumed on success");
    }

    /// @notice Standing changes accessible depth and NOTHING else.
    function test_T2_StandingChangesDepthOnly() public view {
        assertEq(gate.depthAllowanceFor(0), 1e18, "zero standing still gets non-zero depth");
        assertEq(gate.depthAllowanceFor(TRADER_STANDING), EXPECTED_ALLOWANCE, "standing scales depth");

        // The anti-whitelist property: nobody is excluded. An address with no standing at all can
        // still trade, just smaller.
        assertGt(gate.depthAllowanceFor(0), 0, "no address may be denied access outright");
    }

    // =======================================================================================
    // THE GATE. Four fail-closed cases. All must revert.
    // =======================================================================================

    /// @notice CASE 1 — forged signature. Eve signs a credential naming herself as locker-bound,
    ///         but she has no standing, so her allowance is the base and the large swap fails.
    /// @dev This is the attack that matters: if identity were self-reported, Eve would simply claim
    ///      to be `trader` and take the larger size.
    function test_T2_FailsClosed_ForgedSignature() public {
        TenureGateProbe.DepthCredential memory c = _credential(EXPECTED_ALLOWANCE, 1, block.timestamp + 1 hours);

        // Eve signs the trader's credential. Recovery yields EVE, not the trader — so Eve gets
        // Eve's standing (zero), not the trader's.
        bytes memory eveSig = _sign(eveKey, c);

        _expectHookRevert(
            abi.encodeWithSelector(TenureGateProbe.ExceedsDepthAllowance.selector, EXPECTED_ALLOWANCE, 1e18)
        );
        _swap(-int256(EXPECTED_ALLOWANCE), abi.encode(c, eveSig));
    }

    /// @notice CASE 1b — a garbage signature must not recover to a usable address.
    function test_T2_FailsClosed_GarbageSignature() public {
        TenureGateProbe.DepthCredential memory c = _credential(EXPECTED_ALLOWANCE, 1, block.timestamp + 1 hours);
        bytes memory garbage = new bytes(65);

        _expectHookRevert(abi.encodeWithSelector(TenureGateProbe.InvalidSignature.selector));
        _swap(-int256(EXPECTED_ALLOWANCE), abi.encode(c, garbage));
    }

    /// @notice CASE 2 — missing credential. Absent hookData is a revert, never a default allowance.
    function test_T2_FailsClosed_MissingCredential() public {
        _expectHookRevert(abi.encodeWithSelector(TenureGateProbe.MissingCredential.selector));
        _swap(-int256(EXPECTED_ALLOWANCE), "");
    }

    /// @notice CASE 3 — replayed nonce. A credential is single-use.
    /// @dev A replayable signature is a size cap that never expires.
    function test_T2_FailsClosed_ReplayedNonce() public {
        TenureGateProbe.DepthCredential memory c = _credential(EXPECTED_ALLOWANCE, 7, block.timestamp + 1 hours);
        bytes memory sig = _sign(traderKey, c);
        bytes memory data = abi.encode(c, sig);

        _swap(-int256(1e18), data);
        assertTrue(gate.nonceUsed(trader, 7), "nonce consumed");

        _expectHookRevert(abi.encodeWithSelector(TenureGateProbe.ReplayedNonce.selector));
        _swap(-int256(1e18), data);
    }

    /// @notice CASE 4 — expired deadline.
    function test_T2_FailsClosed_ExpiredDeadline() public {
        TenureGateProbe.DepthCredential memory c = _credential(EXPECTED_ALLOWANCE, 1, block.timestamp + 1 hours);
        bytes memory sig = _sign(traderKey, c);

        vm.warp(block.timestamp + 2 hours);

        _expectHookRevert(abi.encodeWithSelector(TenureGateProbe.ExpiredCredential.selector));
        _swap(-int256(1e18), abi.encode(c, sig));
    }

    // =======================================================================================
    // Binding: the credential must not be liftable to another context.
    // =======================================================================================

    /// @notice A credential signed for a different locker must not work through this one.
    function test_T2_FailsClosed_WrongLocker() public {
        TenureGateProbe.DepthCredential memory c = _credential(EXPECTED_ALLOWANCE, 1, block.timestamp + 1 hours);
        c.locker = address(0xBEEF); // signed for some other router
        bytes memory sig = _sign(traderKey, c);

        _expectHookRevert(abi.encodeWithSelector(TenureGateProbe.WrongLocker.selector));
        _swap(-int256(1e18), abi.encode(c, sig));
    }

    /// @notice A credential signed for a different pool must not work on this one.
    function test_T2_FailsClosed_WrongPool() public {
        TenureGateProbe.DepthCredential memory c = _credential(EXPECTED_ALLOWANCE, 1, block.timestamp + 1 hours);
        c.poolId = bytes32(uint256(0xDEAD));
        bytes memory sig = _sign(traderKey, c);

        _expectHookRevert(abi.encodeWithSelector(TenureGateProbe.WrongPool.selector));
        _swap(-int256(1e18), abi.encode(c, sig));
    }

    /// @notice A credential cannot be stretched beyond the size the trader authorised, even if
    ///         their standing would otherwise permit it.
    function test_T2_FailsClosed_ExceedsSignedMaxSize() public {
        TenureGateProbe.DepthCredential memory c = _credential(1e18, 1, block.timestamp + 1 hours);
        bytes memory sig = _sign(traderKey, c);

        _expectHookRevert(abi.encodeWithSelector(TenureGateProbe.ExceedsDepthAllowance.selector, 2e18, 1e18));
        _swap(-int256(2e18), abi.encode(c, sig));
    }
}
