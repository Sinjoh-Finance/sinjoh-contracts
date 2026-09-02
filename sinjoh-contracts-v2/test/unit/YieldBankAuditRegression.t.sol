// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { YieldBankNFT } from "../../src/yield-banks/YieldBankNFT.sol";
import {
    CollectionPortfolioAllocator
} from "../../src/yield-banks/CollectionPortfolioAllocator.sol";
import { PriceHub } from "../../src/yield-banks/PriceHub.sol";
import { StrategyRegistry } from "../../src/yield-banks/StrategyRegistry.sol";
import { BaseSleeve } from "../../src/yield-banks/sleeves/BaseSleeve.sol";
import { CoreStockTokenSleeve } from "../../src/yield-banks/sleeves/CoreStockTokenSleeve.sol";
import { USDGSleeve } from "../../src/yield-banks/sleeves/USDGSleeve.sol";
import { IPriceHub } from "../../src/yield-banks/interfaces/IPriceHub.sol";
import {
    ISeaDropTokenContractMetadata
} from "../../src/yield-banks/interfaces/INonFungibleSeaDropToken.sol";
import { YieldBankCollectionState } from "../../src/yield-banks/YieldBankTypes.sol";
import {
    MockYieldBankAggregator,
    MockYieldBankAllocationRoute,
    MockYieldBankAsset,
    MockYieldBankCollectionPointer,
    MockYieldBankEligibilityPolicy,
    MockYieldBankCollectionMetadata,
    MockYieldBankRevenueRouter,
    MockYieldBankSeaDrop,
    MockYieldBankSleeve
} from "../mocks/MockYieldBankIntegrations.sol";

contract YieldBankOpenSeaConfigurationRegressionTest is Test {
    address private constant OTHER_RECEIVER = address(0xBEEF);

    MockYieldBankSeaDrop private seaDrop;
    MockYieldBankRevenueRouter private revenueRouter;
    YieldBankNFT private nft;

    function setUp() external {
        seaDrop = new MockYieldBankSeaDrop();
        revenueRouter = new MockYieldBankRevenueRouter(7_500, 1_200, 1_300);
        nft = new YieldBankNFT(
            address(this),
            address(this),
            address(revenueRouter),
            address(new MockYieldBankCollectionMetadata()),
            address(seaDrop),
            100,
            650
        );
    }

    function testRoyaltyReceiverAndRateCannotBeRedirected() external {
        ISeaDropTokenContractMetadata.SeaDropRoyaltyInfo memory changedRate =
            ISeaDropTokenContractMetadata.SeaDropRoyaltyInfo({
                royaltyAddress: address(revenueRouter), royaltyBps: 600
            });
        vm.expectRevert(
            abi.encodeWithSelector(
                YieldBankNFT.ImmutableRoyaltyInfo.selector, address(revenueRouter), uint96(600)
            )
        );
        nft.setRoyaltyInfo(changedRate);

        ISeaDropTokenContractMetadata.SeaDropRoyaltyInfo memory changedReceiver =
            ISeaDropTokenContractMetadata.SeaDropRoyaltyInfo({
                royaltyAddress: OTHER_RECEIVER, royaltyBps: nft.royaltyBps()
            });
        vm.expectRevert(
            abi.encodeWithSelector(
                YieldBankNFT.ImmutableRoyaltyInfo.selector, OTHER_RECEIVER, uint96(nft.royaltyBps())
            )
        );
        nft.setRoyaltyInfo(changedReceiver);
    }
}

contract YieldBankInvestmentPauseRegressionTest is Test {
    MockYieldBankAsset private input;
    MockYieldBankCollectionPointer private collection;
    MockYieldBankSleeve private core;
    MockYieldBankSleeve private market;
    MockYieldBankSleeve private usdg;
    CollectionPortfolioAllocator private allocator;

    function setUp() external {
        input = new MockYieldBankAsset("Wrapped Ether", "WETH");
        collection = new MockYieldBankCollectionPointer();
        core = new MockYieldBankSleeve(address(input), "CORE");
        market = new MockYieldBankSleeve(address(input), "MARKET");
        usdg = new MockYieldBankSleeve(address(input), "USDG");
        allocator = new CollectionPortfolioAllocator(
            address(collection),
            address(this),
            address(this),
            address(this),
            address(collection),
            address(core),
            address(market),
            address(usdg),
            4_000,
            3_750,
            2_250
        );
        collection.setProceedsVault(address(this));
        collection.setState(YieldBankCollectionState.INVESTMENT_PAUSED);
        input.mint(address(this), 1_000 ether);
        input.approve(address(allocator), type(uint256).max);
    }

    function testPauseBlocksEveryNewAllocationAndStrategyEntryPath() external {
        CollectionPortfolioAllocator.AllocationCall[3] memory calls;
        vm.expectRevert(
            abi.encodeWithSelector(
                CollectionPortfolioAllocator.InvestmentUnavailable.selector,
                YieldBankCollectionState.INVESTMENT_PAUSED
            )
        );
        allocator.allocatePrimary(address(input), 1_000 ether, address(this), calls);

        vm.expectRevert(
            abi.encodeWithSelector(
                CollectionPortfolioAllocator.InvestmentUnavailable.selector,
                YieldBankCollectionState.INVESTMENT_PAUSED
            )
        );
        allocator.allocate(address(input), 1_000 ether, abi.encode(calls));

        vm.expectRevert(
            abi.encodeWithSelector(
                CollectionPortfolioAllocator.InvestmentUnavailable.selector,
                YieldBankCollectionState.INVESTMENT_PAUSED
            )
        );
        allocator.depositToAdapter(address(market), address(0xADA7), 1 ether, 1 ether, "");

        vm.expectRevert(
            abi.encodeWithSelector(
                CollectionPortfolioAllocator.InvestmentUnavailable.selector,
                YieldBankCollectionState.INVESTMENT_PAUSED
            )
        );
        allocator.collectAdapter(address(market), address(0xADA7), "");
    }

    function testPauseStillAllowsRiskReducingWithdrawalsAndExits() external {
        assertEq(
            allocator.withdrawFromAdapter(address(market), address(0xADA7), 1 ether, 0, ""), 1 ether
        );
        allocator.exitAdapter(address(market), address(0xADA7), 0, "");
    }

    function allocationOperator() external view returns (address) {
        return address(this);
    }
}

