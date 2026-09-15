// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;
import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AirdropAssetRegistry} from "../../src/yield-banks/airdrop/AirdropAssetRegistry.sol";
import {AirdropRegistryDeployer} from "../../src/yield-banks/airdrop/AirdropRegistryDeployer.sol";
import {AirdropPinnedReleaseCheck} from "../../src/yield-banks/airdrop/AirdropPinnedReleaseCheck.sol";
import {AirdropReleaseVerifier} from "../../src/yield-banks/airdrop/AirdropReleaseVerifier.sol";
contract AirPreparationToken is ERC20 {constructor() ERC20("fixture","FIX") {}}
contract AirPreparationClaim {function validate() external pure {} address public subject;address public rewardAsset;constructor(address s,address r){subject=s;rewardAsset=r;}}
contract AirPreparationVerifier {
 bytes32 immutable expected;bool public reject;
 constructor(bytes memory payload){expected=keccak256(abi.encodePacked(AirdropReleaseVerifier.verifyAirdrop.selector,payload));}
 function setReject() external {reject=true;}
 fallback() external {require(!reject,"release mismatch");require(keccak256(msg.data)==expected,"arguments changed");}
}
contract AirdropReleasePreparationTest is Test {
 function _assets() private returns(AirdropRegistryDeployer.Asset[] memory a){
  a=new AirdropRegistryDeployer.Asset[](2);address reward=address(new AirPreparationToken());
  for(uint256 i;i<2;++i){address token=address(new AirPreparationToken());address[] memory claims=new address[](1);claims[0]=address(new AirPreparationClaim(token,reward));a[i]=AirdropRegistryDeployer.Asset(token,keccak256(abi.encode(i)),i+1,i==0,claims);}
 }
 function testRegistryIsFullyInitializedAndOnlyGovernanceOwnsIt() public {
  AirdropRegistryDeployer.Asset[] memory a=_assets();address gov=address(0xB0B);
  AirdropRegistryDeployer deployer=new AirdropRegistryDeployer(gov,keccak256("catalog"),a);AirdropAssetRegistry r=deployer.registry();
  assertEq(r.owner(),gov);assertEq(r.listed(1),a[1].token);assertEq(r.minimumHoldingUnits(a[1].token),2);assertEq(r.claimRoute(a[0].token,0).adapter,a[0].claims[0]);
  (,,,bool enabled)=r.assets(a[0].token);assertTrue(enabled);(,,,enabled)=r.assets(a[1].token);assertFalse(enabled);
  vm.expectRevert();r.setEnabled(a[0].token,false);vm.prank(address(deployer));vm.expectRevert();r.setEnabled(a[0].token,false);
  vm.prank(gov);r.setEnabled(a[0].token,false);
 }
 function testRegistryRejectsDuplicateAssetsAndInvalidClaimsAtomically() public {
  AirdropRegistryDeployer.Asset[] memory a=_assets();a[1]=a[0];vm.expectRevert();new AirdropRegistryDeployer(address(this),keccak256("catalog"),a);
  a=_assets();a[1].claims=a[0].claims;vm.expectRevert();new AirdropRegistryDeployer(address(this),keccak256("catalog"),a);
  a=_assets();a[0].minimumHolding=0;vm.expectRevert();new AirdropRegistryDeployer(address(this),keccak256("catalog"),a);
 }
 function testPinnedCheckCallsExactArgumentsAndPropagatesFailure() public {
  bytes memory payload=hex"12345678";AirPreparationVerifier verifier=new AirPreparationVerifier(payload);AirdropPinnedReleaseCheck check=new AirdropPinnedReleaseCheck(address(verifier),payload);
  assertEq(check.releaseHash(),keccak256(payload));vm.prank(address(0xB0B));check.verify();
  verifier.setReject();vm.expectRevert("release mismatch");check.verify();
 }
 function testPinnedCheckRejectsCodeChangesOrInvalidPreparation() public {
  AirPreparationVerifier verifier=new AirPreparationVerifier(hex"1234");AirdropPinnedReleaseCheck check=new AirdropPinnedReleaseCheck(address(verifier),hex"1234");
  vm.etch(address(verifier),hex"00");vm.expectRevert("verifier changed");check.verify();
  vm.expectRevert();new AirdropPinnedReleaseCheck(address(0xBAD),hex"1234");vm.expectRevert();new AirdropPinnedReleaseCheck(address(verifier),new bytes(45001));
 }
}
