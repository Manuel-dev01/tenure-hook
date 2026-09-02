// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IStandingRegistry} from "./interfaces/IStandingRegistry.sol";

/// @title OperatorStandingRegistry
/// @notice Standing written directly by the pool operator.
///
/// @dev THIS IS A FALLBACK, NOT A MOCK. If Brevis proving is unavailable, a pool can run Tenure
///      with the operator publishing standing it has computed off-chain. The mechanism, identical
///      fee for everyone, depth varying with standing, is unchanged; only the *source* of the
///      standing figure is less trustless. `TenureRegistry` is the ZK-attested version and is a
///      drop-in replacement via `TenureHook.setRegistry`.
///
/// @dev The honest difference, stated so it is never blurred: with this registry you trust the
///      operator's arithmetic. With `TenureRegistry` you trust a ZK proof and a verifying-key hash.
///      Both are shippable; only one is trustless, and the README says which is deployed.
///
/// @dev Applies the same minimum-sample rule as the ZK registry, so behaviour does not change when
///      the source is swapped. See analysis/minimum-sample-decision.md.
contract OperatorStandingRegistry is IStandingRegistry {
    /// @notice Minimum observed swaps before an address has standing at all.
    uint256 public constant MIN_STANDING_SWAPS = 20;

    struct Standing {
        uint16 balanceBps;
        uint16 swapCount;
    }

    mapping(address => Standing) public standing;

    address public operator;

    error NotOperator();
    error BalanceOutOfRange(uint16 balanceBps);

    event StandingRecorded(address indexed trader, uint16 balanceBps, uint16 swapCount);
    event OperatorTransferred(address indexed operator);

    modifier onlyOperator() {
        if (msg.sender != operator) revert NotOperator();
        _;
    }

    constructor(address _operator) {
        operator = _operator;
    }

    /// @notice Record standing for an address.
    /// @param trader The address.
    /// @param balanceBps Directional balance in basis points, 0..10000.
    /// @param swapCount Number of swaps the figure was computed over.
    function setStanding(address trader, uint16 balanceBps, uint16 swapCount) external onlyOperator {
        if (balanceBps > 10_000) revert BalanceOutOfRange(balanceBps);
        standing[trader] = Standing({balanceBps: balanceBps, swapCount: swapCount});
        emit StandingRecorded(trader, balanceBps, swapCount);
    }

    /// @notice Hand operator rights to another address.
    /// @param _operator The new operator.
    function transferOperator(address _operator) external onlyOperator {
        operator = _operator;
        emit OperatorTransferred(_operator);
    }

    /// @inheritdoc IStandingRegistry
    function standingOf(address trader) external view returns (uint256) {
        Standing memory s = standing[trader];
        if (s.swapCount < MIN_STANDING_SWAPS) return 0;
        return s.balanceBps;
    }
}
