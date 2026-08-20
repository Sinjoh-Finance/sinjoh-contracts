// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IGovernanceController } from "../src/interfaces/IGovernanceController.sol";
import { SinjohStakingEngine } from "../src/SinjohStakingEngine.sol";
import { DeployStakingProtocol } from "../script/DeployStakingProtocol.s.sol";
import { TestBase } from "./TestBase.sol";
import { MockERC20 } from "./mocks/Mocks.sol";

contract DeployStakingProtocolHarness is DeployStakingProtocol {
    function deployForTest(Parameters memory parameters, bytes32 manifestHash, address deployer)
        external
        returns (Deployment memory deployment)
    {
        _validate(parameters, deployer);
        deployment = _deploy(parameters, manifestHash);
        _verify(parameters, deployment);
    }
}

contract DeployStakingProtocolTest is TestBase {
    uint256 private constant TESTNET_CHAIN_ID = 46_630;
    address private constant GUARDIAN = address(0xBEEF);
    address private constant PROTOCOL_FEE_RECIPIENT = address(0xFEE);
    address private constant ALICE = address(0xA11CE);

    DeployStakingProtocolHarness private script;
    MockERC20 private token;

    function setUp() public {
        vm.chainId(TESTNET_CHAIN_ID);
        script = new DeployStakingProtocolHarness();
        token = new MockERC20();
    }

    function testDeploysAndVerifiesCompleteStakingProtocol() public {
        DeployStakingProtocol.Deployment memory deployment =
            script.deployForTest(_parameters(true), keccak256("reviewed-manifest"), address(this));

        assertEq(deployment.controller.authority(), address(this));
        assertEq(
            uint256(deployment.controller.mode()), uint256(IGovernanceController.Mode.INDIVIDUAL)
        );
        assertEq(address(deployment.staking.stakingToken()), address(token));
        assertEq(deployment.staking.emergencyGuardian(), GUARDIAN);
        assertEq(address(deployment.votesAdapter.staking()), address(deployment.staking));
        assertEq(address(deployment.rewards.staking()), address(deployment.staking));
        assertEq(deployment.rewards.protocolFeeRecipient(), PROTOCOL_FEE_RECIPIENT);
        assertTrue(deployment.controllerRuntimeCodeHash != bytes32(0));
        assertTrue(deployment.stakingRuntimeCodeHash != bytes32(0));
        assertTrue(deployment.votesAdapterRuntimeCodeHash != bytes32(0));
        assertTrue(deployment.rewardsRuntimeCodeHash != bytes32(0));
    }

    function testVotesAdapterCanBeOmitted() public {
        DeployStakingProtocol.Deployment memory deployment =
            script.deployForTest(_parameters(false), keccak256("reviewed-manifest"), address(this));
        assertEq(address(deployment.votesAdapter), address(0));
    }

    function testRejectsWrongChainBeforeDeployment() public {
        DeployStakingProtocol.Parameters memory parameters = _parameters(true);
        vm.chainId(TESTNET_CHAIN_ID + 1);
        vm.expectPartialRevert(DeployStakingProtocol.WrongChain.selector);
        script.deployForTest(parameters, bytes32(0), address(this));
    }

    function testRejectsUnexpectedSigner() public {
        vm.expectPartialRevert(DeployStakingProtocol.WrongDeployer.selector);
        script.deployForTest(_parameters(true), bytes32(0), address(0xBAD));
    }

    function testRejectsGuardianThatIsAlsoGovernance() public {
        DeployStakingProtocol.Parameters memory parameters = _parameters(true);
        parameters.emergencyGuardian = address(this);
        vm.expectRevert(DeployStakingProtocol.InvalidGuardian.selector);
        script.deployForTest(parameters, bytes32(0), address(this));
    }

    function testRejectsWrongStakingTokenRuntimeHash() public {
        DeployStakingProtocol.Parameters memory parameters = _parameters(true);
        parameters.stakingTokenRuntimeCodeHash = bytes32(uint256(1));
        vm.expectPartialRevert(DeployStakingProtocol.WrongStakingTokenCodeHash.selector);
        script.deployForTest(parameters, bytes32(0), address(this));
    }

    function testPostDeploymentStakeFundCloseUnstakeAndClaimCanary() public {
        DeployStakingProtocol.Deployment memory deployment =
            script.deployForTest(_parameters(true), keccak256("reviewed-manifest"), address(this));

        vm.warp(100);
        token.mint(ALICE, 100e18);
        vm.startPrank(ALICE);
        token.approve(address(deployment.staking), type(uint256).max);
        deployment.staking.stake(100e18);
        vm.stopPrank();

        vm.warp(101);
        uint256 scheduleId = deployment.rewards
            .createSchedule(
                SinjohStakingEngine.ScheduleInput({
                    rewardToken: address(token),
                    interval: 30 minutes,
                    claimPeriod: 1 days,
                    permissionlessExecution: true,
                    fixedExecutorReward: 0,
                    executorRewardBps: 0,
                    executorRewardCap: 0,
                    unclaimedDestination: address(0xCAFE)
                })
            );

        token.mint(address(this), 10_000e18);
        token.approve(address(deployment.rewards), type(uint256).max);
        deployment.rewards.fund(address(token), 10_000e18, abi.encode(scheduleId));

        vm.prank(GUARDIAN);
        deployment.staking.pause();
        vm.startPrank(ALICE);
        deployment.staking.unstake(40e18);
        deployment.staking.unstake(60e18);
        vm.stopPrank();
        assertEq(deployment.staking.balanceOf(ALICE), 0);

        deployment.staking.resume();
        SinjohStakingEngine.DistributionSchedule memory schedule =
            deployment.rewards.getSchedule(scheduleId);
        vm.warp(schedule.nextEpoch);
        deployment.rewards.executeEpoch(scheduleId);

        assertEq(deployment.rewards.claimable(scheduleId, 1, ALICE), 9_900e18);
        uint64[] memory epochIds = new uint64[](1);
        epochIds[0] = 1;
        vm.prank(ALICE);
        deployment.rewards.claim(scheduleId, epochIds);

        assertEq(token.balanceOf(ALICE), 9_900e18 + 100e18);
        assertEq(deployment.rewards.totalLiability(address(token)), 0);
        assertEq(token.balanceOf(PROTOCOL_FEE_RECIPIENT), 100e18);
        assertEq(deployment.votesAdapter.getVotes(ALICE), 0);
        assertEq(deployment.votesAdapter.getPastVotes(ALICE, 100), 100e18);
    }

    function _parameters(bool deployVotesAdapter)
        private
        view
        returns (DeployStakingProtocol.Parameters memory parameters)
    {
        parameters = DeployStakingProtocol.Parameters({
            schemaVersion: 1,
            network: "robinhood-testnet",
            chainId: TESTNET_CHAIN_ID,
            expectedDeployer: address(this),
            governanceMode: IGovernanceController.Mode.INDIVIDUAL,
            authority: address(this),
            emergencyGuardian: GUARDIAN,
            stakingToken: address(token),
            stakingTokenRuntimeCodeHash: address(token).codehash,
            protocolFeeRecipient: PROTOCOL_FEE_RECIPIENT,
            deployVotesAdapter: deployVotesAdapter
        });
    }
}
