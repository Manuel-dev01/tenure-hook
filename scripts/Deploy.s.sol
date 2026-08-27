// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "v4-periphery/test/shared/HookMiner.sol";

import {TenureHook} from "../src/TenureHook.sol";
import {TenureRegistry} from "../src/TenureRegistry.sol";
import {IStandingRegistry} from "../src/interfaces/IStandingRegistry.sol";

/// @title Deploy — TenureRegistry + CREATE2-mined TenureHook
/// @notice Deploys the ZK-attested registry, mines a hook address encoding beforeSwap ONLY, and
///         sets the circuit's verifying-key hash.
///
/// @dev `setVkHash` IS NOT OPTIONAL AND IS NOT CEREMONY. `TenureRegistry.expectedVkHash` starts at
///      zero and every callback reverts until it is set. Leaving it unset does not merely disable
///      the registry — a misconfigured value would accept proofs from a different circuit
///      entirely. This script sets it and then READS IT BACK, because a deploy log is not
///      evidence. See analysis/submission-checklist.md.
///
/// @dev The mined address deliberately encodes beforeSwap and nothing else. Without
///      BEFORE_SWAP_RETURNS_DELTA the hook is structurally incapable of altering execution
///      economics, whatever code anyone later adds (the fee-parity rule).
contract Deploy is Script {
    /// @notice CREATE2 deployer proxy, present at the same address on every chain Foundry targets.
    address internal constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address operator = vm.addr(pk);
        IPoolManager manager = IPoolManager(vm.envAddress("POOL_MANAGER"));
        address brevisRequest = vm.envAddress("BREVIS_REQUEST");
        bytes32 vkHash = vm.envBytes32("CIRCUIT_VK_HASH");

        require(vkHash != bytes32(0), "CIRCUIT_VK_HASH must be set: an unset registry accepts nothing");

        vm.startBroadcast(pk);

        TenureRegistry registry = new TenureRegistry(brevisRequest, operator);
        console.log("TenureRegistry:", address(registry));

        // beforeSwap only. No fee permission is mined into the address, by design.
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG);
        (address hookAddr, bytes32 salt) = HookMiner.find(
            CREATE2_DEPLOYER,
            flags,
            type(TenureHook).creationCode,
            abi.encode(manager, operator, IStandingRegistry(address(registry)))
        );

        TenureHook hook = new TenureHook{salt: salt}(manager, operator, IStandingRegistry(address(registry)));
        require(address(hook) == hookAddr, "hook address mining failed");
        console.log("TenureHook:    ", address(hook));

        registry.setVkHash(vkHash);

        vm.stopBroadcast();

        // Read back rather than trusting the transaction we just sent.
        bytes32 onChain = registry.expectedVkHash();
        require(onChain == vkHash, "vkHash readback mismatch");
        console.log("vkHash verified on-chain:");
        console.logBytes32(onChain);

        // Prove the fee permission is genuinely absent from the deployed address.
        uint160 bits = uint160(address(hook)) & 0x3FFF;
        require(bits & uint160(Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG) == 0, "hook must hold no fee power");
        require(bits & uint160(Hooks.BEFORE_SWAP_FLAG) != 0, "hook must hold beforeSwap");
        console.log("fee-neutrality confirmed in the mined address bits");
    }
}
