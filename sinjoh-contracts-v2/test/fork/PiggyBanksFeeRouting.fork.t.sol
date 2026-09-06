// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { PiggyBanksFeeSplitter } from "../../src/yield-banks/PiggyBanksFeeSplitter.sol";
import { CollectionRevenueRouter } from "../../src/yield-banks/CollectionRevenueRouter.sol";
import { YieldBankCollection } from "../../src/yield-banks/YieldBankCollection.sol";
import { YieldBankDistributor } from "../../src/yield-banks/YieldBankDistributor.sol";

interface ILiveSinjohFeeRouter {
    function creator() external view returns (address);
    function subject() external view returns (address);
    function weth() external view returns (address);
    function bound() external view returns (bool);
    function bucketCount() external view returns (uint256);
    function bucketInputOwed(uint8 bucketId, address asset) external view returns (uint256);
    function walletOwed(address recipient, address asset) external view returns (uint256);
    function destinationAllocationTotal(uint8 bucketId) external view returns (uint256);
    function totalLiability(address asset) external view returns (uint256);
    function unaccountedBalance(address asset) external view returns (uint256);
    function allocationInfo(uint8 bucketId, uint8 allocationId)
        external
        view
        returns (
            address destination,
            uint16 bps,
            bool isSink,
            bool creatorMayRepoint,
            bytes memory sinkConfig
        );
    function repointWallet(uint8 bucketId, uint8 allocationId, address newDestination) external;
    function processBucket(
        uint8 bucketId,
        address inputAsset,
        uint256 amountIn,
        uint256 callerMinOut,
        bytes calldata guardData
    ) external returns (uint256 amountOut);
    function sendWallet(address recipient, address asset, uint256 amount) external;
}

interface ILiveAllocator {
    function collection() external view returns (address);
    function revenueRouter() external view returns (address);
    function allocationOperator() external view returns (address);
    function coreWeightBps() external view returns (uint16);
    function marketMakingWeightBps() external view returns (uint16);
    function usdgWeightBps() external view returns (uint16);
    function sleeves(uint256 index) external view returns (address);
    function routeBinding(address inputAsset, address sleeve)
        external
        view
        returns (address route, bytes32 runtimeCodeHash);
}

