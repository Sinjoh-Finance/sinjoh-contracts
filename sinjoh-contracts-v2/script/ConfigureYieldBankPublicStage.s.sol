// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { YieldBankCollection } from "../src/yield-banks/YieldBankCollection.sol";
import { YieldBankMintStagePolicy } from "../src/yield-banks/YieldBankMintStagePolicy.sol";
import { YieldBankNFT } from "../src/yield-banks/YieldBankNFT.sol";
import { PublicDrop } from "../src/yield-banks/interfaces/SeaDropStructs.sol";

/// @notice Exposes one collection-configured tier through OpenSea's single public mint stage.
/// @dev The NFT owner runs this for the initial public rotation. After ownership moves to the
///      collection timelock, submit the same encoded `updatePublicDrop` call through that timelock.
contract ConfigureYieldBankPublicStage is Script {
    uint256 private constant EXPECTED_CHAIN_ID = 4_663;

    error InvalidConfiguration();
    error WrongChain(uint256 expected, uint256 actual);
    error VerificationFailed();

    function run() external returns (PublicDrop memory configuredDrop) {
        if (block.chainid != EXPECTED_CHAIN_ID) {
            revert WrongChain(EXPECTED_CHAIN_ID, block.chainid);
        }
        YieldBankCollection collection = YieldBankCollection(vm.envAddress("YIELD_BANK_COLLECTION"));
        YieldBankNFT nft = collection.nft();
        address policyAddress = nft.mintPolicy();
        uint256 stageIndex = vm.envUint("MINT_PUBLIC_STAGE_INDEX");
        uint256 startTime = vm.envUint("MINT_PUBLIC_STAGE_START_TIME");
        uint256 endTime = vm.envUint("MINT_PUBLIC_STAGE_END_TIME");
        if (
            address(collection).code.length == 0 || address(nft).code.length == 0
                || policyAddress.code.length == 0 || startTime > type(uint48).max
                || endTime > type(uint48).max
        ) revert InvalidConfiguration();

        YieldBankMintStagePolicy policy = YieldBankMintStagePolicy(policyAddress);
        configuredDrop = policy.publicDropForStage(stageIndex, uint48(startTime), uint48(endTime));

        vm.startBroadcast();
        nft.updatePublicDrop(collection.seaDrop(), configuredDrop);
        vm.stopBroadcast();

        PublicDrop memory observed = policy.seaDrop() == collection.seaDrop()
            ? _readPublicDrop(policy, address(nft))
            : revertInvalidConfiguration();
        if (keccak256(abi.encode(observed)) != keccak256(abi.encode(configuredDrop))) {
            revert VerificationFailed();
        }
        console2.log("Collection", address(collection));
        console2.log("NFT", address(nft));
        console2.log("Mint policy", policyAddress);
        console2.log("Public tier index", stageIndex);
        console2.log("Public start", startTime);
        console2.log("Public end", endTime);
    }

    function _readPublicDrop(YieldBankMintStagePolicy policy, address nft)
        private
        view
        returns (PublicDrop memory)
    {
        return ISeaDropPublic(policy.seaDrop()).getPublicDrop(nft);
    }

    function revertInvalidConfiguration() private pure returns (PublicDrop memory) {
        revert InvalidConfiguration();
    }
}

interface ISeaDropPublic {
    function getPublicDrop(address nft) external view returns (PublicDrop memory);
}
