// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {TransientStateLibrary} from "v4-core/src/libraries/TransientStateLibrary.sol";
import {CurrencySettler} from "v4-core/test/utils/CurrencySettler.sol";

/// @title TenureSwapRouter
/// @notice The router the demo app swaps through. Executes one or more swap legs inside a SINGLE
///         `unlock`, forwarding each leg's `hookData` to the pool's hook, and settles every
///         resulting delta directly against the swapper.
///
/// @dev WHY NOT `PoolSwapTest` OR `CompositeRouter`. `PoolSwapTest` opens its own `unlock` per
///      swap and fully settles before returning, so a multi-leg route collapses into several
///      independent transactions and the per-transaction depth meter would never bind — the
///      splitting demonstration would silently prove nothing. `CompositeRouter` (test/routers) does
///      hold one unlock across legs, but it `take`s and `settle`s against `address(this)`, which is
///      correct for a test contract holding its own balances and wrong for a user-facing router.
///      This contract keeps the single-unlock property and moves funds to and from the SWAPPER.
///
/// @dev CUSTODY. This router never holds tokens. `CurrencySettler.settle` with a payer other than
///      `address(this)` performs `transferFrom(payer, manager, amount)`, and `take` sends straight
///      to the recipient. The swapper therefore approves THIS ROUTER for the input currency, and
///      output arrives in their own wallet. There is no sweep function because there is nothing to
///      sweep.
///
/// @dev THE ROUTER IS THE LOCKER, AND THAT IS LOAD-BEARING. `TenureHook` receives this contract's
///      address as `sender` in `beforeSwap`, and requires the presented credential's `locker`
///      field to equal it. A credential signed for a different router is rejected with
///      `WrongLocker`. That binding is why standing cannot be lifted from one route to another,
///      and it is the reason the hook never trusts a self-reported `msgSender()`.
///
/// @dev NO FEE LOGIC EXISTS HERE AND NONE MAY BE ADDED (the fee-parity rule). This contract routes
///      and settles. It cannot and must not influence what anyone pays.
contract TenureSwapRouter is IUnlockCallback {
    using CurrencySettler for Currency;
    using TransientStateLibrary for IPoolManager;

    /// @notice One swap leg. Several legs in one call share a single transaction, which is what
    ///         the hook's per-transaction depth meter accumulates across.
    struct Leg {
        bool zeroForOne;
        /// @dev Negative is exact-input, positive is exact-output, matching v4's convention.
        int256 amountSpecified;
        /// @dev ABI-encoded (TenureHook.DepthCredential, signature). Empty means unsigned, which
        ///      is a supported path: the swap still executes, at base depth.
        bytes hookData;
    }

    /// @dev Which entry point opened the unlock.
    enum Action {
        SWAP,
        ADD_LIQUIDITY
    }

    IPoolManager public immutable manager;

    error UnauthorizedCallback();
    error NoLegs();

    constructor(IPoolManager _manager) {
        manager = _manager;
    }

    /// @notice Execute one or more swap legs against `key` in a single transaction.
    /// @param key The pool.
    /// @param legs The ordered legs. Every leg's `hookData` is forwarded to the hook untouched.
    function swap(PoolKey calldata key, Leg[] calldata legs) external payable {
        if (legs.length == 0) revert NoLegs();
        manager.unlock(abi.encode(Action.SWAP, msg.sender, key, abi.encode(legs)));
    }

    /// @notice Provide liquidity to `key`, settling against the caller.
    /// @dev Present so the demonstration pool can be seeded through the same contract the app
    ///      already talks to, rather than deploying a second router for one call. It is ordinary
    ///      position management and touches nothing the hook reads — `TenureHook` implements
    ///      `beforeSwap` only, so no `hookData` is forwarded here.
    /// @param key The pool.
    /// @param tickLower Lower tick of the position.
    /// @param tickUpper Upper tick of the position.
    /// @param liquidityDelta Liquidity to add (positive) or remove (negative).
    function addLiquidity(PoolKey calldata key, int24 tickLower, int24 tickUpper, int256 liquidityDelta) external {
        manager.unlock(
            abi.encode(Action.ADD_LIQUIDITY, msg.sender, key, abi.encode(tickLower, tickUpper, liquidityDelta))
        );
    }

    /// @notice PoolManager callback. Runs the requested action, then nets both currencies against
    ///         the caller.
    /// @param data ABI-encoded (Action, address caller, PoolKey, bytes payload).
    /// @return An empty bytes value.
    function unlockCallback(bytes calldata data) external override returns (bytes memory) {
        if (msg.sender != address(manager)) revert UnauthorizedCallback();

        (Action action, address caller, PoolKey memory key, bytes memory payload) =
            abi.decode(data, (Action, address, PoolKey, bytes));

        if (action == Action.SWAP) {
            Leg[] memory legs = abi.decode(payload, (Leg[]));
            for (uint256 i = 0; i < legs.length; i++) {
                manager.swap(
                    key,
                    IPoolManager.SwapParams({
                        zeroForOne: legs[i].zeroForOne,
                        amountSpecified: legs[i].amountSpecified,
                        // Unbounded. This demo is about the depth cap, not about price limits; a
                        // real integration would take a limit from the caller.
                        sqrtPriceLimitX96: legs[i].zeroForOne
                            ? TickMath.MIN_SQRT_PRICE + 1
                            : TickMath.MAX_SQRT_PRICE - 1
                    }),
                    legs[i].hookData
                );
            }
        } else {
            (int24 tickLower, int24 tickUpper, int256 liquidityDelta) = abi.decode(payload, (int24, int24, int256));
            manager.modifyLiquidity(
                key,
                IPoolManager.ModifyLiquidityParams({
                    tickLower: tickLower, tickUpper: tickUpper, liquidityDelta: liquidityDelta, salt: bytes32(0)
                }),
                ""
            );
        }

        // Net only AFTER every leg, so the deltas accumulate within one unlock and the hook sees
        // each leg mid-flight. Netting per leg would defeat the point of batching them.
        _net(key.currency0, caller);
        _net(key.currency1, caller);

        return "";
    }

    /// @dev Settle a debt from, or deliver a credit to, the swapper.
    function _net(Currency currency, address swapper) internal {
        int256 delta = manager.currencyDelta(address(this), currency);
        if (delta < 0) {
            // Safe: the branch guarantees delta < 0, so -delta > 0.
            // forge-lint: disable-next-line(unsafe-typecast)
            currency.settle(manager, swapper, uint256(-delta), false);
        } else if (delta > 0) {
            // Safe: the branch guarantees delta > 0.
            // forge-lint: disable-next-line(unsafe-typecast)
            currency.take(manager, swapper, uint256(delta), false);
        }
    }

    receive() external payable {}
}
