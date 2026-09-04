// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { YieldBankCollection } from "../src/yield-banks/YieldBankCollection.sol";
import { CollectionPortfolioAllocator } from "../src/yield-banks/CollectionPortfolioAllocator.sol";
import { CoreStockTokenSleeve } from "../src/yield-banks/sleeves/CoreStockTokenSleeve.sol";
import { DeltaPoolController } from "../src/yield-banks/DeltaPoolController.sol";
import { DeltaV3LPAdapter } from "../src/yield-banks/adapters/DeltaV3LPAdapter.sol";
import { IYieldBankManagedSleeve } from "../src/yield-banks/interfaces/IYieldBankManagedSleeve.sol";
import { IYieldBankV3PositionManager } from "../src/yield-banks/interfaces/IYieldBankV3.sol";

/// @notice Completes a partially executed mainnet lifecycle after a Delta LP position already exists.
/// All collection and integration addresses are supplied at runtime. The position ID is discovered
/// from the live adapter, rather than predicted from a pre-broadcast simulation.
contract CompleteYieldBankProductionTestMainnet is Script {
    using SafeERC20 for IERC20;

    uint256 private constant EXPECTED_CHAIN_ID = 4_663;
    address private constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    error InvalidConfiguration();
    error VerificationFailed(bytes32 stage);
    error WrongChain(uint256 expected, uint256 actual);

    function run() external {
        if (block.chainid != EXPECTED_CHAIN_ID) {
            revert WrongChain(EXPECTED_CHAIN_ID, block.chainid);
        }

        address owner = vm.envAddress("TEST_COLLECTION_OWNER");
        YieldBankCollection collection = YieldBankCollection(vm.envAddress("TEST_COLLECTION"));
        CollectionPortfolioAllocator allocator =
            CollectionPortfolioAllocator(collection.portfolioAllocator());
        DeltaPoolController controller =
            DeltaPoolController(address(allocator.deltaPoolController()));
        address deltaPool = vm.envAddress("LIVE_USDG_WETH_POOL");
        address positionManager = vm.envAddress("LIVE_POSITION_MANAGER");
        address stockToken = vm.envAddress("LIVE_STOCK_TOKEN");
        address usdg = vm.envAddress("LIVE_USDG");
        IERC20 redemptionToken = collection.redemptionToken();
        uint256 redemptionAmount = collection.redemptionTokenAmount();

        (address deltaSleeve, address deltaAdapter,,,) = controller.foundationOf(deltaPool);
        address coreSleeve = allocator.sleeves(0);
        if (
            owner == address(0) || collection.liveSupply() != 1
                || collection.nft().ownerOf(1) != owner || deltaSleeve == address(0)
                || deltaAdapter == address(0) || positionManager.code.length == 0
                || stockToken.code.length == 0 || usdg.code.length == 0
                || allocator.activeDeltaPoolOf(1) != deltaPool
        ) revert InvalidConfiguration();

        uint256[] memory positionIds = DeltaV3LPAdapter(deltaAdapter).positionIds();
        if (positionIds.length != 1) revert InvalidConfiguration();
        uint256 positionId = positionIds[0];
        (,,,,,,, uint128 liquidity,,,,) =
            IYieldBankV3PositionManager(positionManager).positions(positionId);
        if (liquidity == 0) revert InvalidConfiguration();

        DeltaV3LPAdapter.LiquidityAction[] memory actions =
            new DeltaV3LPAdapter.LiquidityAction[](1);
        actions[0] = DeltaV3LPAdapter.LiquidityAction({
            tokenId: positionId, liquidity: liquidity, amount0Minimum: 1, amount1Minimum: 0
        });

        uint256 burnBalanceBefore = redemptionToken.balanceOf(BURN_ADDRESS);
        uint256 ownerRedemptionBefore = redemptionToken.balanceOf(owner);
        if (ownerRedemptionBefore < redemptionAmount) revert InvalidConfiguration();

        vm.startBroadcast();

        // The adapter is already deposit-paused. Exit the complete position in kind so this
        // emergency unwind does not depend on a cross-asset oracle valuation.
        allocator.emergencyExitAdapterInKind(
            deltaSleeve,
            deltaAdapter,
            abi.encode(
                DeltaV3LPAdapter.ExitParams({
                    actions: actions, deadline: block.timestamp + 1 hours
                })
            )
        );

        uint16[3] memory finalWeights = [uint16(10_000), uint16(0), uint16(0)];
        uint64 finalRevision = allocator.setTargetAllocation(
            1, finalWeights, address(0), 1_000, uint48(block.timestamp + 1 days)
        );
        CollectionPortfolioAllocator.RebalanceExecution memory outOfDelta =
            _outOfDeltaExecution(deltaSleeve, usdg);
        allocator.executeTargetAllocation(1, finalRevision, outOfDelta);

        if (
            allocator.activeDeltaPoolOf(1) != address(0)
                || IERC20(coreSleeve).balanceOf(collection.accountOf(1)) == 0
        ) revert VerificationFailed("DELTA_EXIT_ROUTE");

        redemptionToken.forceApprove(address(collection), redemptionAmount);
        collection.burnToken(1, "");
        redemptionToken.forceApprove(address(collection), 0);

        vm.stopBroadcast();

        if (
            DeltaV3LPAdapter(deltaAdapter).positionIds().length != 0
                || DeltaV3LPAdapter(deltaAdapter).totalManagedAssets() != 0
        ) revert VerificationFailed("DELTA_LP_EXIT");
        if (
            redemptionToken.balanceOf(BURN_ADDRESS) - burnBalanceBefore != redemptionAmount
                || ownerRedemptionBefore - redemptionToken.balanceOf(owner) != redemptionAmount
                || collection.liveSupply() != 0 || collection.tokenState(1) != 3
        ) revert VerificationFailed("REDEMPTION");

        console2.log("Test collection", address(collection));
        console2.log("Test account", collection.accountOf(1));
        console2.log("Delta sleeve", deltaSleeve);
        console2.log("Delta adapter", deltaAdapter);
        console2.log("Exited live Delta position", positionId);
        console2.log("Redemption token burned", redemptionAmount);
    }

    function _outOfDeltaExecution(address deltaSleeve, address usdg)
        private
        view
        returns (CollectionPortfolioAllocator.RebalanceExecution memory execution)
    {
        execution.deltaPoolRedemption.minimumOutputs =
            new uint256[](IYieldBankManagedSleeve(deltaSleeve).inventoryAssets().length);
        execution.conversions = new CollectionPortfolioAllocator.ConversionCall[](1);
        execution.conversions[0] = CollectionPortfolioAllocator.ConversionCall({
            asset: usdg, minimumWethOut: 1, routeData: ""
        });
        execution.allocations[0].minimumOutput = 1;
        execution.allocations[0].minimumShares = 1;
        CoreStockTokenSleeve.ConstituentCall[] memory constituents =
            new CoreStockTokenSleeve.ConstituentCall[](1);
        constituents[0].minimumOutput = 1;
        execution.allocations[0].sleeveData = abi.encode(constituents);
        execution.minimumWethRecovered = 1;
        execution.deadline = block.timestamp + 1 hours;
    }
}
