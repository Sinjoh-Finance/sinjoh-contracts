// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;
import {Test} from "forge-std/Test.sol";
import {AirdropCompositeSleeve} from "../../src/yield-banks/airdrop/AirdropCompositeSleeve.sol";
import {AirdropPinnedReleaseCheck} from "../../src/yield-banks/airdrop/AirdropPinnedReleaseCheck.sol";
import {AirdropReleaseVerifier} from "../../src/yield-banks/airdrop/AirdropReleaseVerifier.sol";
interface IExactAirTimelock {function getMinDelay() external view returns(uint256);function isOperationDone(bytes32) external view returns(bool);}
interface IExactAirFeed {function latestRoundData() external view returns(uint80,int256,uint256,uint256,uint80);}
contract AirdropExactReleaseForkTest is Test {
 address constant DEPLOYER=0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49;
 address constant GOVERNANCE=0x7C15804A2d7F5981035895CAb953e5E76393E1B8;
 address constant ETH_FEED=0x78F3556b67E17Df817D51Ef5a990cDaF09E8d3A9;
 string plan;
 AirdropReleaseVerifier.Release release;
 address pinned;
 function setUp() public {
  string memory rpc=vm.envOr("AIRDROP_PREPARED_FORK_URL",string(""));if(bytes(rpc).length==0)vm.skip(true);
  vm.createSelectFork(rpc,vm.envUint("AIRDROP_PREPARED_FORK_BLOCK"));
  plan=vm.readFile("deployments/piggy-banks-airdrop-governance.json");
  string memory configuration=vm.readFile("deployments/piggy-banks-airdrop-configuration.json");
  release=abi.decode(vm.parseJsonBytes(configuration,".release"),(AirdropReleaseVerifier.Release));pinned=vm.parseJsonAddress(configuration,".pinnedCheck");
  require(release.stock.sleeve.code.length==0,"fork already activated");require(pinned.code.length>0,"prepared contracts missing");
 }
 function _operation(uint256 i,string memory field) private pure returns(string memory){return string.concat(".operations[",vm.toString(i),"].",field);}
 function _call(bytes memory data) private {vm.prank(DEPLOYER);(bool ok,bytes memory reason)=GOVERNANCE.call(data);if(!ok)assembly("memory-safe"){revert(add(reason,32),mload(reason))}}
 function _queueAndWait() private {
  uint256 delay=IExactAirTimelock(GOVERNANCE).getMinDelay();assertEq(delay,86400);
  for(uint256 i;i<2;++i){bytes memory data=vm.parseJsonBytes(plan,_operation(i,"scheduleCalldata"));uint256 before=gasleft();_call(data);emit log_named_uint("schedule gas",before-gasleft());}
  // Both operations were queued at the same timestamp; no second delay is added.
  bytes memory early=vm.parseJsonBytes(plan,_operation(0,"executeCalldata"));
  vm.prank(DEPLOYER);(bool earlySuccess,)=GOVERNANCE.call(early);assertFalse(earlySuccess,"timelock allowed early execution");
  vm.warp(block.timestamp+delay);
  // Historical forks do not have tomorrow's Chainlink report. Preserve its actual
  // answer and model a fresh round solely for this time-warped activation test.
  (uint80 round,int256 answer,,,)=IExactAirFeed(ETH_FEED).latestRoundData();
  vm.mockCall(ETH_FEED,abi.encodeCall(IExactAirFeed.latestRoundData,()),abi.encode(round+1,answer,block.timestamp,block.timestamp,round+1));
  string memory stock=vm.readFile("deployments/piggy-banks-stock-preparation.json");_call(vm.parseJsonBytes(stock,".executeCalldata"));
 }
 function testExactBatchPairActivatesAllAssetsAfterOneConcurrentDelay() public {
  _queueAndWait();
  for(uint256 i;i<2;++i){bytes memory data=vm.parseJsonBytes(plan,_operation(i,"executeCalldata"));uint256 before=gasleft();_call(data);emit log_named_uint("execute gas",before-gasleft());assertTrue(IExactAirTimelock(GOVERNANCE).isOperationDone(vm.parseJsonBytes32(plan,_operation(i,"operation"))));if(i==0)assertTrue(AirdropCompositeSleeve(release.stock.sleeve).depositsPaused());}
  assertFalse(AirdropCompositeSleeve(release.stock.sleeve).depositsPaused());AirdropPinnedReleaseCheck(pinned).verify();assertEq(release.assets.length,58);
 }
 function testFinalMismatchRollsBackOpeningDeposits() public {
  _queueAndWait();_call(vm.parseJsonBytes(plan,_operation(0,"executeCalldata")));
  vm.etch(release.assets[0].claims[0].adapter,hex"00");
  vm.expectRevert();this.executeSecond();
  assertTrue(AirdropCompositeSleeve(release.stock.sleeve).depositsPaused());assertFalse(IExactAirTimelock(GOVERNANCE).isOperationDone(vm.parseJsonBytes32(plan,_operation(1,"operation"))));
 }
 function testSecondOperationCannotSkipItsPredecessor() public {_queueAndWait();vm.expectRevert();this.executeSecond();}
 function executeSecond() external {require(msg.sender==address(this));_call(vm.parseJsonBytes(plan,_operation(1,"executeCalldata")));}
}
