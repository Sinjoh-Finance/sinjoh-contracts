// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { YieldBankCollection } from "../src/yield-banks/YieldBankCollection.sol";
import { YieldBankNFT } from "../src/yield-banks/YieldBankNFT.sol";
import { YieldBankAccount } from "../src/yield-banks/YieldBankAccount.sol";
import { YieldBankDistributor } from "../src/yield-banks/YieldBankDistributor.sol";
import { YieldBankProceedsVault } from "../src/yield-banks/YieldBankProceedsVault.sol";
import { CollectionRevenueRouter } from "../src/yield-banks/CollectionRevenueRouter.sol";
import { CollectionPortfolioAllocator } from "../src/yield-banks/CollectionPortfolioAllocator.sol";
import { DeltaPoolController } from "../src/yield-banks/DeltaPoolController.sol";
import { DeltaV3LPAdapter } from "../src/yield-banks/adapters/DeltaV3LPAdapter.sol";
import { IYieldBankManagedSleeve } from "../src/yield-banks/interfaces/IYieldBankManagedSleeve.sol";
import { IYieldBankV3Pool } from "../src/yield-banks/interfaces/IYieldBankV3.sol";
import { IDeltaPositionBuilder } from "../src/yield-banks/interfaces/IDeltaPositionBuilder.sol";
import { PublicDrop } from "../src/yield-banks/interfaces/SeaDropStructs.sol";
import { YieldBankIds } from "../src/yield-banks/libraries/YieldBankIds.sol";

interface IYieldBankProofTransfer {
    function transferWithProof(address recipient, uint256 amount, bytes calldata proof)
        external
        returns (bool);
}

interface ILiveSeaDropWeightedMint {
    function mintPublic(
        address nftContract,
        address feeRecipient,
        address minterIfNotPayer,
        uint256 quantity
    ) external payable;
}

/// @notice Holder used to prove that treasury redemption follows the current NFT owner.
contract YieldBankWeightedTestHolder {
    using SafeERC20 for IERC20;

    address public immutable controller;

    error OnlyController(address caller);

    constructor(address controller_) {
        controller = controller_;
    }

    function burnWithAssets(
        YieldBankCollection collection,
        uint256 tokenId,
        address[] calldata additionalAssets
    ) external {
        if (msg.sender != controller) revert OnlyController(msg.sender);
        collection.burnTokenWithAssets(tokenId, "", additionalAssets);
    }

    function sweep(address asset, address recipient) external {
        if (msg.sender != controller) revert OnlyController(msg.sender);
        IERC20 token = IERC20(asset);
        token.safeTransfer(recipient, token.balanceOf(address(this)));
    }

    function sweepRestricted(address asset, address recipient) external {
        if (msg.sender != controller) revert OnlyController(msg.sender);
        uint256 amount = IERC20(asset).balanceOf(address(this));
        IYieldBankProofTransfer(asset).transferWithProof(recipient, amount, "");
    }
}

