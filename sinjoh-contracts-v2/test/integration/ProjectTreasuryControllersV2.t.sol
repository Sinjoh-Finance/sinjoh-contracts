// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { ProjectGovernorV2 } from "../../src/governance/ProjectGovernorV2.sol";
import { ProjectTimelockV2 } from "../../src/governance/ProjectTimelockV2.sol";
import { TokenGovernanceConfig } from "../../src/governance/TokenGovernanceConfig.sol";
import { ProjectMultisigAccountV2 } from "../../src/multisig/ProjectMultisigAccountV2.sol";
import { ProjectTreasuryVaultV2 } from "../../src/treasury/ProjectTreasuryVaultV2.sol";
import { ProjectVotesToken } from "../../src/token/ProjectVotesToken.sol";
import { MockRegistry } from "../mocks/MockRegistry.sol";
import {
    MockProjectPriceGuard,
    MockProjectSwapAdapter,
    MockTreasuryERC20
} from "../mocks/MockTreasuryIntegrations.sol";
import { TestBase } from "../TestBase.sol";

contract ProjectTreasuryControllersV2IntegrationTest is TestBase {
    uint256 private constant START = 1_000_000;
    address private constant ALICE = address(0xA11CE);
    address private constant SIGNER_A = address(0xA1);
    address private constant SIGNER_B = address(0xB2);
    address private constant SIGNER_C = address(0xC3);
    address private constant RECIPIENT = address(0xBEEF);
    bytes private constant ROUTE_DATA = hex"010203";

    MockRegistry private registry;
    ProjectVotesToken private token;
    MockTreasuryERC20 private assetA;
    MockTreasuryERC20 private assetB;
    MockProjectSwapAdapter private adapter;
    MockProjectPriceGuard private priceGuard;
    bytes32 private approvalRoot;

    function setUp() public {
        vm.warp(START);
        registry = MockRegistry(vm.deployCode("MockRegistry.sol:MockRegistry"));
        ProjectVotesToken.TokenAllocation[] memory allocations =
            new ProjectVotesToken.TokenAllocation[](1);
        allocations[0] = ProjectVotesToken.TokenAllocation({ recipient: ALICE, amount: 1_000e18 });
        token = ProjectVotesToken(
            vm.deployCode(
                "ProjectVotesToken.sol:ProjectVotesToken",
                abi.encode(
                    "Project Token",
                    "PROJECT",
                    address(registry),
                    ALICE,
                    allocations,
                    new address[](0)
                )
            )
        );
        assetA = MockTreasuryERC20(
            vm.deployCode(
                "MockTreasuryIntegrations.sol:MockTreasuryERC20", abi.encode("Asset A", "ASSETA")
            )
        );
        assetB = MockTreasuryERC20(
            vm.deployCode(
                "MockTreasuryIntegrations.sol:MockTreasuryERC20", abi.encode("Asset B", "ASSETB")
            )
        );
        adapter = MockProjectSwapAdapter(
            payable(vm.deployCode("MockTreasuryIntegrations.sol:MockProjectSwapAdapter"))
        );
        priceGuard = MockProjectPriceGuard(
            vm.deployCode("MockTreasuryIntegrations.sol:MockProjectPriceGuard")
        );
        approvalRoot = _approvalLeaf();
        priceGuard.setQuote(20e18, 3_592_000);
        adapter.configure(20e18, type(uint256).max, false);
        assetB.mint(address(adapter), 40e18);
    }

    function testMultisigAndTokenGovernanceExecuteSameTreasuryABI() public {
        ProjectMultisigAccountV2 multisig = ProjectMultisigAccountV2(
            payable(vm.deployCode(
                    "ProjectMultisigAccountV2.sol:ProjectMultisigAccountV2",
                    abi.encode(address(registry), address(token), [SIGNER_A, SIGNER_B, SIGNER_C])
                ))
        );
        TokenGovernanceConfig memory config = TokenGovernanceConfig({
            votingDelay: 1 days,
            votingPeriod: 3 days,
            proposalThresholdBps: 100,
            quorumBps: 1_000,
            timelockDelay: 1 days,
            referenceSupply: 1_000e18
        });
        ProjectTimelockV2 timelock = ProjectTimelockV2(
            payable(vm.deployCode(
                    "ProjectTimelockV2.sol:ProjectTimelockV2",
                    abi.encode(address(registry), address(token), address(token), false, config)
                ))
        );
        ProjectTreasuryVaultV2 multisigVault = _deployVault(address(multisig));
        ProjectTreasuryVaultV2 governanceVault = _deployVault(address(timelock));
        _deposit(multisigVault, 100e18);
        _deposit(governanceVault, 100e18);

        (
            address[] memory multisigTargets,
            uint256[] memory multisigValues,
            bytes[] memory multisigData
        ) = _treasuryActions(multisigVault);
        vm.prank(SIGNER_A);
        bytes32 transactionId = multisig.submit(multisigTargets, multisigValues, multisigData);
        vm.prank(SIGNER_B);
        multisig.confirm(transactionId);
        multisig.execute(transactionId);

        ProjectGovernorV2 governor = timelock.governor();
        (address[] memory govTargets, uint256[] memory govValues, bytes[] memory govData) =
            _treasuryActions(governanceVault);
        string memory description = "Execute Treasury actions";
        vm.warp(START + 1);
        vm.prank(ALICE);
        uint256 proposalId = governor.propose(govTargets, govValues, govData, description);
        vm.warp(governor.proposalSnapshot(proposalId) + 1);
        vm.prank(ALICE);
        governor.castVote(proposalId, 1);
        vm.warp(governor.proposalDeadline(proposalId) + 1);
        governor.queue(govTargets, govValues, govData, keccak256(bytes(description)));
        vm.warp(governor.proposalEta(proposalId));
        governor.execute(govTargets, govValues, govData, keccak256(bytes(description)));

        _assertActionsCompleted(multisigVault);
        _assertActionsCompleted(governanceVault);
        assertEq(assetA.balanceOf(RECIPIENT), 20e18);
    }

    function _deployVault(address controller) private returns (ProjectTreasuryVaultV2 deployed) {
        deployed = ProjectTreasuryVaultV2(
            payable(vm.deployCode(
                    "ProjectTreasuryVaultV2.sol:ProjectTreasuryVaultV2",
                    abi.encode(
                        address(registry),
                        address(token),
                        ALICE,
                        controller,
                        approvalRoot,
                        address(0)
                    )
                ))
        );
    }

    function _deposit(ProjectTreasuryVaultV2 target, uint256 amount) private {
        assetA.mint(ALICE, amount);
        vm.startPrank(ALICE);
        assetA.approve(address(target), amount);
        target.deposit(address(assetA), amount, false);
        vm.stopPrank();
    }

    function _treasuryActions(ProjectTreasuryVaultV2 target)
        private
        view
        returns (address[] memory targets, uint256[] memory values, bytes[] memory data)
    {
        targets = new address[](2);
        values = new uint256[](2);
        data = new bytes[](2);
        targets[0] = address(target);
        targets[1] = address(target);
        data[0] = abi.encodeCall(target.send, (address(assetA), 10e18, RECIPIENT));
        data[1] = abi.encodeCall(
            target.swap,
            (
                address(adapter),
                address(priceGuard),
                address(assetA),
                address(assetB),
                40e18,
                20e18,
                ROUTE_DATA,
                bytes(""),
                new bytes32[](0)
            )
        );
    }

    function _assertActionsCompleted(ProjectTreasuryVaultV2 target) private view {
        assertEq(target.accountedBalance(address(assetA)), 50e18);
        assertEq(target.accountedBalance(address(assetB)), 20e18);
        assertEq(assetA.balanceOf(address(target)), 50e18);
        assertEq(assetB.balanceOf(address(target)), 20e18);
    }

    function _approvalLeaf() private view returns (bytes32) {
        bytes32 inner = keccak256(
            abi.encode(
                keccak256("SINJOH_V2_SWAP_INTEGRATION_APPROVAL"),
                block.chainid,
                address(adapter),
                address(adapter).codehash,
                address(priceGuard),
                address(priceGuard).codehash
            )
        );
        return keccak256(bytes.concat(inner));
    }
}
