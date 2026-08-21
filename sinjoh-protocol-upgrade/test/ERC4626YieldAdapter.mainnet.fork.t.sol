// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { AddressGovernanceController } from "../src/governance/AddressGovernanceController.sol";
import { ERC4626YieldAdapter } from "../src/adapters/ERC4626YieldAdapter.sol";
import { IGovernanceController } from "../src/interfaces/IGovernanceController.sol";
import { YieldBasket } from "../src/YieldBasket.sol";
import { TestBase } from "./TestBase.sol";
import { MockFundable } from "./mocks/Mocks.sol";

/// @notice Opt-in canary for the exact reviewed Robinhood Chain ERC-4626 deployment.
/// @dev The test is inert unless all four environment variables are supplied. The selected
/// funder is impersonated only on the local fork; no transaction is broadcast.
contract ERC4626YieldAdapterMainnetForkTest is TestBase {
    uint256 private constant ROBINHOOD_MAINNET_CHAIN_ID = 4_663;
    address private constant GUARDIAN = address(0xBEEF);

    error InvalidCanaryAmount(uint256 amount);

    function testSelectedERC4626DepositAndFullExitCanary() public {
        string memory rpcUrl = vm.envOr("ROBINHOOD_MAINNET_RPC_URL", string(""));
        address vaultAddress = vm.envOr("YIELD_CANARY_ERC4626_VAULT", address(0));
        address funder = vm.envOr("YIELD_CANARY_FUNDER", address(0));
        uint256 amount = vm.envOr("YIELD_CANARY_AMOUNT", uint256(0));
        if (
            bytes(rpcUrl).length == 0 || vaultAddress == address(0) || funder == address(0)
                || amount == 0
        ) return;
        if (amount > type(uint128).max) revert InvalidCanaryAmount(amount);

        vm.createSelectFork(rpcUrl);
        assertEq(block.chainid, ROBINHOOD_MAINNET_CHAIN_ID);
        IERC4626 vault = IERC4626(vaultAddress);
        IERC20 asset = IERC20(vault.asset());
        assertTrue(address(vault).code.length != 0 && address(asset).code.length != 0);

        AddressGovernanceController controller =
            new AddressGovernanceController(address(this), IGovernanceController.Mode.INDIVIDUAL);
        MockFundable treasury = new MockFundable();
        YieldBasket basket = new YieldBasket(controller, GUARDIAN, asset, address(treasury));
        ERC4626YieldAdapter adapter = new ERC4626YieldAdapter(address(basket), vault);
        basket.configureAdapter(adapter, 10_000, 30 minutes);

        vm.startPrank(funder);
        assertTrue(asset.approve(address(basket), amount));
        basket.fund(address(asset), amount, "");
        vm.stopPrank();
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 shares = basket.allocate(adapter, uint128(amount));
        assertTrue(shares != 0 && adapter.totalAssets() != 0);

        basket.withdrawFromAdapter(adapter, shares);
        uint256 recoveredPrincipal = basket.idlePrincipal();
        if (basket.realizedIdleValue() != 0) {
            basket.realizeIdleValue(basket.realizedIdleValue());
        }
        basket.withdrawIdlePrincipal(recoveredPrincipal);
        assertEq(basket.managedPrincipal(), 0);
        assertEq(vault.balanceOf(address(adapter)), 0);
    }
}
