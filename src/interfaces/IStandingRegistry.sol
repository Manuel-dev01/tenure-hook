// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title IStandingRegistry
/// @notice The single question TenureHook asks about an address.
/// @dev Deliberately minimal so the hook does not depend on how standing was established. In
///      stage 1 an operator wrote it; from stage 3 a Brevis ZK callback does. The hook's read path
///      is identical either way, which is what lets the hook ship even if proving is unavailable.
interface IStandingRegistry {
    /// @notice Proven standing for an address, in basis points.
    /// @dev MUST return 0 rather than reverting for an unknown address: no standing means base
    ///      depth, never exclusion.
    /// @param trader The address to look up.
    /// @return Standing in basis points, 0 if unknown or below the minimum sample.
    function standingOf(address trader) external view returns (uint256);
}
