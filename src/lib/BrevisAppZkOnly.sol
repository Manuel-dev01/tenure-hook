// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice App base that only accepts ZK-attested results.
/// @dev VENDORED from Brevis, `brevis/contracts/contracts/lib/BrevisAppZkOnly.sol`, unmodified
///      except for the pragma and this comment. Reproduced here so the Foundry build does not
///      depend on the Hardhat project's dependency tree. Credit: Brevis Network (MIT).
///      See brevis/ATTRIBUTION.md.
abstract contract BrevisAppZkOnly {
    address public brevisRequest;

    modifier onlyBrevisRequest() {
        require(msg.sender == brevisRequest, "invalid caller");
        _;
    }

    constructor(address _brevisRequest) {
        brevisRequest = _brevisRequest;
    }

    function handleProofResult(bytes32 _vkHash, bytes calldata _appCircuitOutput) internal virtual {
        // to be overridden by custom app
    }

    function brevisCallback(bytes32 _appVkHash, bytes calldata _appCircuitOutput) external onlyBrevisRequest {
        handleProofResult(_appVkHash, _appCircuitOutput);
    }

    function brevisBatchCallback(bytes32[] calldata _appVkHashes, bytes[] calldata _appCircuitOutputs)
        external
        onlyBrevisRequest
    {
        for (uint256 i = 0; i < _appVkHashes.length; i++) {
            handleProofResult(_appVkHashes[i], _appCircuitOutputs[i]);
        }
    }
}
