// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { YieldBankCollection } from "../src/yield-banks/YieldBankCollection.sol";
import { YieldBankNFT } from "../src/yield-banks/YieldBankNFT.sol";
import { YieldBankProceedsVault } from "../src/yield-banks/YieldBankProceedsVault.sol";
import { CollectionPortfolioAllocator } from "../src/yield-banks/CollectionPortfolioAllocator.sol";
import { CoreStockTokenSleeve } from "../src/yield-banks/sleeves/CoreStockTokenSleeve.sol";
import { DeltaPoolController } from "../src/yield-banks/DeltaPoolController.sol";
import { DeltaV3LPAdapter } from "../src/yield-banks/adapters/DeltaV3LPAdapter.sol";
import { IYieldBankManagedSleeve } from "../src/yield-banks/interfaces/IYieldBankManagedSleeve.sol";
import { IYieldBankV3Pool } from "../src/yield-banks/interfaces/IYieldBankV3.sol";
import { IDeltaPositionBuilder } from "../src/yield-banks/interfaces/IDeltaPositionBuilder.sol";
import { PublicDrop } from "../src/yield-banks/interfaces/SeaDropStructs.sol";

interface ILiveSeaDropProductionMint {
    function mintPublic(
        address nftContract,
        address feeRecipient,
        address minterIfNotPayer,
        uint256 quantity
    ) external payable;
}

