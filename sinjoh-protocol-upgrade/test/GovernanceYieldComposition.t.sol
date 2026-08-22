// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { SinjohJoint } from "@sinjoh-treasury/SinjohJoint.sol";
import { SinjohTreasuryVault } from "@sinjoh-treasury/SinjohTreasuryVault.sol";
import { AddressGovernanceController } from "../src/governance/AddressGovernanceController.sol";
import { Governed } from "../src/governance/Governed.sol";
import { SinjohGovernor } from "../src/governance/SinjohGovernor.sol";
import { IGovernanceController } from "../src/interfaces/IGovernanceController.sol";
import { YieldBasket } from "../src/YieldBasket.sol";
import { TestBase } from "./TestBase.sol";
import { MockDirectVotesToken, MockERC20, MockFundable, MockYieldAdapter } from "./mocks/Mocks.sol";

contract GovernanceYieldCompositionTest is TestBase {
    address private constant GUARDIAN = address(0xBEEF);
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant CAROL = address(0xCA401);

    function testJointControlsTreasuryFundingHarvestAndPrincipalReturn() public {
        MockERC20 asset = new MockERC20();
        MockERC20 reward = new MockERC20();
        MockFundable sink = new MockFundable();
        address[3] memory signers = [ALICE, BOB, CAROL];
        SinjohJoint joint = new SinjohJoint(signers, 30 days);
        SinjohTreasuryVault treasury =
            new SinjohTreasuryVault(address(joint), 3 days, address(0), 0);
        AddressGovernanceController controller =
            new AddressGovernanceController(address(joint), IGovernanceController.Mode.MULTISIG);
        YieldBasket basket =
            new YieldBasket(controller, GUARDIAN, IERC20(address(asset)), address(treasury));
        MockYieldAdapter adapter = new MockYieldAdapter(address(asset), reward);
        adapter.setBasket(address(basket));

        _jointExecute(
            joint,
            address(basket),
            abi.encodeCall(basket.configureAdapter, (adapter, uint16(10_000), uint32(30 minutes)))
        );
        YieldBasket.RewardRouteInput[] memory routes = new YieldBasket.RewardRouteInput[](1);
        routes[0] = YieldBasket.RewardRouteInput({
            rewardToken: address(reward), distributor: address(sink), distributionConfig: ""
        });
        _jointExecute(
            joint, address(basket), abi.encodeCall(basket.setAdapterRewardRoutes, (adapter, routes))
        );

        asset.mint(address(treasury), 1_000e18);
        address[] memory fundingTargets = new address[](3);
        uint256[] memory fundingValues = new uint256[](3);
        bytes[] memory fundingData = new bytes[](3);
        fundingTargets[0] = address(basket);
        fundingData[0] = abi.encodeCall(basket.prepareTreasuryFunding, (1_000e18));
        fundingTargets[1] = address(treasury);
        fundingData[1] =
            abi.encodeCall(treasury.transfer, (address(asset), 1_000e18, address(basket)));
        fundingTargets[2] = address(basket);
        fundingData[2] = abi.encodeCall(basket.completeTreasuryFunding, ());
        _jointExecute(
            joint,
            address(joint),
            abi.encodeCall(joint.executeBatch, (fundingTargets, fundingValues, fundingData))
        );
        _jointExecute(
            joint, address(basket), abi.encodeCall(basket.allocate, (adapter, uint128(1_000e18)))
        );

        adapter.setNextReward(25e18);
        vm.warp(block.timestamp + 30 minutes);
        basket.harvest(adapter);
        assertEq(sink.funded(address(reward)), 25e18);

        vm.prank(GUARDIAN);
        basket.pause();
        vm.prank(GUARDIAN);
        vm.expectRevert(Governed.Unauthorized.selector);
        basket.withdrawIdlePrincipal(1);

        _jointExecute(
            joint, address(basket), abi.encodeCall(basket.withdrawFromAdapter, (adapter, 1_000e18))
        );
        _jointExecute(
            joint, address(basket), abi.encodeCall(basket.withdrawIdlePrincipal, (1_000e18))
        );
        assertEq(asset.balanceOf(address(treasury)), 1_000e18);
        assertEq(address(basket.governanceController()), address(controller));
        assertEq(basket.emergencyGuardian(), GUARDIAN);
        assertEq(basket.treasury(), address(treasury));
    }

    function testTokenGovernorBatchControlsWholeTreasuryBasketLifecycle() public {
        MockERC20 asset = new MockERC20();
        MockERC20 reward = new MockERC20();
        MockFundable sink = new MockFundable();
        MockDirectVotesToken subjectToken = new MockDirectVotesToken(ALICE, 100e18);
        vm.roll(block.number + 1);

        address[] memory noProposers = new address[](0);
        address[] memory executors = new address[](1);
        executors[0] = address(0);
        TimelockController timelock =
            new TimelockController(1 hours, noProposers, executors, address(this));
        SinjohGovernor governor = new SinjohGovernor("Sinjoh", subjectToken, timelock, 1, 5, 0, 10);
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));
        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), address(this));

        AddressGovernanceController controller = new AddressGovernanceController(
            address(timelock), IGovernanceController.Mode.TOKEN_GOVERNOR
        );
        SinjohTreasuryVault treasury =
            new SinjohTreasuryVault(address(timelock), 3 days, address(0), 0);
        YieldBasket basket =
            new YieldBasket(controller, GUARDIAN, IERC20(address(asset)), address(treasury));
        MockYieldAdapter adapter = new MockYieldAdapter(address(asset), reward);
        adapter.setBasket(address(basket));
        asset.mint(address(treasury), 1_000e18);

        YieldBasket.RewardRouteInput[] memory routes = new YieldBasket.RewardRouteInput[](1);
        routes[0] = YieldBasket.RewardRouteInput({
            rewardToken: address(reward), distributor: address(sink), distributionConfig: ""
        });
        address[] memory targets = new address[](6);
        bytes[] memory calldatas = new bytes[](6);
        targets[0] = address(basket);
        calldatas[0] = abi.encodeCall(
            basket.configureAdapter, (adapter, uint16(10_000), uint32(30 minutes))
        );
        targets[1] = address(basket);
        calldatas[1] = abi.encodeCall(basket.setAdapterRewardRoutes, (adapter, routes));
        targets[2] = address(basket);
        calldatas[2] = abi.encodeCall(basket.prepareTreasuryFunding, (1_000e18));
        targets[3] = address(treasury);
        calldatas[3] =
            abi.encodeCall(treasury.transfer, (address(asset), 1_000e18, address(basket)));
        targets[4] = address(basket);
        calldatas[4] = abi.encodeCall(basket.completeTreasuryFunding, ());
        targets[5] = address(basket);
        calldatas[5] = abi.encodeCall(basket.allocate, (adapter, uint128(1_000e18)));
        _governorExecute(governor, targets, calldatas, "Fund and allocate treasury basket");

        adapter.setNextReward(25e18);
        vm.warp(block.timestamp + 30 minutes);
        basket.harvest(adapter);
        assertEq(sink.funded(address(reward)), 25e18);

        address[] memory exitTargets = new address[](2);
        bytes[] memory exitCalldatas = new bytes[](2);
        exitTargets[0] = address(basket);
        exitCalldatas[0] = abi.encodeCall(basket.withdrawFromAdapter, (adapter, 1_000e18));
        exitTargets[1] = address(basket);
        exitCalldatas[1] = abi.encodeCall(basket.withdrawIdlePrincipal, (1_000e18));
        _governorExecute(governor, exitTargets, exitCalldatas, "Return basket principal");

        assertEq(asset.balanceOf(address(treasury)), 1_000e18);
        assertTrue(!timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), address(this)));
        assertTrue(timelock.hasRole(timelock.PROPOSER_ROLE(), address(governor)));
        assertTrue(timelock.hasRole(timelock.CANCELLER_ROLE(), address(governor)));
        assertTrue(timelock.hasRole(timelock.EXECUTOR_ROLE(), address(0)));
    }

    function _jointExecute(SinjohJoint joint, address target, bytes memory data) private {
        vm.prank(ALICE);
        uint256 proposalId = joint.propose(target, 0, data);
        vm.prank(BOB);
        joint.confirm(proposalId);
        vm.prank(ALICE);
        joint.execute(proposalId);
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
        vm.warp(block.timestamp + 1 hours);
        governor.execute(targets, values, calldatas, descriptionHash);
    }
}
