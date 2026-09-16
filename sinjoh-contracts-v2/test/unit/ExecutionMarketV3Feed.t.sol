// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;
import {Test} from "forge-std/Test.sol";
import {ExecutionMarketV3Feed} from "../../src/yield-banks/airdrop/ExecutionMarketV3Feed.sol";
contract Token { uint8 public immutable decimals; constructor(uint8 d){decimals=d;} }
contract Pool {
 address public token0;address public token1;uint128 public liquidity=10**24;uint160 public sqrt=uint160(1<<96);bool public unlocked=true;
 constructor(address a,address b){token0=a;token1=b;}
 function set(uint160 s,uint128 l,bool u) external {sqrt=s;liquidity=l;unlocked=u;}
 function slot0() external view returns(uint160,int24,uint16,uint16,uint16,uint8,bool){return(sqrt,0,0,2,2,0,unlocked);}
}
contract Hub {uint8 public failure;function set(uint8 f)external{failure=f;}function quoteUsd18(address)external view returns(uint256,uint48,uint8){return(2000e18,uint48(block.timestamp),failure);} }
contract ExecutionMarketV3FeedTest is Test {
 Token token;Token weth;Pool pool;Hub hub;ExecutionMarketV3Feed feed;
 function setUp() public {vm.warp(1789530000);token=new Token(18);weth=new Token(18);pool=new Pool(address(token),address(weth));hub=new Hub();feed=new ExecutionMarketV3Feed(address(token),address(weth),address(pool),address(hub),1e12);}
 function testOrdinaryMarketMovementDoesNotRequireAPublisherOrHistoricalBand() public { (,int256 initial,,,)=feed.latestRoundData();pool.set(uint160((uint256(1)<<96)*102/100),1e24,true);(,int256 moved,,,)=feed.latestRoundData();assertEq(initial,2000e18);assertApproxEqAbs(uint256(moved),20808e17,10000); }
 function testInverseMarketDirection() public {Pool inverse=new Pool(address(weth),address(token));ExecutionMarketV3Feed inverted=new ExecutionMarketV3Feed(address(token),address(weth),address(inverse),address(hub),1e12);inverse.set(uint160(uint256(1)<<97),1e24,true);(,int256 price,,,)=inverted.latestRoundData();assertEq(price,500e18);}
 function testTokenDecimalsAreNormalized() public {Token small=new Token(6);Pool normalized=new Pool(address(small),address(weth));normalized.set(uint160((uint256(1)<<96)*1e6),1e24,true);ExecutionMarketV3Feed six=new ExecutionMarketV3Feed(address(small),address(weth),address(normalized),address(hub),1e12);(,int256 value,,,)=six.latestRoundData();assertEq(value,2000e18);}
 function testUnavailableQuoteAssetRemainsUnavailable() public {hub.set(3);vm.expectRevert(ExecutionMarketV3Feed.PriceUnavailable.selector);feed.latestRoundData();}
 function testEmptyShallowAndLockedMarketsRemainUnavailable() public {pool.set(0,1e24,true);vm.expectRevert(ExecutionMarketV3Feed.PriceUnavailable.selector);feed.latestRoundData();pool.set(uint160(1<<96),1,true);vm.expectRevert(ExecutionMarketV3Feed.PriceUnavailable.selector);feed.latestRoundData();pool.set(uint160(1<<96),1e24,false);vm.expectRevert(ExecutionMarketV3Feed.PriceUnavailable.selector);feed.latestRoundData();}
 function testDependencyChangesRemainUnavailable() public {vm.etch(address(pool),hex"00");vm.expectRevert(ExecutionMarketV3Feed.PriceUnavailable.selector);feed.latestRoundData();}
 function testWrongMarketPairRejected() public {Token other=new Token(18);vm.expectRevert(ExecutionMarketV3Feed.InvalidConfiguration.selector);new ExecutionMarketV3Feed(address(other),address(weth),address(pool),address(hub),1e12);}
}
