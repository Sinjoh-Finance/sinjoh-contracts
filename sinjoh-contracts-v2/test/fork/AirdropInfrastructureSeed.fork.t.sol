// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;
import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {AirdropInfrastructureSeed} from "../../src/yield-banks/airdrop/AirdropInfrastructureSeed.sol";
import {StockInfrastructureBuilder,StockInfrastructurePositionDescriptor} from "../../src/yield-banks/stock/StockInfrastructureBuilder.sol";
import {DeltaV3SinglePoolRoute} from "../../src/yield-banks/adapters/DeltaV3SinglePoolRoute.sol";
import {IPriceHub} from "../../src/yield-banks/interfaces/IPriceHub.sol";
import {IYieldBankV3Pool} from "../../src/yield-banks/interfaces/IYieldBankV3.sol";
import {CollectionPortfolioAllocator} from "../../src/yield-banks/CollectionPortfolioAllocator.sol";
import {DeltaPoolController} from "../../src/yield-banks/DeltaPoolController.sol";
interface ISeedTestFactory {function createPool(address,address,uint24) external returns(address);function enableFeeAmount(uint24,int24) external;}
interface ISeedTestInitialize {function initialize(uint160) external;}
contract AirdropInfrastructureSeedForkTest is Test {
 address constant WETH=0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;
 address constant USDG=0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168;
 address constant MARKET=0x52e65B17fB6E5BA00Ed806f37Afcd2DaA50271Ca;
 address constant FACTORY=0x1f7d7550B1b028f7571E69A784071F0205FD2EfA;
 address constant GOV=0x7C15804A2d7F5981035895CAb953e5E76393E1B8;
 address pool;address manager;StockInfrastructureBuilder builder;DeltaV3SinglePoolRoute route;IPriceHub hub;
 function setUp() public {
  string memory rpc=vm.envOr("ROBINHOOD_MAINNET_RPC_URL",string(""));if(bytes(rpc).length==0)vm.skip(true);
  vm.createSelectFork(rpc,63325971);vm.deal(address(this),1 ether);
  address factory=_artifact("UniswapV3Factory","");
  manager=_artifact("NonfungiblePositionManager",abi.encode(factory,WETH,address(new StockInfrastructurePositionDescriptor())));
  builder=new StockInfrastructureBuilder(factory,manager,WETH);
  ISeedTestFactory(factory).enableFeeAmount(100,1);pool=ISeedTestFactory(factory).createPool(WETH,USDG,100);
  route=new DeltaV3SinglePoolRoute(MARKET,FACTORY,WETH,USDG,MARKET.codehash,FACTORY.codehash);
  hub=DeltaPoolController(address(CollectionPortfolioAllocator(0x42e14eA9f926ad7b530ce49d433CB6f748f8D0a1).deltaPoolController())).priceHub();
 }
 function _seed() internal returns(AirdropInfrastructureSeed s){s=new AirdropInfrastructureSeed{value:0.01 ether}(pool,MARKET,builder,route,hub,GOV,address(this));}
 function _check(AirdropInfrastructureSeed s) internal view {
  assertEq(IERC721(manager).ownerOf(s.positionId()),GOV);assertGt(IYieldBankV3Pool(pool).liquidity(),0);
  assertEq(IERC20(WETH).balanceOf(address(s)),0);assertEq(IERC20(USDG).balanceOf(address(s)),0);
  assertEq(IERC20(WETH).allowance(address(s),address(route)),0);assertEq(IERC20(WETH).allowance(address(s),address(builder)),0);assertEq(IERC20(USDG).allowance(address(s),address(builder)),0);
 }
 function testAtomicSeedPaysGovernanceAndRefundsDust() public {_check(_seed());}
 function testSeedUsesExecutionTimeAfterTwoHourDeploymentDelay() public {vm.warp(block.timestamp+2 hours);_check(_seed());}
 function testActualSwapProceedsAfterMarketMovement() public {
  (bool ok,)=WETH.call{value:0.001 ether}(abi.encodeWithSignature("deposit()"));assertTrue(ok);IERC20(WETH).approve(address(route),0.001 ether);route.convert(0.001 ether,1,address(this),"");_check(_seed());
 }
 function testWrongValueAndAlreadyInitializedPoolReject() public {
  vm.expectRevert(AirdropInfrastructureSeed.InvalidSeed.selector);new AirdropInfrastructureSeed{value:0.011 ether}(pool,MARKET,builder,route,hub,GOV,address(this));
  (uint160 sqrt,,,,,,)=IYieldBankV3Pool(MARKET).slot0();ISeedTestInitialize(pool).initialize(sqrt);
  vm.expectRevert(AirdropInfrastructureSeed.InvalidSeed.selector);_seed();
 }
 function testUnavailablePriceRejectsBeforeWrappingETH() public {
  vm.mockCall(address(hub),abi.encodeCall(IPriceHub.quoteUsd18,(WETH)),abi.encode(uint256(0),uint48(0),IPriceHub.FailureReason.STALE_FEED));
  uint256 before=address(this).balance;vm.expectRevert(AirdropInfrastructureSeed.InvalidSeed.selector);_seed();assertEq(address(this).balance,before);assertEq(IERC20(WETH).balanceOf(address(this)),0);
 }
 function _artifact(string memory name,bytes memory args) private returns(address deployed){string memory data=vm.readFile(string.concat("deployments/stock-infrastructure/",name,".json"));bytes memory creation=abi.encodePacked(vm.parseJsonBytes(data,".bytecode"),args);assembly("memory-safe"){deployed:=create(0,add(creation,32),mload(creation))}require(deployed.code.length>0);}
}
