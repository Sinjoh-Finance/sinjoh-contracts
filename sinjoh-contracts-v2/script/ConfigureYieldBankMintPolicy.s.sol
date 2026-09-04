// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { YieldBankCollection } from "../src/yield-banks/YieldBankCollection.sol";
import { YieldBankNFT } from "../src/yield-banks/YieldBankNFT.sol";
import { YieldBankMintStagePolicy } from "../src/yield-banks/YieldBankMintStagePolicy.sol";
import { YieldBankMintStage } from "../src/yield-banks/YieldBankTypes.sol";

/// @notice Installs an immutable, caller-supplied paid-mint schedule on any Yield Bank collection.
/// @dev No collection address, price, supply, wallet limit, or fee is compiled into this script.
contract ConfigureYieldBankMintPolicy is Script {
    uint256 private constant EXPECTED_CHAIN_ID = 4_663;

    error InvalidConfiguration();
    error WrongChain(uint256 expected, uint256 actual);
    error VerificationFailed();

    function run() external returns (YieldBankMintStagePolicy policy) {
        if (block.chainid != EXPECTED_CHAIN_ID) {
            revert WrongChain(EXPECTED_CHAIN_ID, block.chainid);
        }

        YieldBankCollection collection = YieldBankCollection(vm.envAddress("YIELD_BANK_COLLECTION"));
        YieldBankNFT nft = collection.nft();
        uint256[] memory ends = vm.envUint("MINT_STAGE_ENDS", ",");
        uint256[] memory prices = vm.envUint("MINT_STAGE_PRICES_WEI", ",");
        uint256[] memory starts = vm.envUint("MINT_STAGE_START_TIMES", ",");
        uint256[] memory timeEnds = vm.envUint("MINT_STAGE_END_TIMES", ",");
        uint256[] memory limits = vm.envUint("MINT_STAGE_WALLET_LIMITS", ",");
        uint256[] memory fees = vm.envUint("MINT_STAGE_FEE_BPS", ",");
        uint256[] memory dropIndexes = vm.envUint("MINT_STAGE_DROP_INDEXES", ",");
        bool[] memory restrictFeeRecipients = vm.envBool("MINT_STAGE_RESTRICT_FEE_RECIPIENTS", ",");
        uint256 length = ends.length;

        if (
            address(collection).code.length == 0 || address(nft).code.length == 0 || length == 0
                || length > 16 || prices.length != length || starts.length != length
                || timeEnds.length != length || limits.length != length || fees.length != length
                || dropIndexes.length != length || restrictFeeRecipients.length != length
                || nft.mintPolicy() != address(0) || nft.totalMinted() != 0
        ) revert InvalidConfiguration();

        YieldBankMintStage[] memory stages = new YieldBankMintStage[](length);
        for (uint256 i; i < length; ++i) {
            if (
                ends[i] > type(uint64).max || prices[i] > type(uint80).max
                    || starts[i] > type(uint48).max || timeEnds[i] > type(uint48).max
                    || limits[i] > type(uint16).max || fees[i] > type(uint16).max
                    || dropIndexes[i] > type(uint8).max
            ) revert InvalidConfiguration();
            stages[i] = YieldBankMintStage({
                endTokenId: uint64(ends[i]),
                mintPrice: uint80(prices[i]),
                startTime: uint48(starts[i]),
                endTime: uint48(timeEnds[i]),
                maxMintsPerWallet: uint16(limits[i]),
                feeBps: uint16(fees[i]),
                dropStageIndex: uint8(dropIndexes[i]),
                restrictFeeRecipients: restrictFeeRecipients[i]
            });
        }

        vm.startBroadcast();
        policy = new YieldBankMintStagePolicy(address(nft), collection.maxSupply(), stages);
        nft.setMintPolicy(address(policy));
        vm.stopBroadcast();

        if (
            nft.mintPolicy() != address(policy) || policy.nft() != address(nft)
                || policy.maxSupply() != collection.maxSupply() || policy.stageCount() != length
        ) revert VerificationFailed();
        for (uint256 i; i < length; ++i) {
            YieldBankMintStage memory configured = policy.stage(i);
            if (
                configured.endTokenId != stages[i].endTokenId
                    || configured.mintPrice != stages[i].mintPrice
                    || configured.startTime != stages[i].startTime
                    || configured.endTime != stages[i].endTime
                    || configured.maxMintsPerWallet != stages[i].maxMintsPerWallet
                    || configured.feeBps != stages[i].feeBps
                    || configured.dropStageIndex != stages[i].dropStageIndex
                    || configured.restrictFeeRecipients != stages[i].restrictFeeRecipients
            ) revert VerificationFailed();
        }

        console2.log("Collection", address(collection));
        console2.log("NFT", address(nft));
        console2.log("Mint policy", address(policy));
    }
}
