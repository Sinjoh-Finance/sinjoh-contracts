// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {YieldBankAccount} from "../../src/yield-banks/YieldBankAccount.sol";

interface ITreasuryCollectionCapabilities {
    function accountOf(uint256) external view returns(address);
    function accountImplementation() external view returns(address);
    function portfolioAllocator() external view returns(address);
    function collectionTimelock() external view returns(address);
    function nft() external view returns(address);
}
interface ITreasuryOwnerCapabilities {function ownerOf(uint256) external view returns(address);}
contract TreasuryCapabilityToken is ERC20 {
    constructor(address recipient) ERC20("Local capability test", "LOCAL") {_mint(recipient, 100 ether);}
}

/// Checks the real existing treasury without replacing its bytecode, roles or balances.
/// The locally issued ERC20 solely demonstrates receipt and withdrawal permissions.
contract YieldBankExistingTreasuryCapabilitiesForkTest is Test {
    ITreasuryCollectionCapabilities constant collection=ITreasuryCollectionCapabilities(0xc275fa302Cd53DFa42D41b1C5b770661d923ba43);
    YieldBankAccount treasury;
    address owner;
    function setUp() public {
        string memory rpc=vm.envOr("ROBINHOOD_MAINNET_RPC_URL",string(""));
        require(bytes(rpc).length!=0,"mainnet read RPC required");
        vm.createSelectFork(rpc,vm.envUint("TREASURY_CAPABILITY_FORK_BLOCK"));
        treasury=YieldBankAccount(collection.accountOf(334));
        owner=ITreasuryOwnerCapabilities(collection.nft()).ownerOf(334);
        assertFalse(treasury.closed());
    }
    function testExistingTreasuryIsFixedCloneOfReviewedImplementation() public view {
        address implementation=collection.accountImplementation();
        bytes memory clone=abi.encodePacked(hex"363d3d373d3d3d363d73",implementation,hex"5af43d82803e903d91602b57fd5bf3");
        assertEq(address(treasury).code,clone);
        assertEq(implementation.codehash,keccak256(type(YieldBankAccount).runtimeCode));
        assertEq(treasury.collection(),address(collection));
    }
    function testTreasuryReceivesTokensButOwnerAndNewSleeveCannotWithdrawOrApprove() public {
        TreasuryCapabilityToken token=new TreasuryCapabilityToken(address(this));
        token.transfer(address(treasury),1 ether);
        assertEq(token.balanceOf(address(treasury)),1 ether);
        vm.prank(owner);vm.expectRevert(abi.encodeWithSelector(YieldBankAccount.OnlyCollection.selector,owner));
        treasury.releaseDirectAsset(address(token),owner);
        vm.prank(owner);vm.expectRevert(abi.encodeWithSelector(YieldBankAccount.OnlyPortfolioAllocator.selector,owner));
        treasury.approveRebalance(address(token),1 ether);
        address newSleeve=address(0xA1D0);
        vm.prank(newSleeve);vm.expectRevert(abi.encodeWithSelector(YieldBankAccount.OnlyPortfolioAllocator.selector,newSleeve));
        treasury.approveRebalance(address(token),1 ether);
        vm.prank(owner);vm.expectRevert(abi.encodeWithSelector(YieldBankAccount.OnlyRedemptionBeneficiary.selector,owner));
        treasury.recoverDirectAsset(address(token));
        assertEq(token.balanceOf(address(treasury)),1 ether);
    }
    function testNoGeneralExecutionOrUpgradeEntryPointEvenForGovernance() public {
        address governance=collection.collectionTimelock();
        address implementation=collection.accountImplementation();
        vm.prank(owner);
        (bool executed,)=address(treasury).call(abi.encodeWithSignature("execute(address,uint256,bytes)",address(this),0,hex""));
        assertFalse(executed);
        vm.prank(governance);
        (bool upgraded,)=address(treasury).call(abi.encodeWithSignature("upgradeToAndCall(address,bytes)",address(this),hex""));
        assertFalse(upgraded);
        assertEq(collection.accountImplementation(),implementation);
    }
}
