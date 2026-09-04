// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { YieldBankCollection } from "../src/yield-banks/YieldBankCollection.sol";
import { YieldBankDistributor } from "../src/yield-banks/YieldBankDistributor.sol";
import { CollectionRevenueRouter } from "../src/yield-banks/CollectionRevenueRouter.sol";
import { CollectionPortfolioAllocator } from "../src/yield-banks/CollectionPortfolioAllocator.sol";
import { MarketMakingSleeve } from "../src/yield-banks/sleeves/MarketMakingSleeve.sol";
import { DeltaPoolController } from "../src/yield-banks/DeltaPoolController.sol";
import { DeltaV3LPAdapter } from "../src/yield-banks/adapters/DeltaV3LPAdapter.sol";
import { DeltaV3SinglePoolRoute } from "../src/yield-banks/adapters/DeltaV3SinglePoolRoute.sol";
import { IYieldBankManagedSleeve } from "../src/yield-banks/interfaces/IYieldBankManagedSleeve.sol";
import { IYieldBankV3PositionManager } from "../src/yield-banks/interfaces/IYieldBankV3.sol";
import { YieldBankIds } from "../src/yield-banks/libraries/YieldBankIds.sol";
import { YieldBankWeightedTestHolder } from "./RunYieldBankWeightedTestMainnet.s.sol";