/// @notice Mainnet phase one for the four-token weighted launch canary. All collection,
/// integration, asset, and amount inputs are runtime configuration. The script stops after a
/// real Delta LP position exists so phase two can discover its actual onchain token ID.
contract RunYieldBankWeightedTestMainnet is Script {
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
        YieldBankNFT nft = collection.nft();
        YieldBankProceedsVault vault = collection.proceedsVault();
        CollectionRevenueRouter router =
            CollectionRevenueRouter(payable(collection.revenueRouter()));
        CollectionPortfolioAllocator allocator =
            CollectionPortfolioAllocator(collection.portfolioAllocator());
        YieldBankDistributor distributor = collection.distributor();
        DeltaPoolController controller =
            DeltaPoolController(address(allocator.deltaPoolController()));
        IERC20 pairedAsset = IERC20(vm.envAddress("LIVE_PAIRED_ASSET"));
        address deltaPool = vm.envAddress("LIVE_PAIRED_WETH_POOL");
        uint256 mintPrice = vm.envUint("TEST_MINT_PRICE");
        uint256 firstDistribution = vm.envUint("TEST_FIRST_DISTRIBUTION_AMOUNT");
        uint256 directOne = vm.envUint("TEST_DIRECT_TOKEN_ONE_AMOUNT");
        uint256 directTwo = vm.envUint("TEST_DIRECT_TOKEN_TWO_AMOUNT");
        uint256 deltaPairedAmount = vm.envUint("TEST_DELTA_PAIRED_AMOUNT");
        (address deltaSleeve, address deltaAdapter,,,) = controller.foundationOf(deltaPool);
        address marketSleeve = allocator.sleeves(1);

        if (
            owner == address(0) || mintPrice == 0 || firstDistribution == 0 || directOne == 0
                || directTwo == 0 || deltaPairedAmount == 0 || collection.maxSupply() != 4
                || collection.mintedSupply() != 0 || collection.feeWeightOf(1) != 2
                || collection.feeWeightOf(2) != 5 || collection.feeWeightOf(3) != 15
                || collection.feeWeightOf(4) != 60 || collection.maximumTotalFeeWeight() != 82
                || allocator.coreWeightBps() != 0 || allocator.marketMakingWeightBps() != 10_000
                || allocator.usdgWeightBps() != 0 || nft.owner() != owner
                || vault.allocationOperator() != owner || allocator.allocationOperator() != owner
                || deltaSleeve == address(0) || deltaAdapter == address(0)
                || controller.pairedAssetOf(deltaPool) != address(pairedAsset)
        ) revert InvalidConfiguration();

        address[4] memory accounts;
        uint256[4] memory beforeShares;
        YieldBankWeightedTestHolder holder;

        vm.startBroadcast();

        PublicDrop memory stage = PublicDrop({
            mintPrice: _toUint80(mintPrice),
            startTime: 1,
            endTime: type(uint48).max,
            maxTotalMintableByWallet: 4,
            feeBps: 0,
            restrictFeeRecipients: false
        });
        nft.updateCreatorPayoutAddress(collection.seaDrop(), address(vault));
        nft.updatePublicDrop(collection.seaDrop(), stage);
        ILiveSeaDropWeightedMint(collection.seaDrop()).mintPublic{ value: mintPrice * 4 }(
            address(nft), owner, address(0), 4
        );

        CollectionPortfolioAllocator.AllocationCall[3] memory primaryCalls;
        primaryCalls[1].minimumOutput = mintPrice * 4;
        primaryCalls[1].minimumShares = 1;
        vault.allocateReceipts(1, 1, primaryCalls);

        for (uint256 i; i < 4; ++i) {
            accounts[i] = collection.accountOf(i + 1);
            beforeShares[i] = IERC20(marketSleeve).balanceOf(accounts[i]);
            if (accounts[i] == address(0) || beforeShares[i] == 0) {
                revert VerificationFailed("PRIMARY_DELIVERY");
            }
        }

        holder = new YieldBankWeightedTestHolder(owner);
        nft.transferFrom(owner, address(holder), 2);

        pairedAsset.safeTransfer(accounts[0], directOne);
        pairedAsset.safeTransfer(accounts[1], directTwo);

        CollectionPortfolioAllocator.AllocationCall[3] memory revenueCalls;
        revenueCalls[1].minimumOutput = 1;
        revenueCalls[1].minimumShares = 1;
        pairedAsset.forceApprove(address(router), firstDistribution);
        router.fund(
            collection.collectionId(),
            address(pairedAsset),
            firstDistribution,
            YieldBankIds.PROJECT_REVENUE,
            abi.encode(revenueCalls)
        );
        pairedAsset.forceApprove(address(router), 0);

        uint256[4] memory pending;
        for (uint256 i; i < 4; ++i) {
            pending[i] = distributor.pending(i + 1, marketSleeve);
            if (pending[i] == 0) revert VerificationFailed("WEIGHTED_PENDING");
        }
        _verifyWeightRatios(pending, 82);

        uint256[] memory tokenIds = new uint256[](4);
        for (uint256 i; i < 4; ++i) {
            tokenIds[i] = i + 1;
        }
        router.deliverToTreasuries(tokenIds);
        for (uint256 i; i < 4; ++i) {
            if (IERC20(marketSleeve).balanceOf(accounts[i]) - beforeShares[i] != pending[i]) {
                revert VerificationFailed("WEIGHTED_DELIVERY");
            }
        }

        uint16[3] memory deltaWeights = [uint16(0), uint16(10_000), uint16(0)];
        uint64 revision = allocator.setTargetAllocation(
            4, deltaWeights, deltaPool, 1_000, uint48(block.timestamp + 1 days)
        );
        CollectionPortfolioAllocator.RebalanceExecution memory intoDelta;
        intoDelta.redemptions[1].minimumOutputs =
            new uint256[](IYieldBankManagedSleeve(marketSleeve).inventoryAssets().length);
        intoDelta.allocations[1].minimumOutput = 1;
        intoDelta.allocations[1].minimumShares = 1;
        intoDelta.minimumWethRecovered = 1;
        intoDelta.deadline = block.timestamp + 1 hours;
        allocator.executeTargetAllocation(4, revision, intoDelta);

        uint256 idleWeth = IERC20(address(collection.weth())).balanceOf(deltaSleeve);
        if (idleWeth < 4) revert VerificationFailed("DELTA_BALANCE");
        uint256 adapterAssets = idleWeth - 2;
        (, int24 currentTick,,,,,) = IYieldBankV3Pool(deltaPool).slot0();
        int24 tickSpacing = IYieldBankV3Pool(deltaPool).tickSpacing();
        int24 alignedTick = currentTick / tickSpacing * tickSpacing;
        uint256 wethToConvert = adapterAssets / 4;
        IDeltaPositionBuilder.Rung[] memory rungs = new IDeltaPositionBuilder.Rung[](1);
        rungs[0] = IDeltaPositionBuilder.Rung({
            tickLower: alignedTick - (tickSpacing * 1_000),
            tickUpper: alignedTick + (tickSpacing * 1_000),
            amount0: adapterAssets - wethToConvert,
            amount1: deltaPairedAmount,
            amount0Min: 1,
            amount1Min: 1
        });
        allocator.depositToAdapter(
            deltaSleeve,
            deltaAdapter,
            adapterAssets,
            1,
            abi.encode(
                DeltaV3LPAdapter.DepositParams({
                    wethToConvert: wethToConvert,
                    minimumPairedAssetOut: 1,
                    routeData: "",
                    rungs: rungs,
                    minimumCurrentTick: currentTick - (tickSpacing * 100),
                    maximumCurrentTick: currentTick + (tickSpacing * 100),
                    deadline: block.timestamp + 1 hours
                })
            )
        );
        vm.stopBroadcast();

        if (
            collection.liveSupply() != 4 || collection.totalLiveFeeWeight() != 82
                || nft.ownerOf(2) != address(holder)
                || pairedAsset.balanceOf(accounts[0]) != directOne
                || pairedAsset.balanceOf(accounts[1]) != directTwo
                || allocator.activeDeltaPoolOf(4) != deltaPool
                || DeltaV3LPAdapter(deltaAdapter).totalManagedAssets() == 0
        ) revert VerificationFailed("PHASE_ONE_FINAL");

        (bool releaseOk,) = accounts[0].call(
            abi.encodeCall(YieldBankAccount.releaseDirectAsset, (address(pairedAsset), owner))
        );
        (bool recoverOk,) = accounts[0].call(
            abi.encodeCall(YieldBankAccount.recoverDirectAsset, (address(pairedAsset)))
        );
        if (releaseOk || recoverOk) revert VerificationFailed("DIRECT_ASSET_LOCK");

        console2.log("Test collection", address(collection));
        console2.log("Test NFT", address(nft));
        console2.log("Revenue router", address(router));
        console2.log("Distributor", address(distributor));
        console2.log("Token 1 account", accounts[0]);
        console2.log("Token 2 account", accounts[1]);
        console2.log("Token 3 account", accounts[2]);
        console2.log("Token 4 account", accounts[3]);
        console2.log("Transferred owner contract", address(holder));
        console2.log("Delta sleeve", deltaSleeve);
        console2.log("Delta adapter", deltaAdapter);
        console2.log("Phase one complete; run completion after the position is onchain");
    }

    function _verifyWeightRatios(uint256[4] memory amounts, uint256 denominator) private pure {
        uint256 total = amounts[0] + amounts[1] + amounts[2] + amounts[3];
        uint256[4] memory weights = [uint256(2), uint256(5), uint256(15), uint256(60)];
        for (uint256 i; i < 4; ++i) {
            uint256 expected = total * weights[i] / denominator;
            uint256 difference =
                amounts[i] > expected ? amounts[i] - expected : expected - amounts[i];
            // Each entitlement is independently rounded down by the distributor. Rebuilding an
            // expected entitlement from the sum can therefore differ by up to one wei per token.
            if (difference > amounts.length) revert VerificationFailed("WEIGHT_RATIO");
        }
    }

    function _toUint80(uint256 value) private pure returns (uint80 result) {
        if (value > type(uint80).max) revert InvalidConfiguration();
        result = uint80(value);
    }
}
