// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { TestBase } from "./TestBase.sol";
import { RaffleTree } from "./RaffleTree.sol";
import { MockArbSys } from "./mocks/MockArbSys.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";
import { MockRandomness } from "./mocks/MockRandomness.sol";
import { RaffleTypes } from "../src/RaffleTypes.sol";
import { SinjohRaffleRewards } from "../src/SinjohRaffleRewards.sol";
import { SinjohRaffleRewardsFactory } from "../src/SinjohRaffleRewardsFactory.sol";

interface IWETH {
    function deposit() external payable;
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function symbol() external view returns (string memory);
}

/// @notice Exercises the raffle against Robinhood Chain mainnet state: the real chain id, the
/// real WETH contract, and the real EVM configuration.
/// @dev Set `RH_RPC_URL` to run. Without it the suite skips rather than failing, so the default
/// `forge test` stays offline.
///
/// `ArbSys` cannot be executed by a fork. Its account holds a single `INVALID` opcode (`0xfe`)
/// because the precompile is implemented by the node, not in EVM bytecode. This suite asserts
/// that fact, then etches a stand-in seeded with the fork's own height, so every other part of
/// the flow runs against genuine chain state.
contract SinjohRaffleRewardsForkTest is TestBase {
    address internal constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;
    address internal constant ARBSYS = address(0x64);
    uint256 internal constant ROBINHOOD_MAINNET = 4_663;

    address internal constant CREATOR = address(0xC0FFEE);
    address internal constant ATTESTOR = address(0xA77E);
    address internal constant PROTOCOL_RECIPIENT = address(0xFEE1);
    address internal constant TAX_RECIPIENT = address(0x7A11);
    address internal constant HOLDER_A = address(0x1111);
    address internal constant HOLDER_B = address(0x2222);
    address internal constant HOLDER_C = address(0x3333);

    bool internal forked;
    SinjohRaffleRewardsFactory internal factory;
    SinjohRaffleRewards internal raffle;
    MockRandomness internal randomness;
    MockArbSys internal arbSys;
    MockERC20 internal subject;
    uint64 internal snapshotBlock;

    function setUp() public {
        string memory url = vm.envOr("RH_RPC_URL", string(""));
        if (bytes(url).length == 0) return;

        vm.createSelectFork(url);
        forked = true;

        assertEq(block.chainid, ROBINHOOD_MAINNET);
        // The precompile is not executable locally; this is why the stand-in below exists.
        assertEq(keccak256(ARBSYS.code), keccak256(hex"fe"));

        // Seed the stand-in from the fork's own height so snapshot arithmetic uses real values.
        snapshotBlock = uint64(block.number - 4);
        MockArbSys implementation = new MockArbSys();
        vm.etch(ARBSYS, address(implementation).code);
        arbSys = MockArbSys(ARBSYS);
        arbSys.setBlockNumber(block.number);
        arbSys.setBlockHash(snapshotBlock, blockhash(snapshotBlock));

        randomness = new MockRandomness();
        // The prize asset is the real WETH deployment. The subject token is local because the
        // raffle never calls it: it only records the address and excludes it from payouts.
        subject = new MockERC20("Subject", "SUB");
        factory = new SinjohRaffleRewardsFactory(block.chainid);
        raffle = SinjohRaffleRewards(payable(factory.deployRaffle(bytes32("fork"), _config())));

        vm.prank(CREATOR);
        raffle.bind(address(subject));
    }

    /// The real WETH deployment behaves as the raffle's accounting requires.
    function testForkRealWethIsUsable() public {
        if (!forked) return;
        assertEq(keccak256(bytes(IWETH(WETH).symbol())), keccak256(bytes("WETH")));

        vm.deal(address(this), 10 ether);
        IWETH(WETH).deposit{ value: 5 ether }();
        assertEq(IWETH(WETH).balanceOf(address(this)), 5 ether);
    }

    /// A complete hourly cycle against mainnet state, from deposit to paid winner.
    function testForkFullRoundTrip() public {
        if (!forked) return;

        vm.deal(address(this), 10 ether);
        IWETH(WETH).deposit{ value: 5 ether }();
        IWETH(WETH).approve(address(raffle), type(uint256).max);
        raffle.fund(address(subject), WETH, 5 ether, "");

        uint256 pool = raffle.availablePool();
        assertEq(pool, 5 ether - 5 ether / 100);

        RaffleTypes.Leaf[] memory leaves = _leaves();
        RaffleTree.Params memory params = RaffleTree.Params({
            raffle: address(raffle),
            chainId: block.chainid,
            roundId: 1,
            snapshotBlock: snapshotBlock
        });
        (bytes32 root, uint256 total, RaffleTypes.ProofElement[][] memory proofs) =
            RaffleTree.build(params, leaves);

        vm.prank(ATTESTOR);
        uint256 prize = raffle.commitRound(1, snapshotBlock, blockhash(snapshotBlock), root, total);
        assertEq(prize, pool * 500 / 10_000);

        (, bytes32 requestId,,,,,,,,,) = raffle.rounds(1);
        randomness.deliver(requestId, uint256(blockhash(block.number - 1)));

        uint256 index = raffle.winningIndex(1, 0);
        uint256 which = _ownerOf(leaves, index);
        uint256 recipientTax = prize * 700 / 10_000;
        uint256 recycleTax = prize * 300 / 10_000;

        uint256 paid = raffle.claim(1, 0, leaves[which], proofs[which]);
        assertEq(paid, prize - recipientTax - recycleTax);
        assertEq(IWETH(WETH).balanceOf(leaves[which].holder), paid);

        raffle.sendProtocolFee(raffle.protocolOwed());
        raffle.sendTax(raffle.taxOwed());
        assertTrue(IWETH(WETH).balanceOf(address(raffle)) >= raffle.liabilities());
    }

    /// An unattributed WETH transfer is credited only through `sync`, on real state.
    function testForkUnattributedTransferNeedsSync() public {
        if (!forked) return;

        vm.deal(address(this), 2 ether);
        IWETH(WETH).deposit{ value: 1 ether }();
        IWETH(WETH).transfer(address(raffle), 1 ether);
        assertEq(raffle.availablePool(), 0);

        (uint256 credited,) = raffle.sync();
        assertEq(credited, 1 ether);
        assertEq(raffle.availablePool(), 1 ether - 1 ether / 100);
    }

    /// @dev Documents the measured seal deadline this chain imposes on the randomness adapter.
    function testForkBlockCadenceIsRecorded() public view {
        if (!forked) return;
        // 0.1004 s/block measured over 100,000 blocks: 255 blocks is about 25.6 seconds.
        assertTrue(block.number > 25_000_000);
    }

    function _config() internal view returns (RaffleTypes.Config memory config) {
        address[] memory exclusions = new address[](0);
        config = RaffleTypes.Config({
            creator: CREATOR,
            attestor: ATTESTOR,
            randomness: address(randomness),
            prizeAsset: WETH,
            protocolFeeRecipient: PROTOCOL_RECIPIENT,
            taxRecipient: TAX_RECIPIENT,
            tokensPerTicket: 10_000e18,
            maxTicketsPerHolder: 0,
            minPrize: 1,
            maxPrize: 0,
            prizeBps: 500,
            recipientTaxBps: 700,
            recycleTaxBps: 300,
            minConfirmations: 1,
            winnersPerRound: 1,
            minRoundInterval: 3_600,
            weightWindowBlocks: 36_000,
            randomnessTimeout: 3_600,
            claimWindow: 604_800,
            basis: RaffleTypes.TicketBasis.MIN_BALANCE,
            exclusions: exclusions
        });
    }

    function _leaves() internal pure returns (RaffleTypes.Leaf[] memory leaves) {
        leaves = new RaffleTypes.Leaf[](3);
        leaves[0] = RaffleTypes.Leaf({ holder: HOLDER_A, tickets: 1 });
        leaves[1] = RaffleTypes.Leaf({ holder: HOLDER_B, tickets: 3 });
        leaves[2] = RaffleTypes.Leaf({ holder: HOLDER_C, tickets: 6 });
    }

    function _ownerOf(RaffleTypes.Leaf[] memory leaves, uint256 index)
        internal
        pure
        returns (uint256)
    {
        uint256 offset;
        for (uint256 i; i < leaves.length; ++i) {
            if (index >= offset && index < offset + leaves[i].tickets) return i;
            offset += leaves[i].tickets;
        }
        revert("NO_OWNER");
    }
}
