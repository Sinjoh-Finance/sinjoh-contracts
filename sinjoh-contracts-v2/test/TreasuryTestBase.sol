// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { ProjectTreasuryVaultV2 } from "../src/treasury/ProjectTreasuryVaultV2.sol";
import { ProjectVotesToken } from "../src/token/ProjectVotesToken.sol";
import { MockRegistry } from "./mocks/MockRegistry.sol";
import {
    MockProjectBasketManager,
    MockProjectController,
    MockProjectPriceGuard,
    MockProjectSwapAdapter,
    MockTreasuryERC20
} from "./mocks/MockTreasuryIntegrations.sol";
import { TestBase } from "./TestBase.sol";

abstract contract TreasuryTestBase is TestBase {
    uint256 internal constant START = 1_000_000;
    uint256 internal constant BASKET_ID = 7;
    address internal constant CREATOR = address(0xC0FFEE);
    address internal constant DEPOSITOR = address(0xD0051E);
    address internal constant RECIPIENT = address(0xBEEF);
    address internal constant OUTSIDER = address(0xBAD);
    bytes internal constant ROUTE_DATA = hex"010203";

    MockRegistry internal registry;
    ProjectVotesToken internal token;
    MockProjectController internal projectController;
    MockTreasuryERC20 internal assetA;
    MockTreasuryERC20 internal assetB;
    MockProjectSwapAdapter internal adapter;
    MockProjectPriceGuard internal priceGuard;
    MockProjectBasketManager internal basketManager;
    ProjectTreasuryVaultV2 internal vault;

    function _setUpTreasury() internal {
        vm.warp(START);
        registry = MockRegistry(vm.deployCode("MockRegistry.sol:MockRegistry"));
        ProjectVotesToken.TokenAllocation[] memory allocations =
            new ProjectVotesToken.TokenAllocation[](1);
        allocations[0] =
            ProjectVotesToken.TokenAllocation({ recipient: DEPOSITOR, amount: 1_000_000e18 });
        token = ProjectVotesToken(
            vm.deployCode(
                "ProjectVotesToken.sol:ProjectVotesToken",
                abi.encode(
                    "Project Token",
                    "PROJECT",
                    address(registry),
                    CREATOR,
                    allocations,
                    new address[](0)
                )
            )
        );
        projectController = MockProjectController(
            vm.deployCode(
                "MockTreasuryIntegrations.sol:MockProjectController", abi.encode(token.projectId())
            )
        );
        assetA = MockTreasuryERC20(
            vm.deployCode(
                "MockTreasuryIntegrations.sol:MockTreasuryERC20", abi.encode("Asset A", "ASSETA")
            )
        );
        assetB = MockTreasuryERC20(
            vm.deployCode(
                "MockTreasuryIntegrations.sol:MockTreasuryERC20", abi.encode("Asset B", "ASSETB")
            )
        );
        adapter = MockProjectSwapAdapter(
            payable(vm.deployCode("MockTreasuryIntegrations.sol:MockProjectSwapAdapter"))
        );
        priceGuard = MockProjectPriceGuard(
            vm.deployCode("MockTreasuryIntegrations.sol:MockProjectPriceGuard")
        );
        basketManager = MockProjectBasketManager(
            payable(vm.deployCode("MockTreasuryIntegrations.sol:MockProjectBasketManager"))
        );

        bytes32 root = _approvalLeaf(address(assetA), address(assetB), keccak256(ROUTE_DATA));
        vault = ProjectTreasuryVaultV2(
            payable(vm.deployCode(
                    "ProjectTreasuryVaultV2.sol:ProjectTreasuryVaultV2",
                    abi.encode(
                        address(registry),
                        address(token),
                        CREATOR,
                        address(projectController),
                        root,
                        address(basketManager)
                    )
                ))
        );
        _createBasket(BASKET_ID, 0, new address[](0), new uint256[](0));
        priceGuard.setQuote(1, 1_086_400);
        adapter.configure(1, type(uint256).max, false);
        vm.deal(DEPOSITOR, 1_000 ether);
    }

    function _createBasket(
        uint256 basketId,
        uint256 burnPrice,
        address[] memory assets,
        uint256[] memory amounts
    ) internal {
        basketManager.createBasket(
            address(vault), basketId, token.projectId(), address(token), burnPrice, assets, amounts
        );
    }

    function _approvalLeaf(address assetIn, address assetOut, bytes32 routeHash)
        internal
        view
        returns (bytes32)
    {
        bytes32 inner = keccak256(
            abi.encode(
                keccak256("SINJOH_V2_TREASURY_SWAP_APPROVAL"),
                block.chainid,
                token.projectId(),
                address(adapter),
                address(adapter).codehash,
                address(priceGuard),
                address(priceGuard).codehash,
                assetIn,
                assetOut,
                routeHash
            )
        );
        return keccak256(bytes.concat(inner));
    }

    function _controllerCall(bytes memory data) internal returns (bytes memory) {
        return projectController.execute(address(vault), data);
    }

    function _deposit(address asset, uint256 amount, bool routeToBasket) internal {
        MockTreasuryERC20(asset).mint(DEPOSITOR, amount);
        vm.startPrank(DEPOSITOR);
        MockTreasuryERC20(asset).approve(address(vault), amount);
        vault.deposit(asset, amount, routeToBasket);
        vm.stopPrank();
    }

    function _configureSingleAssetRoute(address asset, uint16 bps) internal {
        address[] memory assets = new address[](1);
        assets[0] = asset;
        _controllerCall(abi.encodeCall(vault.configureBasketRoute, (BASKET_ID, bps, assets)));
    }
}
