// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseTestHooks} from "v4-core/src/test/BaseTestHooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";

/// @title StandingRegistryStub — placeholder for the Brevis-backed registry.
/// @notice T2 tests identity binding, not proving. This stands in for the registry that will
///         receive `handleProofResult` from Brevis and record standing per address.
/// @dev NOT the real registry. The real one validates `_vkHash` against an expected value — see
///      CLAUDE.md §2. Anyone may write here; that is fine because T2 is testing the hook's
///      signature handling, not the registry's authorisation.
contract StandingRegistryStub {
    /// @notice Standing earned by an address, in whatever unit the circuit ultimately outputs.
    mapping(address => uint256) public standingOf;

    /// @notice Set an address's standing. Stub only — the real registry writes from a ZK callback.
    /// @param who The address whose standing is being set.
    /// @param standing The standing value.
    function setStanding(address who, uint256 standing) external {
        standingOf[who] = standing;
    }
}

/// @title TenureGateProbe — Milestone 0 instrument for T2. Disposable.
/// @notice Answers exactly one question: can a hook bind a swap to a trader **unforgeably**, and
///         does it fail closed when it cannot?
///
/// @dev THE PROBLEM THIS SOLVES. `beforeSwap` receives the locker (the router), never the trader.
///      v4-periphery exposes `IMsgSender.msgSender()` for this, but it is **self-reported** — a
///      malicious router can name any address. Since Tenure grants larger size caps, an
///      unauthenticated identity claim means anyone can claim the highest standing in the pool and
///      take the largest size. Self-reported identity is not identity. See CLAUDE.md §7 and §X.
///
/// @dev THE MECHANISM. The trader signs an EIP-712 `DepthCredential` binding the locker, the pool,
///      a maximum size, a nonce, and a deadline. The hook recovers the signer and reads *that*
///      address's standing. Standing is therefore an asset the trader presents, not a property the
///      pool assigns.
///
/// @dev NO FEE LOGIC EXISTS IN THIS CONTRACT AND NONE MAY BE ADDED. CLAUDE.md §X: the fee is
///      identical for every address; standing changes accessible depth only.
///
/// @dev Derived from Uniswap v4-core test scaffolding (BUSL-1.1). Built on `BaseTestHooks` because
///      this is a throwaway gate, exactly as the Roundtrip probe was — the real hook will use
///      OpenZeppelin's `uniswap-hooks` BaseHook (CLAUDE.md §6).
contract TenureGateProbe is BaseTestHooks {
    using PoolIdLibrary for PoolKey;

    /// @notice A trader's signed authorisation to consume depth on one pool, once.
    /// @dev Every field is load-bearing:
    ///      - `locker`   binds the credential to one router, so it cannot be lifted and replayed
    ///                   through a different one.
    ///      - `poolId`   binds it to one pool.
    ///      - `maxSize`  binds it to a size, so an observed credential cannot be reused for a
    ///                   larger swap than the trader authorised.
    ///      - `nonce`    makes it single-use.
    ///      - `deadline` bounds it in time. A replayable signature is a size cap that never expires.
    struct DepthCredential {
        address locker;
        bytes32 poolId;
        uint256 maxSize;
        uint256 nonce;
        uint256 deadline;
    }

    /// @dev keccak256("DepthCredential(address locker,bytes32 poolId,uint256 maxSize,uint256 nonce,uint256 deadline)")
    bytes32 public constant DEPTH_CREDENTIAL_TYPEHASH =
        keccak256("DepthCredential(address locker,bytes32 poolId,uint256 maxSize,uint256 nonce,uint256 deadline)");

    /// @dev keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")
    bytes32 private constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    /// @notice Depth available to an address with no standing at all. Nobody is excluded — the
    ///         mechanism caps size, it does not deny access. This is the anti-whitelist property
    ///         and it must remain non-zero.
    uint256 public constant BASE_DEPTH_ALLOWANCE = 1e18;

    /// @notice Additional depth per unit of standing. Linear and deliberately dull: any curve here
    ///         would be a tuning constant, and CLAUDE.md §3 forbids tuned heuristics.
    uint256 public constant DEPTH_PER_STANDING = 5e17;

    StandingRegistryStub public immutable registry;

    /// @notice Consumed credential nonces, per trader.
    mapping(address => mapping(uint256 => bool)) public nonceUsed;

    error MissingCredential();
    error ExpiredCredential();
    error WrongLocker();
    error WrongPool();
    error ReplayedNonce();
    error ExceedsDepthAllowance(uint256 requested, uint256 allowed);
    error InvalidSignature();

    constructor(StandingRegistryStub _registry) {
        registry = _registry;
    }

    /// @notice The EIP-712 domain separator for this hook instance.
    /// @dev Computed on read rather than cached so the tests cannot pass against a stale chainId.
    function domainSeparator() public view returns (bytes32) {
        return keccak256(
            abi.encode(EIP712_DOMAIN_TYPEHASH, keccak256("Tenure"), keccak256("1"), block.chainid, address(this))
        );
    }

    /// @notice The EIP-712 digest a trader signs to authorise a swap.
    /// @param c The credential being signed.
    /// @return The digest to sign.
    function hashCredential(DepthCredential memory c) public view returns (bytes32) {
        bytes32 structHash =
            keccak256(abi.encode(DEPTH_CREDENTIAL_TYPEHASH, c.locker, c.poolId, c.maxSize, c.nonce, c.deadline));
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator(), structHash));
    }

    /// @notice Depth a given standing entitles an address to consume in one swap.
    /// @param standing The address's proven standing.
    /// @return The maximum swap size permitted.
    function depthAllowanceFor(uint256 standing) public pure returns (uint256) {
        return BASE_DEPTH_ALLOWANCE + (standing * DEPTH_PER_STANDING);
    }

    /// @notice Enforces the trader's depth allowance. Fails closed on every unauthenticated path.
    /// @param sender The locker (router) — NOT the trader. Used only to bind the credential.
    /// @param key The pool being swapped through.
    /// @param params The swap parameters; only the size is consulted.
    /// @param hookData ABI-encoded (DepthCredential, signature).
    /// @return selector The beforeSwap selector.
    /// @return delta Always ZERO_DELTA — this hook does not price.
    /// @return lpFeeOverride Always 0. The fee is identical for every address (CLAUDE.md §X).
    function beforeSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata hookData
    ) external override returns (bytes4 selector, BeforeSwapDelta delta, uint24 lpFeeOverride) {
        // Fail closed: no credential is not "default allowance", it is a revert. An unauthenticated
        // swap must never reach the size check.
        if (hookData.length == 0) revert MissingCredential();

        (DepthCredential memory c, bytes memory sig) = abi.decode(hookData, (DepthCredential, bytes));

        if (block.timestamp > c.deadline) revert ExpiredCredential();
        if (c.locker != sender) revert WrongLocker();
        if (c.poolId != PoolId.unwrap(key.toId())) revert WrongPool();

        address trader = _recover(hashCredential(c), sig);
        if (trader == address(0)) revert InvalidSignature();

        if (nonceUsed[trader][c.nonce]) revert ReplayedNonce();
        nonceUsed[trader][c.nonce] = true;

        uint256 requested = params.amountSpecified < 0
            // forge-lint: disable-next-line(unsafe-typecast)
            ? uint256(-params.amountSpecified) // exactIn
            // forge-lint: disable-next-line(unsafe-typecast)
            : uint256(params.amountSpecified); // exactOut

        // The stricter of what the trader authorised and what their standing earns.
        uint256 allowed = depthAllowanceFor(registry.standingOf(trader));
        if (c.maxSize < allowed) allowed = c.maxSize;

        if (requested > allowed) revert ExceedsDepthAllowance(requested, allowed);

        return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    /// @dev ECDSA recovery with malleability rejection. Returns address(0) on any malformed input
    ///      so the caller reverts rather than proceeding with a bogus trader.
    function _recover(bytes32 digest, bytes memory sig) internal pure returns (address) {
        if (sig.length != 65) return address(0);
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly ("memory-safe") {
            r := mload(add(sig, 0x20))
            s := mload(add(sig, 0x40))
            v := byte(0, mload(add(sig, 0x60)))
        }
        // Reject the upper half of the curve order: signatures are malleable otherwise, and a
        // malleable signature is a second valid credential for the same nonce.
        if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
            return address(0);
        }
        if (v != 27 && v != 28) return address(0);
        return ecrecover(digest, v, r, s);
    }
}
