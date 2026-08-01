// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { RaffleTypes } from "../src/RaffleTypes.sol";

/// @notice Reference ticket-interval Merkle-sum tree, mirroring the off-chain worker.
/// @dev Leaves must be sorted ascending by holder with nonzero tickets. Padding leaves carry
/// zero tickets, so they own an empty interval no index can select.
library RaffleTree {
    bytes32 internal constant LEAF_DOMAIN = keccak256("SINJOH_RAFFLE_LEAF_V1");
    bytes32 internal constant NODE_DOMAIN = keccak256("SINJOH_RAFFLE_NODE_V1");
    bytes32 internal constant EMPTY_DOMAIN = keccak256("SINJOH_RAFFLE_EMPTY_V1");

    struct Params {
        address raffle;
        uint256 chainId;
        uint64 roundId;
        uint64 snapshotBlock;
    }

    function leafHash(Params memory params, address holder, uint256 tickets)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                LEAF_DOMAIN,
                params.chainId,
                params.raffle,
                params.roundId,
                params.snapshotBlock,
                holder,
                tickets
            )
        );
    }

    function nodeHash(bytes32 leftHash, uint256 leftSum, bytes32 rightHash, uint256 rightSum)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(NODE_DOMAIN, leftHash, leftSum, rightHash, rightSum));
    }

    function emptyLeafHash(uint64 roundId) internal pure returns (bytes32) {
        return keccak256(abi.encode(EMPTY_DOMAIN, roundId));
    }

    /// @return root committed root hash
    /// @return rootSum committed total tickets
    /// @return proofs one proof per input leaf, in input order
    function build(Params memory params, RaffleTypes.Leaf[] memory leaves)
        internal
        pure
        returns (bytes32 root, uint256 rootSum, RaffleTypes.ProofElement[][] memory proofs)
    {
        uint256 count = leaves.length;
        uint256 width = 1;
        while (width < count) {
            width <<= 1;
        }
        uint256 depth;
        while ((uint256(1) << depth) < width) {
            ++depth;
        }

        bytes32[][] memory hashes = new bytes32[][](depth + 1);
        uint256[][] memory sums = new uint256[][](depth + 1);
        hashes[0] = new bytes32[](width);
        sums[0] = new uint256[](width);

        bytes32 padding = emptyLeafHash(params.roundId);
        for (uint256 i; i < width; ++i) {
            if (i < count) {
                hashes[0][i] = leafHash(params, leaves[i].holder, leaves[i].tickets);
                sums[0][i] = leaves[i].tickets;
            } else {
                hashes[0][i] = padding;
                sums[0][i] = 0;
            }
        }

        for (uint256 level; level < depth; ++level) {
            uint256 parentWidth = hashes[level].length / 2;
            hashes[level + 1] = new bytes32[](parentWidth);
            sums[level + 1] = new uint256[](parentWidth);
            for (uint256 i; i < parentWidth; ++i) {
                hashes[level + 1][i] = nodeHash(
                    hashes[level][2 * i],
                    sums[level][2 * i],
                    hashes[level][2 * i + 1],
                    sums[level][2 * i + 1]
                );
                sums[level + 1][i] = sums[level][2 * i] + sums[level][2 * i + 1];
            }
        }

        root = hashes[depth][0];
        rootSum = sums[depth][0];

        proofs = new RaffleTypes.ProofElement[][](count);
        for (uint256 i; i < count; ++i) {
            proofs[i] = new RaffleTypes.ProofElement[](depth);
            uint256 index = i;
            for (uint256 level; level < depth; ++level) {
                uint256 sibling = index ^ 1;
                proofs[i][level] = RaffleTypes.ProofElement({
                    siblingHash: hashes[level][sibling],
                    siblingSum: sums[level][sibling],
                    siblingIsLeft: sibling < index
                });
                index >>= 1;
            }
        }
    }

    /// @notice Ticket-interval start for a leaf, computed directly from the sorted leaf set.
    function offsetOf(RaffleTypes.Leaf[] memory leaves, uint256 index)
        internal
        pure
        returns (uint256 offset)
    {
        for (uint256 i; i < index; ++i) {
            offset += leaves[i].tickets;
        }
    }
}
