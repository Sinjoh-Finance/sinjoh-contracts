// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { SinjohJoint } from "@sinjoh-treasury/SinjohJoint.sol";
import { SinjohTreasuryFactory } from "@sinjoh-treasury/SinjohTreasuryFactory.sol";
import { SinjohTreasuryVault } from "@sinjoh-treasury/SinjohTreasuryVault.sol";
import { SinjohGovernor } from "../src/governance/SinjohGovernor.sol";
import { TokenHolderTreasuryFactory } from "../src/governance/TokenHolderTreasuryFactory.sol";
import { TestBase } from "./TestBase.sol";
import { MockDirectVotesToken, MockERC20 } from "./mocks/Mocks.sol";

/// @dev Implements every historical-vote probe the factory previously made except the one
///      OpenZeppelin Governor actually uses to create proposals and count votes.
contract MockVotesTokenWithoutPastVotes {
    function clock() external view returns (uint48) {
        return uint48(block.number);
    }

    function getVotes(address) external pure returns (uint256) {
        return 1;
    }

    function getPastTotalSupply(uint256) external pure returns (uint256) {
        return 1;
    }
}

contract TokenHolderTreasuryFactoryTest is TestBase {
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant CAROL = address(0xCA401);
    address private constant RECIPIENT = address(0xCAFE);

    TokenHolderTreasuryFactory private factory;
    MockDirectVotesToken private subjectToken;

    function setUp() public {
        factory = new TokenHolderTreasuryFactory();
        subjectToken = new MockDirectVotesToken(ALICE, 100e18);
        vm.prank(ALICE);
        assertTrue(subjectToken.transfer(BOB, 40e18));
        vm.roll(block.number + 1);
    }

    function testCreatesTokenGovernedVaultThroughTheExistingGovernorSlot() public {
        (SinjohTreasuryVault vault, SinjohGovernor governor, TimelockController timelock) =
            factory.createTokenHolderTreasury(address(subjectToken), "Token Treasury", _config());

        assertEq(vault.governor(), address(timelock));
        assertEq(address(governor.token()), address(subjectToken));
        assertEq(factory.tokenForVault(address(vault)), address(subjectToken));
        assertEq(factory.governorForVault(address(vault)), address(governor));
        assertEq(factory.timelockForVault(address(vault)), address(timelock));
        assertTrue(timelock.hasRole(timelock.PROPOSER_ROLE(), address(governor)));
        assertTrue(timelock.hasRole(timelock.CANCELLER_ROLE(), address(governor)));
        assertTrue(timelock.hasRole(timelock.EXECUTOR_ROLE(), address(0)));
        assertTrue(!timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), address(factory)));
    }

    function testTokenHoldersTransferVaultAssetsThroughProposalVoteAndTimelock() public {
        (SinjohTreasuryVault vault, SinjohGovernor governor,) =
            factory.createTokenHolderTreasury(address(subjectToken), "Token Treasury", _config());
        MockERC20 treasuryAsset = new MockERC20();
        treasuryAsset.mint(address(vault), 1_000e18);

        address[] memory targets = new address[](1);
        targets[0] = address(vault);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeCall(vault.transfer, (address(treasuryAsset), 250e18, RECIPIENT));
        _governorExecute(governor, targets, calldatas, "Send treasury assets");

        assertEq(treasuryAsset.balanceOf(RECIPIENT), 250e18);
        assertEq(treasuryAsset.balanceOf(address(vault)), 750e18);
    }

    function testTokenGovernorReplacesJointThroughTheExistingVaultHandoff() public {
        SinjohTreasuryFactory standardFactory = new SinjohTreasuryFactory();
        (SinjohJoint joint, SinjohTreasuryVault vault) =
            standardFactory.createStandardTreasury([ALICE, BOB, CAROL]);
        (SinjohGovernor governor, TimelockController timelock) = factory.createTokenHolderGovernor(
            address(subjectToken), "Successor Token Governor", _config()
        );

        vm.prank(ALICE);
        uint256 nominationId = joint.propose(
            address(vault),
            0,
            abi.encodeCall(SinjohTreasuryVault.nominateGovernor, (address(timelock)))
        );
        vm.prank(BOB);
        joint.confirm(nominationId);
        vm.prank(ALICE);
        joint.execute(nominationId);
        assertEq(vault.governor(), address(joint));
        assertEq(vault.pendingGovernor(), address(timelock));

        vm.warp(block.timestamp + vault.GOVERNOR_HANDOFF_DELAY());
        address[] memory handoffTargets = new address[](1);
        handoffTargets[0] = address(vault);
        bytes[] memory handoffCalldatas = new bytes[](1);
        handoffCalldatas[0] = abi.encodeCall(SinjohTreasuryVault.acceptGovernorship, ());
        _governorExecute(governor, handoffTargets, handoffCalldatas, "Accept vault governorship");
        assertEq(vault.governor(), address(timelock));

        MockERC20 treasuryAsset = new MockERC20();
        treasuryAsset.mint(address(vault), 100e18);
        address[] memory transferTargets = new address[](1);
        transferTargets[0] = address(vault);
        bytes[] memory transferCalldatas = new bytes[](1);
        transferCalldatas[0] =
            abi.encodeCall(vault.transfer, (address(treasuryAsset), 100e18, RECIPIENT));
        _governorExecute(governor, transferTargets, transferCalldatas, "Transfer after handoff");
        assertEq(treasuryAsset.balanceOf(RECIPIENT), 100e18);
    }

    function testVotingUsesHistoricalWalletBalancesWithoutDelegation() public {
        (SinjohTreasuryVault vault, SinjohGovernor governor,) =
            factory.createTokenHolderTreasury(address(subjectToken), "Token Treasury", _config());
        MockERC20 treasuryAsset = new MockERC20();
        treasuryAsset.mint(address(vault), 100e18);

        address[] memory targets = new address[](1);
        targets[0] = address(vault);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeCall(vault.transfer, (address(treasuryAsset), 1e18, RECIPIENT));
        string memory description = "Snapshot wallet balances";

        vm.prank(ALICE);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);
        vm.roll(governor.proposalSnapshot(proposalId) + 1);

        vm.prank(ALICE);
        assertTrue(subjectToken.transfer(BOB, 60e18));
        vm.prank(ALICE);
        governor.castVote(proposalId, 1);
        vm.prank(BOB);
        governor.castVote(proposalId, 1);

        (, uint256 forVotes,) = governor.proposalVotes(proposalId);
        assertEq(forVotes, 100e18);
        assertEq(subjectToken.delegates(ALICE), address(0));
        assertEq(subjectToken.delegates(BOB), address(0));
    }

    function testRejectsAnAddressThatDoesNotImplementHistoricalVotes() public {
        MockERC20 plainToken = new MockERC20();
        vm.expectRevert(
            abi.encodeWithSelector(
                TokenHolderTreasuryFactory.InvalidSubjectToken.selector, address(plainToken)
            )
        );
        factory.createTokenHolderTreasury(address(plainToken), "Unsupported", _config());
    }

    function testRejectsSubjectTokenWithoutPastVotes() public {
        MockVotesTokenWithoutPastVotes incompleteToken = new MockVotesTokenWithoutPastVotes();
        vm.expectRevert(
            abi.encodeWithSelector(
                TokenHolderTreasuryFactory.InvalidSubjectToken.selector, address(incompleteToken)
            )
        );
        factory.createTokenHolderTreasury(address(incompleteToken), "Unsupported", _config());
    }

    function testRejectsUnsafeGovernanceConfiguration() public {
        TokenHolderTreasuryFactory.GovernanceConfig memory config = _config();

        config.votingDelay = 0;
        vm.expectRevert(
            abi.encodeWithSelector(TokenHolderTreasuryFactory.InvalidVotingDelay.selector, 0)
        );
        factory.createTokenHolderTreasury(address(subjectToken), "Unsafe", config);

        config = _config();
        config.votingPeriod = 0;
        vm.expectRevert(
            abi.encodeWithSelector(TokenHolderTreasuryFactory.InvalidVotingPeriod.selector, 0)
        );
        factory.createTokenHolderTreasury(address(subjectToken), "Unsafe", config);

        config = _config();
        config.proposalThreshold = 0;
        vm.expectRevert(
            abi.encodeWithSelector(TokenHolderTreasuryFactory.InvalidProposalThreshold.selector, 0)
        );
        factory.createTokenHolderTreasury(address(subjectToken), "Unsafe", config);

        config = _config();
        config.quorumNumerator = 0;
        vm.expectRevert(
            abi.encodeWithSelector(TokenHolderTreasuryFactory.InvalidQuorumNumerator.selector, 0)
        );
        factory.createTokenHolderTreasury(address(subjectToken), "Unsafe", config);

        config = _config();
        config.timelockDelay = 1 hours - 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                TokenHolderTreasuryFactory.InvalidTimelockDelay.selector, 1 hours - 1
            )
        );
        factory.createTokenHolderTreasury(address(subjectToken), "Unsafe", config);
    }

    function _governorExecute(
        SinjohGovernor governor,
        address[] memory targets,
        bytes[] memory calldatas,
        string memory description
    ) private {
        uint256[] memory values = new uint256[](targets.length);
        bytes32 descriptionHash = keccak256(bytes(description));
        vm.prank(ALICE);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);
        vm.roll(governor.proposalSnapshot(proposalId) + 1);
        vm.prank(ALICE);
        governor.castVote(proposalId, 1);
        vm.roll(governor.proposalDeadline(proposalId) + 1);
        governor.queue(targets, values, calldatas, descriptionHash);
        vm.expectRevert();
        governor.execute(targets, values, calldatas, descriptionHash);
        vm.warp(block.timestamp + 1 hours);
        governor.execute(targets, values, calldatas, descriptionHash);
    }

    function _config()
        private
        pure
        returns (TokenHolderTreasuryFactory.GovernanceConfig memory config)
    {
        config = TokenHolderTreasuryFactory.GovernanceConfig({
            votingDelay: 1,
            votingPeriod: 5,
            proposalThreshold: 1e18,
            quorumNumerator: 10,
            timelockDelay: 1 hours,
            governorHandoffDelay: 3 days
        });
    }
}
