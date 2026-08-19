// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { InvariantTestBase } from "./TestBase.sol";
import { MockArbSys } from "./mocks/MockArbSys.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";
import { SinjohAirdropDistributor } from "../src/SinjohAirdropDistributor.sol";

contract AirdropHandler {
    address internal constant HOLDER = address(0x1234);
    uint64 internal constant FIRST_SNAPSHOT = 900;

    MockERC20 public immutable subject;
    MockERC20 public immutable asset;
    SinjohAirdropDistributor public immutable distributor;
    bytes32 public immutable id;
    uint256 public totalGrossFunded;

    constructor() {
        subject = new MockERC20("Subject", "SUB");
        asset = new MockERC20("Asset", "AST");
        distributor = new SinjohAirdropDistributor(address(this), address(0xFEE1));
        id = distributor.accountId(address(this), address(subject), address(asset));
        asset.approve(address(distributor), type(uint256).max);
    }

    function fund(uint96 rawAmount) external {
        uint256 amount = uint256(rawAmount) % 1e24 + 1;
        asset.mint(address(this), amount);
        address[] memory exclusions = new address[](0);
        bytes memory config = abi.encode(
            SinjohAirdropDistributor.Config({
                minPayout: 1, maxBatchSize: 16, minConfirmations: 5, exclusions: exclusions
            })
        );
        distributor.fund(address(subject), address(asset), amount, config);
        totalGrossFunded += amount;
    }

    function commitAndPush(uint96 rawBudget) external {
        (uint256 totalFunded,, uint256 latestRoot, uint64 latestEpoch,) =
            distributor.accountFinancials(id);
        if (totalFunded == latestRoot || latestEpoch >= 90) return;

        uint256 budget = uint256(rawBudget) % (totalFunded - latestRoot) + 1;
        uint256 newRootSum = latestRoot + budget;
        uint64 epoch = latestEpoch + 1;
        uint64 snapshot = FIRST_SNAPSHOT + latestEpoch;
        bytes32 snapshotHash = keccak256(abi.encode("INVARIANT_SNAPSHOT", snapshot));
        MockArbSys(distributor.ARBSYS()).setBlockHash(snapshot, snapshotHash);
        bytes32 root = distributor.leafHash(id, epoch, snapshot, HOLDER, newRootSum);
        distributor.commitEpoch(
            address(this),
            address(subject),
            address(asset),
            epoch,
            snapshot,
            snapshotHash,
            root,
            newRootSum
        );

        SinjohAirdropDistributor.Leaf[] memory leaves = new SinjohAirdropDistributor.Leaf[](1);
        leaves[0] = SinjohAirdropDistributor.Leaf({ holder: HOLDER, cumulativeAmount: newRootSum });
        SinjohAirdropDistributor.ProofElement[][] memory proofs =
            new SinjohAirdropDistributor.ProofElement[][](1);
        proofs[0] = new SinjohAirdropDistributor.ProofElement[](0);
        distributor.push(address(this), address(subject), address(asset), epoch, leaves, proofs);
    }
}

contract SinjohAirdropDistributorInvariantTest is InvariantTestBase {
    AirdropHandler internal handler;
    SinjohAirdropDistributor internal distributor;
    MockERC20 internal asset;
    bytes32 internal id;

    function setUp() public {
        MockArbSys implementation = new MockArbSys();
        vm.etch(address(0x64), address(implementation).code);
        MockArbSys(address(0x64)).setBlockNumber(1_000);

        handler = new AirdropHandler();
        distributor = handler.distributor();
        asset = handler.asset();
        id = handler.id();
        _targetedContracts.push(address(handler));
    }

    function invariantLiabilityNeverExceedsBalance() public view {
        assertTrue(
            distributor.totalLiability(address(asset)) <= asset.balanceOf(address(distributor))
        );
    }

    function invariantAccountBoundsAlwaysHold() public view {
        (uint256 totalFunded, uint256 totalPaid, uint256 latestRoot,,) =
            distributor.accountFinancials(id);
        assertTrue(totalPaid <= latestRoot);
        assertTrue(latestRoot <= totalFunded);
    }

    function invariantAggregateEqualsDetailedLiability() public view {
        (uint256 totalFunded, uint256 totalPaid,,,) = distributor.accountFinancials(id);
        assertEq(
            distributor.totalLiability(address(asset)),
            totalFunded - totalPaid + distributor.protocolOwed(address(asset))
        );
    }

    function invariantProtocolFeeEqualsOnePercentOfCumulativeFunding() public view {
        assertEq(
            distributor.protocolOwed(address(asset)),
            handler.totalGrossFunded() * distributor.PROTOCOL_FEE_BPS() / distributor.BPS()
        );
    }
}
