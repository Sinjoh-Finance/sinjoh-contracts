// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { ProjectVotesToken } from "../../src/token/ProjectVotesToken.sol";
import { ProjectIds } from "../../src/libraries/ProjectIds.sol";
import { MockRegistry } from "../mocks/MockRegistry.sol";
import { TestBase } from "../TestBase.sol";

contract ProjectVotesTokenTest is TestBase {
    uint256 private constant ALICE_KEY = 0xA11CE;
    uint256 private constant SUPPLY = 1_000e18;
    address private constant CREATOR = address(0xC0FFEE);
    address private constant BOB = address(0xB0B);
    address private constant EXCLUDED_ONE = address(0x1000);
    address private constant EXCLUDED_TWO = address(0x2000);

    MockRegistry private registry;
    ProjectVotesToken private token;
    address private alice;

    function setUp() public {
        vm.warp(1_000);
        alice = vm.addr(ALICE_KEY);
        registry = new MockRegistry();
        token = _deployDefault();
    }

    function testConstructorPublishesIdentityMetadataAndAllocations() public view {
        assertEq(keccak256(bytes(token.name())), keccak256(bytes("Project Token")));
        assertEq(keccak256(bytes(token.symbol())), keccak256(bytes("PROJECT")));
        assertEq(token.registry(), address(registry));
        assertEq(token.creator(), CREATOR);
        assertEq(
            token.projectId(), ProjectIds.derive(block.chainid, address(registry), address(token))
        );
        assertEq(token.initialSupply(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(alice), 800e18);
        assertEq(token.balanceOf(BOB), 200e18);
        assertEq(token.eligibleVotingSupply(), SUPPLY);
    }

    function testAutomaticVotingNeedsNoDelegation() public view {
        assertEq(token.getVotes(alice), 800e18);
        assertEq(token.getVotes(BOB), 200e18);
        assertEq(token.delegates(alice), alice);
    }

    function testConfiguredAndAutomaticExclusionsAreDiscoverable() public view {
        assertEq(token.votingExclusionCount(), 5);
        assertEq(token.votingExclusionAt(0), address(0));
        assertEq(token.votingExclusionAt(1), address(token));
        assertEq(token.votingExclusionAt(2), token.BURN_ADDRESS());
        assertEq(token.votingExclusionAt(3), EXCLUDED_ONE);
        assertEq(token.votingExclusionAt(4), EXCLUDED_TWO);
        assertTrue(token.isVotingExcluded(address(0)));
        assertTrue(token.isVotingExcluded(address(token)));
        assertTrue(token.isVotingExcluded(token.BURN_ADDRESS()));
        assertTrue(token.isVotingExcluded(EXCLUDED_ONE));
    }

    function testTransferWritesHistoricalWalletAndSupplyCheckpoints() public {
        vm.warp(1_100);
        vm.prank(alice);
        assertTrue(token.transfer(BOB, 100e18));

        vm.warp(1_101);
        assertEq(token.getPastVotes(alice, 1_099), 800e18);
        assertEq(token.getPastVotes(alice, 1_100), 700e18);
        assertEq(token.getPastVotes(BOB, 1_099), 200e18);
        assertEq(token.getPastVotes(BOB, 1_100), 300e18);
        assertEq(token.getPastTotalSupply(1_100), SUPPLY);
    }

    function testTransferIntoAndOutOfExcludedCustodyUpdatesEligibleSupply() public {
        vm.warp(1_100);
        vm.prank(alice);
        assertTrue(token.transfer(EXCLUDED_ONE, 125e18));
        assertEq(token.getVotes(EXCLUDED_ONE), 0);
        assertEq(token.eligibleVotingSupply(), SUPPLY - 125e18);

        vm.warp(1_200);
        vm.prank(EXCLUDED_ONE);
        assertTrue(token.transfer(BOB, 25e18));
        assertEq(token.eligibleVotingSupply(), SUPPLY - 100e18);

        vm.warp(1_201);
        assertEq(token.getPastTotalSupply(1_099), SUPPLY);
        assertEq(token.getPastTotalSupply(1_100), SUPPLY - 125e18);
        assertEq(token.getPastTotalSupply(1_200), SUPPLY - 100e18);
    }

    function testCanonicalBurnAddressHasNoVotesOrVotingSupply() public {
        address burnAddress = token.BURN_ADDRESS();
        vm.warp(1_100);
        vm.prank(alice);
        assertTrue(token.transfer(burnAddress, 300e18));

        assertEq(token.balanceOf(burnAddress), 300e18);
        assertEq(token.getVotes(burnAddress), 0);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.eligibleVotingSupply(), SUPPLY - 300e18);

        vm.warp(1_101);
        assertEq(token.getPastVotes(burnAddress, 1_100), 0);
        assertEq(token.getPastTotalSupply(1_100), SUPPLY - 300e18);
    }

    function testTrueBurnReducesRawAndEligibleSupply() public {
        vm.warp(1_100);
        vm.prank(alice);
        token.burn(50e18);

        assertEq(token.totalSupply(), SUPPLY - 50e18);
        assertEq(token.eligibleVotingSupply(), SUPPLY - 50e18);
        assertEq(token.getVotes(alice), 750e18);

        vm.warp(1_101);
        assertEq(token.getPastTotalSupply(1_100), SUPPLY - 50e18);
    }

    function testBurnFromUsesAllowanceAndCheckpoints() public {
        vm.prank(alice);
        token.approve(BOB, 40e18);
        vm.warp(1_100);
        vm.prank(BOB);
        token.burnFrom(alice, 40e18);

        assertEq(token.allowance(alice, BOB), 0);
        assertEq(token.getVotes(alice), 760e18);
        assertEq(token.eligibleVotingSupply(), SUPPLY - 40e18);
    }

    function testPermitSetsAllowance() public {
        uint256 deadline = 10_000;
        uint256 value = 25e18;
        bytes32 typeHash = keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );
        bytes32 structHash = keccak256(abi.encode(typeHash, alice, BOB, value, 0, deadline));
        bytes32 digest =
            keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ALICE_KEY, digest);

        token.permit(alice, BOB, value, deadline, v, r, s);
        assertEq(token.allowance(alice, BOB), value);
        assertEq(token.nonces(alice), 1);
    }

    function testMultipleChangesAtOneTimestampUseFinalCheckpointValue() public {
        vm.warp(1_100);
        vm.prank(alice);
        assertTrue(token.transfer(BOB, 10e18));
        vm.prank(alice);
        assertTrue(token.transfer(BOB, 20e18));
        vm.warp(1_101);

        assertEq(token.getPastVotes(alice, 1_100), 770e18);
        assertEq(token.getPastVotes(BOB, 1_100), 230e18);
    }

    function testDelegateAlwaysReverts() public {
        vm.expectRevert(ProjectVotesToken.DelegationUnsupported.selector);
        token.delegate(BOB);
    }

    function testDelegateBySigAlwaysReverts() public {
        vm.expectRevert(ProjectVotesToken.DelegationUnsupported.selector);
        token.delegateBySig(BOB, 0, 0, 0, bytes32(0), bytes32(0));
    }

    function testCurrentAndFutureHistoricalLookupsRevert() public {
        vm.expectPartialRevert(ProjectVotesToken.FutureLookup.selector);
        token.getPastVotes(alice, block.timestamp);
        vm.expectPartialRevert(ProjectVotesToken.FutureLookup.selector);
        token.getPastTotalSupply(block.timestamp + 1);
    }

    function testConstructorRejectsNonContractRegistry() public {
        vm.expectRevert(
            abi.encodeWithSelector(ProjectVotesToken.InvalidRegistry.selector, address(0x1234))
        );
        new ProjectVotesToken(
            "Project", "PRJ", address(0x1234), CREATOR, _oneAllocation(alice, 1), _noExclusions()
        );
    }

    function testConstructorRejectsZeroCreator() public {
        vm.expectRevert(ProjectVotesToken.InvalidCreator.selector);
        new ProjectVotesToken(
            "Project",
            "PRJ",
            address(registry),
            address(0),
            _oneAllocation(alice, 1),
            _noExclusions()
        );
    }

    function testConstructorRejectsEmptyMetadata() public {
        vm.expectRevert(ProjectVotesToken.InvalidMetadata.selector);
        new ProjectVotesToken(
            "", "PRJ", address(registry), CREATOR, _oneAllocation(alice, 1), _noExclusions()
        );
    }

    function testConstructorRejectsEmptyAllocations() public {
        ProjectVotesToken.TokenAllocation[] memory allocations =
            new ProjectVotesToken.TokenAllocation[](0);
        vm.expectRevert(ProjectVotesToken.InvalidAllocations.selector);
        new ProjectVotesToken(
            "Project", "PRJ", address(registry), CREATOR, allocations, _noExclusions()
        );
    }

    function testConstructorRejectsZeroAllocation() public {
        vm.expectRevert(
            abi.encodeWithSelector(ProjectVotesToken.InvalidAllocation.selector, uint256(0))
        );
        new ProjectVotesToken(
            "Project", "PRJ", address(registry), CREATOR, _oneAllocation(alice, 0), _noExclusions()
        );
    }

    function testConstructorRejectsDuplicateAllocationRecipient() public {
        ProjectVotesToken.TokenAllocation[] memory allocations =
            new ProjectVotesToken.TokenAllocation[](2);
        allocations[0] = ProjectVotesToken.TokenAllocation({ recipient: alice, amount: 1 });
        allocations[1] = ProjectVotesToken.TokenAllocation({ recipient: alice, amount: 2 });
        vm.expectRevert(
            abi.encodeWithSelector(ProjectVotesToken.DuplicateAllocation.selector, alice)
        );
        new ProjectVotesToken(
            "Project", "PRJ", address(registry), CREATOR, allocations, _noExclusions()
        );
    }

    function testConstructorRejectsUnsortedVotingExclusions() public {
        address[] memory exclusions = new address[](2);
        exclusions[0] = EXCLUDED_TWO;
        exclusions[1] = EXCLUDED_ONE;
        vm.expectPartialRevert(ProjectVotesToken.UnsortedVotingExclusions.selector);
        new ProjectVotesToken(
            "Project", "PRJ", address(registry), CREATOR, _oneAllocation(alice, 1), exclusions
        );
    }

    function testConstructorRejectsReservedVotingExclusion() public {
        address[] memory exclusions = new address[](1);
        exclusions[0] = token.BURN_ADDRESS();
        vm.expectRevert(
            abi.encodeWithSelector(
                ProjectVotesToken.ReservedVotingExclusion.selector, token.BURN_ADDRESS()
            )
        );
        new ProjectVotesToken(
            "Project", "PRJ", address(registry), CREATOR, _oneAllocation(alice, 1), exclusions
        );
    }

    function testAllSupplyMayStartInExcludedLaunchCustodyAndGainVotesOnDistribution() public {
        ProjectVotesToken custodyToken = new ProjectVotesToken(
            "Project",
            "PRJ",
            address(registry),
            CREATOR,
            _oneAllocation(EXCLUDED_ONE, SUPPLY),
            _defaultExclusions()
        );

        assertEq(custodyToken.totalSupply(), SUPPLY);
        assertEq(custodyToken.balanceOf(EXCLUDED_ONE), SUPPLY);
        assertEq(custodyToken.eligibleVotingSupply(), 0);
        assertEq(custodyToken.getVotes(EXCLUDED_ONE), 0);

        vm.warp(1_100);
        vm.prank(EXCLUDED_ONE);
        assertTrue(custodyToken.transfer(alice, 125e18));

        assertEq(custodyToken.getVotes(alice), 125e18);
        assertEq(custodyToken.eligibleVotingSupply(), 125e18);

        vm.warp(1_101);
        assertEq(custodyToken.getPastVotes(alice, 1_099), 0);
        assertEq(custodyToken.getPastVotes(alice, 1_100), 125e18);
        assertEq(custodyToken.getPastTotalSupply(1_099), 0);
        assertEq(custodyToken.getPastTotalSupply(1_100), 125e18);
    }

    function _deployDefault() private returns (ProjectVotesToken deployed) {
        ProjectVotesToken.TokenAllocation[] memory allocations =
            new ProjectVotesToken.TokenAllocation[](2);
        allocations[0] = ProjectVotesToken.TokenAllocation({ recipient: alice, amount: 800e18 });
        allocations[1] = ProjectVotesToken.TokenAllocation({ recipient: BOB, amount: 200e18 });
        deployed = new ProjectVotesToken(
            "Project Token",
            "PROJECT",
            address(registry),
            CREATOR,
            allocations,
            _defaultExclusions()
        );
    }

    function _oneAllocation(address recipient, uint256 amount)
        private
        pure
        returns (ProjectVotesToken.TokenAllocation[] memory allocations)
    {
        allocations = new ProjectVotesToken.TokenAllocation[](1);
        allocations[0] = ProjectVotesToken.TokenAllocation({ recipient: recipient, amount: amount });
    }

    function _defaultExclusions() private pure returns (address[] memory exclusions) {
        exclusions = new address[](2);
        exclusions[0] = EXCLUDED_ONE;
        exclusions[1] = EXCLUDED_TWO;
    }

    function _noExclusions() private pure returns (address[] memory exclusions) {
        exclusions = new address[](0);
    }
}
