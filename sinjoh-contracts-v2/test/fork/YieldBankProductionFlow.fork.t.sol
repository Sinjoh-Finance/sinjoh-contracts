// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { CreationCodeStoreV2 } from "../../src/core/CreationCodeStoreV2.sol";
import {
    CollectionPortfolioAllocator
} from "../../src/yield-banks/CollectionPortfolioAllocator.sol";
import { CollectionRevenueRouter } from "../../src/yield-banks/CollectionRevenueRouter.sol";
import { CollectionTimelock } from "../../src/yield-banks/CollectionTimelock.sol";
import { DeltaPoolController } from "../../src/yield-banks/DeltaPoolController.sol";
import { PriceHub } from "../../src/yield-banks/PriceHub.sol";
import { YieldBankAccount } from "../../src/yield-banks/YieldBankAccount.sol";
import { YieldBankCollection } from "../../src/yield-banks/YieldBankCollection.sol";
import { YieldBankNFT } from "../../src/yield-banks/YieldBankNFT.sol";
import { YieldBankProtocolRegistry } from "../../src/yield-banks/YieldBankProtocolRegistry.sol";
import { YieldBankPublicFactory } from "../../src/yield-banks/YieldBankPublicFactory.sol";
import { YieldBankSupportBundle } from "../../src/yield-banks/YieldBankSupportBundle.sol";
import {
    YieldBankFeeWeightRange,
    YieldBankRedemptionMode
} from "../../src/yield-banks/YieldBankTypes.sol";
import { YieldBankProceedsVault } from "../../src/yield-banks/YieldBankProceedsVault.sol";
import { CoreStockTokenSleeve } from "../../src/yield-banks/sleeves/CoreStockTokenSleeve.sol";
import { MarketMakingSleeve } from "../../src/yield-banks/sleeves/MarketMakingSleeve.sol";
import { USDGSleeve } from "../../src/yield-banks/sleeves/USDGSleeve.sol";
import { PublicDrop } from "../../src/yield-banks/interfaces/SeaDropStructs.sol";
import { YieldBankIds } from "../../src/yield-banks/libraries/YieldBankIds.sol";
import {
    MockYieldBankAggregator,
    MockYieldBankAsset
} from "../mocks/MockYieldBankIntegrations.sol";

interface ILiveSeaDropMint {
    function mintPublic(
        address nftContract,
        address feeRecipient,
        address minterIfNotPayer,
        uint256 quantity
    ) external payable;
}