contract YieldBankSleevePricingRegressionTest is Test {
    MockYieldBankAsset private accounting;
    MockYieldBankAsset private reward;
    MockYieldBankAggregator private accountingFeed;
    MockYieldBankAggregator private rewardFeed;
    PriceHub private priceHub;
    StrategyRegistry private registry;
    MockYieldBankEligibilityPolicy private eligibility;
    USDGSleeve private sleeve;

    function setUp() external {
        accounting = new MockYieldBankAsset("USDG", "USDG");
        reward = new MockYieldBankAsset("Reward", "RWD");
        accountingFeed = new MockYieldBankAggregator(8, 1e8);
        rewardFeed = new MockYieldBankAggregator(8, 2e8);
        priceHub = new PriceHub(address(this), address(this));
        priceHub.configureFeed(
            address(accounting), address(accountingFeed), address(0), 1 days, 0, false, 100
        );
        priceHub.configureFeed(
            address(reward), address(rewardFeed), address(0), 1 days, 0, false, 100
        );
        registry = new StrategyRegistry(address(this));
        eligibility = new MockYieldBankEligibilityPolicy();
        sleeve = new USDGSleeve(
            "Test USDG Sleeve",
            "T-USDG",
            address(accounting),
            address(this),
            address(this),
            address(this),
            address(priceHub),
            address(registry),
            address(eligibility),
            0,
            0,
            100
        );
        sleeve.addInventoryAsset(address(reward));
        accounting.mint(address(this), 2_000 ether);
        accounting.approve(address(sleeve), type(uint256).max);
        sleeve.deposit(1_000 ether, address(this), 1, "");
        reward.mint(address(sleeve), 100 ether);
    }

    function testDepositFailsInsteadOfUsingZeroNavWhenHeldAssetPriceIsStale() external {
        vm.warp(block.timestamp + 2 days);
        accountingFeed.setAnswer(1e8, block.timestamp);

        vm.expectRevert(
            abi.encodeWithSelector(
                BaseSleeve.OracleUnavailable.selector,
                address(reward),
                IPriceHub.FailureReason.STALE_FEED
            )
        );
        sleeve.deposit(1_000 ether, address(this), 1, "");
    }
}

contract YieldBankCoreSlippageRegressionTest is Test {
    function testEachCoreConstituentRequiresANonzeroOutputFloor() external {
        MockYieldBankAsset weth = new MockYieldBankAsset("Wrapped Ether", "WETH");
        MockYieldBankAsset stock = new MockYieldBankAsset("Stock Token", "STOCK");
        MockYieldBankAggregator wethFeed = new MockYieldBankAggregator(8, 2_000e8);
        MockYieldBankAggregator stockFeed = new MockYieldBankAggregator(8, 100e8);
        PriceHub hub = new PriceHub(address(this), address(this));
        hub.configureFeed(address(weth), address(wethFeed), address(0), 1 days, 0, false, 100);
        hub.configureFeed(address(stock), address(stockFeed), address(0), 1 days, 0, false, 100);
        CoreStockTokenSleeve sleeve = new CoreStockTokenSleeve(
            "Test Stock Token Sleeve",
            "T-STOCK",
            address(weth),
            address(this),
            address(this),
            address(this),
            address(hub),
            address(new StrategyRegistry(address(this))),
            address(new MockYieldBankEligibilityPolicy()),
            0,
            0,
            100
        );
        MockYieldBankAllocationRoute route =
            new MockYieldBankAllocationRoute(address(weth), address(stock));
        sleeve.addConstituent(address(stock), address(route), address(route).codehash, 10_000);
        CoreStockTokenSleeve.ConstituentCall[] memory calls =
            new CoreStockTokenSleeve.ConstituentCall[](1);
        calls[0] = CoreStockTokenSleeve.ConstituentCall({ minimumOutput: 0, routeData: "" });
        weth.mint(address(this), 1 ether);
        weth.approve(address(sleeve), 1 ether);

        vm.expectRevert(BaseSleeve.InvalidConfiguration.selector);
        sleeve.deposit(1 ether, address(this), 1, abi.encode(calls));
    }
}
