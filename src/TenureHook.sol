// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "uniswap-hooks/src/base/BaseHook.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";
import {IStandingRegistry} from "./interfaces/IStandingRegistry.sol";

/// @title TenureHook
/// @notice Depth is the product. Every address pays the same fee; what you earn is how much of the
///         book you can reach in a single swap.
///
/// @dev THE ENTITLEMENT. Each pool has a configured **depth tranche**, the maximum any single swap
///      may consume. A trader's *standing* determines what fraction of that tranche they can take.
///      Standing is presented by the trader as an EIP-712 credential, not assigned by the pool.
///
/// @dev THE FEE IS IDENTICAL FOR EVERY ADDRESS. This contract contains no fee logic and none may be
///      added. `beforeSwap` returns a zero fee override unconditionally, and the hook's mined
///      address deliberately excludes `BEFORE_SWAP_RETURNS_DELTA`, so it is not merely policy,
///      the permission to alter execution economics is absent from the address itself.
///      See the fee-parity rule: if a change makes a fee vary by address, the change is wrong.
///
/// @dev NOBODY IS EXCLUDED. An address with no standing, or presenting no credential at all, still
///      receives `BASE_DEPTH_BPS` of the tranche. The mechanism caps size; it never denies access.
///      This is the difference between Tenure and an allowlist, and it is enforced in code rather
///      than promised in prose.
///
/// @dev WHERE STANDING COMES FROM. The hook reads `IStandingRegistry` and does not care how the
///      value got there. In stage 1 an operator wrote it directly; from stage 3 a Brevis ZK
///      callback does, with `_vkHash` validated. Because the read path is identical either way,
///      the hook remains shippable even if proving is unavailable, the operator-written registry
///      is a complete, honest fallback rather than a mock.
contract TenureHook is BaseHook {
    using PoolIdLibrary for PoolKey;

    // -------------------------------------------------------------------------------------
    // depth
    // -------------------------------------------------------------------------------------

    /// @notice Basis-point denominator. 10_000 bps = 100% of a pool's depth tranche.
    uint256 public constant BPS = 10_000;

    /// @notice Fraction of the tranche available to an address with zero standing.
    /// @dev Deliberately non-zero. This constant IS the anti-whitelist property: with no standing
    ///      and no credential, a trader still reaches 5% of the tranche. Lowering it to zero would
    ///      convert Tenure into an allowlist and invalidate the entire pitch.
    uint256 public constant BASE_DEPTH_BPS = 500;

    /// @notice Standing at which an address reaches the full tranche.
    /// @dev Depth rises linearly from BASE_DEPTH_BPS at standing 0 to BPS at this value, then
    ///      stops. Linear and monotonic: there are no brackets to be sorted into and no cliff to
    ///      sit just below. The anti-goal blacklist forbids tuned heuristics, so this is a straight line
    ///      rather than a curve with fitted parameters.
    uint256 public constant FULL_DEPTH_STANDING = 10_000;

    /// @dev Namespace for the per-transaction consumed-depth accumulator. Hook-local transient
    ///      storage (EIP-1153): persists across every leg of one transaction and is cleared by the
    ///      EVM at transaction end. That lifetime was verified in this repository's Milestone 0
    ///      work, see analysis/roundtrip-negative-result.md, Q1, so it is a measured property
    ///      rather than an assumed one.
    bytes32 private constant T_CONSUMED_NAMESPACE = keccak256("tenure.consumedDepth.v1");

    /// @notice The maximum a single swap may consume, per pool, in input-token units.
    /// @dev Set by the operator per pool. Zero means the pool is unconfigured and unrestricted.
    mapping(PoolId => uint256) public depthTranche;

    /// @notice Where proven standing is read from. Swappable without touching swap-time logic.
    IStandingRegistry public registry;

    /// @notice Consumed credential nonces, per trader.
    mapping(address => mapping(uint256 => bool)) public nonceUsed;

    /// @notice The address permitted to write standing and configure tranches.
    address public operator;

    // -------------------------------------------------------------------------------------
    // EIP-712
    // -------------------------------------------------------------------------------------

    /// @dev keccak256("DepthCredential(address locker,bytes32 poolId,uint256 maxSize,uint256 nonce,uint256 deadline)")
    bytes32 public constant DEPTH_CREDENTIAL_TYPEHASH =
        keccak256("DepthCredential(address locker,bytes32 poolId,uint256 maxSize,uint256 nonce,uint256 deadline)");

    /// @dev keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")
    bytes32 private constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    /// @notice A trader's signed authorisation to consume depth on one pool, once.
    /// @dev Every field is load-bearing. `beforeSwap` receives the locker (router), never the
    ///      trader, and `IMsgSender.msgSender()` is self-reported, a malicious router could
    ///      otherwise name any high-standing address. Self-reported identity is not identity.
    ///      - `locker`   binds the credential to one router so it cannot be lifted elsewhere
    ///      - `poolId`   binds it to one pool
    ///      - `maxSize`  binds it to a size, so an observed credential cannot be reused larger
    ///      - `nonce`    makes it single-use
    ///      - `deadline` bounds it in time; a replayable signature is a cap that never expires
    struct DepthCredential {
        address locker;
        bytes32 poolId;
        uint256 maxSize;
        uint256 nonce;
        uint256 deadline;
    }

    error NotOperator();
    error ExpiredCredential();
    error WrongLocker();
    error WrongPool();
    error ReplayedNonce();
    error InvalidSignature();
    error ExceedsDepthAllowance(uint256 requested, uint256 allowed);
    error DepthExhaustedThisTx(uint256 requested, uint256 remaining);

    event RegistryUpdated(address indexed registry);
    event DepthTrancheUpdated(PoolId indexed poolId, uint256 tranche);
    event DepthConsumed(address indexed trader, PoolId indexed poolId, uint256 size, uint256 allowed);

    modifier onlyOperator() {
        if (msg.sender != operator) revert NotOperator();
        _;
    }

    constructor(IPoolManager _poolManager, address _operator, IStandingRegistry _registry) BaseHook(_poolManager) {
        operator = _operator;
        registry = _registry;
    }

    /// @inheritdoc BaseHook
    /// @dev `beforeSwapReturnDelta` is deliberately false. Without it the hook cannot alter swap
    ///      economics even if someone later tried to, so fee neutrality is enforced by the mined
    ///      address rather than by policy alone.
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // -------------------------------------------------------------------------------------
    // operator surface (Stage 1; replaced by the Brevis registry in Stage 3)
    // -------------------------------------------------------------------------------------

    /// @notice Point the hook at a different standing source.
    /// @dev Used to swap the stage-1 operator registry for the Brevis-backed one. It cannot change
    ///      fees, only where depth entitlement is read from.
    /// @param _registry The new registry.
    function setRegistry(IStandingRegistry _registry) external onlyOperator {
        registry = _registry;
        emit RegistryUpdated(address(_registry));
    }

    /// @notice Standing for an address, as reported by the current registry.
    /// @param trader The address to look up.
    function standingOf(address trader) public view returns (uint256) {
        if (address(registry) == address(0)) return 0;
        return registry.standingOf(trader);
    }

    /// @notice Configure the maximum a single swap may consume on a pool.
    /// @param key The pool.
    /// @param tranche Maximum single-swap size in input-token units. Zero leaves the pool uncapped.
    function setDepthTranche(PoolKey calldata key, uint256 tranche) external onlyOperator {
        depthTranche[key.toId()] = tranche;
        emit DepthTrancheUpdated(key.toId(), tranche);
    }

    // -------------------------------------------------------------------------------------
    // views
    // -------------------------------------------------------------------------------------

    /// @notice Fraction of a pool's depth tranche an address with `standing` may consume, in bps.
    /// @dev Linear from BASE_DEPTH_BPS at standing 0 to BPS at FULL_DEPTH_STANDING, then flat.
    ///      Continuous and monotonic, no brackets, no cliffs, nothing to tune.
    /// @param standing The address's proven standing.
    /// @return The accessible fraction in basis points.
    function depthFractionBps(uint256 standing) public pure returns (uint256) {
        if (standing >= FULL_DEPTH_STANDING) return BPS;
        return BASE_DEPTH_BPS + ((BPS - BASE_DEPTH_BPS) * standing) / FULL_DEPTH_STANDING;
    }

    /// @notice The maximum single-swap size available to `trader` on `key`.
    /// @param key The pool.
    /// @param trader The address whose standing is consulted.
    /// @return The cap in input-token units. `type(uint256).max` if the pool is unconfigured.
    function maxSwapSize(PoolKey calldata key, address trader) public view returns (uint256) {
        uint256 tranche = depthTranche[key.toId()];
        if (tranche == 0) return type(uint256).max;
        return (tranche * depthFractionBps(standingOf(trader))) / BPS;
    }

    /// @notice The EIP-712 domain separator for this hook instance.
    function domainSeparator() public view returns (bytes32) {
        return keccak256(
            abi.encode(EIP712_DOMAIN_TYPEHASH, keccak256("Tenure"), keccak256("1"), block.chainid, address(this))
        );
    }

    /// @notice The EIP-712 digest a trader signs to present standing for a swap.
    /// @param c The credential.
    /// @return The digest to sign.
    function hashCredential(DepthCredential memory c) public view returns (bytes32) {
        bytes32 structHash =
            keccak256(abi.encode(DEPTH_CREDENTIAL_TYPEHASH, c.locker, c.poolId, c.maxSize, c.nonce, c.deadline));
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator(), structHash));
    }

    // -------------------------------------------------------------------------------------
    // the hook
    // -------------------------------------------------------------------------------------

    /// @notice Caps the swap at the depth the trader's standing entitles them to.
    /// @dev A swap with no credential is NOT rejected. It receives base depth. Presenting a
    ///      credential is how a trader claims *more* than base, never how they gain entry.
    /// @param sender The locker (router), not the trader. Used only to bind the credential.
    /// @param key The pool being swapped through.
    /// @param params The swap parameters; only the size is consulted.
    /// @param hookData Empty, or an ABI-encoded (DepthCredential, signature).
    /// @return The beforeSwap selector, a zero delta, and a zero fee override.
    function _beforeSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata hookData
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        uint256 tranche = depthTranche[key.toId()];

        // Unconfigured pool: nothing to enforce.
        if (tranche == 0) {
            return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }

        uint256 requested = params.amountSpecified < 0
            // forge-lint: disable-next-line(unsafe-typecast)
            ? uint256(-params.amountSpecified)
            // forge-lint: disable-next-line(unsafe-typecast)
            : uint256(params.amountSpecified);

        address trader;
        uint256 signedCap = type(uint256).max;

        if (hookData.length > 0) {
            (DepthCredential memory c, bytes memory sig) = abi.decode(hookData, (DepthCredential, bytes));

            if (block.timestamp > c.deadline) revert ExpiredCredential();
            if (c.locker != sender) revert WrongLocker();
            if (c.poolId != PoolId.unwrap(key.toId())) revert WrongPool();

            trader = _recover(hashCredential(c), sig);
            if (trader == address(0)) revert InvalidSignature();

            if (nonceUsed[trader][c.nonce]) revert ReplayedNonce();
            nonceUsed[trader][c.nonce] = true;

            signedCap = c.maxSize;
        }
        // else: trader stays address(0), whose standing is 0, which yields BASE_DEPTH_BPS.

        // `entitled` is the ceiling standing earns, per transaction. `allowed` is what THIS swap
        // may take: the stricter of the entitlement and what the trader actually authorised.
        uint256 entitled = (tranche * depthFractionBps(standingOf(trader))) / BPS;
        uint256 allowed = signedCap < entitled ? signedCap : entitled;

        if (requested > allowed) revert ExceedsDepthAllowance(requested, allowed);

        // --- the per-transaction meter ---
        //
        // Without this, the cap is cosmetic: a trader signs several credentials and splits one
        // large take into N cap-sized swaps in a single transaction, at near-zero extra cost.
        // "Depth is the product" would then gate nothing.
        //
        // Consumption accumulates against the RECOVERED TRADER, not the credential, so signing
        // more credentials cannot raise the ceiling. It is checked against `entitled` rather than
        // `allowed`, for the same reason.
        //
        // Unsigned swaps meter against address(0). Under per-transaction scope that is safe: a
        // shared anonymous bucket can only be shared within one transaction, and one transaction
        // has one initiator. Crucially, unsigned swaps are NOT exempt, exempting them would make
        // signing strictly worse than not signing, and the cheapest route to the whole book would
        // be to stay anonymous and split. That would run the mechanism backwards.
        uint256 consumed = _consumedDepth(trader);
        if (consumed + requested > entitled) {
            revert DepthExhaustedThisTx(requested, entitled - consumed);
        }
        _setConsumedDepth(trader, consumed + requested);

        emit DepthConsumed(trader, key.toId(), requested, allowed);

        // Zero fee override, unconditionally. The fee is identical for every address (the fee-parity rule).
        return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    /// @notice Depth already consumed by `trader` in this transaction.
    /// @dev Cleared automatically at transaction end by EIP-1153 semantics. Exposed for tests and
    ///      for integrators that want to know the remaining allowance mid-transaction.
    /// @param trader The meter key: the recovered signer, or address(0) for unsigned swaps.
    function consumedDepthThisTx(address trader) external view returns (uint256) {
        return _consumedDepth(trader);
    }

    /// @dev Reads the per-transaction accumulator for one meter key.
    function _consumedDepth(address trader) internal view returns (uint256 v) {
        bytes32 slot = keccak256(abi.encode(T_CONSUMED_NAMESPACE, trader));
        assembly ("memory-safe") {
            v := tload(slot)
        }
    }

    /// @dev Writes the per-transaction accumulator for one meter key.
    function _setConsumedDepth(address trader, uint256 v) internal {
        bytes32 slot = keccak256(abi.encode(T_CONSUMED_NAMESPACE, trader));
        assembly ("memory-safe") {
            tstore(slot, v)
        }
    }

    /// @dev ECDSA recovery rejecting malleable signatures. Returns address(0) on malformed input so
    ///      the caller reverts rather than proceeding with a bogus trader.
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
        // Upper-half s is rejected: a malleable signature is a second valid credential for the
        // same nonce, which would defeat the replay guard.
        if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
            return address(0);
        }
        if (v != 27 && v != 28) return address(0);
        return ecrecover(digest, v, r, s);
    }
}
