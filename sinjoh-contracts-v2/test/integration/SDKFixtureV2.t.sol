// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { ProjectTreasuryVaultV2 } from "../../src/treasury/ProjectTreasuryVaultV2.sol";

contract SDKFixtureV2Test is Test {
    bytes32 private constant AIRDROP_LEAF_DOMAIN = keccak256("SINJOH_V2_AIRDROP_LEAF");
    bytes32 private constant AIRDROP_NODE_DOMAIN = keccak256("SINJOH_V2_AIRDROP_NODE");
    bytes32 private constant EIP712_DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );
    bytes32 private constant AIRDROP_COMMITMENT_TYPEHASH = keccak256(
        "AirdropEpochCommitment(bytes32 accountId,uint64 epochId,uint64 snapshotBlock,bytes32 snapshotBlockHash,uint48 snapshotTime,bytes32 rootHash,uint256 rootSum,uint256 epochAmount,uint256 totalEligibleWeight,uint32 leafCount,bytes32 artifactHash)"
    );

    function testTreasurySendFixtureMatchesCanonicalSolidityEncoding() public view {
        string memory json = vm.readFile("sdk/fixtures/treasury-send.json");
        address asset = vm.parseJsonAddress(json, ".asset");
        uint256 amount = vm.parseUint(vm.parseJsonString(json, ".amount"));
        address recipient = vm.parseJsonAddress(json, ".recipient");
        bytes memory expected = vm.parseJsonBytes(json, ".calldata");

        assertEq(abi.encodeCall(ProjectTreasuryVaultV2.send, (asset, amount, recipient)), expected);
    }

    function testAirdropTreeFixtureMatchesCanonicalSolidityHashing() public view {
        string memory json = vm.readFile("sdk/fixtures/airdrop-tree.json");
        uint256 chainId = vm.parseUint(vm.parseJsonString(json, ".chainId"));
        address airdrop = vm.parseJsonAddress(json, ".airdrop");
        bytes32 accountId = vm.parseJsonBytes32(json, ".accountId");
        uint64 epochId = uint64(vm.parseUint(vm.parseJsonString(json, ".epochId")));
        uint64 snapshotBlock = uint64(vm.parseUint(vm.parseJsonString(json, ".snapshotBlock")));
        uint48 snapshotTime = uint48(vm.parseUint(vm.parseJsonString(json, ".snapshotTime")));

        bytes32[] memory leafHashes = new bytes32[](3);
        uint256[] memory weights = new uint256[](3);
        uint256[] memory amounts = new uint256[](3);
        for (uint256 index; index < 3; ++index) {
            string memory base = string.concat(".holders[", vm.toString(index), "]");
            address holder = vm.parseJsonAddress(json, string.concat(base, ".holder"));
            weights[index] = vm.parseUint(vm.parseJsonString(json, string.concat(base, ".weight")));
            amounts[index] = vm.parseUint(vm.parseJsonString(json, string.concat(base, ".amount")));
            leafHashes[index] = _airdropLeafHash(
                chainId,
                airdrop,
                accountId,
                epochId,
                snapshotBlock,
                snapshotTime,
                holder,
                weights[index],
                amounts[index]
            );
            assertEq(leafHashes[index], vm.parseJsonBytes32(json, string.concat(base, ".leafHash")));
        }

        bytes32 pairHash = _airdropNodeHash(
            leafHashes[0], weights[0], amounts[0], 1, leafHashes[1], weights[1], amounts[1], 1
        );
        assertEq(pairHash, vm.parseJsonBytes32(json, ".pairHash"));

        bytes32 rootHash = _airdropNodeHash(
            pairHash,
            weights[0] + weights[1],
            amounts[0] + amounts[1],
            2,
            leafHashes[2],
            weights[2],
            amounts[2],
            1
        );
        assertEq(rootHash, vm.parseJsonBytes32(json, ".rootHash"));

        bytes32 domainSeparator = keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256("Sinjoh Project Airdrop"),
                keccak256("2"),
                chainId,
                airdrop
            )
        );
        bytes32 structHash = keccak256(
            abi.encode(
                AIRDROP_COMMITMENT_TYPEHASH,
                accountId,
                epochId,
                snapshotBlock,
                vm.parseJsonBytes32(json, ".snapshotBlockHash"),
                snapshotTime,
                rootHash,
                vm.parseUint(vm.parseJsonString(json, ".rootSum")),
                vm.parseUint(vm.parseJsonString(json, ".epochAmount")),
                vm.parseUint(vm.parseJsonString(json, ".totalEligibleWeight")),
                uint32(vm.parseJsonUint(json, ".leafCount")),
                vm.parseJsonBytes32(json, ".artifactHash")
            )
        );
        assertEq(
            keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash)),
            vm.parseJsonBytes32(json, ".typedDataDigest")
        );
    }

    function _airdropLeafHash(
        uint256 chainId,
        address airdrop,
        bytes32 accountId,
        uint64 epochId,
        uint64 snapshotBlock,
        uint48 snapshotTime,
        address holder,
        uint256 weight,
        uint256 amount
    ) private pure returns (bytes32) {
        bytes32 inner = keccak256(
            abi.encode(
                AIRDROP_LEAF_DOMAIN,
                chainId,
                airdrop,
                accountId,
                epochId,
                snapshotBlock,
                snapshotTime,
                holder,
                weight,
                amount
            )
        );
        return keccak256(bytes.concat(inner));
    }

    function _airdropNodeHash(
        bytes32 leftHash,
        uint256 leftWeight,
        uint256 leftAmount,
        uint32 leftCount,
        bytes32 rightHash,
        uint256 rightWeight,
        uint256 rightAmount,
        uint32 rightCount
    ) private pure returns (bytes32) {
        return keccak256(
            abi.encode(
                AIRDROP_NODE_DOMAIN,
                leftHash,
                leftWeight,
                leftAmount,
                leftCount,
                rightHash,
                rightWeight,
                rightAmount,
                rightCount
            )
        );
    }
}
