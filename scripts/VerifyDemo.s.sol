// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";

import {TenureHook} from "../src/TenureHook.sol";
import {TenureSwapRouter} from "../src/TenureSwapRouter.sol";
import {DemoERC20} from "../src/DemoERC20.sol";

/// @title VerifyDemo — does the deployed cap actually bind?
/// @notice Runs against the REAL deployed Sepolia contracts. Simulate it, do not broadcast:
///
///   forge script scripts/VerifyDemo.s.sol --rpc-url $RPC_URL
///
///         A deploy log proves a transaction landed; it does not prove the mechanism works. This
///         asserts four behaviours against live state:
///
///           1. a swap inside the allowance succeeds
///           2. a swap over the allowance reverts with `ExceedsDepthAllowance`
///           3. two legs in one transaction accumulate, and the second reverts
///              `DepthExhaustedThisTx` — the splitting attack
///           4. an unsigned swap still executes, at base depth
///
///         (4) is the anti-whitelist property, the one most easily lost in a refactor, so it is
///         asserted rather than assumed.
///
/// @dev THE FAILURES ARE MATCHED BY SELECTOR, NOT BY "IT REVERTED". A swap can revert for a dozen
///      reasons that have nothing to do with depth — a bad approval, no liquidity, a price limit —
///      and a test that only checks `!success` would pass for any of them and prove nothing. v4
///      wraps hook reverts in `CustomRevert.WrappedError`, so the expected selector is searched for
///      inside the returndata rather than compared against its first four bytes.
///
/// @dev No `try/catch`, and no helper contract: Foundry forbids `address(this)` in a script, which
///      `try this.f()` needs. Low-level calls avoid it and let us read the revert data.
contract VerifyDemo is Script {
    using PoolIdLibrary for PoolKey;

    uint24 internal constant FEE = 3000;
    int24 internal constant TICK_SPACING = 60;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address me = vm.addr(pk);
        TenureHook hook = TenureHook(vm.envAddress("HOOK"));
        TenureSwapRouter router = TenureSwapRouter(payable(vm.envAddress("ROUTER")));

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(vm.envAddress("CURRENCY0")),
            currency1: Currency.wrap(vm.envAddress("CURRENCY1")),
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(hook))
        });

        uint256 allowance = hook.maxSwapSize(key, me);
        uint256 base = (hook.depthTranche(key.toId()) * hook.BASE_DEPTH_BPS()) / hook.BPS();

        console.log("standing (bps) :", hook.standingOf(me));
        console.log("allowance      :", allowance);
        console.log("base depth     :", base);
        console.log("");

        vm.startPrank(me);
        DemoERC20(Currency.unwrap(key.currency0)).mint(me, 10_000_000e18);
        DemoERC20(Currency.unwrap(key.currency0)).approve(address(router), type(uint256).max);
        DemoERC20(Currency.unwrap(key.currency1)).approve(address(router), type(uint256).max);

        // --- 1. inside the allowance ---
        (bool ok, bytes memory ret) = _swap(router, key, hook, pk, _one(allowance / 2, 1));
        require(ok, _why("1. swap inside the allowance reverted", ret));
        console.log("1. swap at half the allowance   OK");

        // --- 2. over the allowance ---
        (ok, ret) = _swap(router, key, hook, pk, _one(allowance + 1e18, 2));
        require(!ok, "2. oversized swap did NOT revert");
        require(_has(ret, TenureHook.ExceedsDepthAllowance.selector), _why("2. wrong revert", ret));
        console.log("2. over the allowance           reverted ExceedsDepthAllowance");

        // --- 3. splitting across two legs of ONE transaction ---
        uint256 leg = (allowance * 3) / 4; // each leg fits; together they do not
        Order[] memory two = new Order[](2);
        two[0] = Order(leg, 301);
        two[1] = Order(leg, 302);
        (ok, ret) = _swap(router, key, hook, pk, two);
        require(!ok, "3. split across legs did NOT revert");
        require(_has(ret, TenureHook.DepthExhaustedThisTx.selector), _why("3. wrong revert", ret));
        console.log("3. split across legs in one tx  reverted DepthExhaustedThisTx");

        // --- 4. unsigned still swaps, at base depth ---
        TenureSwapRouter.Leg[] memory unsigned_ = new TenureSwapRouter.Leg[](1);
        unsigned_[0] = TenureSwapRouter.Leg({zeroForOne: true, amountSpecified: -int256(base / 2), hookData: ""});
        (ok, ret) = _raw(router, key, unsigned_);
        require(ok, _why("4. unsigned swap reverted", ret));
        console.log("4. unsigned swap at base depth  OK - nobody is excluded");

        vm.stopPrank();
        console.log("");
        console.log("ALL FOUR CONFIRMED ON THE DEPLOYED CONTRACTS.");
    }

    struct Order {
        uint256 size;
        uint256 nonce;
    }

    function _one(uint256 size, uint256 nonce) internal pure returns (Order[] memory o) {
        o = new Order[](1);
        o[0] = Order(size, nonce);
    }

    /// @dev Build a signed credential per order and fire them as legs of one transaction.
    function _swap(TenureSwapRouter router, PoolKey memory key, TenureHook hook, uint256 pk, Order[] memory orders)
        internal
        returns (bool, bytes memory)
    {
        TenureSwapRouter.Leg[] memory legs = new TenureSwapRouter.Leg[](orders.length);
        for (uint256 i = 0; i < orders.length; i++) {
            TenureHook.DepthCredential memory c = TenureHook.DepthCredential({
                locker: address(router),
                poolId: PoolId.unwrap(key.toId()),
                maxSize: orders[i].size,
                nonce: orders[i].nonce,
                deadline: block.timestamp + 3600
            });
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, hook.hashCredential(c));
            legs[i] = TenureSwapRouter.Leg({
                zeroForOne: true,
                amountSpecified: -int256(orders[i].size),
                hookData: abi.encode(c, abi.encodePacked(r, s, v))
            });
        }
        return _raw(router, key, legs);
    }

    function _raw(TenureSwapRouter router, PoolKey memory key, TenureSwapRouter.Leg[] memory legs)
        internal
        returns (bool ok, bytes memory ret)
    {
        (ok, ret) = address(router).call(abi.encodeCall(TenureSwapRouter.swap, (key, legs)));
    }

    /// @dev v4 wraps hook reverts, so look for the selector anywhere in the returndata.
    function _has(bytes memory data, bytes4 selector) internal pure returns (bool) {
        if (data.length < 4) return false;
        for (uint256 i = 0; i + 4 <= data.length; i++) {
            if (
                data[i] == selector[0] && data[i + 1] == selector[1] && data[i + 2] == selector[2]
                    && data[i + 3] == selector[3]
            ) return true;
        }
        return false;
    }

    function _why(string memory label, bytes memory ret) internal pure returns (string memory) {
        return string.concat(label, " | returndata 0x", _hex(ret));
    }

    function _hex(bytes memory b) internal pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";
        uint256 n = b.length > 64 ? 64 : b.length;
        bytes memory out = new bytes(n * 2);
        for (uint256 i = 0; i < n; i++) {
            out[i * 2] = alphabet[uint8(b[i]) >> 4];
            out[i * 2 + 1] = alphabet[uint8(b[i]) & 0x0f];
        }
        return string(out);
    }
}
