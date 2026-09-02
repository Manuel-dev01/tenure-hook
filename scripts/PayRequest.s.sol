// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";

/// @notice The single BrevisRequest method this repo calls. Signature taken verbatim from the
///         Brevis SDK's own generated bindings (brevis-sdk v0.3.33, sdk/eth/bindings.go:16092),
///         not from documentation and not from a block explorer:
///
///           function sendRequest(bytes32,uint64,address,(address,uint64),uint8) payable
interface IBrevisRequest {
    struct Callback {
        address target;
        uint64 gas;
    }

    function sendRequest(bytes32 _proofId, uint64 _nonce, address _refundee, Callback calldata _callback, uint8 _option)
        external
        payable;

    function queryRequestStatus(bytes32 _proofId, uint64 _nonce) external view returns (uint8, uint8);
}

/// @title PayRequest — pay for a query the Brevis gateway has already accepted
/// @notice Step 4 of the round trip. `npm run gateway` submits the proof and returns a query key;
///         nothing happens on-chain until that key is paid for here. Brevis then aggregates and
///         calls `brevisCallback` on the registry.
///
/// @dev RUN `npm run gateway` FIRST AND USE ITS OUTPUT. PROOF_ID and NONCE are the two halves of
///      the returned query key. A nonce is minted per submission, so a key from an earlier run is
///      not interchangeable with a later one.
///
/// @dev THE REGISTRY MUST ALREADY HAVE ITS VK HASH SET. `TenureRegistry.expectedVkHash` starts at
///      zero and `handleProofResult` reverts on mismatch, so paying before `setVkHash` buys a
///      callback that reverts. `Deploy.s.sol` sets it and reads it back; verify before paying.
///
/// @dev NO FEE LOGIC EXISTS HERE AND NONE MAY BE ADDED. This pays Brevis for proof aggregation.
///      It has nothing to do with swap fees, which are identical for every address by construction
///      (the fee-parity rule).
contract PayRequest is Script {
    /// @notice ZK mode. The alternative (coChain/OP mode) trades the proof for an optimistic
    ///         challenge window, which would weaken the one property this project sells.
    uint8 internal constant OPTION_ZK = 0;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address refundee = vm.addr(pk);

        IBrevisRequest brevisRequest = IBrevisRequest(vm.envAddress("BREVIS_REQUEST"));
        address registry = vm.envAddress("REGISTRY");
        bytes32 proofId = vm.envBytes32("PROOF_ID");
        uint64 nonce = uint64(vm.envUint("NONCE"));
        uint256 feeWei = vm.envOr("FEE_WEI", uint256(0));
        uint64 callbackGas = uint64(vm.envOr("CALLBACK_GAS", uint256(400_000)));

        require(proofId != bytes32(0), "PROOF_ID unset: run `npm run gateway` and use its query key");
        require(registry != address(0), "REGISTRY unset");

        console.log("BrevisRequest:", address(brevisRequest));
        console.log("callback     :", registry);
        console.log("refundee     :", refundee);
        console.log("fee (wei)    :", feeWei);

        vm.startBroadcast(pk);
        brevisRequest.sendRequest{value: feeWei}(
            proofId, nonce, refundee, IBrevisRequest.Callback({target: registry, gas: callbackGas}), OPTION_ZK
        );
        vm.stopBroadcast();

        console.log("");
        console.log("Paid. Brevis aggregates and calls brevisCallback in ~2 minutes.");
        console.log("Poll:  cast call <BREVIS_REQUEST> 'queryRequestStatus(bytes32,uint64)(uint8,uint8)' \\");
        console.log("         <PROOF_ID> <NONCE> --rpc-url <RPC>");
        console.log("Success is a StandingRecorded event on the registry, not a status code alone.");
    }
}
