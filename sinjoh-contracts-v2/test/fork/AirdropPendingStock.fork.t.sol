// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;
import {AirdropCompositeInfrastructureForkTest} from "./AirdropCompositeInfrastructure.fork.t.sol";
import {DeltaPoolController} from "../../src/yield-banks/DeltaPoolController.sol";
import {PriceHub} from "../../src/yield-banks/PriceHub.sol";
interface IAirPendingAggregator {function latestRoundData() external view returns(uint80,int256,uint256,uint256,uint80);}
interface IAirPendingTimelock {
    function getTimestamp(bytes32) external view returns(uint256);
    function isOperationDone(bytes32) external view returns(bool);
}
/// @notice Rehearses the queued production Stock activation through the actual timelock
/// before creating Airdrop infrastructure. Only this isolated fork advances chain time.
contract AirdropPendingStockForkTest is AirdropCompositeInfrastructureForkTest {
    function testQueuedStockActivationThenAirdropRegistrationPreservesBothGenerations() public {
        _fork();
        string memory pending=vm.readFile("deployments/piggy-banks-stock-preparation.json");
        address stock=vm.parseJsonAddress(pending,".composite");
        address stockPool=vm.parseJsonAddress(pending,".registrationPool");
        address governance=vm.parseJsonAddress(pending,".governance");
        bytes32 operation=0xdf428b6330c22c6029ed837808480ee237fc3c797202a015d03c09f1aef28bf3;
        IAirPendingTimelock timelock=IAirPendingTimelock(governance);
        uint256 ready=timelock.getTimestamp(operation);
        assertGt(ready,1,"expected pending production Stock activation");
        assertEq(stock.code.length,0,"Stock already activated; refresh rehearsal");
        DeltaPoolController controller=DeltaPoolController(address(ALLOCATOR.deltaPoolController()));
        uint64 nonce=vm.getNonce(address(controller));
        assertEq(nonce,vm.parseJsonUint(pending,".controllerNonce"));
        address bank=COLLECTION.accountOf(334);
        bytes32 oldInfrastructure=_infrastructureHash(address(controller),OLD_FACTORY);
        vm.warp(ready);
        // Time travel does not create future Chainlink rounds. Model a fresh ETH/USD
        // round at the same price, as in the atomic activation test. Production execution
        // must check an actual fresh round and never bypass the heartbeat requirement.
        address wethFeed=PriceHub(address(controller.priceHub())).feedDetails(WETH).feed;
        (uint80 round,int256 answer,,,)=IAirPendingAggregator(wethFeed).latestRoundData();
        vm.mockCall(wethFeed,abi.encodeCall(IAirPendingAggregator.latestRoundData,()),abi.encode(round+1,answer,block.timestamp,block.timestamp,round+1));
        vm.prank(vm.parseJsonAddress(pending,".deployer"));
        (bool ok,bytes memory reason)=governance.call(vm.parseJsonBytes(pending,".executeCalldata"));
        if(!ok)assembly("memory-safe"){revert(add(reason,32),mload(reason))}
        assertTrue(timelock.isOperationDone(operation));
        assertGt(stock.code.length,0);assertTrue(controller.isAllocationPool(stockPool));
        assertEq(vm.getNonce(address(controller)),nonce+4);
        assertEq(COLLECTION.accountOf(334),bank);
        _deployInfrastructure();
        address predicted=vm.computeCreateAddress(address(controller),nonce+6);
        _registerComposite(controller);
        assertEq(address(composite),predicted,"prediction must include pending Stock CREATEs");
        assertTrue(controller.isAllocationPool(stockPool));
        assertTrue(controller.isAllocationPool(INJOH_POOL));
        assertTrue(controller.isAllocationPool(registrationPool));
        assertEq(_infrastructureHash(address(controller),OLD_FACTORY),oldInfrastructure);
    }
}
