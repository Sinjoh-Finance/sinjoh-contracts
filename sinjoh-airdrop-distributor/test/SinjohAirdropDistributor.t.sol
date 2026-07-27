// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { TestBase } from "./TestBase.sol";
import { MockArbSys } from "./mocks/MockArbSys.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";
import { SinjohAirdropDistributor } from "../src/SinjohAirdropDistributor.sol";

contract SinjohAirdropDistributorTest is TestBase {
    address internal constant HOLDER_A = address(0x1111);
    address internal constant HOLDER_B = address(0x2222);
    address internal constant FUNDER_A = address(0xA001);
    address internal constant FUNDER_B = address(0xB002);
    address internal constant PROTOCOL_RECIPIENT = address(0xFEE1);
    uint64 internal constant SNAPSHOT = 900;
    bytes32 internal constant SNAPSHOT_HASH = keccak256("SNAPSHOT_900");

    MockERC20 internal subject;
    MockERC20 internal asset;
    SinjohAirdropDistributor internal distributor;
    MockArbSys internal arbSys;

    function setUp() public {
        subject = new MockERC20("Subject", "SUB");
        asset = new MockERC20("Asset", "AST");
        distributor = new SinjohAirdropDistributor(address(this), PROTOCOL_RECIPIENT);

        MockArbSys implementation = new MockArbSys();
        vm.etch(distributor.ARBSYS(), address(implementation).code);
        arbSys = MockArbSys(distributor.ARBSYS());
        arbSys.setBlockNumber(1_000);
        arbSys.setBlockHash(SNAPSHOT, SNAPSHOT_HASH);

        asset.mint(address(this), 100_000);
        asset.approve(address(distributor), type(uint256).max);
    }

    function testSeparateTransferCannotBeClaimedAsFunding() public {
        assertTrue(asset.transfer(address(distributor), 500));
        bytes32 id = _fund(1_000, 1);

        (,,,,,,,,, uint256 totalFunded,,,) = distributor.accounts(id);
        assertEq(totalFunded, 1_000);
        assertEq(distributor.protocolOwed(address(asset)), 10);
        assertEq(distributor.totalLiability(address(asset)), 1_010);
        assertEq(asset.balanceOf(address(distributor)), 1_510);
    }

    function testFrontRunnerCannotStealFundingAttribution() public {
        bytes memory config = _config(1);
        uint256 gross = _grossForNet(1_000);
        asset.mint(FUNDER_A, gross);
        asset.mint(FUNDER_B, gross);
        vm.prank(FUNDER_A);
        asset.approve(address(distributor), type(uint256).max);
        vm.prank(FUNDER_B);
        asset.approve(address(distributor), type(uint256).max);

        vm.prank(FUNDER_B);
        distributor.fund(address(subject), address(asset), gross, config);
        vm.prank(FUNDER_A);
        distributor.fund(address(subject), address(asset), gross, config);

        bytes32 idA = distributor.accountId(FUNDER_A, address(subject), address(asset));
        bytes32 idB = distributor.accountId(FUNDER_B, address(subject), address(asset));
        (,,,,,,,,, uint256 fundedA,,,) = distributor.accounts(idA);
        (,,,,,,,,, uint256 fundedB,,,) = distributor.accounts(idB);
        assertEq(fundedA, 1_000);
        assertEq(fundedB, 1_000);
        assertTrue(idA != idB);
    }

    function testFundingChargesProtocolFeeExactlyOnceAndCanDeliver() public {
        bytes32 id = _fund(9_900, 1);
        (,,,,,,,,, uint256 totalFunded,,,) = distributor.accounts(id);
        assertEq(totalFunded, 9_900);
        assertEq(distributor.protocolOwed(address(asset)), 100);
        assertEq(distributor.totalLiability(address(asset)), 10_000);

        distributor.sendProtocolFee(address(asset), 100);

        assertEq(asset.balanceOf(PROTOCOL_RECIPIENT), 100);
        assertEq(distributor.protocolOwed(address(asset)), 0);
        assertEq(distributor.totalLiability(address(asset)), 9_900);
    }

    function testFeeOnTransferFundingRevertsWithoutCredit() public {
        asset.setFeeBps(100);
        vm.expectPartialRevert(SinjohAirdropDistributor.UnexpectedBalanceDelta.selector);
        distributor.fund(address(subject), address(asset), 1_000, _config(1));

        bytes32 id = distributor.accountId(address(this), address(subject), address(asset));
        (,,,,,,,,,,,, bool configured) = distributor.accounts(id);
        assertTrue(!configured);
        assertEq(distributor.totalLiability(address(asset)), 0);
        assertEq(asset.balanceOf(address(distributor)), 0);
    }

    function testRootCannotExceedThatFundersAccount() public {
        bytes32 id = _fund(100, 1);
        uint256 gross = _grossForNet(1_000);
        asset.mint(FUNDER_B, gross);
        vm.prank(FUNDER_B);
        asset.approve(address(distributor), type(uint256).max);
        vm.prank(FUNDER_B);
        distributor.fund(address(subject), address(asset), gross, _config(1));

        bytes32 root = distributor.leafHash(id, 1, SNAPSHOT, HOLDER_A, 101);
        vm.expectRevert(SinjohAirdropDistributor.InvalidRoot.selector);
        distributor.commitEpoch(
            address(this), address(subject), address(asset), 1, SNAPSHOT, SNAPSHOT_HASH, root, 101
        );
    }

    function testFalsifiedSiblingSumOrDirectionReverts() public {
        bytes32 id = _fund(1_000, 1);
        (SinjohAirdropDistributor.Leaf[] memory leaves, bytes32 root) =
            _twoLeaves(id, 1, SNAPSHOT, 400, 600);
        _commit(id, 1, SNAPSHOT, root, 1_000);
        SinjohAirdropDistributor.ProofElement[][] memory proofs =
            _twoProofs(id, 1, SNAPSHOT, 400, 600);
        proofs[0][0].siblingSum = 599;

        vm.expectRevert(SinjohAirdropDistributor.InvalidProof.selector);
        distributor.push(address(this), address(subject), address(asset), 1, leaves, proofs);

        proofs = _twoProofs(id, 1, SNAPSHOT, 400, 600);
        proofs[0][0].siblingIsLeft = true;
        vm.expectRevert(SinjohAirdropDistributor.InvalidProof.selector);
        distributor.push(address(this), address(subject), address(asset), 1, leaves, proofs);
    }

    function testInvalidProofRevertsBeforeAnyPayment() public {
        bytes32 id = _fund(1_000, 1);
        (SinjohAirdropDistributor.Leaf[] memory leaves, bytes32 root) =
            _twoLeaves(id, 1, SNAPSHOT, 400, 600);
        _commit(id, 1, SNAPSHOT, root, 1_000);
        SinjohAirdropDistributor.ProofElement[][] memory proofs =
            _twoProofs(id, 1, SNAPSHOT, 400, 600);
        proofs[1][0].siblingHash = bytes32(uint256(1));

        vm.expectRevert(SinjohAirdropDistributor.InvalidProof.selector);
        distributor.push(address(this), address(subject), address(asset), 1, leaves, proofs);
        assertEq(asset.balanceOf(HOLDER_A), 0);
        assertEq(distributor.paid(id, HOLDER_A), 0);
    }

    function testRecipientFailureIsIsolated() public {
        bytes32 id = _fund(1_000, 1);
        (SinjohAirdropDistributor.Leaf[] memory leaves, bytes32 root) =
            _twoLeaves(id, 1, SNAPSHOT, 400, 600);
        _commit(id, 1, SNAPSHOT, root, 1_000);
        asset.setFailRecipient(HOLDER_B, true);

        distributor.push(
            address(this),
            address(subject),
            address(asset),
            1,
            leaves,
            _twoProofs(id, 1, SNAPSHOT, 400, 600)
        );

        assertEq(distributor.paid(id, HOLDER_A), 400);
        assertEq(distributor.paid(id, HOLDER_B), 0);
        assertEq(asset.balanceOf(HOLDER_A), 400);
        assertEq(distributor.totalLiability(address(asset)), 610);
    }

    function testDuplicateOrUnsortedHoldersRevert() public {
        bytes32 id = _fund(1_000, 1);
        (SinjohAirdropDistributor.Leaf[] memory leaves, bytes32 root) =
            _twoLeaves(id, 1, SNAPSHOT, 400, 600);
        _commit(id, 1, SNAPSHOT, root, 1_000);
        SinjohAirdropDistributor.ProofElement[][] memory proofs =
            _twoProofs(id, 1, SNAPSHOT, 400, 600);
        (leaves[0], leaves[1]) = (leaves[1], leaves[0]);
        (proofs[0], proofs[1]) = (proofs[1], proofs[0]);

        vm.expectRevert(SinjohAirdropDistributor.InvalidBatch.selector);
        distributor.push(address(this), address(subject), address(asset), 1, leaves, proofs);
    }

    function testRepeatedAndOldProofsCannotDoublePay() public {
        bytes32 id = _fund(1_000, 1);
        (SinjohAirdropDistributor.Leaf[] memory leaves, bytes32 root) =
            _singleLeaf(id, 1, SNAPSHOT, HOLDER_A, 400);
        _commit(id, 1, SNAPSHOT, root, 400);
        SinjohAirdropDistributor.ProofElement[][] memory proofs = _emptyProofs();

        distributor.push(address(this), address(subject), address(asset), 1, leaves, proofs);
        distributor.push(address(this), address(subject), address(asset), 1, leaves, proofs);
        assertEq(asset.balanceOf(HOLDER_A), 400);
        assertEq(distributor.paid(id, HOLDER_A), 400);
    }

    function testBelowFloorCarriesIntoLaterEpoch() public {
        bytes32 id = _fund(1_000, 100);
        (SinjohAirdropDistributor.Leaf[] memory leaves, bytes32 root) =
            _singleLeaf(id, 1, SNAPSHOT, HOLDER_A, 50);
        _commit(id, 1, SNAPSHOT, root, 50);
        distributor.push(address(this), address(subject), address(asset), 1, leaves, _emptyProofs());
        assertEq(distributor.paid(id, HOLDER_A), 0);

        uint64 secondSnapshot = SNAPSHOT + 1;
        bytes32 secondHash = keccak256("SNAPSHOT_901");
        arbSys.setBlockHash(secondSnapshot, secondHash);
        (leaves, root) = _singleLeaf(id, 2, secondSnapshot, HOLDER_A, 120);
        distributor.commitEpoch(
            address(this),
            address(subject),
            address(asset),
            2,
            secondSnapshot,
            secondHash,
            root,
            120
        );
        distributor.push(address(this), address(subject), address(asset), 2, leaves, _emptyProofs());
        assertEq(distributor.paid(id, HOLDER_A), 120);
        assertEq(asset.balanceOf(HOLDER_A), 120);
    }

    function testSkippedOrReplacedEpochIdsRevert() public {
        bytes32 id = _fund(1_000, 1);
        bytes32 root = distributor.leafHash(id, 2, SNAPSHOT, HOLDER_A, 100);
        vm.expectRevert(SinjohAirdropDistributor.InvalidEpoch.selector);
        distributor.commitEpoch(
            address(this), address(subject), address(asset), 2, SNAPSHOT, SNAPSHOT_HASH, root, 100
        );

        root = distributor.leafHash(id, 1, SNAPSHOT, HOLDER_A, 100);
        _commit(id, 1, SNAPSHOT, root, 100);
        vm.expectRevert(SinjohAirdropDistributor.InvalidEpoch.selector);
        distributor.commitEpoch(
            address(this),
            address(subject),
            address(asset),
            1,
            SNAPSHOT + 1,
            SNAPSHOT_HASH,
            root,
            100
        );
    }

    function testWrongExpiredAndParentDomainSnapshotsRevert() public {
        bytes32 id = _fund(1_000, 1);
        bytes32 root = distributor.leafHash(id, 1, SNAPSHOT, HOLDER_A, 100);
        vm.expectRevert(SinjohAirdropDistributor.InvalidSnapshot.selector);
        distributor.commitEpoch(
            address(this),
            address(subject),
            address(asset),
            1,
            SNAPSHOT,
            bytes32(uint256(1)),
            root,
            100
        );

        arbSys.setBlockNumber(uint256(SNAPSHOT) + 256);
        vm.expectRevert(SinjohAirdropDistributor.InvalidSnapshot.selector);
        distributor.commitEpoch(
            address(this), address(subject), address(asset), 1, SNAPSHOT, SNAPSHOT_HASH, root, 100
        );

        arbSys.setBlockNumber(1_000);
        vm.roll(42);
        uint64 parentDomain = uint64(block.number);
        root = distributor.leafHash(id, 1, parentDomain, HOLDER_A, 100);
        vm.expectRevert(SinjohAirdropDistributor.InvalidSnapshot.selector);
        distributor.commitEpoch(
            address(this),
            address(subject),
            address(asset),
            1,
            parentDomain,
            bytes32(uint256(2)),
            root,
            100
        );
    }

    function testFixedMerkleSumFixtureAndUiMultiplierIndependence() public {
        bytes32 id = _fund(1_000, 1);
        bytes32 leafA = distributor.leafHash(id, 1, SNAPSHOT, HOLDER_A, 400);
        bytes32 leafB = distributor.leafHash(id, 1, SNAPSHOT, HOLDER_B, 600);
        bytes32 expectedRoot = keccak256(
            abi.encode(distributor.NODE_DOMAIN(), leafA, uint256(400), leafB, uint256(600))
        );
        assertEq(distributor.nodeHash(leafA, 400, leafB, 600), expectedRoot);
        assertEq(uint256(400) + uint256(600), 1_000);

        subject.setUiMultiplier(50e18);
        assertEq(distributor.leafHash(id, 1, SNAPSHOT, HOLDER_A, 400), leafA);
    }

    function _fund(uint256 amount, uint128 floor) internal returns (bytes32 id) {
        distributor.fund(address(subject), address(asset), _grossForNet(amount), _config(floor));
        id = distributor.accountId(address(this), address(subject), address(asset));
    }

    function _grossForNet(uint256 amount) internal pure returns (uint256) {
        return amount + amount / 99;
    }

    function _config(uint128 floor) internal pure returns (bytes memory) {
        address[] memory exclusions = new address[](0);
        return abi.encode(
            SinjohAirdropDistributor.Config({
                minPayout: floor, maxBatchSize: 16, minConfirmations: 5, exclusions: exclusions
            })
        );
    }

    function _commit(bytes32, uint64 epoch, uint64 snapshot, bytes32 root, uint256 rootSum)
        internal
    {
        distributor.commitEpoch(
            address(this),
            address(subject),
            address(asset),
            epoch,
            snapshot,
            arbSys.arbBlockHash(snapshot),
            root,
            rootSum
        );
    }

    function _singleLeaf(bytes32 id, uint64 epoch, uint64 snapshot, address holder, uint256 amount)
        internal
        view
        returns (SinjohAirdropDistributor.Leaf[] memory leaves, bytes32 root)
    {
        leaves = new SinjohAirdropDistributor.Leaf[](1);
        leaves[0] = SinjohAirdropDistributor.Leaf({ holder: holder, cumulativeAmount: amount });
        root = distributor.leafHash(id, epoch, snapshot, holder, amount);
    }

    function _twoLeaves(bytes32 id, uint64 epoch, uint64 snapshot, uint256 amountA, uint256 amountB)
        internal
        view
        returns (SinjohAirdropDistributor.Leaf[] memory leaves, bytes32 root)
    {
        leaves = new SinjohAirdropDistributor.Leaf[](2);
        leaves[0] = SinjohAirdropDistributor.Leaf({ holder: HOLDER_A, cumulativeAmount: amountA });
        leaves[1] = SinjohAirdropDistributor.Leaf({ holder: HOLDER_B, cumulativeAmount: amountB });
        bytes32 hashA = distributor.leafHash(id, epoch, snapshot, HOLDER_A, amountA);
        bytes32 hashB = distributor.leafHash(id, epoch, snapshot, HOLDER_B, amountB);
        root = distributor.nodeHash(hashA, amountA, hashB, amountB);
    }

    function _twoProofs(bytes32 id, uint64 epoch, uint64 snapshot, uint256 amountA, uint256 amountB)
        internal
        view
        returns (SinjohAirdropDistributor.ProofElement[][] memory proofs)
    {
        bytes32 hashA = distributor.leafHash(id, epoch, snapshot, HOLDER_A, amountA);
        bytes32 hashB = distributor.leafHash(id, epoch, snapshot, HOLDER_B, amountB);
        proofs = new SinjohAirdropDistributor.ProofElement[][](2);
        proofs[0] = new SinjohAirdropDistributor.ProofElement[](1);
        proofs[0][0] = SinjohAirdropDistributor.ProofElement({
            siblingHash: hashB, siblingSum: amountB, siblingIsLeft: false
        });
        proofs[1] = new SinjohAirdropDistributor.ProofElement[](1);
        proofs[1][0] = SinjohAirdropDistributor.ProofElement({
            siblingHash: hashA, siblingSum: amountA, siblingIsLeft: true
        });
    }

    function _emptyProofs()
        internal
        pure
        returns (SinjohAirdropDistributor.ProofElement[][] memory proofs)
    {
        proofs = new SinjohAirdropDistributor.ProofElement[][](1);
        proofs[0] = new SinjohAirdropDistributor.ProofElement[](0);
    }
}
