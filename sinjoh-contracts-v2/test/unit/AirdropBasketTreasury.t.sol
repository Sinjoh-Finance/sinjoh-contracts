// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { AirdropCustodyTest, AirdropTokenMock, AirdropDistributorMock, AirdropBeaconMock } from "./AirdropCustody.t.sol";
import { AirdropBankCustody } from "../../src/yield-banks/airdrop/AirdropBankCustody.sol";
import { PonsAirdropClaimAdapter } from "../../src/yield-banks/airdrop/PonsAirdropClaimAdapter.sol";
import { AirdropIdentityMock } from "./AirdropCustody.t.sol";

contract AirdropBurnableFixture is AirdropTokenMock {
    function destroy(address holder,uint256 amount) external { _burn(holder,amount); }
}
contract AirdropCrossAssetClaimFixture {
    address public subject;
    address public rewardAsset;
    AirdropBurnableFixture public victim;
    constructor(address subject_,address reward_,AirdropBurnableFixture victim_) {subject=subject_;rewardAsset=reward_;victim=victim_;}
    function validate() external pure {}
    function prepare(address holder,bytes calldata) external view returns(address,bytes memory) {
        return (address(this),abi.encodeCall(this.takeAndReward,(holder)));
    }
    function takeAndReward(address holder) external {
        victim.destroy(holder,1 ether);
        AirdropTokenMock(rewardAsset).mint(holder,2 ether);
    }
}
contract AirdropOwnershipChangingReceiver {
    AirdropIdentityMock immutable identity;
    AirdropBankCustody immutable treasury;
    constructor(AirdropIdentityMock identity_,AirdropBankCustody treasury_) {identity=identity_;treasury=treasury_;}
    function claim() external {treasury.claim(address(0));}
    receive() external payable {identity.set(1,address(0xBAD));}
}

