// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ProjectLiquidVotesWrapperV2 } from "../../src/token/ProjectLiquidVotesWrapperV2.sol";
import { ProjectIds } from "../../src/libraries/ProjectIds.sol";
import { MockRegistry } from "../mocks/MockRegistry.sol";
import { TestBase } from "../TestBase.sol";

contract LiquidUnderlying is ERC20 {
    constructor(address recipient, uint256 supply) ERC20("Public Pons Token", "PONS") {
        _mint(recipient, supply);
    }
}

contract TransferTaxUnderlying is ERC20 {
    bool public taxEnabled;

    constructor(address recipient, uint256 supply) ERC20("Taxed Token", "TAX") {
        _mint(recipient, supply);
    }

    function setTaxEnabled(bool enabled) external {
        taxEnabled = enabled;
    }

    function _update(address from, address to, uint256 value) internal override {
        if (!taxEnabled || from == address(0) || to == address(0) || value == 0) {
            super._update(from, to, value);
            return;
        }
        uint256 tax = value / 100;
        super._update(from, to, value - tax);
        super._update(from, address(0), tax);
    }
}

contract ProjectLiquidVotesWrapperV2Test is TestBase {
    uint256 private constant REFERENCE_SUPPLY = 1_000e18;
    address private constant CREATOR = address(0xC0FFEE);
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);

    MockRegistry private registry;
    LiquidUnderlying private underlying;
    ProjectLiquidVotesWrapperV2 private wrapper;

    function setUp() public {
        vm.warp(1_000);
        registry = new MockRegistry();
        underlying = new LiquidUnderlying(ALICE, REFERENCE_SUPPLY);
        wrapper = new ProjectLiquidVotesWrapperV2(
            address(registry),
            address(underlying),
            CREATOR,
            REFERENCE_SUPPLY,
            "Wrapped Public Pons Token",
            "wPONS",
            new address[](0)
        );
        vm.prank(ALICE);
        underlying.approve(address(wrapper), type(uint256).max);
    }

    function testWrapCreatesCurrentAndPastSelfVotes() public {
        vm.warp(1_100);
        vm.prank(ALICE);
        assertTrue(wrapper.depositFor(ALICE, 300e18));

        assertEq(wrapper.balanceOf(ALICE), 300e18);
        assertEq(wrapper.getVotes(ALICE), 300e18);
        assertEq(wrapper.delegates(ALICE), ALICE);
        assertEq(wrapper.eligibleVotingSupply(), 300e18);
        assertEq(underlying.balanceOf(address(wrapper)), 300e18);

        vm.warp(1_101);
        assertEq(wrapper.getPastVotes(ALICE, 1_100), 300e18);
        assertEq(wrapper.getPastTotalSupply(1_100), 300e18);
    }

    function testTransferMovesCurrentVotesWithoutChangingPastSnapshot() public {
        vm.warp(1_100);
        vm.prank(ALICE);
        wrapper.depositFor(ALICE, 300e18);

        vm.warp(1_200);
        vm.prank(ALICE);
        assertTrue(wrapper.transfer(BOB, 125e18));

        assertEq(wrapper.getVotes(ALICE), 175e18);
        assertEq(wrapper.getVotes(BOB), 125e18);
        assertEq(wrapper.eligibleVotingSupply(), 300e18);

        vm.warp(1_201);
        assertEq(wrapper.getPastVotes(ALICE, 1_100), 300e18);
        assertEq(wrapper.getPastVotes(BOB, 1_100), 0);
        assertEq(wrapper.getPastVotes(ALICE, 1_200), 175e18);
        assertEq(wrapper.getPastVotes(BOB, 1_200), 125e18);
        assertEq(wrapper.getPastTotalSupply(1_200), 300e18);
    }

    function testUnwrapBurnsVotesAndRedeemsExactlyOneToOne() public {
        vm.warp(1_100);
        vm.prank(ALICE);
        wrapper.depositFor(ALICE, 300e18);

        uint256 aliceUnderlyingBefore = underlying.balanceOf(ALICE);
        vm.warp(1_200);
        vm.prank(ALICE);
        assertTrue(wrapper.withdrawTo(ALICE, 120e18));

        assertEq(wrapper.balanceOf(ALICE), 180e18);
        assertEq(wrapper.getVotes(ALICE), 180e18);
        assertEq(wrapper.totalSupply(), 180e18);
        assertEq(wrapper.eligibleVotingSupply(), 180e18);
        assertEq(underlying.balanceOf(ALICE), aliceUnderlyingBefore + 120e18);
        assertEq(underlying.balanceOf(address(wrapper)), 180e18);

        vm.warp(1_201);
        assertEq(wrapper.getPastVotes(ALICE, 1_100), 300e18);
        assertEq(wrapper.getPastVotes(ALICE, 1_200), 180e18);
        assertEq(wrapper.getPastTotalSupply(1_200), 180e18);
    }

    function testSnapshotCannotBeDuplicatedByUnwrapTransferAndRewrap() public {
        vm.warp(1_100);
        vm.prank(ALICE);
        wrapper.depositFor(ALICE, 400e18);

        vm.warp(1_200);
        vm.prank(ALICE);
        wrapper.withdrawTo(BOB, 400e18);
        assertEq(wrapper.totalSupply(), 0);

        vm.prank(BOB);
        underlying.approve(address(wrapper), 400e18);
        vm.warp(1_300);
        vm.prank(BOB);
        wrapper.depositFor(BOB, 400e18);

        vm.warp(1_301);
        assertEq(wrapper.getPastVotes(ALICE, 1_100), 400e18);
        assertEq(wrapper.getPastVotes(BOB, 1_100), 0);
        assertEq(wrapper.getPastTotalSupply(1_100), 400e18);
        assertEq(wrapper.getPastVotes(ALICE, 1_200), 0);
        assertEq(wrapper.getPastVotes(BOB, 1_200), 0);
        assertEq(wrapper.getPastTotalSupply(1_200), 0);
        assertEq(wrapper.getPastVotes(ALICE, 1_300), 0);
        assertEq(wrapper.getPastVotes(BOB, 1_300), 400e18);
        assertEq(wrapper.getPastTotalSupply(1_300), 400e18);
        assertEq(wrapper.getVotes(ALICE) + wrapper.getVotes(BOB), wrapper.totalSupply());
        assertEq(wrapper.totalSupply(), underlying.balanceOf(address(wrapper)));
    }

    function testIdentityUsesUnderlyingSubjectAndReferenceSupply() public view {
        assertEq(address(wrapper.subject()), address(underlying));
        assertEq(address(wrapper.underlying()), address(underlying));
        assertEq(wrapper.registry(), address(registry));
        assertEq(wrapper.creator(), CREATOR);
        assertEq(
            wrapper.projectId(),
            ProjectIds.derive(block.chainid, address(registry), address(underlying))
        );
        assertEq(wrapper.initialSupply(), REFERENCE_SUPPLY);
    }

    function testDelegationIsUnsupported() public {
        vm.expectRevert(ProjectLiquidVotesWrapperV2.DelegationUnsupported.selector);
        wrapper.delegate(BOB);
    }

    function testWrapRejectsUnderlyingThatDeliversLessThanRequested() public {
        TransferTaxUnderlying taxed = new TransferTaxUnderlying(ALICE, REFERENCE_SUPPLY);
        ProjectLiquidVotesWrapperV2 taxedWrapper = _taxedWrapper(taxed);
        taxed.setTaxEnabled(true);
        vm.prank(ALICE);
        taxed.approve(address(taxedWrapper), 100e18);

        vm.prank(ALICE);
        vm.expectPartialRevert(ProjectLiquidVotesWrapperV2.UnexpectedBalanceDelta.selector);
        taxedWrapper.depositFor(ALICE, 100e18);

        assertEq(taxedWrapper.totalSupply(), 0);
        assertEq(taxed.balanceOf(address(taxedWrapper)), 0);
        assertEq(taxed.balanceOf(ALICE), REFERENCE_SUPPLY);
    }

    function testUnwrapRejectsUnderlyingThatDeliversLessThanRequested() public {
        TransferTaxUnderlying taxed = new TransferTaxUnderlying(ALICE, REFERENCE_SUPPLY);
        ProjectLiquidVotesWrapperV2 taxedWrapper = _taxedWrapper(taxed);
        vm.prank(ALICE);
        taxed.approve(address(taxedWrapper), 100e18);
        vm.prank(ALICE);
        taxedWrapper.depositFor(ALICE, 100e18);

        taxed.setTaxEnabled(true);
        vm.prank(ALICE);
        vm.expectPartialRevert(ProjectLiquidVotesWrapperV2.UnexpectedBalanceDelta.selector);
        taxedWrapper.withdrawTo(ALICE, 100e18);

        assertEq(taxedWrapper.balanceOf(ALICE), 100e18);
        assertEq(taxedWrapper.totalSupply(), 100e18);
        assertEq(taxed.balanceOf(address(taxedWrapper)), 100e18);
    }

    function _taxedWrapper(TransferTaxUnderlying taxed)
        private
        returns (ProjectLiquidVotesWrapperV2)
    {
        return new ProjectLiquidVotesWrapperV2(
            address(registry),
            address(taxed),
            CREATOR,
            REFERENCE_SUPPLY,
            "Wrapped Taxed Token",
            "wTAX",
            new address[](0)
        );
    }
}
