// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;
import {Test} from "forge-std/Test.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {ExecutionMarketV4Feed} from "../../src/yield-banks/airdrop/ExecutionMarketV4Feed.sol";
import {Token, Hub} from "./ExecutionMarketV3Feed.t.sol";
contract MarketViewFixture {
    address public immutable poolManager;
    bytes32 public id;
    uint160 public sqrt = uint160(1 << 96);
    uint128 public liquidity = 1e24;
    constructor(address manager) { poolManager = manager; }
    function set(bytes32 id_, uint160 sqrt_, uint128 liquidity_) external { id=id_; sqrt=sqrt_; liquidity=liquidity_; }
    function getSlot0(PoolId id_) external view returns(uint160,int24,uint24,uint24) { require(PoolId.unwrap(id_)==id);return(sqrt,0,0,0); }
    function getLiquidity(PoolId id_) external view returns(uint128) { require(PoolId.unwrap(id_)==id);return liquidity; }
}
contract ExecutionMarketV4FeedTest is Test {
    using PoolIdLibrary for PoolKey;
    Token token; Token quote; Hub hub; MarketViewFixture view_; ExecutionMarketV4Feed feed; PoolKey key;
    function setUp() public {
        vm.warp(1789530000);token=new Token(18);quote=new Token(18);hub=new Hub();view_=new MarketViewFixture(address(hub));
        key=PoolKey(Currency.wrap(address(token)<address(quote)?address(token):address(quote)),Currency.wrap(address(token)<address(quote)?address(quote):address(token)),3000,60,IHooks(address(0)));
        view_.set(PoolId.unwrap(key.toId()),uint160(1<<96),1e24);
        feed=new ExecutionMarketV4Feed(address(token),address(quote),address(view_),address(hub),key,1e12);
    }
    function testCurrentMarketWithoutPublisherOrAgeingObservation() public {
        vm.warp(block.timestamp+2 days);
        view_.set(PoolId.unwrap(key.toId()),uint160(uint256(1)<<97),1e24);
        (uint80 round,int256 price,,uint256 at,uint80 answered)=feed.latestRoundData();
        assertEq(round,block.timestamp);assertEq(at,block.timestamp);assertEq(answered,round);
        assertEq(uint256(price),address(token)<address(quote)?8000e18:500e18);
    }
    function testUnavailableUnderlierStillFails() public {hub.set(3);vm.expectRevert(ExecutionMarketV4Feed.PriceUnavailable.selector);feed.latestRoundData();}
    function testLiquidityAndUninitializedMarketFail() public {
        view_.set(PoolId.unwrap(key.toId()),uint160(1<<96),1);
        vm.expectRevert(ExecutionMarketV4Feed.PriceUnavailable.selector);feed.latestRoundData();
        view_.set(PoolId.unwrap(key.toId()),0,1e24);
        vm.expectRevert(ExecutionMarketV4Feed.PriceUnavailable.selector);feed.latestRoundData();
    }
    function testChangedStateReaderFails() public {vm.etch(address(view_),hex"00");vm.expectRevert(ExecutionMarketV4Feed.PriceUnavailable.selector);feed.latestRoundData();}
    function testUnknownMarketRejected() public {key.fee=500;vm.expectRevert();new ExecutionMarketV4Feed(address(token),address(quote),address(view_),address(hub),key,1e12);}
    function testWrongTokenPairRejected() public {Token other=new Token(18);vm.expectRevert(ExecutionMarketV4Feed.InvalidConfiguration.selector);new ExecutionMarketV4Feed(address(other),address(quote),address(view_),address(hub),key,1e12);}
    function testNativePoolRequiresCanonicalWrappedAsset() public {
        key.currency0=Currency.wrap(address(0));key.currency1=Currency.wrap(address(token));
        vm.expectRevert(ExecutionMarketV4Feed.InvalidConfiguration.selector);new ExecutionMarketV4Feed(address(token),address(quote),address(view_),address(hub),key,1e12);
        address canonical=0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;vm.etch(canonical,address(quote).code);
        view_.set(PoolId.unwrap(key.toId()),uint160(1<<96),1e24);
        ExecutionMarketV4Feed nativeFeed=new ExecutionMarketV4Feed(address(token),canonical,address(view_),address(hub),key,1e12);
        (,int256 value,,,)=nativeFeed.latestRoundData();assertEq(value,2000e18);
    }
    function testChangedHookFails() public {
        Token hook=new Token(18);key.hooks=IHooks(address(hook));view_.set(PoolId.unwrap(key.toId()),uint160(1<<96),1e24);
        ExecutionMarketV4Feed hooked=new ExecutionMarketV4Feed(address(token),address(quote),address(view_),address(hub),key,1e12);
        vm.etch(address(hook),hex"00");vm.expectRevert(ExecutionMarketV4Feed.PriceUnavailable.selector);hooked.latestRoundData();
    }
}
