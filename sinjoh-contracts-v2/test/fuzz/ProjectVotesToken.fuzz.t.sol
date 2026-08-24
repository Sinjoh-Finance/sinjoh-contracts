// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { ProjectVotesToken } from "../../src/token/ProjectVotesToken.sol";
import { MockRegistry } from "../mocks/MockRegistry.sol";
import { TestBase } from "../TestBase.sol";

contract ProjectVotesTokenFuzzTest is TestBase {
    uint256 private constant SUPPLY = 1_000_000e18;
    address private constant HOLDER = address(0xA11CE);
    address private constant RECEIVER = address(0xB0B);
    address private constant EXCLUDED = address(0xFEE1);

    ProjectVotesToken private token;

    function setUp() public {
        vm.warp(1_000);
        MockRegistry registry = new MockRegistry();
        ProjectVotesToken.TokenAllocation[] memory allocations =
            new ProjectVotesToken.TokenAllocation[](1);
        allocations[0] = ProjectVotesToken.TokenAllocation({ recipient: HOLDER, amount: SUPPLY });
        address[] memory exclusions = new address[](1);
        exclusions[0] = EXCLUDED;
        token = new ProjectVotesToken(
            "Project", "PRJ", address(registry), HOLDER, allocations, exclusions
        );
    }

    function testFuzzEligibleTransferConservesVotingSupply(uint256 rawAmount) public {
        uint256 amount = rawAmount % (SUPPLY + 1);
        vm.prank(HOLDER);
        assertTrue(token.transfer(RECEIVER, amount));
        assertEq(token.eligibleVotingSupply(), SUPPLY);
        assertEq(token.getVotes(HOLDER) + token.getVotes(RECEIVER), SUPPLY);
    }

    function testFuzzExcludedTransferRemovesAndRestoresVotingSupply(uint256 rawAmount) public {
        uint256 amount = rawAmount % (SUPPLY + 1);
        vm.prank(HOLDER);
        assertTrue(token.transfer(EXCLUDED, amount));
        assertEq(token.eligibleVotingSupply(), SUPPLY - amount);
        assertEq(token.getVotes(EXCLUDED), 0);

        vm.prank(EXCLUDED);
        assertTrue(token.transfer(RECEIVER, amount));
        assertEq(token.eligibleVotingSupply(), SUPPLY);
        assertEq(token.getVotes(RECEIVER), amount);
    }

    function testFuzzBurnAddressNeverReceivesVotes(uint256 rawAmount) public {
        uint256 amount = rawAmount % (SUPPLY + 1);
        address burnAddress = token.BURN_ADDRESS();
        vm.prank(HOLDER);
        assertTrue(token.transfer(burnAddress, amount));
        assertEq(token.getVotes(burnAddress), 0);
        assertEq(token.eligibleVotingSupply(), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzTrueBurnReducesBothSupplies(uint256 rawAmount) public {
        uint256 amount = rawAmount % (SUPPLY + 1);
        vm.prank(HOLDER);
        token.burn(amount);
        assertEq(token.totalSupply(), SUPPLY - amount);
        assertEq(token.eligibleVotingSupply(), SUPPLY - amount);
    }

    function testFuzzHistoricalVotesAreUnaffectedByLaterTransfers(
        uint256 rawFirst,
        uint256 rawSecond
    ) public {
        uint256 first = rawFirst % (SUPPLY + 1);
        vm.prank(HOLDER);
        assertTrue(token.transfer(RECEIVER, first));
        uint48 snapshot = token.clock();

        vm.warp(uint256(snapshot) + 1);
        uint256 remaining = SUPPLY - first;
        uint256 second = rawSecond % (remaining + 1);
        vm.prank(HOLDER);
        assertTrue(token.transfer(RECEIVER, second));

        assertEq(token.getPastVotes(HOLDER, snapshot), SUPPLY - first);
        assertEq(token.getPastVotes(RECEIVER, snapshot), first);
        assertEq(token.getPastTotalSupply(snapshot), SUPPLY);
    }
}
