// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { ProjectLiquidityManagerV2 } from "../../src/liquidity/ProjectLiquidityManagerV2.sol";
import { MockProjectToken } from "../mocks/MockProjectToken.sol";
import { MockRegistry } from "../mocks/MockRegistry.sol";
import { MockERC20 } from "../mocks/liquidity/MockERC20.sol";
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

contract ProjectLiquidityManagerV2FuzzTest is Test {
    MockProjectToken private subject;
    MockERC20 private quote;
    MockPriceGuard private guard;
    MockSwapAdapter private adapter;
    ProjectLiquidityManagerV2 private manager;

    function setUp() public {
        MockRegistry registry = new MockRegistry();
        subject = new MockProjectToken(address(registry), address(this), 0);
        quote = new MockERC20("Quote", "Q");
        guard = new MockPriceGuard();
        adapter = new MockSwapAdapter();
        MockV3Pool pool = new MockV3Pool();
        MockV3Factory factory = new MockV3Factory();
        factory.setPool(address(pool));
        MockV3PositionManager v3PositionManager = new MockV3PositionManager();
        MockPermit2 permit2 = new MockPermit2();
        MockV4PositionManager v4PositionManager = new MockV4PositionManager(permit2);
        manager = new ProjectLiquidityManagerV2(
            address(registry),
            address(subject),
            address(factory),
            address(v3PositionManager),
            address(v4PositionManager),
            address(new MockV4StateView()),
            address(permit2),
            address(0xFEE)
        );
        quote.mint(address(this), type(uint128).max);
        quote.approve(address(manager), type(uint256).max);
        subject.mint(address(adapter), type(uint128).max);
    }

    function testFuzzSplitFundingAlwaysProducesExactAccountCredit(uint96 rawFirst, uint96 rawSecond)
        public
    {
        uint256 first = bound(uint256(rawFirst), 1, 1e24);
        uint256 second = bound(uint256(rawSecond), 1, 1e24);
        ProjectLiquidityManagerV2.Config memory config = _config();
        _fund(first, config);
        _fund(second, config);
        bytes32 id = manager.projectAccountId(address(this));
        assertEq(manager.accountStatus(id).pendingQuote, first + second);
        assertEq(manager.totalLiability(address(quote)), first + second);
        assertEq(quote.balanceOf(address(manager)), first + second);
    }

    function testFuzzInvalidSwapShareCannotCreateAccount(uint16 rawSwapBps) public {
        uint16 swapBps = rawSwapBps;
        if (swapBps >= 4_500 && swapBps <= 5_500) return;
        ProjectLiquidityManagerV2.Config memory config = _config();
        config.quoteSwapBps = swapBps;
        bytes32 projectId = subject.projectId();
        vm.expectRevert(ProjectLiquidityManagerV2.InvalidConfiguration.selector);
        manager.fund(projectId, address(subject), address(quote), 1_000, abi.encode(config));
        assertFalse(manager.accountStatus(manager.projectAccountId(address(this))).configured);
    }

    function testFuzzMintNeverConsumesMoreQuoteThanRequested(uint96 rawNotional) public {
        uint256 notional = bound(uint256(rawNotional), 100, 1e24);
        ProjectLiquidityManagerV2.Config memory config = _config();
        _fund(notional, config);
        guard.setMinimum(notional / 2);
        uint256 managerQuoteBefore = quote.balanceOf(address(manager));
        manager.mint(address(this), address(subject), notional, notional / 2, "");
        uint256 quoteSpent = managerQuoteBefore - quote.balanceOf(address(manager));
        assertLe(quoteSpent, notional);
        assertEq(quote.balanceOf(address(manager)), manager.totalLiability(address(quote)));
        assertEq(subject.balanceOf(address(manager)), manager.totalLiability(address(subject)));
    }

    function _fund(uint256 amount, ProjectLiquidityManagerV2.Config memory config) private {
        manager.fund(
            subject.projectId(), address(subject), address(quote), amount, abi.encode(config)
        );
    }

    function _config() private view returns (ProjectLiquidityManagerV2.Config memory config) {
        config = ProjectLiquidityManagerV2.Config({
            venue: ProjectLiquidityManagerV2.Venue.UNISWAP_V3,
            quoteAsset: address(quote),
            poolFee: 3_000,
            tickSpacing: 60,
            hooks: address(0),
            swapAdapter: address(adapter),
            priceGuard: address(guard),
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
}
