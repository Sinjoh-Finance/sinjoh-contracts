// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { ProjectGovernorV2 } from "../src/governance/ProjectGovernorV2.sol";
import { ProjectTimelockV2 } from "../src/governance/ProjectTimelockV2.sol";
import { TokenGovernanceConfig } from "../src/governance/TokenGovernanceConfig.sol";
import { ProjectPoSNFT } from "../src/staking/ProjectPoSNFT.sol";
import { ProjectStakingPoolV2 } from "../src/staking/ProjectStakingPoolV2.sol";
import { ProjectVotesToken } from "../src/token/ProjectVotesToken.sol";
import { MockControlledModule } from "./mocks/MockControlledModule.sol";
import { MockRegistry } from "./mocks/MockRegistry.sol";
import { TestBase } from "./TestBase.sol";

abstract contract GovernanceTestBase is TestBase {
    uint256 internal constant START = 1_000_000;
    uint256 internal constant REFERENCE_SUPPLY = 1_000e18;
    uint64 internal constant LOCK_DURATION = 1 days;
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant CAROL = address(0xCA901);
    address internal constant OUTSIDER = address(0xBAD);
    address internal constant TREASURY = address(0x7EA5);
    address internal constant STAKING_CONTROLLER = address(0x600D);

    MockRegistry internal registry;
    ProjectVotesToken internal token;
    ProjectStakingPoolV2 internal stakingPool;
    ProjectPoSNFT internal posNFT;
    ProjectTimelockV2 internal timelock;
    ProjectGovernorV2 internal governor;
    MockControlledModule internal module;

    function _setUpLiquidGovernance() internal {
        vm.warp(START);
        registry = new MockRegistry();
        token = _deployToken(registry);
        _deployGovernance(address(token), _defaultConfig());
        module = new MockControlledModule(address(timelock));
        vm.warp(START + 1);
    }

    function _setUpStakedGovernance(bool createStakes) internal {
        vm.warp(START);
        registry = new MockRegistry();
        token = _deployToken(registry);
        stakingPool = new ProjectStakingPoolV2(
            address(registry),
            address(token),
            TREASURY,
            STAKING_CONTROLLER,
            address(0),
            LOCK_DURATION,
            new address[](0)
        );
        posNFT = stakingPool.posNFT();
        if (createStakes) {
            _stake(ALICE, 600e18);
            _stake(BOB, 300e18);
            _stake(CAROL, 100e18);
        }
        _deployGovernance(address(stakingPool), _defaultConfig());
        module = new MockControlledModule(address(timelock));
        vm.warp(START + 1);
    }

    function _deployGovernance(address voteSource, TokenGovernanceConfig memory config) internal {
        timelock = new ProjectTimelockV2(
            address(registry), address(token), voteSource, voteSource != address(token), config
        );
        governor = timelock.governor();
    }

    function _deployToken(MockRegistry registry_) internal returns (ProjectVotesToken deployed) {
        ProjectVotesToken.TokenAllocation[] memory allocations =
            new ProjectVotesToken.TokenAllocation[](3);
        allocations[0] = ProjectVotesToken.TokenAllocation({ recipient: ALICE, amount: 600e18 });
        allocations[1] = ProjectVotesToken.TokenAllocation({ recipient: BOB, amount: 300e18 });
        allocations[2] = ProjectVotesToken.TokenAllocation({ recipient: CAROL, amount: 100e18 });
        deployed = new ProjectVotesToken(
            "Project Token", "PROJECT", address(registry_), ALICE, allocations, new address[](0)
        );
    }

    function _defaultConfig() internal pure returns (TokenGovernanceConfig memory config) {
        config = TokenGovernanceConfig({
            votingDelay: 1 days,
            votingPeriod: 3 days,
            proposalThresholdBps: 100,
            quorumBps: 1_000,
            timelockDelay: 1 days,
            referenceSupply: REFERENCE_SUPPLY
        });
    }

    function _stake(address holder, uint256 amount) internal returns (uint256 tokenId) {
        vm.startPrank(holder);
        token.approve(address(stakingPool), amount);
        tokenId = stakingPool.stake(amount, holder);
        vm.stopPrank();
    }

    function _proposalData(uint256 value)
        internal
        view
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas)
    {
        targets = new address[](1);
        values = new uint256[](1);
        calldatas = new bytes[](1);
        targets[0] = address(module);
        calldatas[0] = abi.encodeCall(module.setValue, (value));
    }

    function _propose(address proposer, uint256 value, string memory description)
        internal
        returns (uint256 proposalId)
    {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) =
            _proposalData(value);
        vm.prank(proposer);
        proposalId = governor.propose(targets, values, calldatas, description);
    }

    function _activate(uint256 proposalId) internal {
        vm.warp(governor.proposalSnapshot(proposalId) + 1);
    }

    function _finishVoting(uint256 proposalId) internal {
        vm.warp(governor.proposalDeadline(proposalId) + 1);
    }

    function _queue(uint256 value, string memory description)
        internal
        returns (uint256 proposalId)
    {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) =
            _proposalData(value);
        proposalId = governor.queue(targets, values, calldatas, keccak256(bytes(description)));
    }

    function _execute(uint256 value, string memory description)
        internal
        returns (uint256 proposalId)
    {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) =
            _proposalData(value);
        proposalId = governor.execute(targets, values, calldatas, keccak256(bytes(description)));
    }
}
