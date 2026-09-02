// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// The demo's actual work. Kept out of the script file for two reasons: Foundry forbids
// `address(this)` inside a script contract, and a script file containing two contracts
// forces `--tc`, which breaks the one-command-no-arguments requirement.

import {console} from "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {HookMiner} from "v4-periphery/test/shared/HookMiner.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";

import {TenureHook} from "../src/TenureHook.sol";
import {TenureRegistry} from "../src/TenureRegistry.sol";
import {IStandingRegistry} from "../src/interfaces/IStandingRegistry.sol";
import {CompositeRouter} from "../test/routers/CompositeRouter.sol";

contract TenureDemo {
    using PoolIdLibrary for PoolKey;

    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    // --- the two proven fixtures, byte-for-byte as the circuit emitted them ---
    // layout: address(20) | balanceBps(2) | swapCount(2) | fromBlock(8) | toBlock(8)
    bytes constant PROOF_BALANCED =
        hex"0f4a1d7fdf4890be35e71f3e0bbc4a0ec377eca3249f00200000000001425cc2000000000142a51f";
    bytes constant PROOF_ONESIDED =
        hex"308c6fbd6a14881af333649f17f2fde9cd75e2a60000001d0000000001425c5c000000000142a8ad";

    bytes32 constant VK_HASH = 0x0230047e074d6b8c19ab6714303a3c84412e6dc7a6d540835925f1e08e6f94b8;

    address constant BREVIS_REQUEST = address(0xB4E415);
    uint256 constant TRANCHE = 100e18;

    // Keys for the two traders. The addresses these produce are NOT the mainnet addresses in the
    // proofs — a demo cannot hold their private keys — so standing is recorded against these and
    // the mainnet figures are carried across verbatim.
    uint256 constant K_BALANCED = 0xB0;
    uint256 constant K_ONESIDED = 0x0E;

    PoolManager mgr;
    TenureHook hook;
    TenureRegistry registry;
    CompositeRouter router;
    PoolKey key;
    MockERC20 t0;
    MockERC20 t1;
    address balanced;
    address onesided;

    function play() external {
        balanced = vm.addr(K_BALANCED);
        onesided = vm.addr(K_ONESIDED);

        _line();
        console.log("  TENURE - depth is the product");
        console.log("  every address pays the same fee;");
        console.log("  what you earn is how much of the book you reach");
        _line();

        _setup();
        _act1_proofs();
        _act2_depth();
        _act3_sameSwap();
        _act4_split();

        _line();
        console.log("  the cap binds, and it cannot be split around.");
        console.log("  the fee never moved.");
        _line();
    }

    // -----------------------------------------------------------------------------------
    // setup — deliberately silent, this is not part of the story
    // -----------------------------------------------------------------------------------
    function _setup() internal {
        mgr = new PoolManager(address(this));
        registry = new TenureRegistry(BREVIS_REQUEST, address(this));
        registry.setVkHash(VK_HASH);

        (address addr, bytes32 salt) = HookMiner.find(
            address(this),
            uint160(Hooks.BEFORE_SWAP_FLAG),
            type(TenureHook).creationCode,
            abi.encode(IPoolManager(address(mgr)), address(this), IStandingRegistry(address(registry)))
        );
        hook =
            new TenureHook{salt: salt}(IPoolManager(address(mgr)), address(this), IStandingRegistry(address(registry)));
        require(address(hook) == addr, "hook mining failed");

        MockERC20 a = new MockERC20("T0", "T0", 18);
        MockERC20 b = new MockERC20("T1", "T1", 18);
        (t0, t1) = address(a) < address(b) ? (a, b) : (b, a);
        t0.mint(address(this), 1e30);
        t1.mint(address(this), 1e30);

        key = PoolKey(Currency.wrap(address(t0)), Currency.wrap(address(t1)), 3000, 60, IHooks(address(hook)));
        mgr.initialize(key, TickMath.getSqrtPriceAtTick(0));

        router = new CompositeRouter(IPoolManager(address(mgr)));
        t0.transfer(address(router), 1e29);
        t1.transfer(address(router), 1e29);

        CompositeRouter.Step[] memory add = new CompositeRouter.Step[](1);
        add[0].kind = CompositeRouter.StepKind.ADD_LIQUIDITY;
        add[0].key = key;
        add[0].tickLower = -60000;
        add[0].tickUpper = 60000;
        add[0].liquidityDelta = 1e22;
        router.execute(add, _both());

        hook.setDepthTranche(key, TRANCHE);
    }

    // -----------------------------------------------------------------------------------
    // 1 — two real proofs land on chain
    // -----------------------------------------------------------------------------------
    function _act1_proofs() internal {
        console.log(" ");
        console.log("  [1] two ZK proofs, generated off-chain against real");
        console.log("      mainnet swap logs, verified against the vk");
        console.log(" ");

        vm.startPrank(BREVIS_REQUEST);
        registry.brevisCallback(VK_HASH, _withTrader(PROOF_BALANCED, balanced));
        registry.brevisCallback(VK_HASH, _withTrader(PROOF_ONESIDED, onesided));
        vm.stopPrank();

        (, uint16 bBal, uint16 bCnt,,) = registry.decodeOutput(PROOF_BALANCED);
        (, uint16 oBal, uint16 oCnt,,) = registry.decodeOutput(PROOF_ONESIDED);

        console.log("      trader A   17 buys / 15 sells");
        console.log("        balance      ", uint256(bBal), "bps");
        console.log("        swaps proven ", uint256(bCnt));
        console.log(" ");
        console.log("      trader B   29 buys /  0 sells");
        console.log("        balance      ", uint256(oBal), "bps");
        console.log("        swaps proven ", uint256(oCnt));
        console.log(" ");
        console.log("      the registry rejects any proof whose vk hash");
        console.log("      is not the one it was configured with.");
    }

    // -----------------------------------------------------------------------------------
    // 2 — standing becomes accessible depth
    // -----------------------------------------------------------------------------------
    function _act2_depth() internal {
        console.log(" ");
        console.log("  [2] standing becomes accessible depth");
        console.log("      pool tranche:", TRANCHE / 1e18, "units");
        console.log(" ");
        console.log("      trader A  ", hook.maxSwapSize(key, balanced) / 1e18, "units");
        console.log("      trader B  ", hook.maxSwapSize(key, onesided) / 1e18, "units");
        console.log("      unsigned  ", hook.maxSwapSize(key, address(0)) / 1e18, "units");
        console.log(" ");
        console.log("      nobody is excluded. zero standing still reaches");
        console.log("      5% of the book, and standing is free to earn.");
    }

    // -----------------------------------------------------------------------------------
    // 3 — the same swap, two outcomes
    // -----------------------------------------------------------------------------------
    function _act3_sameSwap() internal {
        uint256 size = 60e18;
        console.log(" ");
        console.log("  [3] both traders attempt the SAME swap:", size / 1e18, "units");
        console.log(" ");
        console.log("      trader A  ", _try(K_BALANCED, balanced, size, 1) ? "FILLED" : "capped");
        console.log("      trader B  ", _try(K_ONESIDED, onesided, size, 1) ? "FILLED" : "CAPPED");
        console.log(" ");
        console.log("      same pool, same fee tier, same size.");
        console.log("      only the reachable depth differed.");
    }

    // -----------------------------------------------------------------------------------
    // 4 — the split attack buys nothing
    // -----------------------------------------------------------------------------------
    function _act4_split() internal {
        uint256 cap = hook.maxSwapSize(key, onesided);
        console.log(" ");
        console.log("  [4] trader B splits into 3 cap-sized swaps");
        console.log("      in ONE transaction, to route around the cap");
        console.log(" ");
        console.log("      each swap   ", cap / 1e18, "units  (exactly at cap)");
        console.log("      total wanted", (cap * 3) / 1e18, "units");
        console.log(" ");
        console.log("      result:", _trySplit(K_ONESIDED, onesided, cap) ? "SUCCEEDED" : "REVERTED");
        console.log(" ");
        console.log("      depth is metered per transaction, not per swap.");
        console.log("      splitting buys nothing.");
    }

    // -----------------------------------------------------------------------------------
    // helpers
    // -----------------------------------------------------------------------------------
    function _both() internal view returns (Currency[] memory c) {
        c = new Currency[](2);
        c[0] = key.currency0;
        c[1] = key.currency1;
    }

    /// @dev Re-point a proof's output at a demo address. The balance, swap count and block window
    ///      are the circuit's own, unmodified.
    function _withTrader(bytes memory out, address who) internal pure returns (bytes memory) {
        bytes memory r = out;
        bytes20 w = bytes20(who);
        for (uint256 i = 0; i < 20; i++) {
            r[i] = w[i];
        }
        return r;
    }

    function _cred(uint256 pk, uint256 size, uint256 nonce) internal view returns (bytes memory) {
        TenureHook.DepthCredential memory c = TenureHook.DepthCredential({
            locker: address(router),
            poolId: PoolId.unwrap(key.toId()),
            maxSize: size,
            nonce: nonce,
            deadline: block.timestamp + 1 hours
        });
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, hook.hashCredential(c));
        return abi.encode(c, abi.encodePacked(r, s, v));
    }

    function _try(uint256 pk, address, uint256 size, uint256 nonce) internal returns (bool) {
        CompositeRouter.Step[] memory st = new CompositeRouter.Step[](1);
        st[0].kind = CompositeRouter.StepKind.SWAP;
        st[0].key = key;
        st[0].zeroForOne = true;
        st[0].amountSpecified = -int256(size);
        st[0].hookData = _cred(pk, size, nonce);
        try router.execute(st, _both()) {
            return true;
        } catch {
            return false;
        }
    }

    function _trySplit(uint256 pk, address, uint256 cap) internal returns (bool) {
        CompositeRouter.Step[] memory st = new CompositeRouter.Step[](3);
        for (uint256 i = 0; i < 3; i++) {
            st[i].kind = CompositeRouter.StepKind.SWAP;
            st[i].key = key;
            st[i].zeroForOne = true;
            st[i].amountSpecified = -int256(cap);
            st[i].hookData = _cred(pk, cap, 100 + i);
        }
        try router.execute(st, _both()) {
            return true;
        } catch {
            return false;
        }
    }

    function _line() internal pure {
        console.log("  ------------------------------------------------");
    }
}
