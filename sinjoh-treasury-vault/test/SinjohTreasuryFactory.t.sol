// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { SinjohJoint } from "../src/SinjohJoint.sol";
import { SinjohTreasuryFactory } from "../src/SinjohTreasuryFactory.sol";
import { SinjohTreasuryVault } from "../src/SinjohTreasuryVault.sol";
import { TestBase } from "./TestBase.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";

contract SinjohTreasuryFactoryTest is TestBase {
    address internal constant SIGNER_A = address(0xA1);
    address internal constant SIGNER_B = address(0xB2);
    address internal constant SIGNER_C = address(0xC3);
    address internal constant RECIPIENT = address(0xBEEF);
    uint256 internal constant START = 1_000_000;

    SinjohTreasuryFactory internal factory;

    function setUp() public {
        vm.warp(START);
        factory = new SinjohTreasuryFactory();
    }

    function testCreatesWiredStandardTreasury() public {
        (SinjohJoint joint, SinjohTreasuryVault vault) =
            factory.createStandardTreasury([SIGNER_A, SIGNER_B, SIGNER_C]);

        assertEq(vault.governor(), address(joint));
        assertEq(vault.GOVERNOR_HANDOFF_DELAY(), factory.GOVERNOR_HANDOFF_DELAY());
        assertEq(vault.RECOVERY_ADDRESS(), address(0));
        assertEq(vault.RECOVERY_INACTIVITY_PERIOD(), 0);
        assertEq(joint.PROPOSAL_TTL(), factory.PROPOSAL_TTL());
        assertTrue(joint.isSigner(SIGNER_A));
        assertTrue(joint.isSigner(SIGNER_B));
        assertTrue(joint.isSigner(SIGNER_C));
        assertEq(factory.jointForVault(address(vault)), address(joint));
    }

    function testFactoryRejectsInvalidSigners() public {
        vm.expectPartialRevert(SinjohJoint.DuplicateSigner.selector);
        factory.createStandardTreasury([SIGNER_A, SIGNER_A, SIGNER_C]);

        vm.expectPartialRevert(SinjohJoint.InvalidSigner.selector);
        factory.createStandardTreasury([SIGNER_A, address(0), SIGNER_C]);
    }

    function testCreatedTreasuriesAreIndependent() public {
        (SinjohJoint jointOne, SinjohTreasuryVault vaultOne) =
            factory.createStandardTreasury([SIGNER_A, SIGNER_B, SIGNER_C]);
        (, SinjohTreasuryVault vaultTwo) =
            factory.createStandardTreasury([SIGNER_A, SIGNER_B, address(0xD4)]);

        assertTrue(address(vaultOne) != address(vaultTwo));

        MockERC20 token = new MockERC20();
        token.mint(address(vaultTwo), 100);

        // Treasury one's quorum cannot move treasury two's funds.
        vm.prank(SIGNER_A);
        uint256 proposalId = jointOne.propose(
            address(vaultTwo),
            0,
            abi.encodeCall(SinjohTreasuryVault.transfer, (address(token), 100, RECIPIENT))
        );
        vm.prank(SIGNER_B);
        jointOne.confirm(proposalId);
        vm.prank(SIGNER_A);
        vm.expectPartialRevert(SinjohJoint.ExecutionFailed.selector);
        jointOne.execute(proposalId);

        assertEq(token.balanceOf(address(vaultTwo)), 100);
    }

    function testCreatedTreasuryExecutesTransfers() public {
        (SinjohJoint joint, SinjohTreasuryVault vault) =
            factory.createStandardTreasury([SIGNER_A, SIGNER_B, SIGNER_C]);

        MockERC20 token = new MockERC20();
        token.mint(address(vault), 100);

        vm.prank(SIGNER_A);
        uint256 proposalId = joint.propose(
            address(vault),
            0,
            abi.encodeCall(SinjohTreasuryVault.transfer, (address(token), 60, RECIPIENT))
        );
        vm.prank(SIGNER_C);
        joint.confirm(proposalId);
        vm.prank(SIGNER_B);
        joint.execute(proposalId);

        assertEq(token.balanceOf(RECIPIENT), 60);
        assertEq(token.balanceOf(address(vault)), 40);
    }
}