contract PiggyBanksFeeRoutingForkTest is Test {
    uint256 private constant CHAIN_ID = 4663;
    uint256 private constant TOKEN_COUNT = 3_333;
    uint256 private constant DELIVERY_BATCH = 20;

    address private constant CREATOR = 0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49;
    address private constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;
    address private constant INJOH = 0x2cC0FAC44B8252f6B10208B091aFf2c94B4da77D;
    address private constant INJOH_FEE_ROUTER = 0x7E97EadeA120321c65CC09B6FDECc6Eb15D55b2f;
    address private constant PIGGY_BANKS_COLLECTION = 0xc275fa302Cd53DFa42D41b1C5b770661d923ba43;
    address private constant PIGGY_BANKS_REVENUE_ROUTER =
        0x9e4E01d2C3c939d870c040192AA143cB139bcc9F;
    address private constant PIGGY_BANKS_ALLOCATOR = 0x42e14eA9f926ad7b530ce49d433CB6f748f8D0a1;
    address private constant PIGGY_BANKS_DISTRIBUTOR = 0x23e9f67F1c45149D2DAAf26198c6BDe093918407;
    address private constant USDG_SLEEVE = 0x9e02f4E267fcEf8c1DC89f148529D20F1aD040A1;
    address private constant WETH_TO_USDG_ROUTE = 0xFDabbF3eCF728A7a705CbD81bA1107a01Cfd76c5;
    bytes32 private constant COLLECTION_ID =
        0xfb1a1db66c842cee14b9e9cb3612e10a287139e6ce45f9362d40bbba151fd2ca;

    ILiveSinjohFeeRouter private feeRouter;
    YieldBankCollection private collection;
    CollectionRevenueRouter private revenueRouter;
    ILiveAllocator private allocator;
    YieldBankDistributor private distributor;

    function setUp() external {
        vm.createSelectFork(vm.envString("ROBINHOOD_MAINNET_RPC_URL"));
        assertEq(block.chainid, CHAIN_ID);

        feeRouter = ILiveSinjohFeeRouter(INJOH_FEE_ROUTER);
        collection = YieldBankCollection(PIGGY_BANKS_COLLECTION);
        revenueRouter = CollectionRevenueRouter(payable(PIGGY_BANKS_REVENUE_ROUTER));
        allocator = ILiveAllocator(PIGGY_BANKS_ALLOCATOR);
        distributor = YieldBankDistributor(PIGGY_BANKS_DISTRIBUTOR);
    }

    function testCurrentChain_RepointSettleFeesAndVerifyWeightedDelivery() external {
        _assertLiveBindings();
        _assertEveryBankHasExpectedWeight();

        PiggyBanksFeeSplitter splitter = new PiggyBanksFeeSplitter(
            WETH,
            CREATOR,
            INJOH_FEE_ROUTER,
            INJOH,
            PIGGY_BANKS_COLLECTION,
            COLLECTION_ID,
            PIGGY_BANKS_REVENUE_ROUTER
        );

        uint256 creatorWethBefore = IERC20(WETH).balanceOf(CREATOR);
        uint256 distributorReceivedBefore = distributor.totalReceived(USDG_SLEEVE);
        uint256[4] memory pendingBefore = _representativePending();
        uint256 pendingBucket = feeRouter.bucketInputOwed(0, WETH);
        uint256 existingNftWeth = IERC20(WETH).balanceOf(PIGGY_BANKS_REVENUE_ROUTER)
            - revenueRouter.accountedEscrow(WETH);
        uint256 existingNftNative =
            PIGGY_BANKS_REVENUE_ROUTER.balance - revenueRouter.accountedEscrow(address(0));
        assertGt(pendingBucket, 0, "no current INJOH bucket balance to rehearse");
        assertGt(existingNftWeth + existingNftNative, 0, "no current NFT fees to rehearse");

        vm.prank(CREATOR);
        feeRouter.repointWallet(0, 0, address(splitter));
        (address destination, uint16 allocationBps, bool isSink, bool mayRepoint,) =
            feeRouter.allocationInfo(0, 0);
        assertEq(destination, address(splitter));
        assertEq(allocationBps, 8_000);
        assertFalse(isSink);
        assertTrue(mayRepoint);

        feeRouter.processBucket(0, WETH, pendingBucket, pendingBucket, "");
        uint256 splitterCredit = feeRouter.walletOwed(address(splitter), WETH);
        assertGt(splitterCredit, 0);
        feeRouter.sendWallet(address(splitter), WETH, splitterCredit);
        assertEq(IERC20(WETH).balanceOf(address(splitter)), splitterCredit);

        splitter.settle();
        uint256 expectedCreatorShare = splitterCredit / 2;
        assertEq(splitter.totalCreatorReleased(), expectedCreatorShare);
        assertEq(splitter.totalPiggyBanksFunded(), expectedCreatorShare);
        assertEq(IERC20(WETH).balanceOf(CREATOR) - creatorWethBefore, expectedCreatorShare);
        assertEq(IERC20(WETH).balanceOf(address(splitter)), splitterCredit % 2);

        if (existingNftWeth != 0) {
            (bytes memory sourceData,,) = splitter.previewFundingData(existingNftWeth);
            bytes32 routeHash = keccak256(sourceData);
            vm.prank(CREATOR);
            assertEq(revenueRouter.syncRoyalty(WETH, sourceData), existingNftWeth);
            assertEq(revenueRouter.failedNftAllocation(WETH, routeHash), 0);
        }
        if (existingNftNative != 0) {
            (bytes memory sourceData,,) = splitter.previewFundingData(existingNftNative);
            bytes32 routeHash = keccak256(sourceData);
            vm.prank(CREATOR);
            assertEq(revenueRouter.syncNativeRoyalty(sourceData), existingNftNative);
            assertEq(revenueRouter.failedNftAllocation(WETH, routeHash), 0);
        }

        uint256 receivedIncrease =
            distributor.totalReceived(USDG_SLEEVE) - distributorReceivedBefore;
        assertGt(receivedIncrease, 0);
        _assertWeightedPendingIncrease(pendingBefore);
        _deliverRepresentativeBanks();
        _assertRepresentativeDelivered();
        _assertNoTransitResidue(address(splitter));
        _assertNoTransitResidue(PIGGY_BANKS_ALLOCATOR);
        _assertNoTransitResidue(WETH_TO_USDG_ROUTE);
        assertEq(revenueRouter.accountedEscrow(WETH), 0);
        assertEq(revenueRouter.accountedEscrow(address(0)), 0);
        assertEq(IERC20(WETH).balanceOf(PIGGY_BANKS_REVENUE_ROUTER), 0);
        assertEq(PIGGY_BANKS_REVENUE_ROUTER.balance, 0);
        assertEq(feeRouter.unaccountedBalance(WETH), 0);
        assertEq(IERC20(WETH).balanceOf(INJOH_FEE_ROUTER), feeRouter.totalLiability(WETH));
        assertTrue(distributor.solvent(USDG_SLEEVE));
    }

    function _assertLiveBindings() private view {
        assertTrue(feeRouter.bound());
        assertEq(feeRouter.creator(), CREATOR);
        assertEq(feeRouter.subject(), INJOH);
        assertEq(feeRouter.weth(), WETH);
        assertEq(feeRouter.bucketCount(), 4);

        (address destination, uint16 allocationBps, bool isSink, bool mayRepoint,) =
            feeRouter.allocationInfo(0, 0);
        assertEq(destination, CREATOR);
        assertEq(allocationBps, 8_000);
        assertFalse(isSink);
        assertTrue(mayRepoint);

        assertEq(address(revenueRouter.collection()), PIGGY_BANKS_COLLECTION);
        assertEq(address(revenueRouter.allocator()), PIGGY_BANKS_ALLOCATOR);
        assertEq(revenueRouter.royaltyBackingBps(), 10_000);
        assertEq(revenueRouter.royaltyCreatorBps(), 0);
        assertEq(revenueRouter.royaltySinjohBps(), 0);
        assertEq(address(collection.distributor()), PIGGY_BANKS_DISTRIBUTOR);
        assertEq(address(collection.weth()), WETH);
        assertEq(collection.collectionId(), COLLECTION_ID);
        assertEq(collection.maxSupply(), TOKEN_COUNT);
        assertEq(collection.liveSupply(), TOKEN_COUNT);
        assertEq(collection.totalLiveFeeWeight(), 8_130);
        assertEq(collection.feeWeightOf(1), 60);
        assertEq(collection.feeWeightOf(4), 15);
        assertEq(collection.feeWeightOf(34), 5);
        assertEq(collection.feeWeightOf(334), 2);

        assertEq(allocator.collection(), PIGGY_BANKS_COLLECTION);
        assertEq(allocator.revenueRouter(), PIGGY_BANKS_REVENUE_ROUTER);
        assertEq(allocator.allocationOperator(), CREATOR);
        assertEq(allocator.coreWeightBps(), 0);
        assertEq(allocator.marketMakingWeightBps(), 0);
        assertEq(allocator.usdgWeightBps(), 10_000);
        assertEq(allocator.sleeves(2), USDG_SLEEVE);
        (address route, bytes32 runtimeCodeHash) = allocator.routeBinding(WETH, USDG_SLEEVE);
        assertEq(route, WETH_TO_USDG_ROUTE);
        assertEq(route.codehash, runtimeCodeHash);
    }

    function _representativePending() private view returns (uint256[4] memory values) {
        values[0] = distributor.pending(1, USDG_SLEEVE);
        values[1] = distributor.pending(4, USDG_SLEEVE);
        values[2] = distributor.pending(34, USDG_SLEEVE);
        values[3] = distributor.pending(334, USDG_SLEEVE);
    }

    function _assertWeightedPendingIncrease(uint256[4] memory beforeValues) private view {
        uint256 alpha = distributor.pending(1, USDG_SLEEVE) - beforeValues[0];
        uint256 prime = distributor.pending(4, USDG_SLEEVE) - beforeValues[1];
        uint256 premium = distributor.pending(34, USDG_SLEEVE) - beforeValues[2];
        uint256 standard = distributor.pending(334, USDG_SLEEVE) - beforeValues[3];
        assertGt(standard, 0);
        assertApproxEqAbs(alpha, standard * 30, 30);
        assertApproxEqAbs(prime * 2, standard * 15, 30);
        assertApproxEqAbs(premium * 2, standard * 5, 30);
    }

    function _assertEveryBankHasExpectedWeight() private view {
        for (uint256 tokenId = 1; tokenId <= TOKEN_COUNT; ++tokenId) {
            uint96 expected = tokenId <= 3 ? 60 : tokenId <= 33 ? 15 : tokenId <= 333 ? 5 : 2;
            assertEq(collection.feeWeightOf(tokenId), expected, "unexpected bank weight");
        }
    }

    function _deliverRepresentativeBanks() private {
        uint256[] memory tokenIds = new uint256[](4);
        tokenIds[0] = 1;
        tokenIds[1] = 4;
        tokenIds[2] = 34;
        tokenIds[3] = 334;
        assertLe(tokenIds.length, DELIVERY_BATCH);
        revenueRouter.deliverToTreasuries(tokenIds);
    }

    function _assertRepresentativeDelivered() private view {
        assertEq(distributor.pending(1, USDG_SLEEVE), 0);
        assertEq(distributor.pending(4, USDG_SLEEVE), 0);
        assertEq(distributor.pending(34, USDG_SLEEVE), 0);
        assertEq(distributor.pending(334, USDG_SLEEVE), 0);
        assertGt(IERC20(USDG_SLEEVE).balanceOf(collection.accountOf(1)), 0);
        assertGt(IERC20(USDG_SLEEVE).balanceOf(collection.accountOf(4)), 0);
        assertGt(IERC20(USDG_SLEEVE).balanceOf(collection.accountOf(34)), 0);
        assertGt(IERC20(USDG_SLEEVE).balanceOf(collection.accountOf(334)), 0);
    }

    function _assertNoTransitResidue(address target) private view {
        assertEq(target.balance, 0, "native residue");
        assertEq(IERC20(WETH).balanceOf(target), 0, "WETH residue");
        assertEq(IERC20(USDG_SLEEVE).balanceOf(target), 0, "sleeve residue");
    }
}
