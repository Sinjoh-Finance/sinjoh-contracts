// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { ProjectLiquidityManagerV2 } from "../../src/liquidity/ProjectLiquidityManagerV2.sol";
import { ProjectRegistryV2 } from "../../src/core/ProjectRegistryV2.sol";
import { ProjectModuleBits } from "../../src/libraries/ProjectModuleBits.sol";
import { ProjectRouterV2 } from "../../src/router/ProjectRouterV2.sol";
import { RouterAction, RouterActionType } from "../../src/router/RouterTypes.sol";
import { MockRouterSink } from "../mocks/MockRouterIntegrations.sol";
import { MockPriceGuard } from "../mocks/liquidity/MockPriceGuard.sol";
import { MockSwapAdapter } from "../mocks/liquidity/MockSwapAdapter.sol";
import {
    MockPermit2,
    MockV3Factory,
    MockV3Pool,
    MockV3PositionManager,
    MockV4PositionManager,
    MockV4StateView
} from "../mocks/liquidity/MockUniswap.sol";
import { RouterTestBase } from "../RouterTestBase.sol";

contract ProjectRouterLiquidityManagerV2IntegrationTest is RouterTestBase {
    ProjectLiquidityManagerV2 private manager;
    MockSwapAdapter private liquidityAdapter;
    MockPriceGuard private liquidityGuard;
    MockV3PositionManager private v3PositionManager;

    function setUp() public {
        _setUpRouterDependencies();
        MockV3Pool pool = new MockV3Pool();
        MockV3Factory factory = new MockV3Factory();
        factory.setPool(address(pool));
        v3PositionManager = new MockV3PositionManager();
        MockPermit2 permit2 = new MockPermit2();
        MockV4PositionManager v4PositionManager = new MockV4PositionManager(permit2);
        MockV4StateView stateView = new MockV4StateView();
        liquidityAdapter = new MockSwapAdapter();
        liquidityGuard = new MockPriceGuard();
        bytes32 approvalRoot = _liquidityApprovalLeaf();
        manager = new ProjectLiquidityManagerV2(
            address(registry),
            address(token),
            address(factory),
            address(v3PositionManager),
            address(v4PositionManager),
            address(stateView),
            address(permit2),
            FEE_RECIPIENT,
            approvalRoot
        );
        liquiditySink = MockRouterSink(payable(address(manager)));
        vm.prank(HOLDER);
        assertTrue(token.transfer(address(liquidityAdapter), 1_000_000));
    }

    function testRouterFundsAndKeeperMintsOnePermanentProjectPosition() public {
        bytes memory config = abi.encode(
            ProjectLiquidityManagerV2.FundingConfig({
                config: _config(), integrationApprovalProof: new bytes32[](0)
            })
        );
        RouterAction memory action = RouterAction({
            actionType: RouterActionType.ADD_LIQUIDITY,
            allocationBps: 10_000,
            recipient: address(manager),
            adapter: address(0),
            priceGuard: address(0),
            actionConfig: config
        });
        ProjectRouterV2 router = _deployRouter(_singleRoute(address(assetA), action), bytes32(0));

        _fund(router, address(assetA), 10_000);
        _execute(router, address(assetA), type(uint256).max);

        bytes32 account = manager.accountId(address(router), address(token));
        (uint256 pendingQuote, uint256 pendingSubject, uint256 positionId,, bool configured) =
            manager.accountFinancials(account);
        assertTrue(configured);
        assertEq(pendingQuote, 9_900);
        assertEq(pendingSubject, 0);
        assertEq(positionId, 0);
        assertEq(assetA.allowance(address(router), address(manager)), 0);

        (uint256 mintedPosition, uint128 liquidity) =
            manager.mint(address(router), address(token), 9_900, 4_950, "");
        (pendingQuote, pendingSubject, positionId,,) = manager.accountFinancials(account);
        assertEq(positionId, mintedPosition);
        assertGt(liquidity, 0);
        assertGt(pendingQuote + pendingSubject, 0);
        assertEq(v3PositionManager.ownerOf(positionId), address(manager));

        ProjectRegistryV2.ProjectRegistration memory registration = _multisigRegistration();
        registration.enabledModules = ProjectModuleBits.LIQUIDITY;
        registration.liquidityManager = address(manager);
        bytes32 registeredProjectId = _register(registration, "ipfs://liquidity-project");
        assertEq(registeredProjectId, token.projectId());
        assertEq(
            registry.moduleBits(registeredProjectId, address(manager)), ProjectModuleBits.LIQUIDITY
        );
    }

    function _config() private view returns (ProjectLiquidityManagerV2.Config memory config) {
        config = ProjectLiquidityManagerV2.Config({
            venue: ProjectLiquidityManagerV2.Venue.UNISWAP_V3,
            quoteAsset: address(assetA),
            poolFee: 3_000,
            tickSpacing: 60,
            hooks: address(0),
            swapAdapter: address(liquidityAdapter),
            priceGuard: address(liquidityGuard),
            swapRouteData: hex"01",
            quoteSwapBps: 5_000,
            maxMintSlippageBps: 500,
            minNotionalPerMint: 100,
            maxNotionalPerMint: type(uint128).max,
            minMintInterval: 0,
            feeMode: ProjectLiquidityManagerV2.FeeMode.RECYCLE,
            feeRecipient: address(0)
        });
    }

    function _liquidityApprovalLeaf() private view returns (bytes32) {
        bytes32 inner = keccak256(
            abi.encode(
                keccak256("SINJOH_V2_SWAP_INTEGRATION_APPROVAL"),
                block.chainid,
                address(liquidityAdapter),
                address(liquidityAdapter).codehash,
                address(liquidityGuard),
                address(liquidityGuard).codehash
            )
        );
        return keccak256(bytes.concat(inner));
    }
}
