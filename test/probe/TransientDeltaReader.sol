// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IExttload} from "v4-core/src/interfaces/IExttload.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {CurrencyDelta} from "v4-core/src/libraries/CurrencyDelta.sol";
import {NonzeroDeltaCount} from "v4-core/src/libraries/NonzeroDeltaCount.sol";

/// @title TransientDeltaReader
/// @notice Reads the PoolManager's EIP-1153 transient flash-accounting state from
///         *outside* the PoolManager, via `IExttload`.
///
/// @dev Slot derivation is IMPORTED from v4-core, never transcribed. The go/no-go gate warns that a
///      wrong slot returns plausible-looking garbage rather than reverting — the worst failure
///      mode available. Importing makes the derivation compile-time bound to the pinned
///      submodule (v4-core v4.0.0, e50237c), so it cannot silently drift from the values the
///      PoolManager actually writes:
///
///        - `NonzeroDeltaCount.NONZERO_DELTA_COUNT_SLOT` — v4-core/src/libraries/NonzeroDeltaCount.sol:9-10
///          declared as bytes32(uint256(keccak256("NonzeroDeltaCount")) - 1)
///        - `CurrencyDelta._computeSlot(target, currency)` — v4-core/src/libraries/CurrencyDelta.sol:10-16
///          keccak256 over the 64-byte preimage (mask160(target) ‖ mask160(currency))
///
///      Both are `internal` members, so they are usable by import and require no copying.
///
/// @dev Sign convention, inherited from v4-core flash accounting:
///      NEGATIVE delta = the target owes the PoolManager (a debt).
///      POSITIVE delta = the PoolManager owes the target (a credit).
///
/// @dev Derived from Uniswap v4-core (BUSL-1.1). Slot derivations are v4-core's, used by import.
library TransientDeltaReader {
    /// @notice Number of currencies the PoolManager currently has a non-zero delta open on,
    ///         summed across every target in the current unlock.
    /// @param manager The PoolManager to read transient state from.
    /// @return count The global non-zero delta count at the moment of the call.
    function nonzeroDeltaCount(IExttload manager) internal view returns (uint256 count) {
        // Reads v4-core's NONZERO_DELTA_COUNT_SLOT — see NonzeroDeltaCount.sol:9-10.
        count = uint256(manager.exttload(NonzeroDeltaCount.NONZERO_DELTA_COUNT_SLOT));
    }

    /// @notice The outstanding currency delta the PoolManager is holding for `target`.
    /// @param manager The PoolManager to read transient state from.
    /// @param target The address the delta is credited to — in a hook this is the LOCKER
    ///        (the router), never the EOA. See the v4 trap list.
    /// @param currency The currency to read the delta for.
    /// @return delta Negative = target owes the manager. Positive = manager owes target.
    function currencyDelta(IExttload manager, address target, Currency currency)
        internal
        view
        returns (int256 delta)
    {
        // Slot derived by v4-core's own _computeSlot — see CurrencyDelta.sol:10-16.
        bytes32 slot = CurrencyDelta._computeSlot(target, currency);
        delta = int256(uint256(manager.exttload(slot)));
    }
}
