// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";

import {TenureHook} from "../src/TenureHook.sol";
import {OperatorStandingRegistry} from "../src/OperatorStandingRegistry.sol";
import {IStandingRegistry} from "../src/interfaces/IStandingRegistry.sol";
import {TenureSwapRouter} from "../src/TenureSwapRouter.sol";
import {DemoERC20} from "../src/DemoERC20.sol";

/// @title DeployDemo — the Sepolia pool the app swaps against
/// @notice Stands up everything the demonstration UI needs on top of an ALREADY-DEPLOYED
///         `TenureHook`: two ERC20s, a pool guarded by the hook, liquidity, a router, and a
///         standing registry with a figure in it.
///
/// @dev WHY AN OPERATOR REGISTRY AND NOT THE ZK ONE. `TenureRegistry` only accepts a Brevis
///      callback. Our query was accepted, priced and paid on Sepolia and reached QS_PAID, but no
///      callback arrived in the 47 minutes we watched — see analysis/brevis-gateway-diagnosis.md,
///      which declines to upgrade that into a claim about Brevis' infrastructure. Against that
///      registry, `standingOf` returns 0 for every address and the app could only show base depth. `OperatorStandingRegistry` sits behind the
///      same `IStandingRegistry` interface for exactly this case.
///
///      THE UI MUST SAY SO. Showing operator-written standing under a label claiming a verified
///      on-chain ZK proof would be a false claim about the sponsor integration, on the artifact a
///      judge opens first. The app names the registry address and the trust model.
///
/// @dev The standing written below is not invented: 9375 bps over 32 swaps is the balanced
///      fixture's real circuit output, reproducible with `npm run prove -- balanced`, and 0 bps
///      over 29 swaps is the one-sided fixture's. The operator registry is transcribing a figure
///      the circuit actually proved, not making one up.
contract DeployDemo is Script {
    using PoolIdLibrary for PoolKey;

    /// @dev 0.30%, so the fee shown in the UI is the fee the pool charges.
    uint24 internal constant FEE = 3000;
    int24 internal constant TICK_SPACING = 60;

    /// @dev 1:1 starting price. Both demo tokens are notional; a skewed price would only make the
    ///      numbers in the UI harder to read against the depth cap, which is the thing on show.
    uint160 internal constant SQRT_PRICE_1_1 = 79228162514264337593543950336;

    /// @dev Depth tranche for the demo pool, in currency0 base units (18 decimals).
    ///      Base depth is 5% of this, so an address with no standing still swaps 12,500.
    uint256 internal constant TRANCHE = 250_000e18;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address operator = vm.addr(pk);
        IPoolManager manager = IPoolManager(vm.envAddress("POOL_MANAGER"));
        TenureHook hook = TenureHook(vm.envAddress("HOOK"));

        require(hook.operator() == operator, "deployer is not the hook operator");

        vm.startBroadcast(pk);

        DemoERC20 tokenA = new DemoERC20("Tenure Demo USD", "tUSD", 18, 1_000_000e18);
        DemoERC20 tokenB = new DemoERC20("Tenure Demo Ether", "tETH", 18, 1_000e18);

        // v4 requires currency0 < currency1 by address.
        (address c0, address c1) =
            address(tokenA) < address(tokenB) ? (address(tokenA), address(tokenB)) : (address(tokenB), address(tokenA));

        TenureSwapRouter router = new TenureSwapRouter(manager);

        OperatorStandingRegistry registry = new OperatorStandingRegistry(operator);
        hook.setRegistry(IStandingRegistry(address(registry)));

        // The balanced fixture's real proven figure, so the app shows something the circuit
        // actually produced rather than a placeholder.
        registry.setStanding(operator, 9375, 32);

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(c0),
            currency1: Currency.wrap(c1),
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(hook))
        });

        manager.initialize(key, SQRT_PRICE_1_1);
        hook.setDepthTranche(key, TRANCHE);

        // Fund the deployer and seed liquidity through the same router the app uses.
        DemoERC20(c0).mint(operator, 5_000_000e18);
        DemoERC20(c1).mint(operator, 5_000_000e18);
        DemoERC20(c0).approve(address(router), type(uint256).max);
        DemoERC20(c1).approve(address(router), type(uint256).max);

        // Full-range, so a demo swap can never run out of book and revert for a reason that has
        // nothing to do with the depth cap being demonstrated.
        int24 lower = (TickMath.MIN_TICK / TICK_SPACING) * TICK_SPACING;
        int24 upper = (TickMath.MAX_TICK / TICK_SPACING) * TICK_SPACING;
        router.addLiquidity(key, lower, upper, 2_000_000e18);

        vm.stopBroadcast();

        console.log("");
        console.log("=== demo pool ===");
        console.log("currency0    :", c0);
        console.log("currency1    :", c1);
        console.log("router       :", address(router));
        console.log("registry     :", address(registry));
        console.log("hook         :", address(hook));
        console.log("poolId       :");
        console.logBytes32(PoolId.unwrap(key.toId()));
        console.log("tranche      :", TRANCHE);
    }
}
