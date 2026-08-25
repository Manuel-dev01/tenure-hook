// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// TENURE — STAGE 3. The registry: circuit output -> on-chain standing.
//
// The security-critical behaviour here is _vkHash validation. Ignoring it lets anyone submit a
// proof from a DIFFERENT circuit — one that outputs whatever they choose — and drive our callback.
// There is a published audit finding against exactly this pattern, so it gets its own tests and an
// S5 mutation rather than a comment.

import {Test} from "forge-std/Test.sol";
import {TenureRegistry} from "../src/TenureRegistry.sol";

contract TenureRegistryTest is Test {
    TenureRegistry internal registry;

    address internal brevisRequest = address(0xB2E415);
    address internal operator = address(this);
    address internal trader = address(0xA11CE);

    bytes32 internal constant REAL_VK = 0x1cb76a97800eca38048ce06ba3199638113b0218e56ed9c9b212fbedbd8a79fc;
    bytes32 internal constant OTHER_VK = bytes32(uint256(0xBAD));

    function setUp() public {
        registry = new TenureRegistry(brevisRequest, operator);
    }

    /// @dev Circuit output layout: address(20) ‖ balanceBps(2) ‖ swapCount(2) ‖ from(8) ‖ to(8).
    function _output(address who, uint16 balanceBps, uint16 swapCount, uint64 from, uint64 to)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodePacked(bytes20(who), bytes2(balanceBps), bytes2(swapCount), bytes8(from), bytes8(to));
    }

    function _callback(bytes32 vk, bytes memory out) internal {
        vm.prank(brevisRequest);
        registry.brevisCallback(vk, out);
    }

    // =======================================================================================
    // vkHash — the security-critical path
    // =======================================================================================

    /// @notice An unconfigured registry accepts nothing rather than everything.
    function test_VkHash_UnsetRegistryRejectsAllProofs() public {
        vm.expectRevert(TenureRegistry.VkHashNotSet.selector);
        _callback(REAL_VK, _output(trader, 7777, 20, 100, 200));
    }

    /// @notice A proof from a different circuit is rejected even when well-formed.
    /// @dev THE ATTACK: without this check, any circuit's output would be written as standing.
    function test_VkHash_ProofFromDifferentCircuitRejected() public {
        registry.setVkHash(REAL_VK);
        vm.expectRevert(abi.encodeWithSelector(TenureRegistry.UnexpectedVkHash.selector, OTHER_VK, REAL_VK));
        _callback(OTHER_VK, _output(trader, 10000, 999, 100, 200));
    }

    /// @notice A proof from our circuit is accepted and recorded.
    function test_VkHash_MatchingProofAccepted() public {
        registry.setVkHash(REAL_VK);
        _callback(REAL_VK, _output(trader, 7777, 20, 25831950, 25832026));

        (uint16 bal, uint16 count, uint64 from, uint64 to,) = registry.standing(trader);
        assertEq(bal, 7777, "balance recorded");
        assertEq(count, 20, "swap count recorded");
        assertEq(from, 25831950, "attested window start");
        assertEq(to, 25832026, "attested window end");
        assertEq(registry.standingOf(trader), 7777, "standing readable by the hook");
    }

    /// @notice Only the Brevis request contract may deliver a callback.
    function test_OnlyBrevisRequestMayCallBack() public {
        registry.setVkHash(REAL_VK);
        vm.expectRevert(bytes("invalid caller"));
        registry.brevisCallback(REAL_VK, _output(trader, 7777, 20, 100, 200));
    }

    /// @notice Only the operator may set the expected vk hash.
    function test_OnlyOperatorMaySetVkHash() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert(TenureRegistry.NotOperator.selector);
        registry.setVkHash(REAL_VK);
    }

    // =======================================================================================
    // minimum sample — standing is undefined below N swaps
    // =======================================================================================

    /// @notice Below the minimum sample an address has NO standing, not a low score.
    /// @dev It falls to base depth alongside every unsigned swapper. Nobody is excluded, and a
    ///      lucky short window cannot manufacture standing.
    function test_MinimumSample_BelowThresholdHasNoStanding() public {
        registry.setVkHash(REAL_VK);
        // A perfect 10000bps balance, but over only 4 swaps — noise, not a measurement.
        _callback(REAL_VK, _output(trader, 10000, 4, 100, 120));

        (uint16 bal, uint16 count,,,) = registry.standing(trader);
        assertEq(bal, 10000, "raw figure is still recorded for audit");
        assertEq(count, 4, "sample size is visible");
        assertEq(registry.standingOf(trader), 0, "but it confers no standing");
    }

    /// @notice At exactly the minimum sample, standing applies.
    function test_MinimumSample_BoundaryIsInclusive() public {
        registry.setVkHash(REAL_VK);
        uint16 n = uint16(registry.MIN_STANDING_SWAPS());

        _callback(REAL_VK, _output(trader, 6000, n - 1, 100, 200));
        assertEq(registry.standingOf(trader), 0, "one below the minimum confers nothing");

        _callback(REAL_VK, _output(trader, 6000, n, 100, 200));
        assertEq(registry.standingOf(trader), 6000, "at the minimum it counts");
    }

    /// @notice An address never seen has no standing and does not revert.
    function test_UnknownAddressReturnsZeroNotRevert() public view {
        assertEq(registry.standingOf(address(0xDEAD)), 0, "unknown means base depth, never exclusion");
    }

    // =======================================================================================
    // output decoding
    // =======================================================================================

    /// @notice A truncated circuit output is rejected rather than silently misread.
    function test_MalformedOutputRejected() public {
        registry.setVkHash(REAL_VK);
        vm.expectRevert(abi.encodeWithSelector(TenureRegistry.MalformedCircuitOutput.selector, uint256(10)));
        _callback(REAL_VK, new bytes(10));
    }

    /// @notice Decoding matches the circuit's documented layout exactly.
    /// @dev These are the real values the circuit emitted in the Stage 2 S5 check.
    function test_DecodeMatchesCircuitLayout() public view {
        bytes memory out = _output(0x51C72848c68a965f66FA7a88855F9f7784502a7F, 7777, 18, 25831950, 25832026);
        (address who, uint16 bal, uint16 count, uint64 from, uint64 to) = registry.decodeOutput(out);
        assertEq(who, 0x51C72848c68a965f66FA7a88855F9f7784502a7F);
        assertEq(bal, 7777);
        assertEq(count, 18);
        assertEq(from, 25831950);
        assertEq(to, 25832026);
    }
}
