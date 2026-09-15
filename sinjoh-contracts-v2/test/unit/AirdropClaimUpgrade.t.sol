// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {AirdropTokenMock,AirdropIdentityMock,AirdropBeaconMock,AirdropDistributorMock} from "./AirdropCustody.t.sol";
import {AirdropAssetRegistry} from "../../src/yield-banks/airdrop/AirdropAssetRegistry.sol";
import {AirdropVault} from "../../src/yield-banks/airdrop/AirdropVault.sol";
import {AirdropBankCustody} from "../../src/yield-banks/airdrop/AirdropBankCustody.sol";
import {PonsAirdropClaimAdapter} from "../../src/yield-banks/airdrop/PonsAirdropClaimAdapter.sol";

contract AirdropClaimUpgradeTest is Test {
    AirdropTokenMock token;
    AirdropTokenMock reward;
    AirdropBeaconMock beacon;
    AirdropDistributorMock distributor;
    AirdropAssetRegistry registry;
    AirdropVault vault;
    address alice=address(0xA11CE);

    function setUp() public {
        token=new AirdropTokenMock();reward=new AirdropTokenMock();
        beacon=new AirdropBeaconMock();distributor=new AirdropDistributorMock(address(token),address(reward));
        registry=new AirdropAssetRegistry(address(this),keccak256("catalog"));
        registry.register(address(token),keccak256("evidence"));
        registry.addClaimRoute(address(token),address(new PonsAirdropClaimAdapter(address(distributor),address(beacon))));
        registry.setEnabled(address(token),true);
        AirdropIdentityMock identity=new AirdropIdentityMock();identity.set(1,alice);
        vault=new AirdropVault(address(this),address(identity),address(registry));
        token.mint(address(this),100 ether);token.approve(address(vault),100 ether);
        vault.deposit(1,address(token),50 ether);
    }

    function testIssuerUpgradeBlocksNewPrincipalButPreservesExitsAndReceivedRewards() public {
        AirdropBankCustody treasury=vault.treasuryOf(1);
        reward.mint(address(treasury),7 ether);
        beacon.upgrade(address(token));
        vm.expectRevert(PonsAirdropClaimAdapter.InvalidClaim.selector);
        vault.deposit(1,address(token),1 ether);
        vault.withdraw(1,address(token),50 ether);
        assertEq(token.balanceOf(address(this)),100 ether);
        vm.prank(alice);treasury.claim(address(reward));
        assertEq(reward.balanceOf(alice),7 ether);
    }

    function testReviewedReplacementRestoresEntryWithoutMovingTheBanksTreasury() public {
        address treasury=address(vault.treasuryOf(1));
        beacon.upgrade(address(token));
        PonsAirdropClaimAdapter replacement=new PonsAirdropClaimAdapter(address(distributor),address(beacon));
        vm.expectRevert(AirdropAssetRegistry.InvalidAsset.selector);
        registry.replaceClaimRoute(address(token),0,address(replacement));
        registry.setEnabled(address(token),false);
        registry.replaceClaimRoute(address(token),0,address(replacement));
        registry.setEnabled(address(token),true);
        vault.deposit(1,address(token),1 ether);
        assertEq(address(vault.treasuryOf(1)),treasury);
        assertEq(vault.principalOf(1,address(token)),51 ether);
    }

    function testUnreviewedCallerCannotReplaceClaimProgram() public {
        registry.setEnabled(address(token),false);
        PonsAirdropClaimAdapter replacement=new PonsAirdropClaimAdapter(address(distributor),address(beacon));
        vm.prank(alice);vm.expectRevert();registry.replaceClaimRoute(address(token),0,address(replacement));
    }

    function testStaleClaimIntegrationCannotBeEnabledAgain() public {
        registry.setEnabled(address(token),false);
        beacon.upgrade(address(token));
        vm.expectRevert(PonsAirdropClaimAdapter.InvalidClaim.selector);
        registry.setEnabled(address(token),true);
    }
}
