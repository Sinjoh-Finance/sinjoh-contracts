// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { ProjectModuleBits } from "../src/libraries/ProjectModuleBits.sol";
import { ProjectRouterV2 } from "../src/router/ProjectRouterV2.sol";
import { RouterAction, RouterActionType, RouterRouteInput } from "../src/router/RouterTypes.sol";
import { ProjectTreasuryVaultV2 } from "../src/treasury/ProjectTreasuryVaultV2.sol";
import { RegistryTestBase } from "./RegistryTestBase.sol";
import { MockRouterSink } from "./mocks/MockRouterIntegrations.sol";
import {
    MockProjectPriceGuard,
    MockProjectSwapAdapter,
    MockTreasuryERC20
} from "./mocks/MockTreasuryIntegrations.sol";

abstract contract RouterTestBase is RegistryTestBase {
    address internal constant FEE_RECIPIENT = address(0xFEE);
    address internal constant RECIPIENT = address(0xBEEF);
    bytes internal constant ROUTE_DATA = hex"010203";

    MockTreasuryERC20 internal assetA;
    MockTreasuryERC20 internal assetB;
    MockProjectSwapAdapter internal adapter;
    MockProjectPriceGuard internal priceGuard;
    MockRouterSink internal airdropSink;
    MockRouterSink internal raffleSink;
    MockRouterSink internal liquiditySink;
    ProjectTreasuryVaultV2 internal treasury;

    function _setUpRouterDependencies() internal {
        _setUpRegistry();
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
        airdropSink = _deploySink();
        raffleSink = _deploySink();
        liquiditySink = _deploySink();
        treasury = ProjectTreasuryVaultV2(
            payable(vm.deployCode(
                    "ProjectTreasuryVaultV2.sol:ProjectTreasuryVaultV2",
                    abi.encode(
                        address(registry),
                        address(token),
                        CREATOR,
                        address(projectController),
                        bytes32(0),
                        address(0)
                    )
                ))
        );
        priceGuard.setQuote(1, 2_000_000);
        adapter.configure(1, type(uint256).max, false);
        vm.deal(HOLDER, 1_000 ether);
    }

    function _deployRouter(RouterRouteInput[] memory routes, bytes32 approvalRoot)
        internal
        returns (ProjectRouterV2 deployed)
    {
        deployed = ProjectRouterV2(
            payable(vm.deployCode(
                    "ProjectRouterV2.sol:ProjectRouterV2",
                    abi.encode(
                        address(registry),
                        address(token),
                        CREATOR,
                        address(projectController),
                        FEE_RECIPIENT,
                        address(treasury),
                        address(airdropSink),
                        address(raffleSink),
                        address(liquiditySink),
                        approvalRoot,
                        routes
                    )
                ))
        );
    }

    function _singleRoute(address inputAsset, RouterAction memory action)
        internal
        pure
        returns (RouterRouteInput[] memory routes)
    {
        routes = new RouterRouteInput[](1);
        routes[0].inputAsset = inputAsset;
        routes[0].actions = new RouterAction[](1);
        routes[0].actions[0] = action;
    }

    function _sendAction(address recipient, uint16 bps)
        internal
        pure
        returns (RouterAction memory)
    {
        return RouterAction({
            actionType: RouterActionType.SEND,
            allocationBps: bps,
            recipient: recipient,
            adapter: address(0),
            priceGuard: address(0),
            actionConfig: ""
        });
    }

    function _fund(ProjectRouterV2 router, address asset, uint256 amount) internal {
        if (asset == address(token)) {
            vm.startPrank(HOLDER);
            token.approve(address(router), amount);
            router.fund(token.projectId(), address(token), asset, amount, "");
            vm.stopPrank();
        } else {
            MockTreasuryERC20(asset).mint(HOLDER, amount);
            vm.startPrank(HOLDER);
            MockTreasuryERC20(asset).approve(address(router), amount);
            router.fund(token.projectId(), address(token), asset, amount, "");
            vm.stopPrank();
        }
    }

    function _execute(ProjectRouterV2 router, address asset, uint256 maxAmount) internal {
        (, RouterAction[] memory actions) = router.activeRoute(asset);
        uint256 count = actions.length;
        router.execute(asset, maxAmount, new uint256[](count), new bytes[](count));
    }

    function _controllerCall(ProjectRouterV2 router, bytes memory data)
        internal
        returns (bytes memory)
    {
        return projectController.execute(address(router), data);
    }

    function _deploySink() internal returns (MockRouterSink) {
        return MockRouterSink(
            payable(vm.deployCode(
                    "MockRouterIntegrations.sol:MockRouterSink",
                    abi.encode(address(registry), address(token), token.projectId())
                ))
        );
    }

    function _swapLeaf(address inputAsset, address outputAsset) internal view returns (bytes32) {
        bytes32 inner = keccak256(
            abi.encode(
                keccak256("SINJOH_V2_ROUTER_SWAP_APPROVAL"),
                block.chainid,
                address(adapter).codehash,
                address(priceGuard).codehash,
                inputAsset,
                outputAsset,
                keccak256(ROUTE_DATA)
            )
        );
        return keccak256(bytes.concat(inner));
    }

    function _registerRouterAndAirdrop(ProjectRouterV2 router) internal returns (bytes32) {
        ProjectRegistryV2.ProjectRegistration memory registration = _multisigRegistration();
        registration.router = address(router);
        registration.airdrop = address(airdropSink);
        registration.enabledModules = ProjectModuleBits.ROUTER | ProjectModuleBits.AIRDROP;
        return _register(registration, "");
    }
}
import { ProjectRegistryV2 } from "../src/core/ProjectRegistryV2.sol";
