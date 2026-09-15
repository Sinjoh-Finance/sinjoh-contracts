// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;
import {AirdropCompositeInfrastructureForkTest} from "./AirdropCompositeInfrastructure.fork.t.sol";
import {DeltaPoolController} from "../../src/yield-banks/DeltaPoolController.sol";
import {DeltaV3SinglePoolRoute} from "../../src/yield-banks/adapters/DeltaV3SinglePoolRoute.sol";
import {DeltaV3TwapUsdFeed} from "../../src/yield-banks/adapters/DeltaV3TwapUsdFeed.sol";
import {YieldBankSelfServiceExecutionRouter} from "../../src/yield-banks/YieldBankSelfServiceExecutionRouter.sol";
import {StockCompositeLPAdapter} from "../../src/yield-banks/stock/StockCompositeLPAdapter.sol";
import {AirdropCompositeSleeve} from "../../src/yield-banks/airdrop/AirdropCompositeSleeve.sol";
import {AirdropCustodyFactory} from "../../src/yield-banks/airdrop/AirdropCustodyFactory.sol";
import {AirdropAssetRegistry} from "../../src/yield-banks/airdrop/AirdropAssetRegistry.sol";
import {PriceHub} from "../../src/yield-banks/PriceHub.sol";
interface IAirAtomicAggregator { function latestRoundData() external view returns(uint80,int256,uint256,uint256,uint80); }
interface IAirAtomicTimelock {
    function getMinDelay() external view returns(uint256);
    function scheduleBatch(address[] calldata,uint256[] calldata,bytes[] calldata,bytes32,bytes32,uint256) external;
    function executeBatch(address[] calldata,uint256[] calldata,bytes[] calldata,bytes32,bytes32) external payable;
    function isOperationDone(bytes32) external view returns(bool);
}

contract AirdropAtomicActivationForkTest is AirdropCompositeInfrastructureForkTest {
    function testOneTimelockBatchMaterializesSleeveAndConnectsItsNewCustody() public {
        _fork();_deployInfrastructure();
        address governance=COLLECTION.collectionTimelock();
        address deployer=0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49;
        DeltaPoolController controller=DeltaPoolController(address(ALLOCATOR.deltaPoolController()));
        uint64 nonce=vm.getNonce(address(controller));
        bytes32 predecessor=0xdf428b6330c22c6029ed837808480ee237fc3c797202a015d03c09f1aef28bf3;
        address expectedSleeve=vm.computeCreateAddress(address(controller),nonce+6);
        AirdropCustodyFactory custodyFactory=new AirdropCustodyFactory(governance);
        AirdropAssetRegistry registry=new AirdropAssetRegistry(governance,keccak256("reviewed catalog"));
        bytes32 salt=keccak256("airdrop atomic custody rehearsal");
        (address vault,address book)=custodyFactory.predict(expectedSleeve,address(COLLECTION),address(registry),salt);
        assertEq(expectedSleeve.code.length,0);assertEq(vault.code.length,0);assertEq(book.code.length,0);
        address[] memory targets=new address[](5);bytes[] memory calls=new bytes[](5);uint256[] memory values=new uint256[](5);
        targets[0]=address(controller);
        calls[0]=abi.encodeCall(DeltaPoolController.configureInfrastructure,(factory,DeltaPoolController.InfrastructureConfig({
            positionManager:manager,positionBuilder:address(builder),factoryRuntimeCodeHash:factory.codehash,
            positionManagerRuntimeCodeHash:manager.codehash,positionBuilderRuntimeCodeHash:address(builder).codehash,
            routeCreationCodeHash:keccak256(type(DeltaV3SinglePoolRoute).creationCode),sleeveCreationCodeHash:keccak256(type(AirdropCompositeSleeve).creationCode),
            adapterCreationCodeHash:keccak256(type(StockCompositeLPAdapter).creationCode),feedCreationCodeHash:keccak256(type(DeltaV3TwapUsdFeed).creationCode)
        })));
        targets[1]=ALLOCATOR.allocationOperator();
        calls[1]=abi.encodeCall(YieldBankSelfServiceExecutionRouter.executeGovernanceCall,(address(controller),abi.encodeCall(DeltaPoolController.materializePool,(
            registrationPool,DeltaPoolController.MaterializationConfig(1,controller.maximumAdapterCapBps(),500),
            type(DeltaV3SinglePoolRoute).creationCode,type(AirdropCompositeSleeve).creationCode,type(StockCompositeLPAdapter).creationCode
        ))));
        targets[2]=address(custodyFactory);calls[2]=abi.encodeCall(AirdropCustodyFactory.deploy,(expectedSleeve,address(COLLECTION),address(registry),salt));
        targets[3]=expectedSleeve;calls[3]=abi.encodeCall(AirdropCompositeSleeve.configureAirdropVault,(vault));
        targets[4]=expectedSleeve;calls[4]=abi.encodeCall(AirdropCompositeSleeve.configureTargetBook,(book));
        IAirAtomicTimelock timelock=IAirAtomicTimelock(governance);
        uint256 delay=timelock.getMinDelay();assertEq(delay,86400);
        vm.prank(deployer);timelock.scheduleBatch(targets,values,calls,predecessor,salt,delay);
        vm.warp(block.timestamp+delay);
        vm.prank(deployer);vm.expectRevert();timelock.executeBatch(targets,values,calls,predecessor,salt);
        assertEq(vm.getNonce(address(controller)),nonce);
        // A historical fork has no future Chainlink rounds. Model a normal fresh ETH/USD
        // round after the one-day wait, preserving its price and all heartbeat protections.
        // The deployment runner must check real current oracle freshness again before execution.
        address wethFeed=PriceHub(address(controller.priceHub())).feedDetails(WETH).feed;
        (uint80 round,int256 answer,,,)=IAirAtomicAggregator(wethFeed).latestRoundData();
        vm.mockCall(wethFeed,abi.encodeCall(IAirAtomicAggregator.latestRoundData,()),abi.encode(round+1,answer,block.timestamp,block.timestamp,round+1));
        string memory stock=vm.readFile("deployments/piggy-banks-stock-preparation.json");
        vm.prank(deployer);(bool ok,bytes memory reason)=governance.call(vm.parseJsonBytes(stock,".executeCalldata"));
        if(!ok)assembly("memory-safe"){revert(add(reason,32),mload(reason))}
        assertTrue(timelock.isOperationDone(predecessor));assertEq(vm.getNonce(address(controller)),nonce+4);
        vm.prank(deployer);timelock.executeBatch(targets,values,calls,predecessor,salt);
        bytes32 operation=keccak256(abi.encode(targets,values,calls,predecessor,salt));assertTrue(timelock.isOperationDone(operation));
        AirdropCompositeSleeve deployed=AirdropCompositeSleeve(expectedSleeve);
        assertEq(address(deployed.airdropVault()),vault);assertEq(address(deployed.targetBook()),book);
        assertTrue(deployed.depositsPaused(),"entry remains closed until remaining release configuration");
        assertTrue(controller.isAllocationPool(registrationPool));assertTrue(controller.isAllocationPool(INJOH_POOL));
    }
}
