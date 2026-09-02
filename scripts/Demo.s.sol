// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// TENURE, the whole mechanism in one command, for recording.
//
//   forge script scripts/Demo.s.sol
//
// No arguments, no RPC, no network. Deterministic and fast: nothing proves live, because a real
// proof takes ~100 seconds. The two circuit outputs replayed below were produced by the PRODUCTION
// circuit against real mainnet swap logs and verified against the vk, see
// analysis/production-circuit-proof.md. Reproduce them with:
//
//   cd brevis/prover && go run ./cmd/main.go
//   cd brevis/app    && npm run prove -- balanced      (and -- onesided)

import {Script} from "forge-std/Script.sol";
import {TenureDemo} from "./TenureDemo.sol";

/// @notice Entrypoint:  forge script scripts/Demo.s.sol
/// @dev All work lives in TenureDemo - see that file for why.
contract Demo is Script {
    function run() external {
        new TenureDemo().play();
    }
}
