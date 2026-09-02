// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { StdInvariant } from "forge-std/StdInvariant.sol";
import { Test } from "forge-std/Test.sol";
import { YieldBankCollection } from "../../src/yield-banks/YieldBankCollection.sol";
import { YieldBankAccount } from "../../src/yield-banks/YieldBankAccount.sol";
import { YieldBankNFT } from "../../src/yield-banks/YieldBankNFT.sol";
import { YieldBankProceedsVault } from "../../src/yield-banks/YieldBankProceedsVault.sol";
import {
    CollectionPortfolioAllocator
} from "../../src/yield-banks/CollectionPortfolioAllocator.sol";
import {
    YieldBankConfig,
    YieldBankFeeWeightRange,
    YieldBankTokenState
} from "../../src/yield-banks/YieldBankTypes.sol";
import {
    MockYieldBankAsset,
    MockYieldBankEligibilityPolicy,
    MockYieldBankPrimaryAllocator,
    MockYieldBankCollectionMetadata,
    MockYieldBankRevenueRouter,
    MockYieldBankSeaDrop,
    MockYieldBankTimelock,
    MockYieldBankWETH
} from "../mocks/MockYieldBankIntegrations.sol";

contract YieldBankInvariantHandler is Test {
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant OPERATOR = address(0x0A110C);

    YieldBankCollection public immutable collection;
    YieldBankNFT public immutable nft;
    YieldBankProceedsVault public immutable vault;
    MockYieldBankSeaDrop public immutable seaDrop;
    MockYieldBankAsset public immutable distributionAsset;

    constructor(
        YieldBankCollection collection_,
        MockYieldBankSeaDrop seaDrop_,
        MockYieldBankAsset distributionAsset_
    ) {
        collection = collection_;
        nft = collection_.nft();
        vault = collection_.proceedsVault();
        seaDrop = seaDrop_;
        distributionAsset = distributionAsset_;
    }

    function mint(uint256 rawQuantity, uint96 rawValue) external {
        uint256 remaining = collection.maxSupply() - collection.mintedSupply();
        if (remaining == 0) return;
        uint256 maximum = remaining < 4 ? remaining : 4;
        uint256 quantity = bound(rawQuantity, 1, maximum);
        uint256 value = bound(uint256(rawValue), 1, 10 ether);
        vm.deal(address(this), value);
        seaDrop.mint{ value: value }(nft, ALICE, quantity);
    }

    function allocate(uint256 rawReceiptId) external {
        uint256 count = vault.receiptCount();
        if (count == 0) return;
        uint256 receiptId = bound(rawReceiptId, 1, count);
        (,,,,,, bool allocated) = vault.receipts(receiptId);
        if (allocated) return;
        CollectionPortfolioAllocator.AllocationCall[3] memory calls;
        vm.prank(OPERATOR);
        vault.allocateReceipts(receiptId, receiptId, calls);
    }

    function distribute(uint96 rawAmount) external {
        uint256 supply = collection.liveSupply();
        if (supply == 0) return;
        uint256 amount = bound(uint256(rawAmount), 1, 100 ether);
        address source = collection.revenueRouter();
        distributionAsset.mint(source, amount);
        vm.startPrank(source);
        distributionAsset.approve(address(collection.distributor()), amount);
        collection.accrueDistribution(address(distributionAsset), amount);
        vm.stopPrank();
    }

    function deliverRevenue(uint256 rawTokenId) external {
        uint256 minted = collection.mintedSupply();
        if (minted == 0) return;
        uint256 tokenId = bound(rawTokenId, 1, minted);
        if (collection.tokenState(tokenId) != uint8(YieldBankTokenState.ACTIVE)) return;
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;
        vm.prank(collection.revenueRouter());
        collection.deliverRevenueBatch(tokenIds);
    }

    function transfer(uint256 rawTokenId, bool toBob) external {
        uint256 minted = collection.mintedSupply();
        if (minted == 0) return;
        uint256 tokenId = bound(rawTokenId, 1, minted);
        if (collection.tokenState(tokenId) != uint8(YieldBankTokenState.ACTIVE)) return;
        address owner = nft.ownerOf(tokenId);
        address recipient = toBob ? BOB : ALICE;
        if (owner == recipient) recipient = owner == ALICE ? BOB : ALICE;
        vm.prank(owner);
        nft.transferFrom(owner, recipient, tokenId);
    }

    function burn(uint256 rawTokenId) external {
        uint256 minted = collection.mintedSupply();
        if (minted == 0) return;
        uint256 tokenId = bound(rawTokenId, 1, minted);
        if (collection.tokenState(tokenId) != uint8(YieldBankTokenState.ACTIVE)) return;
        address owner = nft.ownerOf(tokenId);
        vm.prank(owner);
        collection.burnToken(tokenId, "");
    }
}

