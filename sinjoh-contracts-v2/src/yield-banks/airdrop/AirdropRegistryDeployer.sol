// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;
import {AirdropAssetRegistry} from "./AirdropAssetRegistry.sol";

/// @notice Creates a fully populated, governance-owned registry before sleeve activation.
/// Constructor-only authority cannot be retained or used to modify the registry later.
contract AirdropRegistryDeployer {
 struct Asset {address token;bytes32 evidenceHash;uint256 minimumHolding;bool enabled;address[] claims;}
 AirdropAssetRegistry public immutable registry;
 constructor(address governance,bytes32 catalogHash,Asset[] memory assets){
  require(governance!=address(0)&&assets.length>0&&assets.length<=100,"invalid registry release");
  AirdropAssetRegistry created=new AirdropAssetRegistry(address(this),catalogHash);
  for(uint256 i;i<assets.length;++i){Asset memory a=assets[i];
   require(a.claims.length>0&&a.claims.length<=8,"invalid claim count");
   created.register(a.token,a.evidenceHash);created.setMinimumHoldingUnits(a.token,a.minimumHolding);
   for(uint256 j;j<a.claims.length;++j)created.addClaimRoute(a.token,a.claims[j]);
   created.setEnabled(a.token,a.enabled);
  }
  created.transferOwnership(governance);registry=created;
 }
}
