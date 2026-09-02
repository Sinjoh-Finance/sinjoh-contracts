// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Script } from "forge-std/Script.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { CollectionPortfolioAllocator } from "../src/yield-banks/CollectionPortfolioAllocator.sol";
import { PriceHub } from "../src/yield-banks/PriceHub.sol";
import { YieldBankCollection } from "../src/yield-banks/YieldBankCollection.sol";
import { YieldBankDistributor } from "../src/yield-banks/YieldBankDistributor.sol";
import { YieldBankNFT } from "../src/yield-banks/YieldBankNFT.sol";
import { YieldBankProceedsVault } from "../src/yield-banks/YieldBankProceedsVault.sol";
import { YieldBankSupportBundle } from "../src/yield-banks/YieldBankSupportBundle.sol";
import { IYieldBankSleeve } from "../src/yield-banks/interfaces/IYieldBankSleeve.sol";
import {
    IYieldBankAllocationRoute
} from "../src/yield-banks/interfaces/IYieldBankAllocationRoute.sol";
import { CoreStockTokenSleeve } from "../src/yield-banks/sleeves/CoreStockTokenSleeve.sol";
import { PublicDrop } from "../src/yield-banks/interfaces/SeaDropStructs.sol";
import { YieldBankRedemptionMode } from "../src/yield-banks/YieldBankTypes.sol";
import {
    MockYieldBankAggregator,
    MockYieldBankAsset
} from "../test/mocks/MockYieldBankIntegrations.sol";

interface ILiveSeaDropMintTest {
    function mintPublic(
        address nftContract,
        address feeRecipient,
        address minterIfNotPayer,
        uint256 quantity
    ) external payable;
}

interface ITestMintableERC20 is IERC20 {
    function mint(address recipient, uint256 amount) external;
}

interface ITestWETH is IERC20 {
    function deposit() external payable;
}

contract TestYieldBankRoute is IYieldBankAllocationRoute {
    using SafeERC20 for IERC20;

    address public immutable inputAsset;
    address public immutable outputAsset;
    address public immutable owner;
    bool public immutable mintOutput;

    constructor(address inputAsset_, address outputAsset_, address owner_, bool mintOutput_) {
        inputAsset = inputAsset_;
        outputAsset = outputAsset_;
        owner = owner_;
        mintOutput = mintOutput_;
    }

    function convert(uint256 amountIn, uint256 minimumOutput, address receiver, bytes calldata)
        external
        returns (uint256 amountOut)
    {
        IERC20(inputAsset).safeTransferFrom(msg.sender, address(this), amountIn);
        amountOut = amountIn;
        require(amountOut >= minimumOutput && receiver != address(0));
        if (mintOutput) {
            ITestMintableERC20(outputAsset).mint(receiver, amountOut);
        } else {
            IERC20(outputAsset).safeTransfer(receiver, amountOut);
        }
    }

    function recover(address asset, address recipient) external {
        require(msg.sender == owner && recipient != address(0));
        IERC20 token = IERC20(asset);
        token.safeTransfer(recipient, token.balanceOf(address(this)));
    }
}