contract YieldBankCollectionInvariantTest is StdInvariant, Test {
    uint256 private constant MAX_SUPPLY = 12;
    address private constant CREATOR = address(0xC0FFEE);
    address private constant SINJOH = address(0x51A70A);
    address private constant OPERATOR = address(0x0A110C);
    address private constant GUARDIAN = address(0x6A4D1A);
    uint16 private constant PRIMARY_BACKING_BPS = 7_500;
    uint16 private constant PRIMARY_CREATOR_BPS = 1_200;
    uint16 private constant PRIMARY_SINJOH_BPS = 1_300;
    uint16 private constant CORE_WEIGHT_BPS = 4_000;
    uint16 private constant MARKET_MAKING_WEIGHT_BPS = 3_750;
    uint16 private constant USDG_WEIGHT_BPS = 2_250;

    MockYieldBankWETH private weth;
    MockYieldBankAsset private core;
    MockYieldBankAsset private market;
    MockYieldBankAsset private yieldSleeve;
    MockYieldBankAsset private distributionAsset;
    MockYieldBankEligibilityPolicy private policy;
    MockYieldBankCollectionMetadata private metadata;
    MockYieldBankRevenueRouter private revenueRouter;
    MockYieldBankTimelock private timelock;
    MockYieldBankSeaDrop private seaDrop;
    MockYieldBankPrimaryAllocator private allocator;
    YieldBankCollection private collection;
    YieldBankProceedsVault private vault;
    YieldBankAccount private accountImplementation;

    function setUp() public {
        weth = new MockYieldBankWETH();
        core = new MockYieldBankAsset("Core", "CORE");
        market = new MockYieldBankAsset("Market", "MM");
        yieldSleeve = new MockYieldBankAsset("USDG", "YLD");
        policy = new MockYieldBankEligibilityPolicy();
        metadata = new MockYieldBankCollectionMetadata();
        revenueRouter = new MockYieldBankRevenueRouter(
            PRIMARY_BACKING_BPS, PRIMARY_CREATOR_BPS, PRIMARY_SINJOH_BPS
        );
        timelock = new MockYieldBankTimelock();
        seaDrop = new MockYieldBankSeaDrop();
        address[3] memory sleeves = [address(core), address(market), address(yieldSleeve)];
        allocator = new MockYieldBankPrimaryAllocator(
            sleeves, CORE_WEIGHT_BPS, MARKET_MAKING_WEIGHT_BPS, USDG_WEIGHT_BPS
        );
        accountImplementation = new YieldBankAccount();
        collection = new YieldBankCollection(_config());
        vault = collection.proceedsVault();
        distributionAsset = new MockYieldBankAsset("Distribution", "DIST");
        YieldBankInvariantHandler handler =
            new YieldBankInvariantHandler(collection, seaDrop, distributionAsset);
        targetContract(address(handler));
    }

    function invariantNativeAndWrappedProceedsConserveEveryWei() public view {
        assertEq(address(vault).balance, vault.accountedNative());
        assertEq(
            weth.totalSupply() + vault.accountedNative() + CREATOR.balance + SINJOH.balance,
            vault.totalNetProceeds()
        );
    }

    function invariantReceiptLiabilitiesReconcileExactly() public view {
        uint256 pendingBacking;
        uint256 unallocatedNative;
        uint256 netProceeds;
        for (uint256 receiptId = 1; receiptId <= vault.receiptCount(); ++receiptId) {
            (
                ,,
                uint256 net,
                uint256 backingRemaining,
                uint256 creatorFee,
                uint256 sinjohFee,
                bool allocated
            ) = vault.receipts(receiptId);
            netProceeds += net;
            if (allocated) {
                assertEq(backingRemaining, 0);
            } else {
                pendingBacking += backingRemaining;
                unallocatedNative += backingRemaining + creatorFee + sinjohFee;
            }
        }
        assertEq(pendingBacking, vault.totalPendingBacking());
        assertEq(unallocatedNative, vault.accountedNative());
        assertEq(netProceeds, vault.totalNetProceeds());
    }

    function invariantTokenLifecycleAndSupplyAreOneWay() public view {
        uint256 active;
        uint256 activeFeeWeight;
        uint256 pendingBacking;
        for (uint256 tokenId = 1; tokenId <= collection.mintedSupply(); ++tokenId) {
            uint8 tokenState = collection.tokenState(tokenId);
            uint8 primaryState = vault.primaryStateOf(tokenId);
            if (tokenState == uint8(YieldBankTokenState.ACTIVE)) {
                active += 1;
                activeFeeWeight += collection.distributor().feeWeightOf(tokenId);
                collection.nft().ownerOf(tokenId);
                assertTrue(
                    primaryState == vault.PRIMARY_PENDING()
                        || primaryState == vault.PRIMARY_ALLOCATED()
                );
            } else {
                assertEq(tokenState, uint8(YieldBankTokenState.BURNED));
                assertTrue(
                    primaryState == vault.PRIMARY_RELEASED()
                        || primaryState == vault.PRIMARY_ALLOCATED()
                );
            }
            if (primaryState == vault.PRIMARY_PENDING()) {
                pendingBacking += vault.pendingBackingOf(tokenId);
            } else {
                assertEq(vault.pendingBackingOf(tokenId), 0);
            }
        }
        assertEq(active, collection.liveSupply());
        assertEq(activeFeeWeight, collection.totalLiveFeeWeight());
        assertLe(collection.liveSupply(), collection.mintedSupply());
        assertLe(collection.mintedSupply(), collection.maxSupply());
        assertEq(pendingBacking, vault.totalPendingBacking());
    }

    function invariantAllocatedSleeveSharesEqualAllocatedBacking() public view {
        assertEq(
            core.totalSupply() + market.totalSupply() + yieldSleeve.totalSupply(),
            vault.totalAllocatedBacking()
        );
    }

    function invariantEveryDistributionAssetIsSolventAndConserved() public view {
        address[] memory assets = collection.distributor().distributionAssets();
        for (uint256 i; i < assets.length; ++i) {
            address asset = assets[i];
            uint256 accounted = collection.distributor().accountedBalance(asset);
            assertGe(
                MockYieldBankAsset(asset).balanceOf(address(collection.distributor())), accounted
            );
            assertEq(
                collection.distributor().totalReceived(asset),
                collection.distributor().totalDelivered(asset) + accounted
            );
        }
    }

    function _config() private view returns (YieldBankConfig memory c) {
        c = YieldBankConfig({
            collectionId: keccak256("SINJOH_YIELD_BANKS_INVARIANT"),
            maxSupply: MAX_SUPPLY,
            feeWeightRanges: new YieldBankFeeWeightRange[](0),
            secondaryRoyaltyBps: 500,
            primaryBackingBps: PRIMARY_BACKING_BPS,
            primaryCreatorBps: PRIMARY_CREATOR_BPS,
            primarySinjohBps: PRIMARY_SINJOH_BPS,
            royaltyBackingBps: 10_000,
            royaltyCreatorBps: 0,
            royaltySinjohBps: 0,
            exitTaxBps: 500,
            coreWeightBps: CORE_WEIGHT_BPS,
            marketMakingWeightBps: MARKET_MAKING_WEIGHT_BPS,
            usdgWeightBps: USDG_WEIGHT_BPS,
            creator: CREATOR,
            openSeaManager: CREATOR,
            sinjohFeeRecipient: SINJOH,
            redemptionToken: address(0),
            redemptionTokenAmount: 0,
            redemptionTokenCodeHash: bytes32(0),
            revenueRouter: address(revenueRouter),
            eligibilityPolicy: address(policy),
            portfolioAllocator: address(allocator),
            allocationOperator: OPERATOR,
            collectionTimelock: address(timelock),
            guardian: GUARDIAN,
            metadata: address(metadata),
            weth: address(weth),
            seaDrop: address(seaDrop),
            coreSleeve: address(core),
            marketMakingSleeve: address(market),
            usdgSleeve: address(yieldSleeve),
            accountImplementation: address(accountImplementation),
            integrationCodeHashes: [
                address(revenueRouter).codehash,
                address(policy).codehash,
                address(allocator).codehash,
                address(timelock).codehash,
                address(metadata).codehash,
                address(weth).codehash,
                address(seaDrop).codehash,
                address(core).codehash,
                address(market).codehash,
                address(yieldSleeve).codehash
            ]
        });
    }
}
