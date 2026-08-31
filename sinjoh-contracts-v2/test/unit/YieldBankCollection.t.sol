// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { YieldBankCollection } from "../../src/yield-banks/YieldBankCollection.sol";
import { YieldBankNFT } from "../../src/yield-banks/YieldBankNFT.sol";
import { YieldBankAccount } from "../../src/yield-banks/YieldBankAccount.sol";
import { YieldBankProceedsVault } from "../../src/yield-banks/YieldBankProceedsVault.sol";
import {
    CollectionPortfolioAllocator
} from "../../src/yield-banks/CollectionPortfolioAllocator.sol";
import {
    AllowListData,
    PublicDrop,
    SignedMintValidationParams,
    TokenGatedDropStage
} from "../../src/yield-banks/interfaces/SeaDropStructs.sol";
import {
    YieldBankCollectionState,
    YieldBankConfig,
    YieldBankTokenState
} from "../../src/yield-banks/YieldBankTypes.sol";
import {
    MockYieldBankAsset,
    MockYieldBankBurnableAsset,
    MockYieldBankEligibilityPolicy,
    MockYieldBankPrimaryAllocator,
    MockYieldBankRenderer,
    MockYieldBankRevenueRouter,
    MockYieldBankSeaDrop,
    MockYieldBankTimelock,
    MockYieldBankWETH
} from "../mocks/MockYieldBankIntegrations.sol";

contract HostileYieldBankReceiver is IERC721Receiver {
    YieldBankCollection private immutable collection;
    bool public burnBlocked;

    constructor(YieldBankCollection collection_) {
        collection = collection_;
    }

    function onERC721Received(address, address, uint256 tokenId, bytes calldata)
        external
        returns (bytes4)
    {
        try collection.burnToken(tokenId, "") { }
        catch (bytes memory reason) {
            burnBlocked = bytes4(reason) == YieldBankCollection.PrimaryPayoutPending.selector;
        }
        return IERC721Receiver.onERC721Received.selector;
    }
}

