// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseTestHooks} from "v4-core/src/test/BaseTestHooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IExttload} from "v4-core/src/interfaces/IExttload.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {TransientDeltaReader} from "./TransientDeltaReader.sol";

/// @title ProbeHook — Milestone 0 instrument. Disposable.
/// @notice Observes the PoolManager's transient flash-accounting state at `beforeSwap` and
///         records it. Prices NOTHING: returns ZERO_DELTA and a zero fee override, always.
///
/// @dev This contract exists to answer the go/no-go gate's Q1/Q2/Q3 and is expected to be deleted
///      afterwards. It deliberately contains no classification and no pricing — per the go/no-go gate, no hook
///      logic may be written until the go/no-go gate is answered.
///
/// @dev Built on `BaseTestHooks` (v4-core/src/test/BaseTestHooks.sol), NOT on a production hook
///      base. v4-periphery removed `src/utils/BaseHook.sol`; its successor lives in OpenZeppelin's
///      `uniswap-hooks`. BaseTestHooks is a test helper and is appropriate here precisely because
///      the probe is throwaway — it is NOT an acceptable base for the real hook. Consequence:
///      no inherited `poolManager` immutable and no `onlyPoolManager` modifier, so the manager is
///      stored here. Access control is irrelevant on an observation-only contract.
///
/// @dev Derived from Uniswap v4-core test scaffolding (BUSL-1.1).
contract ProbeHook is BaseTestHooks {
    using TransientDeltaReader for IExttload;

    /// @notice One `beforeSwap` observation. Everything is recorded raw; nothing is interpreted here.
    struct Observation {
        // --- identity ---
        address locker; // `sender` in beforeSwap = the address that called swap() = the LOCKER,
        // not the EOA. PoolManager credits deltas to msg.sender at
        // PoolManager.sol:224, so this is the address deltas belong to. The v4 trap list.
        // --- global transient state ---
        uint256 nonzeroDeltaCount; // GLOBAL across all targets in this unlock, not locker-scoped.
        // --- positional deltas for this pool's pair ---
        int256 deltaCurrency0;
        int256 deltaCurrency1;
        // --- the hypothesis under test (see predicateTripped) ---
        Currency inputCurrency;
        Currency outputCurrency;
        int256 deltaInInputCurrency;
        int256 deltaInOutputCurrency;
        bool predicateTripped;
        // --- swap shape, for reading the scenarios back ---
        bool zeroForOne;
        int256 amountSpecified;
        // --- Q1: hook-local transient persistence ---
        bool sawPriorTouch;
        uint256 legIndex;
    }

    Observation[] internal _observations;

    /// @dev The PoolManager, read via IExttload for its transient state.
    IPoolManager public immutable manager;

    // Hook-local transient slots (EIP-1153). Transaction-scoped: written on every leg, cleared
    // by the EVM at tx end. Q1 exists to confirm exactly that lifetime.
    bytes32 private constant T_TOUCHED = keccak256("roundtrip.probe.touched");
    bytes32 private constant T_LEG_INDEX = keccak256("roundtrip.probe.legIndex");

    constructor(IPoolManager _manager) {
        manager = _manager;
    }

    /// @notice Records the PoolManager's transient state at swap time. Observes only.
    /// @param sender The locker (router), not the EOA.
    /// @param key The pool being swapped through.
    /// @param params The swap parameters, used only to derive input/output currency.
    /// @return selector The beforeSwap selector.
    /// @return delta Always ZERO_DELTA — this hook does not price.
    /// @return lpFeeOverride Always 0 — this hook does not touch fees.
    function beforeSwap(address sender, PoolKey calldata key, IPoolManager.SwapParams calldata params, bytes calldata)
        external
        override
        returns (bytes4 selector, BeforeSwapDelta delta, uint24 lpFeeOverride)
    {
        // Built incrementally rather than as a struct literal: a 13-field literal blows the
        // stack under the non-via-ir pipeline.
        Observation memory o;
        o.locker = sender;
        o.zeroForOne = params.zeroForOne;
        o.amountSpecified = params.amountSpecified;

        // --- Q1: hook-local transient persistence across legs of one tx ---
        {
            // Constants are copied to locals first: Solidity only permits literal-valued
            // constants to be referenced directly inside inline assembly.
            bytes32 touchedSlot = T_TOUCHED;
            bytes32 legSlot = T_LEG_INDEX;
            bool touched;
            uint256 leg;
            assembly ("memory-safe") {
                touched := tload(touchedSlot)
                leg := tload(legSlot)
                tstore(touchedSlot, 1)
                tstore(legSlot, add(leg, 1))
            }
            o.sawPriorTouch = touched;
            o.legIndex = leg;
        }

        // --- Q2: read the PoolManager's OWN transient state from inside the hook ---
        {
            IExttload pm = IExttload(address(manager));
            int256 d0 = pm.currencyDelta(sender, key.currency0);
            int256 d1 = pm.currencyDelta(sender, key.currency1);
            o.deltaCurrency0 = d0;
            o.deltaCurrency1 = d1;
            o.nonzeroDeltaCount = pm.nonzeroDeltaCount();

            // Input/output follow PoolManager.sol:214, which names
            // `params.zeroForOne ? key.currency0 : key.currency1` as the input token.
            o.inputCurrency = params.zeroForOne ? key.currency0 : key.currency1;
            o.outputCurrency = params.zeroForOne ? key.currency1 : key.currency0;
            o.deltaInInputCurrency = params.zeroForOne ? d0 : d1;
            o.deltaInOutputCurrency = params.zeroForOne ? d1 : d0;

            // --- the predicate under test (the anti-goal blacklist requires this be categorical, not scored) ---
            // "At beforeSwap, does the locker already hold a non-zero delta of OPPOSING sign in
            //  this swap's output currency?"
            // A swap always credits the locker in the output currency (positive delta). So the
            // opposing sign is a DEBT: the locker already owes the very currency this leg will
            // pay them — i.e. the operation is closing a cycle on that token.
            // Strictly boolean. No threshold, no magnitude, no tuning constant.
            o.predicateTripped = o.deltaInOutputCurrency < 0;
        }

        _observations.push(o);

        // Observation only. No pricing, no fee override. `beforeSwapReturnDelta` is NOT in this
        // hook's mined bitmap, so a non-zero delta here would be ignored anyway — but returning
        // ZERO_DELTA makes the intent explicit rather than incidental.
        return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    /// @notice Number of observations recorded.
    function observationCount() external view returns (uint256) {
        return _observations.length;
    }

    /// @notice Read a recorded observation by index.
    /// @param i Index of the observation.
    function observation(uint256 i) external view returns (Observation memory) {
        return _observations[i];
    }

    /// @notice Discard all recorded observations. Test-scenario hygiene only.
    function clear() external {
        delete _observations;
    }
}
