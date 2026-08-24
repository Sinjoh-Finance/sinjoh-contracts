// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { ProjectVotesToken } from "../../src/token/ProjectVotesToken.sol";
import { MockRegistry } from "../mocks/MockRegistry.sol";
import { InvariantTestBase } from "../TestBase.sol";

contract ProjectVotesTokenHandler {
    ProjectVotesToken public immutable token;
    address public immutable excluded;

    constructor(ProjectVotesToken token_, address excluded_) {
        token = token_;
        excluded = excluded_;
    }

    function sendToBurn(uint256 rawAmount) external {
        uint256 balance = token.balanceOf(address(this));
        require(token.transfer(token.BURN_ADDRESS(), rawAmount % (balance + 1)), "TRANSFER_FAILED");
    }

    function sendToExcluded(uint256 rawAmount) external {
        uint256 balance = token.balanceOf(address(this));
        require(token.transfer(excluded, rawAmount % (balance + 1)), "TRANSFER_FAILED");
    }

    function burn(uint256 rawAmount) external {
        uint256 balance = token.balanceOf(address(this));
        token.burn(rawAmount % (balance + 1));
    }
}

contract ProjectVotesTokenInvariantTest is InvariantTestBase {
    uint256 private constant SUPPLY = 1_000_000e18;
    address private constant EXCLUDED = address(0xFEE1);

    ProjectVotesToken private token;
    ProjectVotesTokenHandler private handler;

    function setUp() public {
        vm.warp(1_000);
        MockRegistry registry = new MockRegistry();
        ProjectVotesToken.TokenAllocation[] memory allocations =
            new ProjectVotesToken.TokenAllocation[](1);
        address[] memory exclusions = new address[](1);
        exclusions[0] = EXCLUDED;

        // Predicting the handler is unnecessary: mint to this test, then transfer after deployment.
        allocations[0] =
            ProjectVotesToken.TokenAllocation({ recipient: address(this), amount: SUPPLY });
        token = new ProjectVotesToken(
            "Project", "PRJ", address(registry), address(this), allocations, exclusions
        );
        handler = new ProjectVotesTokenHandler(token, EXCLUDED);
        assertTrue(token.transfer(address(handler), SUPPLY));
        targetContract(address(handler));
    }

    function invariantEligibleSupplyEqualsEligibleBalances() public view {
        assertEq(token.eligibleVotingSupply(), token.balanceOf(address(handler)));
    }

    function invariantRawSupplyReconcilesAllTrackedBalances() public view {
        uint256 tracked = token.balanceOf(address(handler)) + token.balanceOf(EXCLUDED)
            + token.balanceOf(token.BURN_ADDRESS());
        assertEq(token.totalSupply(), tracked);
    }

    function invariantExcludedAddressesNeverHaveVotes() public view {
        assertEq(token.getVotes(EXCLUDED), 0);
        assertEq(token.getVotes(token.BURN_ADDRESS()), 0);
        assertEq(token.getVotes(address(token)), 0);
    }
}
