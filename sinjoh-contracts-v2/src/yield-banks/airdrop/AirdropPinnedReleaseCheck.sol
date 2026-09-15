// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;
import {AirdropReleaseVerifier} from "./AirdropReleaseVerifier.sol";

/// @notice Stores the reviewed verification arguments before queueing. The timelock's
/// final check needs only a selector, keeping the atomic transaction within sequencer
/// size limits. There is no setter, owner, delegatecall or asset-moving operation.
contract AirdropPinnedReleaseCheck {
 address public immutable verifier;
 bytes32 public immutable verifierCodeHash;
 bytes32 public immutable releaseHash;
 bytes private _release;
 constructor(address verifier_,bytes memory release_){
  require(verifier_.code.length>0&&release_.length>0&&release_.length<=45000,"invalid release check");
  verifier=verifier_;verifierCodeHash=verifier_.codehash;releaseHash=keccak256(release_);_release=release_;
 }
 function verify() external view {
  require(verifier.codehash==verifierCodeHash,"verifier changed");
  (bool ok,bytes memory reason)=verifier.staticcall(abi.encodePacked(AirdropReleaseVerifier.verifyAirdrop.selector,_release));
  if(!ok)assembly("memory-safe"){revert(add(reason,32),mload(reason))}
 }
}