/// @notice Executes phase one of an irreversible, caller-funded mainnet lifecycle against an
/// already configured disposable collection. It stops after the live Delta LP deposit. Run
/// CompleteYieldBankProductionTestMainnet after the position is confirmed onchain; splitting the
/// phases prevents a simulated position ID from being embedded in a later broadcast transaction.
/// Every collection, asset, pool, and amount is supplied at runtime.
contract RunYieldBankProductionTestMainnet is Script {
    uint256 private constant EXPECTED_CHAIN_ID = 4_663;

    error InvalidConfiguration();
    error VerificationFailed(bytes32 stage);
    error WrongChain(uint256 expected, uint256 actual);

    function run() external {
        if (block.chainid != EXPECTED_CHAIN_ID) {
            revert WrongChain(EXPECTED_CHAIN_ID, block.chainid);
        }
        address owner = vm.envAddress("TEST_COLLECTION_OWNER");
        uint256 mintPrice = vm.envUint("TEST_MINT_PRICE");
        YieldBankCollection collection = YieldBankCollection(vm.envAddress("TEST_COLLECTION"));
        YieldBankNFT nft = collection.nft();
        YieldBankProceedsVault vault = collection.proceedsVault();
        CollectionPortfolioAllocator allocator =
            CollectionPortfolioAllocator(collection.portfolioAllocator());
        DeltaPoolController controller =
            DeltaPoolController(address(allocator.deltaPoolController()));
        address deltaPool = vm.envAddress("LIVE_USDG_WETH_POOL");
        address stockToken = vm.envAddress("LIVE_STOCK_TOKEN");
        address usdg = vm.envAddress("LIVE_USDG");
        (address deltaSleeve, address deltaAdapter,,,) = controller.foundationOf(deltaPool);
        address coreSleeve = allocator.sleeves(0);
        address marketSleeve = allocator.sleeves(1);
        address usdgSleeve = allocator.sleeves(2);
        if (
            owner == address(0) || mintPrice == 0 || collection.mintedSupply() != 0
                || nft.owner() != owner || vault.allocationOperator() != owner
                || deltaSleeve == address(0) || deltaAdapter == address(0)
                || controller.pairedAssetOf(deltaPool) != usdg
        ) revert InvalidConfiguration();

        vm.startBroadcast();

        PublicDrop memory stage = PublicDrop({
            mintPrice: _toUint80(mintPrice),
            startTime: 1,
            endTime: type(uint48).max,
            maxTotalMintableByWallet: 1,
            feeBps: 0,
            restrictFeeRecipients: false
        });
        nft.updateCreatorPayoutAddress(collection.seaDrop(), address(vault));
        nft.updatePublicDrop(collection.seaDrop(), stage);
        ILiveSeaDropProductionMint(collection.seaDrop()).mintPublic{ value: mintPrice }(
            address(nft), owner, address(0), 1
        );

        CollectionPortfolioAllocator.AllocationCall[3] memory initial =
            _initialAllocation(allocator, mintPrice, stockToken);
        vault.allocateReceipts(1, 1, initial);

        address account = collection.accountOf(1);
        if (
            account == address(0) || nft.ownerOf(1) != owner
                || IERC20(coreSleeve).balanceOf(account) == 0
                || IERC20(marketSleeve).balanceOf(account) == 0
                || IERC20(usdgSleeve).balanceOf(account) == 0
        ) revert VerificationFailed("PRIMARY_ROUTES");

        uint16[3] memory deltaWeights = [uint16(0), uint16(10_000), uint16(0)];
        uint64 deltaRevision = allocator.setTargetAllocation(
            1, deltaWeights, deltaPool, 1_000, uint48(block.timestamp + 1 days)
        );
        CollectionPortfolioAllocator.RebalanceExecution memory intoDelta =
            _intoDeltaExecution(coreSleeve, marketSleeve, usdgSleeve, stockToken, usdg);
        allocator.executeTargetAllocation(1, deltaRevision, intoDelta);
        if (
            allocator.activeDeltaPoolOf(1) != deltaPool
                || IERC20(deltaSleeve).balanceOf(account) == 0
        ) revert VerificationFailed("DELTA_ROUTE");

        uint256 idleWeth = IERC20(address(collection.weth())).balanceOf(deltaSleeve);
        if (idleWeth < 4) revert VerificationFailed("DELTA_BALANCE");
        // Leave two wei idle to avoid a one-wei downward rounding edge in the 100% adapter cap.
        uint256 adapterAssets = idleWeth - 2;
        (, int24 currentTick,,,,,) = IYieldBankV3Pool(deltaPool).slot0();
        int24 tickSpacing = IYieldBankV3Pool(deltaPool).tickSpacing();
        int24 alignedTick = currentTick / tickSpacing * tickSpacing;
        IDeltaPositionBuilder.Rung[] memory rungs = new IDeltaPositionBuilder.Rung[](1);
        uint256 wethToConvert = adapterAssets / 4;
        rungs[0] = IDeltaPositionBuilder.Rung({
            tickLower: alignedTick - (tickSpacing * 1_000),
            tickUpper: alignedTick + (tickSpacing * 1_000),
            amount0: adapterAssets - wethToConvert,
            amount1: 1,
            amount0Min: 1,
            amount1Min: 1
        });
        DeltaV3LPAdapter.DepositParams memory depositParams = DeltaV3LPAdapter.DepositParams({
            wethToConvert: wethToConvert,
            minimumPairedAssetOut: 1,
            routeData: "",
            rungs: rungs,
            minimumCurrentTick: currentTick - (tickSpacing * 100),
            maximumCurrentTick: currentTick + (tickSpacing * 100),
            deadline: block.timestamp + 1 hours
        });
        allocator.depositToAdapter(
            deltaSleeve, deltaAdapter, adapterAssets, 1, abi.encode(depositParams)
        );
        vm.stopBroadcast();

        if (DeltaV3LPAdapter(deltaAdapter).totalManagedAssets() == 0) {
            revert VerificationFailed("DELTA_LP_DEPOSIT");
        }

        console2.log("Test NFT", address(nft));
        console2.log("Test account", account);
        console2.log("Delta sleeve", deltaSleeve);
        console2.log("Delta adapter", deltaAdapter);
        console2.log("Phase one complete; confirm the live position, then run completion phase");
    }

    function _initialAllocation(
        CollectionPortfolioAllocator allocator,
        uint256 mintPrice,
        address stockToken
    ) private view returns (CollectionPortfolioAllocator.AllocationCall[3] memory calls) {
        uint256 coreAmount = mintPrice * allocator.coreWeightBps() / 10_000;
        uint256 marketCumulative = mintPrice
            * (uint256(allocator.coreWeightBps()) + allocator.marketMakingWeightBps()) / 10_000;
        uint256 marketAmount = marketCumulative - coreAmount;
        uint256 usdgAmount = mintPrice - marketCumulative;

        calls[0].minimumOutput = coreAmount;
        calls[0].minimumShares = 1;
        CoreStockTokenSleeve.ConstituentCall[] memory constituents =
            new CoreStockTokenSleeve.ConstituentCall[](1);
        constituents[0].minimumOutput = 1;
        calls[0].sleeveData = abi.encode(constituents);
        calls[1].minimumOutput = marketAmount;
        calls[1].minimumShares = 1;
        calls[2].minimumOutput = usdgAmount == 0 ? 0 : 1;
        calls[2].minimumShares = usdgAmount == 0 ? 0 : 1;
        if (stockToken.code.length == 0) revert InvalidConfiguration();
    }

    function _intoDeltaExecution(
        address coreSleeve,
        address marketSleeve,
        address usdgSleeve,
        address stockToken,
        address usdg
    ) private view returns (CollectionPortfolioAllocator.RebalanceExecution memory execution) {
        execution.redemptions[0].minimumOutputs =
            new uint256[](IYieldBankManagedSleeve(coreSleeve).inventoryAssets().length);
        execution.redemptions[1].minimumOutputs =
            new uint256[](IYieldBankManagedSleeve(marketSleeve).inventoryAssets().length);
        execution.redemptions[2].minimumOutputs =
            new uint256[](IYieldBankManagedSleeve(usdgSleeve).inventoryAssets().length);
        execution.conversions = new CollectionPortfolioAllocator.ConversionCall[](2);
        execution.conversions[0] = CollectionPortfolioAllocator.ConversionCall({
            asset: stockToken, minimumWethOut: 1, routeData: ""
        });
        execution.conversions[1] = CollectionPortfolioAllocator.ConversionCall({
            asset: usdg, minimumWethOut: 1, routeData: ""
        });
        execution.allocations[1].minimumOutput = 1;
        execution.allocations[1].minimumShares = 1;
        execution.minimumWethRecovered = 1;
        execution.deadline = block.timestamp + 1 hours;
    }

    function _toUint80(uint256 value) private pure returns (uint80 result) {
        if (value > type(uint80).max) revert InvalidConfiguration();
        result = uint80(value);
    }
}