/// @notice Completes the four-token weighted mainnet canary. It generates live Delta fees,
/// collects them, verifies reweighting after burns, unwinds the LP, and burns all remaining NFTs.
contract CompleteYieldBankWeightedTestMainnet is Script {
    using SafeERC20 for IERC20;

    uint256 private constant EXPECTED_CHAIN_ID = 4_663;

    error InvalidConfiguration();
    error VerificationFailed(bytes32 stage);
    error WrongChain(uint256 expected, uint256 actual);

    function run() external {
        if (block.chainid != EXPECTED_CHAIN_ID) {
            revert WrongChain(EXPECTED_CHAIN_ID, block.chainid);
        }

        address owner = vm.envAddress("TEST_COLLECTION_OWNER");
        YieldBankCollection collection = YieldBankCollection(vm.envAddress("TEST_COLLECTION"));
        YieldBankWeightedTestHolder holder =
            YieldBankWeightedTestHolder(vm.envAddress("TEST_TRANSFER_HOLDER"));
        IERC20 pairedAsset = IERC20(vm.envAddress("LIVE_PAIRED_ASSET"));
        address deltaPool = vm.envAddress("LIVE_PAIRED_WETH_POOL");
        address positionManager = vm.envAddress("LIVE_POSITION_MANAGER");
        DeltaV3SinglePoolRoute swapRoute =
            DeltaV3SinglePoolRoute(vm.envAddress("TEST_PAIRED_TO_WETH_ROUTE"));
        uint256 swapAmount = vm.envUint("TEST_YIELD_SWAP_AMOUNT");
        uint256 secondDistribution = vm.envUint("TEST_SECOND_DISTRIBUTION_AMOUNT");

        CollectionRevenueRouter router =
            CollectionRevenueRouter(payable(collection.revenueRouter()));
        CollectionPortfolioAllocator allocator =
            CollectionPortfolioAllocator(collection.portfolioAllocator());
        YieldBankDistributor distributor = collection.distributor();
        DeltaPoolController controller =
            DeltaPoolController(address(allocator.deltaPoolController()));
        (address deltaSleeve, address deltaAdapter,,,) = controller.foundationOf(deltaPool);
        address marketSleeve = allocator.sleeves(1);

        if (
            owner == address(0) || holder.controller() != owner || collection.liveSupply() != 4
                || collection.totalLiveFeeWeight() != 82
                || collection.nft().ownerOf(2) != address(holder)
                || collection.nft().ownerOf(4) != owner
                || pairedAsset.balanceOf(owner) < swapAmount + secondDistribution
                || swapRoute.inputAsset() != address(pairedAsset)
                || swapRoute.outputAsset() != address(collection.weth())
                || allocator.activeDeltaPoolOf(4) != deltaPool || deltaSleeve == address(0)
                || deltaAdapter == address(0) || positionManager.code.length == 0
        ) revert InvalidConfiguration();

        uint256[] memory positionIds = DeltaV3LPAdapter(deltaAdapter).positionIds();
        if (positionIds.length != 1) revert InvalidConfiguration();
        uint256 positionId = positionIds[0];
        (,,,,,,, uint128 liquidity,,,,) =
            IYieldBankV3PositionManager(positionManager).positions(positionId);
        if (liquidity == 0) revert InvalidConfiguration();

        uint256 accountOneDirect = pairedAsset.balanceOf(collection.accountOf(1));
        uint256 accountTwoDirect = pairedAsset.balanceOf(collection.accountOf(2));
        if (accountOneDirect == 0 || accountTwoDirect == 0) {
            revert VerificationFailed("DIRECT_ASSET_SETUP");
        }

        vm.startBroadcast();

        pairedAsset.forceApprove(address(swapRoute), swapAmount);
        swapRoute.convert(swapAmount, 1, owner, "");
        pairedAsset.forceApprove(address(swapRoute), 0);

        uint256 deltaWethBefore = IERC20(address(collection.weth())).balanceOf(deltaSleeve);
        uint256 deltaPairedBefore = pairedAsset.balanceOf(deltaSleeve);
        (address[] memory collectedAssets, uint256[] memory collectedAmounts) =
            allocator.collectAdapter(deltaSleeve, deltaAdapter, abi.encode(positionIds));
        if (
            collectedAssets.length != 2 || collectedAmounts.length != 2
                || collectedAmounts[0] + collectedAmounts[1] == 0
                || IERC20(address(collection.weth())).balanceOf(deltaSleeve) - deltaWethBefore
                    != collectedAmounts[0]
                || pairedAsset.balanceOf(deltaSleeve) - deltaPairedBefore != collectedAmounts[1]
        ) revert VerificationFailed("LIVE_YIELD_COLLECTION");

        address[] memory directAssets = new address[](1);
        directAssets[0] = address(pairedAsset);
        uint256 ownerPairedBeforeBurn = pairedAsset.balanceOf(owner);
        collection.burnTokenWithAssets(1, "", directAssets);
        if (
            pairedAsset.balanceOf(owner) - ownerPairedBeforeBurn != accountOneDirect
                || collection.liveSupply() != 3 || collection.totalLiveFeeWeight() != 80
        ) revert VerificationFailed("FIRST_BURN");

        CollectionPortfolioAllocator.AllocationCall[3] memory revenueCalls;
        revenueCalls[1].minimumOutput = 1;
        revenueCalls[1].minimumShares = 1;
        pairedAsset.forceApprove(address(router), secondDistribution);
        router.fund(
            collection.collectionId(),
            address(pairedAsset),
            secondDistribution,
            YieldBankIds.PROJECT_REVENUE,
            abi.encode(revenueCalls)
        );
        pairedAsset.forceApprove(address(router), 0);

        uint256[3] memory pending;
        for (uint256 i; i < 3; ++i) {
            pending[i] = distributor.pending(i + 2, marketSleeve);
            if (pending[i] == 0) revert VerificationFailed("SECOND_PENDING");
        }
        _verifyRemainingRatios(pending);
        uint256 burnedPending = distributor.pending(1, marketSleeve);
        if (burnedPending != 0) revert VerificationFailed("BURNED_TOKEN_ACCRUAL");
        uint256[] memory remainingIds = new uint256[](3);
        remainingIds[0] = 2;
        remainingIds[1] = 3;
        remainingIds[2] = 4;
        router.deliverToTreasuries(remainingIds);

        uint256 holderPairedBefore = pairedAsset.balanceOf(address(holder));
        holder.burnWithAssets(collection, 2, directAssets);
        if (
            pairedAsset.balanceOf(address(holder)) - holderPairedBefore != accountTwoDirect
                || collection.liveSupply() != 2 || collection.totalLiveFeeWeight() != 75
        ) revert VerificationFailed("TRANSFER_OWNER_BURN");
        holder.sweep(address(pairedAsset), owner);
        holder.sweepRestricted(marketSleeve, owner);

        collection.burnToken(3, "");
        if (collection.liveSupply() != 1 || collection.totalLiveFeeWeight() != 60) {
            revert VerificationFailed("THIRD_BURN");
        }

        MarketMakingSleeve(deltaSleeve).setExitOnly(deltaAdapter);
        DeltaV3LPAdapter.LiquidityAction[] memory actions =
            new DeltaV3LPAdapter.LiquidityAction[](1);
        actions[0] = DeltaV3LPAdapter.LiquidityAction({
            tokenId: positionId, liquidity: liquidity, amount0Minimum: 1, amount1Minimum: 0
        });
        allocator.emergencyExitAdapterInKind(
            deltaSleeve,
            deltaAdapter,
            abi.encode(
                DeltaV3LPAdapter.ExitParams({
                    actions: actions, deadline: block.timestamp + 1 hours
                })
            )
        );

        uint16[3] memory finalWeights = [uint16(0), uint16(10_000), uint16(0)];
        uint64 revision = allocator.setTargetAllocation(
            4, finalWeights, address(0), 1_000, uint48(block.timestamp + 1 days)
        );
        CollectionPortfolioAllocator.RebalanceExecution memory outOfDelta;
        outOfDelta.redemptions[1].minimumOutputs =
            new uint256[](IYieldBankManagedSleeve(marketSleeve).inventoryAssets().length);
        outOfDelta.deltaPoolRedemption.minimumOutputs =
            new uint256[](IYieldBankManagedSleeve(deltaSleeve).inventoryAssets().length);
        outOfDelta.conversions = new CollectionPortfolioAllocator.ConversionCall[](1);
        outOfDelta.conversions[0] = CollectionPortfolioAllocator.ConversionCall({
            asset: address(pairedAsset), minimumWethOut: 1, routeData: ""
        });
        outOfDelta.allocations[1].minimumOutput = 1;
        outOfDelta.allocations[1].minimumShares = 1;
        outOfDelta.minimumWethRecovered = 1;
        outOfDelta.deadline = block.timestamp + 1 hours;
        allocator.executeTargetAllocation(4, revision, outOfDelta);
        collection.burnToken(4, "");

        vm.stopBroadcast();

        if (
            collection.liveSupply() != 0 || collection.totalLiveFeeWeight() != 0
                || uint8(collection.state()) != 3 || collection.tokenState(1) != 3
                || collection.tokenState(2) != 3 || collection.tokenState(3) != 3
                || collection.tokenState(4) != 3 || distributor.accountedBalance(marketSleeve) != 0
                || !distributor.solvent(marketSleeve)
                || allocator.activeDeltaPoolOf(4) != address(0)
                || DeltaV3LPAdapter(deltaAdapter).positionIds().length != 0
                || DeltaV3LPAdapter(deltaAdapter).totalManagedAssets() != 0
        ) revert VerificationFailed("FINAL_STATE");

        console2.log("Test collection", address(collection));
        console2.log("Delta sleeve", deltaSleeve);
        console2.log("Delta adapter", deltaAdapter);
        console2.log("Collected live position", positionId);
        console2.log("Collected WETH", collectedAmounts[0]);
        console2.log("Collected paired asset", collectedAmounts[1]);
        console2.log("All four weighted NFTs burned; collection closed cleanly");
    }

    function _verifyRemainingRatios(uint256[3] memory amounts) private pure {
        uint256 total = amounts[0] + amounts[1] + amounts[2];
        uint256[3] memory weights = [uint256(5), uint256(15), uint256(60)];
        for (uint256 i; i < 3; ++i) {
            uint256 expected = total * weights[i] / 80;
            uint256 difference =
                amounts[i] > expected ? amounts[i] - expected : expected - amounts[i];
            // Entitlements are independently rounded down, so reconstructing from their sum can
            // differ by up to one wei per remaining token.
            if (difference > amounts.length) {
                revert VerificationFailed("SECOND_WEIGHT_RATIO");
            }
        }
    }
}
