// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {IExttload} from "v4-core/src/interfaces/IExttload.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {CurrencySettler} from "v4-core/test/utils/CurrencySettler.sol";
import {TransientDeltaReader} from "../probe/TransientDeltaReader.sol";

/// @title CompositeRouter — the Milestone 0 instrument.
/// @notice Executes an ordered script of pool operations inside a SINGLE `unlock`, so that
///         multi-leg composite operations are visible to hooks mid-flight.
///
/// @dev WHY THIS EXISTS. v4-core's `PoolSwapTest` calls `manager.unlock()` once per `swap()` and
///      fully settles every delta before returning (see PoolSwapTest.unlockCallback). A hook
///      observing at `beforeSwap` therefore sees `nonzeroDeltaCount == 0` on every scenario built
///      from stock routers — every traffic type looks identical, and Q3 would return "no
///      separation" for a tooling reason rather than a real one. That is a false negative, which
///      is the worst outcome available here: it kills a live hypothesis and we never learn it was
///      alive. `ActionsRouter` batches within one unlock but has no SWAP action, so it cannot
///      build multi-leg routes either.
///
/// @dev CONSEQUENCE FOR VALIDITY. Because this router authors the traffic we then measure, every
///      Q3 number inherits its correctness. `test_Control_*` in DiscriminatorTest asserts this
///      router reproduces a hand-calculated intermediate delta before any scenario is recorded.
///      All scenarios run through this one router so that any difference in observed signature is
///      attributable to the shape of the operation and not to router idiosyncrasy.
///
/// @dev Derived from Uniswap v4-core test scaffolding (BUSL-1.1); settlement uses v4-core's
///      `CurrencySettler`.
contract CompositeRouter is IUnlockCallback {
    using CurrencySettler for Currency;
    using TransientDeltaReader for IExttload;

    /// @notice The kind of operation a script step performs.
    enum StepKind {
        SWAP,
        ADD_LIQUIDITY,
        TAKE,
        SETTLE
    }

    /// @notice One step of a composite operation. Fields not relevant to `kind` are ignored.
    struct Step {
        StepKind kind;
        PoolKey key; // SWAP, ADD_LIQUIDITY
        bool zeroForOne; // SWAP
        int256 amountSpecified; // SWAP: negative = exactIn, positive = exactOut
        int24 tickLower; // ADD_LIQUIDITY
        int24 tickUpper; // ADD_LIQUIDITY
        int256 liquidityDelta; // ADD_LIQUIDITY
        Currency currency; // TAKE, SETTLE
        uint256 amount; // TAKE, SETTLE
        bytes hookData; // SWAP, ADD_LIQUIDITY — forwarded to the pool's hook
    }

    IPoolManager public immutable manager;

    error UnauthorizedCallback();

    constructor(IPoolManager _manager) {
        manager = _manager;
    }

    /// @notice Run a script of steps inside one unlock, then net out every listed currency.
    /// @param steps The ordered operations to perform. All execute in a single unlock, so deltas
    ///        accumulate across them and are visible to hooks at each `beforeSwap`.
    /// @param toNet Currencies to settle/take at the end of the script. Any currency the script
    ///        touches must appear here or the unlock reverts with `CurrencyNotSettled`.
    function execute(Step[] calldata steps, Currency[] calldata toNet) external payable {
        manager.unlock(abi.encode(steps, toNet));
    }

    /// @notice PoolManager callback. Executes the script, then nets out.
    /// @param data ABI-encoded (Step[], Currency[]).
    /// @return An empty bytes value.
    function unlockCallback(bytes calldata data) external override returns (bytes memory) {
        if (msg.sender != address(manager)) revert UnauthorizedCallback();

        (Step[] memory steps, Currency[] memory toNet) = abi.decode(data, (Step[], Currency[]));

        for (uint256 i = 0; i < steps.length; i++) {
            _runStep(steps[i]);
        }

        // Net out only AFTER every step has run, so intermediate legs observe live deltas.
        for (uint256 i = 0; i < toNet.length; i++) {
            _net(toNet[i]);
        }

        return "";
    }

    /// @dev Dispatch a single script step.
    function _runStep(Step memory s) internal {
        if (s.kind == StepKind.SWAP) {
            manager.swap(
                s.key,
                IPoolManager.SwapParams({
                    zeroForOne: s.zeroForOne,
                    amountSpecified: s.amountSpecified,
                    // Unbounded: these scenarios are about delta shape, not price limits.
                    sqrtPriceLimitX96: s.zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
                }),
                s.hookData
            );
        } else if (s.kind == StepKind.ADD_LIQUIDITY) {
            manager.modifyLiquidity(
                s.key,
                IPoolManager.ModifyLiquidityParams({
                    tickLower: s.tickLower,
                    tickUpper: s.tickUpper,
                    liquidityDelta: s.liquidityDelta,
                    salt: bytes32(0)
                }),
                s.hookData
            );
        } else if (s.kind == StepKind.TAKE) {
            s.currency.take(manager, address(this), s.amount, false);
        } else {
            s.currency.settle(manager, address(this), s.amount, false);
        }
    }

    /// @dev Settle a debt or take a credit so the unlock can close.
    ///      Reads our own delta through the same reader the hook uses.
    function _net(Currency currency) internal {
        int256 delta = IExttload(address(manager)).currencyDelta(address(this), currency);
        if (delta < 0) {
            // casting to 'uint256' is safe because the branch guarantees delta < 0, so -delta > 0
            // forge-lint: disable-next-line(unsafe-typecast)
            currency.settle(manager, address(this), uint256(-delta), false);
        } else if (delta > 0) {
            // casting to 'uint256' is safe because the branch guarantees delta > 0
            // forge-lint: disable-next-line(unsafe-typecast)
            currency.take(manager, address(this), uint256(delta), false);
        }
    }

    receive() external payable {}
}