/// @notice Exercises one disposable production collection on mainnet.
/// @dev Test-only oracle and ERC-20 deployments are not protocol dependencies or defaults.
contract TestYieldBankCollectionMainnet is Script {
    using SafeERC20 for IERC20;

    uint256 private constant EXPECTED_CHAIN_ID = 4_663;
    uint16 private constant BPS = 10_000;
    uint256 private constant MINT_PRICE = 0.001 ether;
    uint256 private constant DIRECT_ASSET_AMOUNT = 1 ether;

    error VerificationFailed(bytes32 step);

    function run() external {
        if (block.chainid != EXPECTED_CHAIN_ID) revert VerificationFailed("CHAIN");

        uint256 sideKey = vm.envUint("SIDE_WALLET_PRIVATE_KEY");
        uint256 buyerKey = vm.envUint("TEST_BUYER_PRIVATE_KEY");
        address side = vm.addr(sideKey);
        address buyer = vm.addr(buyerKey);
        YieldBankCollection collection = YieldBankCollection(vm.envAddress("TEST_COLLECTION"));
        YieldBankSupportBundle support =
            YieldBankSupportBundle(vm.envAddress("TEST_SUPPORT_BUNDLE"));
        YieldBankNFT nft = collection.nft();
        YieldBankProceedsVault vault = collection.proceedsVault();
        CollectionPortfolioAllocator allocator =
            CollectionPortfolioAllocator(collection.portfolioAllocator());
        address coreSleeve = allocator.sleeves(0);
        address marketSleeve = allocator.sleeves(1);
        address weth = address(collection.weth());

        if (nft.owner() != side || vault.allocationOperator() != side) {
            revert VerificationFailed("OWNER");
        }

        vm.startBroadcast(sideKey);

        MockYieldBankAggregator wethFeed = new MockYieldBankAggregator(8, 3_000e8);
        MockYieldBankAggregator stockFeed = new MockYieldBankAggregator(8, 3_000e8);
        MockYieldBankAsset stockAsset = new MockYieldBankAsset("B", "B");
        TestYieldBankRoute toStock = new TestYieldBankRoute(weth, address(stockAsset), side, true);
        TestYieldBankRoute toWeth = new TestYieldBankRoute(address(stockAsset), weth, side, false);
        ITestWETH(weth).deposit{ value: MINT_PRICE }();
        IERC20(weth).safeTransfer(address(toWeth), MINT_PRICE);
        PriceHub priceHub = support.priceHub();
        bytes memory configureWethFeed = abi.encodeWithSignature(
            "configureFeed(address,address,address,uint32,uint32,bool,uint16)",
            weth,
            address(wethFeed),
            address(0),
            uint32(1 days),
            uint32(1 days),
            false,
            uint16(100)
        );
        bytes memory configureStockFeed = abi.encodeWithSignature(
            "configureFeed(address,address,address,uint32,uint32,bool,uint16)",
            address(stockAsset),
            address(stockFeed),
            address(0),
            uint32(1 days),
            uint32(1 days),
            false,
            uint16(100)
        );
        TimelockController timelock = TimelockController(payable(collection.collectionTimelock()));
        address[] memory targets = new address[](4);
        targets[0] = address(priceHub);
        targets[1] = address(priceHub);
        targets[2] = coreSleeve;
        targets[3] = address(allocator);
        uint256[] memory values = new uint256[](4);
        bytes[] memory payloads = new bytes[](4);
        payloads[0] = configureWethFeed;
        payloads[1] = configureStockFeed;
        payloads[2] = abi.encodeCall(
            CoreStockTokenSleeve.addConstituent,
            (address(stockAsset), address(toStock), address(toStock).codehash, uint16(BPS))
        );
        payloads[3] = abi.encodeCall(
            CollectionPortfolioAllocator.bindRebalanceRoute,
            (address(stockAsset), address(toWeth), address(toWeth).codehash)
        );
        bytes32 operationSalt = keccak256(abi.encode(address(collection), "TEST_CONFIGURATION"));
        timelock.scheduleBatch(targets, values, payloads, bytes32(0), operationSalt, 0);
        timelock.executeBatch(targets, values, payloads, bytes32(0), operationSalt);

        PublicDrop memory stage = PublicDrop({
            // MINT_PRICE is a compile-time constant far below uint80.max.
            // forge-lint: disable-next-line(unsafe-typecast)
            mintPrice: uint80(MINT_PRICE),
            startTime: 1,
            endTime: type(uint48).max,
            maxTotalMintableByWallet: 3,
            feeBps: 0,
            restrictFeeRecipients: false
        });
        nft.updateCreatorPayoutAddress(collection.seaDrop(), address(vault));
        nft.updatePublicDrop(collection.seaDrop(), stage);
        nft.setBaseURI("ipfs://a/");
        ILiveSeaDropMintTest(collection.seaDrop()).mintPublic{ value: MINT_PRICE }(
            address(nft), side, address(0), 1
        );
        if (nft.ownerOf(1) != side || vault.pendingBackingOf(1) != MINT_PRICE) {
            revert VerificationFailed("MINT");
        }

        CollectionPortfolioAllocator.AllocationCall[3] memory initialAllocation;
        initialAllocation[0].minimumOutput = MINT_PRICE;
        initialAllocation[0].minimumShares = 1;
        CoreStockTokenSleeve.ConstituentCall[] memory constituentCalls =
            new CoreStockTokenSleeve.ConstituentCall[](1);
        constituentCalls[0].minimumOutput = MINT_PRICE;
        initialAllocation[0].sleeveData = abi.encode(constituentCalls);
        vault.allocateReceipts(1, 1, initialAllocation);
        address account = collection.accountOf(1);
        if (account == address(0) || IERC20(coreSleeve).balanceOf(account) == 0) {
            revert VerificationFailed("PRIMARY");
        }

        MockYieldBankAsset directAsset = new MockYieldBankAsset("C", "C");
        directAsset.mint(side, DIRECT_ASSET_AMOUNT);
        IERC20(address(directAsset)).safeTransfer(account, DIRECT_ASSET_AMOUNT);
        if (
            directAsset.balanceOf(account) != DIRECT_ASSET_AMOUNT
                || YieldBankDistributor(address(collection.distributor()))
                    .isDistributionAsset(address(directAsset))
        ) revert VerificationFailed("DIRECT_ASSET");

        uint16[3] memory marketWeights = [uint16(0), uint16(BPS), uint16(0)];
        uint64 firstRevision = allocator.setTargetAllocation(
            1, marketWeights, address(0), 100, uint48(block.timestamp + 1 days)
        );
        CollectionPortfolioAllocator.RebalanceExecution memory toMarket;
        toMarket.redemptions[0].minimumOutputs = new uint256[](2);
        toMarket.redemptions[0].minimumOutputs[1] = MINT_PRICE;
        toMarket.conversions = new CollectionPortfolioAllocator.ConversionCall[](1);
        toMarket.conversions[0] = CollectionPortfolioAllocator.ConversionCall({
            asset: address(stockAsset), minimumWethOut: MINT_PRICE, routeData: ""
        });
        toMarket.allocations[1].minimumOutput = MINT_PRICE;
        toMarket.allocations[1].minimumShares = 1;
        toMarket.minimumWethRecovered = MINT_PRICE;
        toMarket.deadline = block.timestamp + 1 days;
        allocator.executeTargetAllocation(1, firstRevision, toMarket);
        if (
            IERC20(coreSleeve).balanceOf(account) != 0
                || IERC20(marketSleeve).balanceOf(account) == 0
        ) revert VerificationFailed("FIRST_REBALANCE");

        (bool funded,) = payable(buyer).call{ value: 0.001 ether }("");
        if (!funded) revert VerificationFailed("BUYER_FUNDING");
        nft.transferFrom(side, buyer, 1);
        vm.stopBroadcast();

        vm.startBroadcast(buyerKey);
        uint16[3] memory coreWeights = [uint16(BPS), uint16(0), uint16(0)];
        uint64 secondRevision = allocator.setTargetAllocation(
            1, coreWeights, address(0), 100, uint48(block.timestamp + 1 days)
        );
        vm.stopBroadcast();

        vm.startBroadcast(sideKey);
        CollectionPortfolioAllocator.RebalanceExecution memory toCore;
        toCore.redemptions[1].minimumOutputs = new uint256[](1);
        toCore.redemptions[1].minimumOutputs[0] = MINT_PRICE;
        toCore.allocations[0].minimumOutput = MINT_PRICE;
        toCore.allocations[0].minimumShares = 1;
        toCore.allocations[0].sleeveData = abi.encode(constituentCalls);
        toCore.minimumWethRecovered = MINT_PRICE;
        toCore.deadline = block.timestamp + 1 days;
        allocator.executeTargetAllocation(1, secondRevision, toCore);
        if (
            IERC20(marketSleeve).balanceOf(account) != 0
                || IERC20(coreSleeve).balanceOf(account) == 0
        ) revert VerificationFailed("SECOND_REBALANCE");
        vm.stopBroadcast();

        vm.startBroadcast(buyerKey);
        nft.transferFrom(buyer, side, 1);
        vm.stopBroadcast();

        vm.startBroadcast(sideKey);
        address[] memory additionalAssets = new address[](1);
        additionalAssets[0] = address(directAsset);
        collection.burnTokenWithAssets(1, "", additionalAssets);
        if (directAsset.balanceOf(side) != DIRECT_ASSET_AMOUNT || collection.liveSupply() != 0) {
            revert VerificationFailed("BURN");
        }

        uint256 sleeveShares = IERC20(coreSleeve).balanceOf(side);
        uint256 stockBefore = stockAsset.balanceOf(side);
        uint256[] memory minimumOutputs = new uint256[](2);
        minimumOutputs[1] = MINT_PRICE;
        IYieldBankSleeve(coreSleeve)
            .redeem(sleeveShares, side, side, YieldBankRedemptionMode.IN_KIND, minimumOutputs, "");
        toStock.recover(weth, side);
        toWeth.recover(address(stockAsset), side);
        vm.stopBroadcast();

        if (
            stockAsset.balanceOf(side) < stockBefore + MINT_PRICE
                || directAsset.balanceOf(account) != 0
        ) revert VerificationFailed("REDEEM");
        (bool ownerQueryOk,) =
            address(nft).staticcall(abi.encodeWithSignature("ownerOf(uint256)", 1));
        if (ownerQueryOk) revert VerificationFailed("NFT_NOT_BURNED");
    }
}