contract YieldBankProductionFlowForkTest is Test {
    uint256 private constant CHAIN_ID = 4_663;
    uint16 private constant BPS = 10_000;
    address private constant GOVERNANCE = 0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49;
    address private constant REGISTRY = 0x09e4542f9fEA13A00aAF400E81bDC10434af5278;
    address private constant SUPERSEDED_FACTORY = 0xDEf30346f545f7D27393C0d6878898D13330d6a4;
    address private constant SIDE_WALLET = 0xe4605138e185FBeE40ff6193A044aa0BE2909216;
    address private constant BUYER = 0x0000000000000000000000000000000000000B0b;
    address private constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;
    address private constant USDG = 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168;
    address private constant SEA_DROP = 0x00005EA00Ac477B1030CE78506496e8C2dE24bf5;

    function testProductionFactorySeaDropAllocationTransferAndRedemption() external {
        string memory rpcUrl = vm.envOr("ROBINHOOD_MAINNET_RPC_URL", string(""));
        if (bytes(rpcUrl).length == 0) vm.skip(true);
        vm.createSelectFork(rpcUrl);
        assertEq(block.chainid, CHAIN_ID);

        YieldBankProtocolRegistry registry = YieldBankProtocolRegistry(REGISTRY);
        YieldBankPublicFactory factory = new YieldBankPublicFactory(
            REGISTRY,
            keccak256("SINJOH_YIELD_BANK_PUBLIC_FACTORY_V1_0_2_FORK_PROOF"),
            WETH,
            USDG,
            SEA_DROP,
            _creationCodeStores(),
            _creationCodeHashes()
        );
        bytes32 factoryVersion = factory.factoryVersion();
        vm.prank(GOVERNANCE);
        registry.registerFactory(address(factory), factoryVersion, address(factory).codehash);
        vm.prank(GOVERNANCE);
        registry.deprecateFactory(SUPERSEDED_FACTORY);
        assertTrue(registry.isFactoryAvailableForNewCollections(address(factory)));
        assertFalse(registry.isFactoryAvailableForNewCollections(SUPERSEDED_FACTORY));

        vm.prank(SIDE_WALLET);
        YieldBankPublicFactory.SystemAddresses memory system =
            factory.createCollection(_request(), keccak256("A-1"));
        YieldBankCollection collection = YieldBankCollection(system.collection);
        YieldBankNFT nft = collection.nft();
        YieldBankProceedsVault vault = collection.proceedsVault();
        assertTrue(registry.isActiveCollection(address(collection)));
        assertEq(nft.name(), "A");
        assertEq(nft.symbol(), "A");
        assertEq(nft.maxSupply(), 3);

        MockYieldBankAggregator wethFeed = new MockYieldBankAggregator(8, 3_000e8);
        PriceHub priceHub = YieldBankSupportBundle(system.supportBundle).priceHub();
        vm.prank(system.collectionTimelock);
        priceHub.configureFeed(WETH, address(wethFeed), address(0), 1 days, 0, false, 100);

        PublicDrop memory stage = PublicDrop({
            mintPrice: 0.01 ether,
            startTime: 1,
            endTime: type(uint48).max,
            maxTotalMintableByWallet: 3,
            feeBps: 500,
            restrictFeeRecipients: false
        });
        vm.startPrank(SIDE_WALLET);
        nft.updateCreatorPayoutAddress(SEA_DROP, address(vault));
        nft.updatePublicDrop(SEA_DROP, stage);
        nft.setBaseURI("ipfs://a/");
        vm.stopPrank();

        vm.deal(BUYER, 1 ether);
        uint256 buyerNativeBefore = BUYER.balance;
        vm.prank(BUYER);
        ILiveSeaDropMint(SEA_DROP).mintPublic{ value: 0.01 ether }(
            address(nft), BUYER, address(0), 1
        );
        assertEq(nft.ownerOf(1), BUYER);
        assertEq(nft.tokenURI(1), "ipfs://a/1");
        assertEq(vault.pendingBackingOf(1), 0.0095 ether);
        assertEq(BUYER.balance, buyerNativeBefore - 0.0095 ether);

        CollectionPortfolioAllocator.AllocationCall[3] memory allocations;
        allocations[1].minimumOutput = 0.0095 ether;
        allocations[1].minimumShares = 1;
        vm.prank(SIDE_WALLET);
        vault.allocateReceipts(1, 1, allocations);
        address account = collection.accountOf(1);
        assertGt(IERC20(system.marketMakingSleeve).balanceOf(account), 0);

        MockYieldBankAsset collectionToken = new MockYieldBankAsset("Collection Token", "TOKEN");
        collectionToken.mint(SIDE_WALLET, 1_000e18);
        vm.prank(SIDE_WALLET);
        assertTrue(collectionToken.transfer(account, 1_000e18));
        assertEq(collectionToken.balanceOf(account), 1_000e18);

        uint16[3] memory targetWeights = [uint16(0), uint16(BPS), uint16(0)];
        vm.prank(BUYER);
        uint64 targetRevision = CollectionPortfolioAllocator(system.portfolioAllocator)
            .setTargetAllocation(
                1, targetWeights, address(0), 100, uint48(block.timestamp + 1 hours)
            );
        CollectionPortfolioAllocator.RebalanceExecution memory rebalance;
        rebalance.redemptions[1].minimumOutputs = new uint256[](1);
        rebalance.redemptions[1].minimumOutputs[0] = 0.0095 ether;
        rebalance.allocations[1].minimumOutput = 0.0095 ether;
        rebalance.allocations[1].minimumShares = 1;
        rebalance.minimumWethRecovered = 0.0095 ether;
        rebalance.deadline = block.timestamp + 1 hours;
        vm.prank(SIDE_WALLET);
        CollectionPortfolioAllocator(system.portfolioAllocator)
            .executeTargetAllocation(1, targetRevision, rebalance);

        vm.prank(BUYER);
        nft.transferFrom(BUYER, SIDE_WALLET, 1);
        assertEq(nft.ownerOf(1), SIDE_WALLET);

        uint256 wethBefore = IERC20(WETH).balanceOf(SIDE_WALLET);
        address[] memory additionalAssets = new address[](1);
        additionalAssets[0] = address(collectionToken);
        vm.prank(SIDE_WALLET);
        collection.burnTokenWithAssets(1, "", additionalAssets);
        assertEq(collectionToken.balanceOf(SIDE_WALLET), 1_000e18);
        uint256 sleeveShares = IERC20(system.marketMakingSleeve).balanceOf(SIDE_WALLET);
        uint256[] memory minimumOutputs = new uint256[](1);
        minimumOutputs[0] = 0.0095 ether;
        vm.prank(SIDE_WALLET);
        MarketMakingSleeve(system.marketMakingSleeve)
            .redeem(
                sleeveShares,
                SIDE_WALLET,
                SIDE_WALLET,
                YieldBankRedemptionMode.IN_KIND,
                minimumOutputs,
                ""
            );
        assertGt(IERC20(WETH).balanceOf(SIDE_WALLET), wethBefore);
        assertEq(collection.liveSupply(), 0);
        (bool ownerCallOk,) =
            address(nft).staticcall(abi.encodeWithSignature("ownerOf(uint256)", 1));
        assertFalse(ownerCallOk);
    }

    function _request()
        private
        pure
        returns (YieldBankPublicFactory.CollectionRequest memory request)
    {
        request.name = "A";
        request.symbol = "A";
        request.maxSupply = 3;
        request.feeWeightRanges = new YieldBankFeeWeightRange[](0);
        request.secondaryRoyaltyBps = 500;
        request.primaryBackingBps = BPS;
        request.royaltyBackingBps = BPS;
        request.marketMakingWeightBps = BPS;
        request.creator = SIDE_WALLET;
        request.openSeaManager = SIDE_WALLET;
        request.sinjohFeeRecipient = SIDE_WALLET;
        request.allocationOperator = SIDE_WALLET;
        request.timelockProposer = SIDE_WALLET;
        request.guardian = SIDE_WALLET;
        request.coreSleeve = YieldBankPublicFactory.SleeveConfig({
            maximumStrategies: 0, maximumAdapterCapBps: 0, maximumOperatorLossBps: 0
        });
        request.marketMakingSleeve = YieldBankPublicFactory.SleeveConfig({
            maximumStrategies: 8, maximumAdapterCapBps: BPS, maximumOperatorLossBps: 1_000
        });
        request.usdgSleeve = YieldBankPublicFactory.SleeveConfig({
            maximumStrategies: 0, maximumAdapterCapBps: 0, maximumOperatorLossBps: 0
        });
        request.deltaRisk = YieldBankPublicFactory.DeltaRiskConfig({
            maximumAdapterCapBps: BPS,
            maximumOperatorLossBps: 1_000,
            maximumPoolFeedHeartbeat: 1 days,
            maximumPoolFeedGracePeriod: 1 days,
            minimumPoolTwapWindow: 5 minutes,
            maximumPoolReferenceDeviationBps: 1_000,
            maximumPoolSpotDeviationBps: 1_000
        });
    }

    function _creationCodeStores()
        private
        returns (YieldBankPublicFactory.CreationCodeStores memory stores)
    {
        stores = YieldBankPublicFactory.CreationCodeStores({
            supportBundle: address(
                new CreationCodeStoreV2(type(YieldBankSupportBundle).creationCode)
            ),
            revenueRouter: address(
                new CreationCodeStoreV2(type(CollectionRevenueRouter).creationCode)
            ),
            portfolioAllocator: address(
                new CreationCodeStoreV2(type(CollectionPortfolioAllocator).creationCode)
            ),
            collectionTimelock: address(
                new CreationCodeStoreV2(type(CollectionTimelock).creationCode)
            ),
            coreSleeve: address(new CreationCodeStoreV2(type(CoreStockTokenSleeve).creationCode)),
            marketMakingSleeve: address(
                new CreationCodeStoreV2(type(MarketMakingSleeve).creationCode)
            ),
            usdgSleeve: address(new CreationCodeStoreV2(type(USDGSleeve).creationCode)),
            accountImplementation: address(
                new CreationCodeStoreV2(type(YieldBankAccount).creationCode)
            ),
            deltaPoolController: address(
                new CreationCodeStoreV2(type(DeltaPoolController).creationCode)
            ),
            collection: address(new CreationCodeStoreV2(type(YieldBankCollection).creationCode))
        });
    }

    function _creationCodeHashes()
        private
        pure
        returns (YieldBankPublicFactory.CreationCodeHashes memory hashes)
    {
        hashes = YieldBankPublicFactory.CreationCodeHashes({
            supportBundle: keccak256(type(YieldBankSupportBundle).creationCode),
            revenueRouter: keccak256(type(CollectionRevenueRouter).creationCode),
            portfolioAllocator: keccak256(type(CollectionPortfolioAllocator).creationCode),
            collectionTimelock: keccak256(type(CollectionTimelock).creationCode),
            coreSleeve: keccak256(type(CoreStockTokenSleeve).creationCode),
            marketMakingSleeve: keccak256(type(MarketMakingSleeve).creationCode),
            usdgSleeve: keccak256(type(USDGSleeve).creationCode),
            accountImplementation: keccak256(type(YieldBankAccount).creationCode),
            deltaPoolController: keccak256(type(DeltaPoolController).creationCode),
            collection: keccak256(type(YieldBankCollection).creationCode)
        });
    }
}
