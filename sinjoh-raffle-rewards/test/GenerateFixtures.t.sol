// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { TestBase } from "./TestBase.sol";
import { RaffleTree } from "./RaffleTree.sol";
import { RaffleTypes } from "../src/RaffleTypes.sol";

/// @notice Emits ticket-tree fixtures for the offchain worker to reproduce.
/// @dev The worker's tree must be byte-identical to this one. A divergence produces roots no
/// proof can satisfy, which would surface only as every claim reverting on a live raffle.
contract GenerateFixturesTest is TestBase {
    address internal constant RAFFLE = 0x00000000000000000000000000000000000ADde5;
    uint64 internal constant ROUND_ID = 7;
    uint64 internal constant SNAPSHOT_BLOCK = 123_456;

    function testWriteTreeFixtures() public {
        RaffleTypes.Leaf[] memory leaves = new RaffleTypes.Leaf[](5);
        leaves[0] = RaffleTypes.Leaf({ holder: address(0x1111), tickets: 1 });
        leaves[1] = RaffleTypes.Leaf({ holder: address(0x2222), tickets: 3 });
        leaves[2] = RaffleTypes.Leaf({ holder: address(0x3333), tickets: 6 });
        leaves[3] = RaffleTypes.Leaf({ holder: address(0x4444), tickets: 40 });
        leaves[4] = RaffleTypes.Leaf({ holder: address(0x5555), tickets: 200 });

        RaffleTree.Params memory params = RaffleTree.Params({
            raffle: RAFFLE, chainId: 4_663, roundId: ROUND_ID, snapshotBlock: SNAPSHOT_BLOCK
        });
        (bytes32 root, uint256 rootSum, RaffleTypes.ProofElement[][] memory proofs) =
            RaffleTree.build(params, leaves);

        string memory json = string.concat(
            '{"chainId":4663,"raffle":"',
            vm.toString(RAFFLE),
            '","roundId":',
            vm.toString(uint256(ROUND_ID)),
            ',"snapshotBlock":',
            vm.toString(uint256(SNAPSHOT_BLOCK)),
            ',"root":"',
            vm.toString(root),
            '","rootSum":',
            vm.toString(rootSum),
            ',"emptyLeaf":"',
            vm.toString(RaffleTree.emptyLeafHash(ROUND_ID)),
            '","leaves":['
        );

        uint256 offset;
        for (uint256 i; i < leaves.length; ++i) {
            json = string.concat(
                json,
                i == 0 ? "" : ",",
                '{"holder":"',
                vm.toString(leaves[i].holder),
                '","tickets":',
                vm.toString(leaves[i].tickets),
                ',"offset":',
                vm.toString(offset),
                ',"leafHash":"',
                vm.toString(RaffleTree.leafHash(params, leaves[i].holder, leaves[i].tickets)),
                '","proof":[',
                _encodeProof(proofs[i]),
                "]}"
            );
            offset += leaves[i].tickets;
        }
        vm.writeFile("test/fixtures/ticket-tree.json", string.concat(json, "]}"));
    }

    /// @notice Emits winning-index derivations so the worker can locate winners without guessing.
    function testWriteSlotIndexFixtures() public {
        bytes32 slotDomain = keccak256("SINJOH_RAFFLE_SLOT_V1");
        uint256 seed = 0x1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF;
        uint256 totalTickets = 250;

        string memory json = string.concat(
            '{"chainId":4663,"raffle":"',
            vm.toString(RAFFLE),
            '","roundId":',
            vm.toString(uint256(ROUND_ID)),
            ',"seed":"',
            vm.toString(seed),
            '","totalTickets":',
            vm.toString(totalTickets),
            ',"indices":['
        );
        for (uint8 slot; slot < 4; ++slot) {
            uint256 index = uint256(
                keccak256(abi.encode(slotDomain, uint256(4_663), RAFFLE, ROUND_ID, slot, seed))
            ) % totalTickets;
            json = string.concat(json, slot == 0 ? "" : ",", vm.toString(index));
        }
        vm.writeFile("test/fixtures/slot-indices.json", string.concat(json, "]}"));
    }

    function _encodeProof(RaffleTypes.ProofElement[] memory proof)
        private
        pure
        returns (string memory encoded)
    {
        for (uint256 i; i < proof.length; ++i) {
            encoded = string.concat(
                encoded,
                i == 0 ? "" : ",",
                '{"siblingHash":"',
                vm.toString(proof[i].siblingHash),
                '","siblingSum":',
                vm.toString(proof[i].siblingSum),
                ',"siblingIsLeft":',
                proof[i].siblingIsLeft ? "true" : "false",
                "}"
            );
        }
    }
}
