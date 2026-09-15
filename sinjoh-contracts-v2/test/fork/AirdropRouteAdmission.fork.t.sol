// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;
import {AirdropRoutesForkTest} from "./AirdropRoutes.fork.t.sol";
import {PriceHub} from "../../src/yield-banks/PriceHub.sol";
import {IPriceHub} from "../../src/yield-banks/interfaces/IPriceHub.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {DeltaV3TwapUsdFeed} from "../../src/yield-banks/adapters/DeltaV3TwapUsdFeed.sol";
import {AirdropObservedV4UsdFeed} from "../../src/yield-banks/airdrop/AirdropObservedV4UsdFeed.sol";
import {AirdropObservationPublisher} from "../../src/yield-banks/airdrop/AirdropObservationPublisher.sol";
interface IAdmissionLiquidity{function liquidity() external view returns(uint128);}

/// Real complete-history oracle -> exact owner 5% minimum -> real purchase and sale.
/// No fabricated token balances, pool prices, Chainlink answers or minimum-one trades.
contract AirdropRouteAdmissionForkTest is AirdropRoutesForkTest {
    PriceHub constant HUB=PriceHub(0xF83C528b5Fe315A224eEA98E084644e24d39C20A);
    address constant WETH_FEED=0x78F3556b67E17Df817D51Ef5a990cDaF09E8d3A9;
    mapping(address=>bool) initialized;
    bool expectObservationRejected;
    AirdropObservationPublisher publisher;
    function setUp() public override {
        string memory rpc=vm.envOr("ROBINHOOD_MAINNET_RPC_URL",string(""));if(bytes(rpc).length==0)vm.skip(true);
        fixture=vm.readFile("deployments/airdrop-research/admission.json");
        vm.createSelectFork(rpc,vm.parseJsonUint(fixture,".block"));
        // Foundry's Ethereum VM lacks Arbitrum's native ArbSys precompile. Supply only
        // its exact canonical block context, never token prices or observation history.
        vm.mockCall(address(0x64),abi.encodeWithSignature("arbBlockNumber()"),abi.encode(vm.parseJsonUint(fixture,".block")));
        publisher=new AirdropObservationPublisher(address(this),address(this),new address[](0));
    }
    function testRoute_34_IRA() public override {
        // Approved catalog entry; 11% venue fee cannot satisfy the bank's 5% cap.
        // The route must reject it, without reducing the owner's minimum.
        vm.expectPartialRevert(bytes4(keccak256("InsufficientOutput(uint256,uint256)")));this.rehearseIRA();
    }
    function rehearseIRA() external {require(msg.sender==address(this));_rehearse(34,0.001 ether);}
    function testRoute_13_VenusCoin() public override {_historicalRehearse(13);}
    function testRoute_28_HI() public override {_historicalRehearse(28);}
    function testRoute_31_PIG() public override {_historicalRehearse(31);}
    function _historicalRehearse(uint256 index) private {
        require(index==13||index==28||index==31);
        fixture=vm.readFile("deployments/airdrop-research/admission-historical.json");
        vm.createSelectFork(vm.envString("ROBINHOOD_MAINNET_RPC_URL"),vm.parseJsonUint(fixture,".block"));
        vm.mockCall(address(0x64),abi.encodeWithSignature("arbBlockNumber()"),abi.encode(vm.parseJsonUint(fixture,".block")));
        publisher=new AirdropObservationPublisher(address(this),address(this),new address[](0));
        _rehearse(index,0.001 ether);
    }
    function testCurrentVenusCoinPriceDeviationRejectsAllocation() public {_requirePriceGuard(13);}
    function testCurrentHIPriceDeviationRejectsAllocation() public {_requirePriceGuard(28);}
    function testCurrentPIGPriceDeviationRejectsAllocation() public {_requirePriceGuard(31);}
    function _requirePriceGuard(uint256 index) private {
        expectObservationRejected=true;
        _configure(vm.parseJsonAddress(fixture,string.concat(".rows[",vm.toString(index),"].subject")));
    }
    function _configure(address subject) private {
        if(initialized[subject])return;initialized[subject]=true;
        string memory p;
        for(uint256 i;i<58;++i){string memory candidate=string.concat(".rows[",vm.toString(i),"]");if(vm.parseJsonAddress(fixture,string.concat(candidate,".subject"))==subject){p=candidate;break;}}
        require(bytes(p).length>0,"missing admission subject");
        address feed;
        if(keccak256(bytes(vm.parseJsonString(fixture,string.concat(p,".kind"))))==keccak256("v3")){
            address pool=vm.parseJsonAddress(fixture,string.concat(p,".pool"));
            feed=address(new DeltaV3TwapUsdFeed(subject,WETH,pool,FACTORY,WETH_FEED,pool.codehash,FACTORY.codehash,WETH_FEED.codehash,1800,300,uint128(10**IERC20Metadata(subject).decimals()),IAdmissionLiquidity(pool).liquidity()/2,"Sinjoh Airdrop V3 TWAP / USD"));
            vm.prank(HUB.timelock());HUB.configureFeed(subject,feed,address(0),86400,0,false,false,300);
            return;
        }
        address quote=vm.parseJsonAddress(fixture,string.concat(p,".quoteAsset"));
        if(quote!=WETH){address quoteFeed=vm.parseJsonAddress(fixture,string.concat(p,".quoteFeed"));vm.prank(HUB.timelock());HUB.configureFeed(quote,quoteFeed,address(0),86400,0,true,true,100);}
        PoolKey memory key=PoolKey(Currency.wrap(vm.parseJsonAddress(fixture,string.concat(p,".key.currency0"))),Currency.wrap(vm.parseJsonAddress(fixture,string.concat(p,".key.currency1"))),uint24(vm.parseJsonUint(fixture,string.concat(p,".key.fee"))),int24(vm.parseJsonInt(fixture,string.concat(p,".key.tickSpacing"))),IHooks(vm.parseJsonAddress(fixture,string.concat(p,".key.hooks"))));
        string memory o=string.concat(p,".observation");
        feed=address(new AirdropObservedV4UsdFeed(address(this),address(publisher),vm.parseJsonAddress(fixture,string.concat(p,".stateView")),address(HUB),subject,quote,key,uint128(vm.parseJsonUint(fixture,string.concat(o,".minimumLiquidity"))),300));
        publisher.configureFeed(feed,true);
        AirdropObservationPublisher.Observation[] memory rows=new AirdropObservationPublisher.Observation[](1);
        rows[0]=AirdropObservationPublisher.Observation(feed,int24(vm.parseJsonInt(fixture,string.concat(o,".meanTick"))),uint48(vm.parseJsonUint(fixture,string.concat(o,".observedAt"))),uint64(vm.parseJsonUint(fixture,string.concat(o,".observedBlock"))),vm.parseJsonBytes32(fixture,string.concat(o,".blockHash")),uint128(vm.parseJsonUint(fixture,string.concat(o,".lowestLiquidity"))),vm.parseJsonBytes32(fixture,string.concat(o,".evidenceHash")));
        vm.mockCall(address(0x64),abi.encodeWithSignature("arbBlockHash(uint256)",uint256(rows[0].blockNumber)),abi.encode(rows[0].blockHash));
        if(expectObservationRejected){
            assertEq(publisher.publish(rows),0,"market deviation should reject publication");
            vm.prank(address(publisher));vm.expectRevert(AirdropObservedV4UsdFeed.PriceUnavailable.selector);
            AirdropObservedV4UsdFeed(feed).observe(rows[0].tick,rows[0].timestamp,rows[0].blockNumber,rows[0].blockHash,rows[0].lowestLiquidity,rows[0].evidenceHash);
            return;
        }
        uint256 before=gasleft();assertEq(publisher.publish(rows),1,"real feed rejected observed history");emit log_named_uint("first publication gas",before-gasleft());
        vm.prank(HUB.timelock());HUB.configureFeed(subject,feed,address(0),120,0,false,false,300);
    }
    function _price(address asset) private view returns(uint256 value){IPriceHub.FailureReason reason;(value,,reason)=HUB.quoteUsd18(asset);assertEq(uint256(reason),0,"oracle unavailable");assertGt(value,0);}
    function _minimum(address input,address output,uint256 amount) private view returns(uint256){uint256 value=Math.mulDiv(amount,_price(input),10**IERC20Metadata(input).decimals());uint256 quote=Math.mulDiv(value,10**IERC20Metadata(output).decimals(),_price(output));return Math.mulDiv(quote,9500,10000,Math.Rounding.Ceil);}
    function _buyMinimum(address subject,uint256 amount) internal override returns(uint256){_configure(subject);return _minimum(WETH,subject,amount);}
    function _sellMinimum(address subject,uint256 amount) internal override returns(uint256){return _minimum(subject,WETH,amount);}
}
