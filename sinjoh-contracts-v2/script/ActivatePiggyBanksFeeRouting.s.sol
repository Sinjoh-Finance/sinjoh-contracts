// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { PiggyBanksFeeSplitter } from "../src/yield-banks/PiggyBanksFeeSplitter.sol";
import { CollectionRevenueRouter } from "../src/yield-banks/CollectionRevenueRouter.sol";

interface IActivatableSinjohFeeRouter {
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
    function bucketInputOwed(uint8 bucketId, address asset) external view returns (uint256);
    function walletOwed(address recipient, address asset) external view returns (uint256);
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

/// @notice One-time activation and current-fee ingestion after the splitter is deployed.
contract ActivatePiggyBanksFeeRouting is Script {
    uint256 private constant CHAIN_ID = 4_663;
    address private constant CREATOR = 0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49;
    address private constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;
    address private constant INJOH_FEE_ROUTER = 0x7E97EadeA120321c65CC09B6FDECc6Eb15D55b2f;
    address private constant PIGGY_BANKS_REVENUE_ROUTER =
        0x9e4E01d2C3c939d870c040192AA143cB139bcc9F;

    error ActivationCheckFailed(bytes32 check);

    function run() external {
        if (block.chainid != CHAIN_ID) revert ActivationCheckFailed("CHAIN_ID");
        address sender = vm.envAddress("PIGGY_BANKS_SPLITTER_SENDER");
        address splitterAddress = vm.envAddress("PIGGY_BANKS_FEE_SPLITTER");
        if (sender != CREATOR) revert ActivationCheckFailed("SENDER");
        if (splitterAddress.code.length == 0) revert ActivationCheckFailed("SPLITTER_CODE");

        PiggyBanksFeeSplitter splitter = PiggyBanksFeeSplitter(splitterAddress);
        IActivatableSinjohFeeRouter feeRouter = IActivatableSinjohFeeRouter(INJOH_FEE_ROUTER);
        CollectionRevenueRouter revenueRouter =
            CollectionRevenueRouter(payable(PIGGY_BANKS_REVENUE_ROUTER));
        if (
            splitter.creatorRecipient() != CREATOR || address(splitter.weth()) != WETH
                || splitter.sourceFeeRouter() != INJOH_FEE_ROUTER
                || address(splitter.revenueRouter()) != PIGGY_BANKS_REVENUE_ROUTER
                || revenueRouter.accountedEscrow(WETH) != 0
                || revenueRouter.accountedEscrow(address(0)) != 0
        ) revert ActivationCheckFailed("PRE_FLIGHT");

        (address currentDestination, uint16 bps, bool isSink, bool mayRepoint,) =
            feeRouter.allocationInfo(0, 0);
        if (
            (currentDestination != CREATOR && currentDestination != splitterAddress) || bps != 8_000
                || isSink || !mayRepoint
        ) revert ActivationCheckFailed("SOURCE_ALLOCATION");

        vm.startBroadcast(sender);
        if (currentDestination == CREATOR) feeRouter.repointWallet(0, 0, splitterAddress);

        uint256 bucketWeth = feeRouter.bucketInputOwed(0, WETH);
        if (bucketWeth != 0) feeRouter.processBucket(0, WETH, bucketWeth, bucketWeth, "");

        uint256 splitterCredit = feeRouter.walletOwed(splitterAddress, WETH);
        if (splitterCredit != 0) feeRouter.sendWallet(splitterAddress, WETH, splitterCredit);
        if (splitter.pendingCreator() != 0 || splitter.pendingPiggyBanks() != 0) splitter.settle();

        uint256 nftWeth = IERC20(WETH).balanceOf(PIGGY_BANKS_REVENUE_ROUTER)
            - revenueRouter.accountedEscrow(WETH);
        if (nftWeth != 0) {
            (bytes memory sourceData,,) = splitter.previewFundingData(nftWeth);
            revenueRouter.syncRoyalty(WETH, sourceData);
        }

        uint256 nftNative =
            PIGGY_BANKS_REVENUE_ROUTER.balance - revenueRouter.accountedEscrow(address(0));
        if (nftNative != 0) {
            (bytes memory sourceData,,) = splitter.previewFundingData(nftNative);
            revenueRouter.syncNativeRoyalty(sourceData);
        }
        vm.stopBroadcast();

        (address finalDestination,,,,) = feeRouter.allocationInfo(0, 0);
        if (
            finalDestination != splitterAddress || feeRouter.walletOwed(splitterAddress, WETH) != 0
                || revenueRouter.accountedEscrow(WETH) != 0
                || revenueRouter.accountedEscrow(address(0)) != 0
        ) revert ActivationCheckFailed("POST_FLIGHT");

        console2.log("Piggy Banks fee splitter activated", splitterAddress);
        console2.log("INJOH bucket WETH processed", bucketWeth);
        console2.log("INJOH creator-leg WETH sent to splitter", splitterCredit);
        console2.log("NFT trading-fee WETH deposited", nftWeth);
        console2.log("NFT trading-fee native ETH deposited", nftNative);
    }
}
