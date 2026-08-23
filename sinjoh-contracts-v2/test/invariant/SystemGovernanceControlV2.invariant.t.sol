// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Vm } from "forge-std/Vm.sol";
import { ProjectMultisigAccountV2 } from "../../src/multisig/ProjectMultisigAccountV2.sol";
import { ProjectVotesToken } from "../../src/token/ProjectVotesToken.sol";
import { ProjectTreasuryVaultV2 } from "../../src/treasury/ProjectTreasuryVaultV2.sol";
import { MockRegistry } from "../mocks/MockRegistry.sol";
import { MockTreasuryERC20 } from "../mocks/MockTreasuryIntegrations.sol";
import { TestBase } from "../TestBase.sol";

contract SystemGovernanceControlV2Handler {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    address private constant SIGNER_A = address(0xA1);
    address private constant SIGNER_B = address(0xB2);
    address private constant OUTSIDER = address(0xBAD);

    ProjectMultisigAccountV2 public immutable multisig;
    ProjectTreasuryVaultV2 public immutable treasury;
    MockTreasuryERC20 public immutable asset;
    address public immutable recipient;

    bytes32 public pendingTransaction;
    uint256 public totalDeposited;
    uint256 public unauthorizedSendSuccesses;

    constructor(
        ProjectMultisigAccountV2 multisig_,
        ProjectTreasuryVaultV2 treasury_,
        MockTreasuryERC20 asset_,
        address recipient_
    ) {
        multisig = multisig_;
        treasury = treasury_;
        asset = asset_;
        recipient = recipient_;
    }

    function deposit(uint128 rawAmount) external {
        uint256 amount = uint256(rawAmount % 1_000_000e18) + 1;
        totalDeposited += amount;
        asset.mint(address(this), amount);
        asset.approve(address(treasury), amount);
        treasury.deposit(address(asset), amount, false);
    }

    function submitSend(uint128 rawAmount) external {
        if (pendingTransaction != bytes32(0)) return;
        uint256 available = treasury.availableBalance(address(asset));
        if (available == 0) return;
        uint256 amount = uint256(rawAmount % available) + 1;
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(treasury);
        calldatas[0] = abi.encodeCall(treasury.send, (address(asset), amount, recipient));
        vm.prank(SIGNER_A);
        try multisig.submit(targets, values, calldatas) returns (bytes32 transactionId) {
            pendingTransaction = transactionId;
        } catch { }
    }

    function confirmSend() external {
        bytes32 transactionId = pendingTransaction;
        if (transactionId == bytes32(0)) return;
        vm.prank(SIGNER_B);
        try multisig.confirm(transactionId) { } catch { }
    }

    function executeSend() external {
        bytes32 transactionId = pendingTransaction;
        if (transactionId == bytes32(0)) return;
        try multisig.execute(transactionId) {
            pendingTransaction = bytes32(0);
        } catch { }
    }

    function attemptControllerBypass(uint128 rawAmount) external {
        uint256 available = treasury.availableBalance(address(asset));
        if (available == 0) return;
        uint256 amount = uint256(rawAmount % available) + 1;
        vm.prank(OUTSIDER);
        (bool success,) = address(treasury)
            .call(abi.encodeCall(treasury.send, (address(asset), amount, recipient)));
        if (success) unauthorizedSendSuccesses += 1;
    }
}

contract SystemGovernanceControlV2InvariantTest is TestBase {
    address private constant SIGNER_A = address(0xA1);
    address private constant SIGNER_B = address(0xB2);
    address private constant SIGNER_C = address(0xC3);
    address private constant CREATOR = address(0xC0FFEE);
    address private constant RECIPIENT = address(0xBEEF);

    MockRegistry private registry;
    ProjectVotesToken private token;
    ProjectMultisigAccountV2 private multisig;
    ProjectTreasuryVaultV2 private treasury;
    MockTreasuryERC20 private asset;
    SystemGovernanceControlV2Handler private handler;

    function setUp() public {
        vm.warp(1_000_000);
        registry = new MockRegistry();
        ProjectVotesToken.TokenAllocation[] memory allocations =
            new ProjectVotesToken.TokenAllocation[](1);
        allocations[0] =
            ProjectVotesToken.TokenAllocation({ recipient: SIGNER_A, amount: 1_000_000e18 });
        token = new ProjectVotesToken(
            "Project", "PRJ", address(registry), CREATOR, allocations, new address[](0)
        );
        multisig = new ProjectMultisigAccountV2(
            address(registry), address(token), [SIGNER_A, SIGNER_B, SIGNER_C]
        );
        treasury = new ProjectTreasuryVaultV2(
            address(registry), address(token), CREATOR, address(multisig), bytes32(0), address(0)
        );
        asset = new MockTreasuryERC20("Asset", "AST");
        handler = new SystemGovernanceControlV2Handler(multisig, treasury, asset, RECIPIENT);
        targetContract(address(handler));
    }

    function invariantEveryDepositedUnitIsStillInTreasuryOrAtTheTypedRecipient() public view {
        assertEq(
            handler.totalDeposited(),
            asset.balanceOf(address(treasury)) + asset.balanceOf(RECIPIENT)
        );
        assertEq(treasury.accountedBalance(address(asset)), asset.balanceOf(address(treasury)));
    }

    function invariantOnlyTheIndependentMultisigControlsTreasury() public view {
        assertEq(treasury.controller(), address(multisig));
        assertEq(multisig.controller(), address(multisig));
        assertEq(treasury.projectId(), multisig.projectId());
        assertEq(handler.unauthorizedSendSuccesses(), 0);
    }

    function invariantMultisigSignersAndThresholdRemainCanonical() public view {
        address[3] memory signers = multisig.signers();
        assertEq(signers[0], SIGNER_A);
        assertEq(signers[1], SIGNER_B);
        assertEq(signers[2], SIGNER_C);
        assertEq(multisig.EXECUTION_THRESHOLD(), 2);
    }

    function invariantLauncherCreatorAndTokenHoldersRetainNoControllerAuthority() public view {
        assertFalse(multisig.isSigner(CREATOR));
        assertFalse(multisig.isSigner(address(this)));
        assertEq(token.getVotes(token.BURN_ADDRESS()), 0);
    }
}
