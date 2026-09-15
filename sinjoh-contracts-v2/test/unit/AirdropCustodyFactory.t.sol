// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;
import {Test} from "forge-std/Test.sol";
import {AirdropCustodyFactory} from "../../src/yield-banks/airdrop/AirdropCustodyFactory.sol";
import {AirdropVault} from "../../src/yield-banks/airdrop/AirdropVault.sol";
import {AirdropTargetBook} from "../../src/yield-banks/airdrop/AirdropTargetBook.sol";
import {AirdropAssetRegistry} from "../../src/yield-banks/airdrop/AirdropAssetRegistry.sol";
contract AirFactorySleeveFixture {
    address public immutable collection;
    address public immutable governance;
    constructor(address c,address g){collection=c;governance=g;}
}
contract AirdropCustodyFactoryTest is Test {
    AirdropCustodyFactory factory;
    AirdropAssetRegistry registry;
    AirFactorySleeveFixture sleeve;
    bytes32 salt=keccak256("release");
    function setUp() public {
        factory=new AirdropCustodyFactory(address(this));
        registry=new AirdropAssetRegistry(address(this),keccak256("catalog"));
        sleeve=new AirFactorySleeveFixture(address(this),address(this));
    }
    function testPredictedContractsMatchExactDeploymentAndBindings() public {
        (address vault,address book)=factory.predict(address(sleeve),address(this),address(registry),salt);
        assertEq(vault.code.length,0);assertEq(book.code.length,0);
        (address createdVault,address createdBook)=factory.deploy(address(sleeve),address(this),address(registry),salt);
        assertEq(createdVault,vault);assertEq(createdBook,book);
        assertEq(AirdropVault(vault).controller(),address(sleeve));assertEq(address(AirdropVault(vault).collection()),address(this));
        assertEq(address(AirdropVault(vault).registry()),address(registry));assertEq(address(AirdropTargetBook(book).sleeve()),address(sleeve));
        assertEq(address(AirdropTargetBook(book).collection()),address(this));
        assertLe(address(factory).code.length,24576);
    }
    function testOutsiderCannotSquatGovernanceDeployment() public {
        vm.prank(address(0xBAD));vm.expectRevert(AirdropCustodyFactory.Unauthorized.selector);factory.deploy(address(sleeve),address(this),address(registry),salt);
    }
    function testCannotDeployBeforeSleeveExists() public {vm.expectRevert(AirdropCustodyFactory.InvalidConfiguration.selector);factory.deploy(address(0xBAD),address(this),address(registry),salt);}
    function testMismatchedCollectionRejected() public {vm.expectRevert(AirdropCustodyFactory.InvalidConfiguration.selector);factory.deploy(address(sleeve),address(factory),address(registry),salt);}
    function testForeignGovernanceRejected() public {
        AirFactorySleeveFixture foreign=new AirFactorySleeveFixture(address(this),address(0xBAD));
        vm.expectRevert(AirdropCustodyFactory.InvalidConfiguration.selector);factory.deploy(address(foreign),address(this),address(registry),salt);
    }
    function testForeignRegistryRejected() public {
        AirdropAssetRegistry foreign=new AirdropAssetRegistry(address(0xBAD),keccak256("catalog"));
        vm.expectRevert(AirdropCustodyFactory.InvalidConfiguration.selector);factory.deploy(address(sleeve),address(this),address(foreign),salt);
    }
    function testSameSaltCannotReplaceExistingCustody() public {
        factory.deploy(address(sleeve),address(this),address(registry),salt);
        vm.expectRevert();factory.deploy(address(sleeve),address(this),address(registry),salt);
    }
    function testChangedArgumentsChangePredictedVault() public {
        (address a,address b)=factory.predict(address(sleeve),address(this),address(registry),salt);
        (address c,address d)=factory.predict(address(sleeve),address(this),address(registry),keccak256("different"));
        assertNotEq(a,c);assertNotEq(b,d);
    }
}