contract AirdropBasketTreasuryTest is AirdropCustodyTest {
    function testIssuerClaimCannotReduceAnotherBasketAssetsPrincipal() public {
        AirdropBurnableFixture victim = new AirdropBurnableFixture();
        _add(victim);vault.deposit(1,address(victim),10 ether);
        AirdropCrossAssetClaimFixture hostile = new AirdropCrossAssetClaimFixture(address(token),address(reward),victim);
        registry.addClaimRoute(address(token),address(hostile));
        vm.expectRevert(AirdropBankCustody.InvalidTransfer.selector);
        c1.collect(address(token),1,"");
        assertEq(victim.balanceOf(address(c1)),10 ether);
        assertEq(c1.principal(address(victim)),10 ether);
        assertEq(c1.available(address(reward)),0);
    }
    function testOwnershipChangeDuringNativePayoutRollsBackEntireClaim() public {
        AirdropOwnershipChangingReceiver receiver = new AirdropOwnershipChangingReceiver(identity,c1);
        identity.set(1,address(receiver));vm.deal(address(c1),1 ether);
        vm.expectRevert(AirdropBankCustody.Unauthorized.selector);receiver.claim();
        assertEq(address(c1).balance,1 ether);
        assertEq(address(receiver).balance,0);
        assertEq(identity.ownerOf(1),address(receiver));
        assertEq(c1.totalPaid(address(0)),0);
    }
    function _add(AirdropTokenMock asset) internal {
        registry.register(address(asset), keccak256("basket-evidence"));
        AirdropDistributorMock d = new AirdropDistributorMock(address(asset), address(reward));
        registry.addClaimRoute(address(asset), address(new PonsAirdropClaimAdapter(address(d), address(beacon))));
        registry.setEnabled(address(asset), true);
        asset.mint(address(this), 1000 ether);
        asset.approve(address(vault), type(uint256).max);
    }

    function testWholeBasketUsesOneTreasuryAndBanksRemainSeparate() public {
        AirdropTokenMock second = new AirdropTokenMock();
        AirdropTokenMock third = new AirdropTokenMock();
        _add(second); _add(third);
        vault.deposit(1, address(second), 60 ether);
        vault.deposit(1, address(third), 40 ether);
        assertEq(address(vault.treasuryOf(1)), address(c1));
        assertEq(address(vault.custodyOf(1, address(second))), address(c1));
        assertEq(address(vault.custodyOf(1, address(third))), address(c1));
        assertTrue(address(c1) != address(c2));
        assertEq(c1.principal(address(token)), 100 ether);
        assertEq(c1.principal(address(second)), 60 ether);
        assertEq(c1.principal(address(third)), 40 ether);
        assertEq(second.balanceOf(address(c1)), 60 ether);
        assertEq(third.balanceOf(address(c1)), 40 ether);
    }

    function testRewardTokenAlsoInBasketProtectsPrincipalAcrossPartialExit() public {
        _add(reward);
        vault.deposit(1, address(reward), 40 ether);
        distributor.authorize(1, address(c1), 7 ether);
        c1.collect(address(token), 0, payload(7 ether));
        assertEq(c1.available(address(reward)), 7 ether);
        vault.withdraw(1, address(reward), 15 ether);
        vm.prank(alice);
        assertEq(c1.claim(address(reward)), 7 ether);
        assertEq(reward.balanceOf(alice), 7 ether);
        assertEq(reward.balanceOf(address(c1)), 25 ether);
        assertEq(c1.principal(address(reward)), 25 ether);
        assertEq(c1.principal(address(token)), 100 ether);
    }

    function testFourthAssetRejectedUntilExistingPositionExits() public {
        AirdropTokenMock second = new AirdropTokenMock();
        AirdropTokenMock third = new AirdropTokenMock();
        AirdropTokenMock fourth = new AirdropTokenMock();
        _add(second); _add(third); _add(fourth);
        vault.deposit(1, address(second), 10 ether);
        vault.deposit(1, address(third), 10 ether);
        vm.expectRevert(AirdropBankCustody.Unauthorized.selector);
        vault.deposit(1, address(fourth), 10 ether);
        assertEq(address(vault.custodyOf(1, address(fourth))), address(0));
        vault.withdraw(1, address(second), 10 ether);
        vault.deposit(1, address(fourth), 10 ether);
        assertEq(address(vault.custodyOf(1, address(fourth))), address(c1));
        assertEq(address(vault.custodyOf(1, address(second))), address(c1));
        second.mint(address(c1), 3 ether);
        vm.prank(alice);
        c1.claim(address(second));
        assertEq(second.balanceOf(alice), 3 ether);
    }

    function testSharedRewardAggregatesOnceAndNoDuplicatePayout() public {
        AirdropTokenMock second = new AirdropTokenMock();
        _add(second);
        vault.deposit(1, address(second), 40 ether);
        distributor.authorize(1, address(c1), 7 ether);
        c1.collect(address(token), 0, payload(7 ether));
        reward.mint(address(c1), 5 ether);
        vm.prank(alice);
        assertEq(c1.claim(address(reward)), 12 ether);
        vm.prank(alice);
        assertEq(c1.claim(address(reward)), 0);
        assertEq(c1.totalPaid(address(reward)), 12 ether);
        assertEq(second.balanceOf(address(c1)), 40 ether);
    }

    function testFuzzBasketClaimsConserveBothPrincipalBalances(uint128 incoming, uint128 rawExit) public {
        _add(reward);
        vault.deposit(1, address(reward), 40 ether);
        reward.mint(address(c1), incoming);
        uint256 exited = bound(uint256(rawExit), 1, 40 ether);
        vault.withdraw(1, address(reward), exited);
        vm.prank(alice);
        c1.claim(address(reward));
        assertEq(reward.balanceOf(alice), incoming);
        assertEq(reward.balanceOf(address(c1)), 40 ether - exited);
        assertEq(c1.principal(address(reward)), 40 ether - exited);
        assertEq(token.balanceOf(address(c1)), 100 ether);
    }
}
