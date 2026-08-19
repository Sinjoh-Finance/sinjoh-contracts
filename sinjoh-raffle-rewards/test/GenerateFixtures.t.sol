// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { TestBase } from "./TestBase.sol";
import { RaffleTree } from "./RaffleTree.sol";
import { RaffleTypes } from "../src/RaffleTypes.sol";

interface VmConfigFixture {
    function writeFile(string calldata path, string calldata data) external;
    function toString(bytes32 value) external pure returns (string memory);
    function toString(bytes calldata value) external pure returns (string memory);
}

/// @notice Emits ticket-tree fixtures for the offchain worker to reproduce.
/// @dev The worker's tree must be byte-identical to this one. A divergence produces roots no
/// proof can satisfy, which would surface only as every claim reverting on a live raffle.
contract GenerateFixturesTest is TestBase {
    address internal constant RAFFLE = 0x00000000000000000000000000000000000ADde5;
    uint64 internal constant ROUND_ID = 7;
    uint64 internal constant SNAPSHOT_BLOCK = 123_456;

    /// The launch tooling computes `configHash` off-chain to predict the raffle
    /// address before deployment. This pins the canonical `abi.encode(Config)`
    /// so the TypeScript encoding can never drift from the factory's.
    function testWriteConfigHashFixture() public {
        VmConfigFixture vmf =
            VmConfigFixture(address(uint160(uint256(keccak256("hevm cheat code")))));
        address[] memory exclusions = new address[](2);
        exclusions[0] = address(0x0000000000000000000000000000000000a11c00);
        exclusions[1] = address(0x0000000000000000000000000000000000b0B000);
        RaffleTypes.StockReward[] memory stockRewards = new RaffleTypes.StockReward[](1);
        stockRewards[0] = RaffleTypes.StockReward({
            asset: address(0x0000000000000000000000000000000000c0de00),
            swapAdapter: address(0x0000000000000000000000000000000000C0De01),
            priceGuard: address(0x0000000000000000000000000000000000c0De02),
            routeData: abi.encode(uint24(10_000)),
            guardData: ""
        });
        RaffleTypes.Config memory config = RaffleTypes.Config({
            creator: address(0xAB01),
            attestor: address(0xAB02),
            randomness: address(0xAB03),
            prizeAsset: address(0xAB04),
            protocolFeeRecipient: address(0xAB05),
            taxRecipient: address(0xAB06),
            tokensPerTicket: 10_000e18,
            maxTicketsPerHolder: 50,
            minPrize: 1,
            maxPrize: 0,
            prizeBps: 500,
            recipientTaxBps: 700,
            recycleTaxBps: 300,
            minConfirmations: 1,
            winnersPerRound: 4,
            minRoundInterval: 3_600,
            weightWindowBlocks: 900,
            randomnessTimeout: 7_200,
            claimWindow: 604_800,
            basis: RaffleTypes.TicketBasis.MIN_BALANCE,
            exclusions: exclusions,
            stockRewards: stockRewards
        });
        bytes memory encoded = abi.encode(config);
        vmf.writeFile(
            "test/fixtures/config-hash.json",
            string.concat(
                '{"description":"canonical abi.encode(RaffleTypes.Config) for the fixed config in GenerateFixtures.t.sol",',
                '"encoded":"',
                vmf.toString(encoded),
                '","configHash":"',
                vmf.toString(keccak256(encoded)),
                '"}'
            )
        );
    }

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