contract YieldBankCollectionTest is Test {
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
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
    MockYieldBankEligibilityPolicy private policy;
    MockYieldBankRenderer private renderer;
    MockYieldBankRevenueRouter private revenueRouter;
    MockYieldBankTimelock private timelock;
    MockYieldBankSeaDrop private seaDrop;
    MockYieldBankPrimaryAllocator private allocator;
    YieldBankCollection private collection;
    YieldBankAccount private accountImplementation;

    function setUp() public {
        weth = new MockYieldBankWETH();
        core = new MockYieldBankAsset("Core", "CORE");
        market = new MockYieldBankAsset("Market", "MM");
        yieldSleeve = new MockYieldBankAsset("USDG", "YLD");
        policy = new MockYieldBankEligibilityPolicy();
        renderer = new MockYieldBankRenderer();
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
        collection = new YieldBankCollection(_config(7));
        vm.deal(ALICE, 100 ether);
    }

    function testSeaDropMintRecordsActualIdleProceedsWithoutAutomaticSplit() public {
        _mint(ALICE, 2, 1 ether);
        assertEq(collection.maxSupply(), 7);
        assertEq(collection.mintedSupply(), 2);
        assertEq(collection.liveSupply(), 2);
        assertEq(collection.nft().ownerOf(1), ALICE);
        assertEq(collection.nft().ownerOf(2), ALICE);
        assertEq(uint8(collection.state()), uint8(YieldBankCollectionState.ACTIVE));
        assertEq(collection.tokenState(1), uint8(YieldBankTokenState.ACTIVE));
        YieldBankProceedsVault vault = collection.proceedsVault();
        assertEq(address(vault).balance, 1 ether);
        assertEq(vault.accountedNative(), 1 ether);
        assertEq(vault.totalPendingBacking(), 0.75 ether);
        assertEq(vault.primaryBackingBps(), PRIMARY_BACKING_BPS);
        assertEq(collection.coreWeightBps(), CORE_WEIGHT_BPS);
        assertEq(weth.balanceOf(CREATOR), 0);
        assertEq(weth.balanceOf(SINJOH), 0);
        assertTrue(collection.accountOf(1) != address(0));
    }

    function testCollectionRejectsEconomicsThatDoNotMatchBoundComponents() public {
        YieldBankConfig memory config = _config(7);
        config.primaryBackingBps = 7_400;
        config.primaryCreatorBps = 1_300;
        vm.expectRevert(YieldBankCollection.InvalidConfiguration.selector);
        new YieldBankCollection(config);
    }

    function testReceiverCannotRedeemBeforeSeaDropPayoutCompletes() public {
        HostileYieldBankReceiver receiver = new HostileYieldBankReceiver(collection);
        vm.deal(ALICE, 1 ether);
        vm.prank(ALICE);
        seaDrop.mint{ value: 1 ether }(collection.nft(), address(receiver), 1);

        assertTrue(receiver.burnBlocked());
        assertEq(collection.nft().ownerOf(1), address(receiver));
        assertEq(collection.proceedsVault().primaryStateOf(1), 1);
        assertEq(collection.proceedsVault().accountedNative(), 1 ether);
    }

    function testManualAllocationSplitsExactNetAndCreatesExactClaims() public {
        _mint(ALICE, 2, 1 ether);
        CollectionPortfolioAllocator.AllocationCall[3] memory calls;
        YieldBankProceedsVault vault = collection.proceedsVault();
        uint256 creatorBefore = CREATOR.balance;
        uint256 sinjohBefore = SINJOH.balance;
        vm.prank(OPERATOR);
        vault.allocateReceipts(1, 1, calls);
        assertEq(CREATOR.balance - creatorBefore, 0.12 ether);
        assertEq(SINJOH.balance - sinjohBefore, 0.13 ether);
        assertEq(weth.balanceOf(CREATOR), 0);
        assertEq(weth.balanceOf(SINJOH), 0);
        assertEq(collection.proceedsVault().totalAllocatedBacking(), 0.75 ether);
        collection.claimPrimary(1);
        collection.claimPrimary(2);
        assertEq(core.balanceOf(collection.accountOf(1)), 0.15 ether);
        assertEq(core.balanceOf(collection.accountOf(2)), 0.15 ether);
        assertEq(market.balanceOf(collection.accountOf(1)), 0.140625 ether);
        assertEq(yieldSleeve.balanceOf(collection.accountOf(1)), 0.084375 ether);
        assertTrue(YieldBankAccount(collection.accountOf(1)).isTrackedAsset(address(core)));
        vm.expectRevert();
        collection.claimPrimary(1);
    }

    function testPositiveTinyMintWithZeroRoundedBackingCanStillRedeem() public {
        _mint(ALICE, 1, 1 wei);
        YieldBankProceedsVault vault = collection.proceedsVault();
        assertEq(vault.pendingBackingOf(1), 0);
        assertEq(vault.primaryStateOf(1), vault.PRIMARY_PENDING());
        vm.prank(ALICE);
        collection.burnToken(1, "");
        assertEq(vault.primaryStateOf(1), vault.PRIMARY_RELEASED());
        assertEq(collection.tokenState(1), uint8(YieldBankTokenState.BURNED));
    }

    function testBurnRequiresActiveDeltaAllocationToBeRebalancedFirst() public {
        _mint(ALICE, 1, 1 ether);
        address pool = address(0xD311A);
        allocator.setActiveDeltaPool(1, pool);
        vm.prank(ALICE);
        vm.expectRevert(
            abi.encodeWithSelector(
                YieldBankCollection.ActiveDeltaPositionRequiresRebalance.selector, 1, pool
            )
        );
        collection.burnToken(1, "");
        assertEq(collection.nft().ownerOf(1), ALICE);
        assertEq(collection.liveSupply(), 1);
    }

    function testDynamicSleeveDoesNotConsumeDistributorCapacity() public {
        MockYieldBankAsset dynamicSleeve =
            new MockYieldBankAsset("Dynamic Delta Sleeve", "DELTA-SLEEVE");
        address controller = address(0xD311AC01);
        allocator.setDeltaPoolController(controller);
        allocator.setDeltaPoolSleeve(address(dynamicSleeve), true);
        uint256 distributionAssetsBefore = collection.distributor().distributionAssetCount();

        vm.prank(controller);
        collection.registerDynamicSleeve(address(dynamicSleeve));

        assertTrue(collection.isSleeveAsset(address(dynamicSleeve)));
        assertEq(collection.distributor().distributionAssetCount(), distributionAssetsBefore);
    }

    function testPendingYieldBankIsTransferableAndRedeemableBeforeAllocation() public {
        _mint(ALICE, 2, 1 ether);
        YieldBankNFT nft = collection.nft();
        vm.prank(ALICE);
        nft.transferFrom(ALICE, BOB, 1);
        uint256 beforeBalance = weth.balanceOf(BOB);
        vm.prank(BOB);
        collection.burnToken(1, "");
        assertEq(weth.balanceOf(BOB) - beforeBalance, 0.35625 ether);
        assertEq(collection.liveSupply(), 1);
        assertEq(collection.tokenState(1), uint8(YieldBankTokenState.BURNED));
        assertEq(collection.distributor().accountedBalance(address(weth)), 0.01875 ether);
    }

    function testSupplyIsImmutablePerCollectionAndDoesNotTriggerARelease() public {
        _mint(ALICE, 7, 3.5 ether);
        assertEq(collection.mintedSupply(), 7);
        assertEq(address(collection.proceedsVault()).balance, 3.5 ether);
        YieldBankNFT nft = collection.nft();
        vm.expectRevert();
        vm.prank(ALICE);
        seaDrop.mint{ value: 0.5 ether }(nft, ALICE, 1);
        vm.expectRevert(abi.encodeWithSelector(YieldBankNFT.ImmutableMaxSupply.selector, 8));
        vm.prank(CREATOR);
        nft.setMaxSupply(8);
    }

    function testCollectionCanMintAgainAfterAllCurrentTokensRedeemBeforeMaxSupply() public {
        _mint(ALICE, 2, 1 ether);
        vm.prank(ALICE);
        collection.burnToken(1, "");
        vm.prank(ALICE);
        collection.burnToken(2, "");
        assertEq(collection.liveSupply(), 0);
        assertEq(uint8(collection.state()), uint8(YieldBankCollectionState.ACTIVE));
        _mint(ALICE, 1, 0.5 ether);
        assertEq(collection.mintedSupply(), 3);
        assertEq(collection.nft().ownerOf(3), ALICE);
    }

    function testCollectionClosesOnlyAfterEveryConfiguredTokenMintsAndRedeems() public {
        _mint(ALICE, 7, 3.5 ether);
        for (uint256 tokenId = 1; tokenId <= 7; ++tokenId) {
            vm.prank(ALICE);
            collection.burnToken(tokenId, "");
        }
        assertEq(collection.liveSupply(), 0);
        assertEq(uint8(collection.state()), uint8(YieldBankCollectionState.CLOSED));
    }

    function testAllocatedYieldBankRemainsTransferableAndRedeemable() public {
        _mint(ALICE, 2, 1 ether);
        CollectionPortfolioAllocator.AllocationCall[3] memory calls;
        YieldBankProceedsVault vault = collection.proceedsVault();
        vm.prank(OPERATOR);
        vault.allocateReceipts(1, 1, calls);
        YieldBankNFT nft = collection.nft();
        vm.prank(ALICE);
        nft.transferFrom(ALICE, BOB, 1);
        vm.prank(BOB);
        collection.burnToken(1, "");
        assertGt(core.balanceOf(BOB), 0);
        assertEq(collection.tokenState(1), uint8(YieldBankTokenState.BURNED));
    }

    function testRedemptionUsesOneProofForEligibilityAndRestrictedShareReceipt() public {
        _mint(ALICE, 2, 1 ether);
        CollectionPortfolioAllocator.AllocationCall[3] memory calls;
        YieldBankProceedsVault vault = collection.proceedsVault();
        vm.prank(OPERATOR);
        vault.allocateReceipts(1, 1, calls);
        bytes memory validProof = abi.encodePacked("eligible-holder");
        policy.setRequiredProofs(validProof, validProof);

        vm.expectRevert(abi.encodeWithSelector(YieldBankCollection.Ineligible.selector, ALICE));
        vm.prank(ALICE);
        collection.burnToken(1, "wrong-proof");

        vm.prank(ALICE);
        collection.burnToken(1, validProof);
        assertGt(core.balanceOf(ALICE), 0);
        assertEq(collection.tokenState(1), uint8(YieldBankTokenState.BURNED));
    }

    function testLaterReceiptAllocationDoesNotReviveReleasedToken() public {
        _mint(ALICE, 2, 1 ether);
        YieldBankProceedsVault vault = collection.proceedsVault();
        vm.prank(ALICE);
        collection.burnToken(1, "");
        assertEq(vault.primaryStateOf(1), vault.PRIMARY_RELEASED());

        CollectionPortfolioAllocator.AllocationCall[3] memory calls;
        vm.prank(OPERATOR);
        vault.allocateReceipts(1, 1, calls);

        assertEq(vault.primaryStateOf(1), vault.PRIMARY_RELEASED());
        assertEq(vault.primaryStateOf(2), vault.PRIMARY_ALLOCATED());
        collection.claimPrimary(2);
        assertEq(vault.primaryStateOf(2), vault.PRIMARY_CLAIMED());
    }

    function testForcedNativeIsExcludedFromAccountingAndRecoverableByTimelock() public {
        _mint(ALICE, 1, 1 ether);
        YieldBankProceedsVault vault = collection.proceedsVault();
        vm.deal(address(vault), address(vault).balance + 3 ether);
        assertEq(vault.accountedNative(), 1 ether);
        assertEq(vault.excessNative(), 3 ether);
        uint256 beforeBalance = BOB.balance;
        vm.prank(address(timelock));
        vault.sweepExcessNative(BOB);
        assertEq(BOB.balance - beforeBalance, 3 ether);
        assertEq(address(vault).balance, vault.accountedNative());
    }

    function testFuzzPrimaryReceiptConservesEveryWei(uint96 rawValue, uint8 rawQuantity) public {
        uint256 value = bound(uint256(rawValue), 1, 10_000 ether);
        uint256 quantity = bound(uint256(rawQuantity), 1, 7);
        vm.deal(ALICE, value);
        _mint(ALICE, quantity, value);
        YieldBankProceedsVault vault = collection.proceedsVault();
        (
            uint256 firstTokenId,
            uint256 receiptQuantity,
            uint256 netProceeds,
            uint256 backing,
            uint256 creatorFee,
            uint256 sinjohFee,
            bool allocated
        ) = vault.receipts(1);
        assertEq(firstTokenId, 1);
        assertEq(receiptQuantity, quantity);
        assertEq(netProceeds, value);
        assertFalse(allocated);
        assertEq(backing + creatorFee + sinjohFee, value);
        uint256 assigned;
        for (uint256 tokenId = 1; tokenId <= quantity; ++tokenId) {
            assigned += vault.pendingBackingOf(tokenId);
        }
        assertEq(assigned, backing);
        assertEq(address(vault).balance, vault.accountedNative());
    }

    function testOnlyPinnedSeaDropCanMintOrPayAndOnlyOperatorCanAllocate() public {
        YieldBankNFT nft = collection.nft();
        vm.expectRevert(abi.encodeWithSelector(YieldBankNFT.OnlyAllowedSeaDrop.selector, ALICE));
        vm.prank(ALICE);
        nft.mintSeaDrop(ALICE, 1);
        (bool ok,) = payable(address(collection.proceedsVault())).call{ value: 1 ether }("");
        assertFalse(ok);
        _mint(ALICE, 1, 1 ether);
        CollectionPortfolioAllocator.AllocationCall[3] memory calls;
        YieldBankProceedsVault vault = collection.proceedsVault();
        vm.expectRevert(abi.encodeWithSelector(YieldBankProceedsVault.OnlyOperator.selector, ALICE));
        vm.prank(ALICE);
        vault.allocateReceipts(1, 1, calls);
    }

    function testSeaDropConfigurationCannotAuthorizeZeroProceedsMints() public {
        YieldBankNFT nft = collection.nft();
        PublicDrop memory publicDrop = PublicDrop({
            mintPrice: 1 ether,
            startTime: 1,
            endTime: type(uint48).max,
            maxTotalMintableByWallet: 20,
            feeBps: 10_000,
            restrictFeeRecipients: true
        });
        vm.expectRevert(YieldBankNFT.PaidMintRequired.selector);
        vm.prank(CREATOR);
        nft.updatePublicDrop(address(seaDrop), publicDrop);

        string[] memory uris = new string[](0);
        AllowListData memory allowList = AllowListData({
            merkleRoot: keccak256("free-leaf"), publicKeyURIs: uris, allowListURI: ""
        });
        vm.expectRevert(YieldBankNFT.PaidMintRequired.selector);
        vm.prank(CREATOR);
        nft.updateAllowList(address(seaDrop), allowList);

        TokenGatedDropStage memory gated = TokenGatedDropStage({
            mintPrice: 1 ether,
            maxTotalMintableByWallet: 20,
            startTime: 1,
            endTime: type(uint48).max,
            dropStageIndex: 1,
            maxTokenSupplyForStage: 7,
            feeBps: 10_000,
            restrictFeeRecipients: true
        });
        vm.expectRevert(YieldBankNFT.PaidMintRequired.selector);
        vm.prank(CREATOR);
        nft.updateTokenGatedDrop(address(seaDrop), address(core), gated);

        SignedMintValidationParams memory signed = SignedMintValidationParams({
            minMintPrice: 1,
            maxMaxTotalMintableByWallet: 20,
            minStartTime: 1,
            maxEndTime: type(uint40).max,
            maxMaxTokenSupplyForStage: 7,
            minFeeBps: 0,
            maxFeeBps: 10_000
        });
        vm.expectRevert(YieldBankNFT.PaidMintRequired.selector);
        vm.prank(CREATOR);
        nft.updateSignedMintValidationParams(address(seaDrop), ALICE, signed);
    }

    function testOpenSeaManagerCanConfigureThenHandOwnershipToTimelock() public {
        YieldBankNFT nft = collection.nft();
        assertEq(nft.owner(), CREATOR);
        address payout = address(collection.proceedsVault());
        PublicDrop memory stage = PublicDrop({
            mintPrice: 0.1 ether,
            startTime: 1,
            endTime: type(uint48).max,
            maxTotalMintableByWallet: 7,
            feeBps: 1_000,
            restrictFeeRecipients: false
        });
        vm.startPrank(CREATOR);
        nft.updateCreatorPayoutAddress(address(seaDrop), payout);
        nft.updatePublicDrop(address(seaDrop), stage);
        vm.stopPrank();
        assertEq(seaDrop.creatorPayoutAddress(address(nft)), payout);
        assertEq(seaDrop.getPublicDrop(address(nft)).mintPrice, stage.mintPrice);
        vm.prank(CREATOR);
        nft.transferOwnership(address(timelock));
        assertEq(nft.pendingOwner(), address(timelock));
        vm.prank(address(timelock));
        nft.acceptOwnership();
        assertEq(nft.owner(), address(timelock));
        assertEq(nft.pendingOwner(), address(0));
    }

    function testGuardianPauseBlocksInvestmentButNotTransferOrBurn() public {
        _mint(ALICE, 2, 1 ether);
        vm.prank(GUARDIAN);
        collection.pauseInvestments();
        CollectionPortfolioAllocator.AllocationCall[3] memory calls;
        YieldBankProceedsVault vault = collection.proceedsVault();
        vm.expectRevert(YieldBankProceedsVault.AllocationIsPaused.selector);
        vm.prank(OPERATOR);
        vault.allocateReceipts(1, 1, calls);
        YieldBankNFT nft = collection.nft();
        vm.prank(ALICE);
        nft.transferFrom(ALICE, BOB, 1);
        vm.prank(BOB);
        collection.burnToken(1, "");
    }

    function testBlockedAddressCannotMintReceiveOrRedeem() public {
        YieldBankNFT nft = collection.nft();
        policy.setBlocked(ALICE, true);
        vm.expectRevert(abi.encodeWithSelector(YieldBankCollection.Ineligible.selector, ALICE));
        vm.prank(ALICE);
        seaDrop.mint{ value: 1 ether }(nft, ALICE, 1);
        policy.setBlocked(ALICE, false);
        _mint(ALICE, 1, 1 ether);
        policy.setBlocked(BOB, true);
        vm.expectRevert(abi.encodeWithSelector(YieldBankNFT.IneligibleRecipient.selector, BOB));
        vm.prank(ALICE);
        nft.transferFrom(ALICE, BOB, 1);
    }

    function testConfiguredProjectTokenIsActuallyBurnedWithTheNft() public {
        MockYieldBankBurnableAsset projectToken =
            new MockYieldBankBurnableAsset("Project Token", "PROJECT");
        uint256 burnAmount = 10_000e18;
        YieldBankConfig memory config = _config(1);
        config.redemptionToken = address(projectToken);
        config.redemptionTokenAmount = burnAmount;
        config.redemptionTokenCodeHash = address(projectToken).codehash;
        YieldBankCollection gatedCollection = new YieldBankCollection(config);

        vm.prank(ALICE);
        seaDrop.mint{ value: 1 ether }(gatedCollection.nft(), ALICE, 1);
        projectToken.mint(ALICE, burnAmount);
        vm.prank(ALICE);
        projectToken.approve(address(gatedCollection), burnAmount);

        uint256 supplyBefore = projectToken.totalSupply();
        vm.prank(ALICE);
        gatedCollection.burnToken(1, "");

        assertEq(projectToken.balanceOf(ALICE), 0);
        assertEq(projectToken.totalSupply(), supplyBefore - burnAmount);
        assertEq(gatedCollection.liveSupply(), 0);
        assertEq(gatedCollection.tokenState(1), uint8(YieldBankTokenState.BURNED));
    }

    function testMissingProjectTokenAllowanceRollsBackNftRedemption() public {
        MockYieldBankBurnableAsset projectToken =
            new MockYieldBankBurnableAsset("Project Token", "PROJECT");
        uint256 burnAmount = 10_000e18;
        YieldBankConfig memory config = _config(1);
        config.redemptionToken = address(projectToken);
        config.redemptionTokenAmount = burnAmount;
        config.redemptionTokenCodeHash = address(projectToken).codehash;
        YieldBankCollection gatedCollection = new YieldBankCollection(config);

        vm.prank(ALICE);
        seaDrop.mint{ value: 1 ether }(gatedCollection.nft(), ALICE, 1);
        projectToken.mint(ALICE, burnAmount);

        vm.expectRevert();
        vm.prank(ALICE);
        gatedCollection.burnToken(1, "");

        assertEq(projectToken.balanceOf(ALICE), burnAmount);
        assertEq(projectToken.totalSupply(), burnAmount);
        assertEq(gatedCollection.nft().ownerOf(1), ALICE);
        assertEq(gatedCollection.liveSupply(), 1);
    }

    function _mint(address minter, uint256 quantity, uint256 netProceeds) private {
        YieldBankNFT nft = collection.nft();
        vm.prank(ALICE);
        seaDrop.mint{ value: netProceeds }(nft, minter, quantity);
    }

    function _config(uint256 supply) private view returns (YieldBankConfig memory c) {
        c = YieldBankConfig({
            collectionId: keccak256("SINJOH_YIELD_BANKS_TEST"),
            maxSupply: supply,
            secondaryRoyaltyBps: 500,
            primaryBackingBps: PRIMARY_BACKING_BPS,
            primaryCreatorBps: PRIMARY_CREATOR_BPS,
            primarySinjohBps: PRIMARY_SINJOH_BPS,
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
            renderer: address(renderer),
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
                address(renderer).codehash,
                address(weth).codehash,
                address(seaDrop).codehash,
                address(core).codehash,
                address(market).codehash,
                address(yieldSleeve).codehash
            ]
        });
    }
}
