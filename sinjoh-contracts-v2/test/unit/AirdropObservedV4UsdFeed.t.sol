// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;
import { Test } from "forge-std/Test.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { PoolId } from "@uniswap/v4-core/src/types/PoolId.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { IPriceHub } from "../../src/yield-banks/interfaces/IPriceHub.sol";
import {
    AirdropObservedV4UsdFeed
} from "../../src/yield-banks/airdrop/AirdropObservedV4UsdFeed.sol";
import { AirdropObservationPublisher } from "../../src/yield-banks/airdrop/AirdropObservationPublisher.sol";

contract AirFeedToken is ERC20 {
    constructor() ERC20("fixture", "FIX") { }
}

contract AirFeedView {
    address public poolManager = address(this);
    int24 public tick;
    uint128 public liquidity = 1e18;

    function set(int24 t, uint128 l) external {
        tick = t;
        liquidity = l;
    }

    function getSlot0(PoolId) external view returns (uint160, int24, uint24, uint24) {
        return (TickMath.getSqrtPriceAtTick(tick), tick, 0, 0);
    }

    function getLiquidity(PoolId) external view returns (uint128) {
        return liquidity;
    }
}

contract AirFeedHub {
    IPriceHub.FailureReason public failure;
    uint48 public age;
    function setAge(uint48 age_) external { age = age_; }

    function set(IPriceHub.FailureReason f) external {
        failure = f;
    }

    function quoteUsd18(address) external view returns (uint256, uint48, IPriceHub.FailureReason) {
        return (2e18, uint48(block.timestamp) - age, failure);
    }
}

contract AirdropObservedV4UsdFeedTest is Test {
    AirdropObservedV4UsdFeed feed;
    AirFeedView view_;
    AirFeedHub hub;
    address observer = address(0xB0B);
    address token;
    address quote;

    function setUp() public {
        token = address(new AirFeedToken());
        quote = address(new AirFeedToken());
        view_ = new AirFeedView();
        hub = new AirFeedHub();
        PoolKey memory key = PoolKey(
            Currency.wrap(token < quote ? token : quote),
            Currency.wrap(token < quote ? quote : token),
            0,
            200,
            IHooks(address(0))
        );
        feed = new AirdropObservedV4UsdFeed(
            address(this), observer, address(view_), address(hub), token, quote, key, 1e12, 300
        );
        vm.warp(10000);
        vm.roll(99);
        vm.mockCall(
            address(0x64), abi.encodeWithSignature("arbBlockNumber()"), abi.encode(uint256(1000))
        );
        vm.mockCall(
            address(0x64),
            abi.encodeWithSignature("arbBlockHash(uint256)", 988),
            abi.encode(keccak256("block"))
        );
    }

    function observe() internal {
        vm.prank(observer);
        feed.observe(0, 9990, 988, keccak256("block"), 1e18, keccak256("evidence"));
    }

    function testObservedPriceUsesQuoteAssetAndFreshTimestamp() public {
        observe();
        (uint80 r, int256 price,, uint256 at, uint80 ar) = feed.latestRoundData();
        assertEq(r, 1);
        assertEq(ar, 1);
        assertEq(price, 2e18);
        assertEq(at, 9990);
    }

    function testFreshSubjectAcceptsOlderQuoteAlreadyValidatedByPriceHub() public {
        hub.setAge(3600);
        observe();
        (, int256 price,, uint256 at,) = feed.latestRoundData();
        assertEq(price, 2e18);
        assertEq(at, 9990);
        hub.set(IPriceHub.FailureReason.STALE_FEED);
        vm.expectRevert(AirdropObservedV4UsdFeed.PriceUnavailable.selector);
        feed.latestRoundData();
    }

    function testOlderL2BlockUsesExplicitObserverAttestation() public {
        vm.mockCall(
            address(0x64), abi.encodeWithSignature("arbBlockNumber()"), abi.encode(uint256(2000))
        );
        observe();
        (, int256 value,,,) = feed.latestRoundData();
        assertEq(value, 2e18);
    }

    function testUninitializedFeedReverts() public {
        vm.expectRevert(AirdropObservedV4UsdFeed.PriceUnavailable.selector);
        feed.latestRoundData();
    }

    function testOnlyObserverCanPublish() public {
        vm.expectRevert(AirdropObservedV4UsdFeed.InvalidObservation.selector);
        feed.observe(0, 9990, 988, keccak256("block"), 1e18, keccak256("evidence"));
    }

    function testStaleObservationReverts() public {
        observe();
        vm.warp(10111);
        vm.expectRevert(AirdropObservedV4UsdFeed.PriceUnavailable.selector);
        feed.latestRoundData();
    }

    function testReplayReverts() public {
        observe();
        vm.prank(observer);
        vm.expectRevert(AirdropObservedV4UsdFeed.InvalidObservation.selector);
        feed.observe(0, 9990, 988, keccak256("block"), 1e18, keccak256("evidence"));
    }

    function testUnconfirmedOrWrongBlockHashReverts() public {
        vm.prank(observer);
        vm.expectRevert(AirdropObservedV4UsdFeed.InvalidObservation.selector);
        feed.observe(0, 9990, 988, keccak256("wrong"), 1e18, keccak256("evidence"));
    }

    function testSpotManipulationReverts() public {
        observe();
        view_.set(1000, 1e18);
        vm.expectRevert(AirdropObservedV4UsdFeed.PriceUnavailable.selector);
        feed.latestRoundData();
    }

    function testLiquidityRemovalReverts() public {
        observe();
        view_.set(0, 1);
        vm.expectRevert(AirdropObservedV4UsdFeed.PriceUnavailable.selector);
        feed.latestRoundData();
    }

    function testHistoricalLiquidityFloorEnforced() public {
        vm.prank(observer);
        vm.expectRevert(AirdropObservedV4UsdFeed.InvalidObservation.selector);
        feed.observe(0, 9990, 988, keccak256("block"), 1, keccak256("evidence"));
    }

    function testUnderlyingOracleFailurePropagates() public {
        observe();
        hub.set(IPriceHub.FailureReason.STALE_FEED);
        vm.expectRevert(AirdropObservedV4UsdFeed.PriceUnavailable.selector);
        feed.latestRoundData();
    }

    function testCodeChangeStopsPricing() public {
        observe();
        vm.etch(token, hex"00");
        vm.expectRevert();
        feed.latestRoundData();
    }

    function testReviewedBatchPublisherCanBeAuthorizedWithoutChangingSharedECDSASignerPolicy() public {
        address publisher=address(new AirFeedHub());
        feed.setQuoteSigner(publisher);
        vm.prank(publisher);feed.observe(0,9990,988,keccak256("block"),1e18,keccak256("evidence"));
        (,int256 price,,,)=feed.latestRoundData();assertEq(price,2e18);
        vm.prank(observer);vm.expectRevert();feed.setQuoteSigner(observer);
    }
    function testBatchPublisherUpdatesActualFeedWithinItsGasBoundAndRejectsReplay() public {
        AirdropObservationPublisher publisher=new AirdropObservationPublisher(address(this),observer,new address[](0));
        feed.setQuoteSigner(address(publisher));publisher.configureFeed(address(feed),true);
        AirdropObservationPublisher.Observation[] memory rows=new AirdropObservationPublisher.Observation[](1);
        rows[0]=AirdropObservationPublisher.Observation(address(feed),0,9990,988,keccak256("block"),1e18,keccak256("evidence"));
        vm.prank(observer);assertEq(publisher.publish(rows),1);
        (,int256 price,,,)=feed.latestRoundData();assertEq(price,2e18);
        vm.prank(observer);assertEq(publisher.publish(rows),0);
        assertEq(feed.roundId(),1);
    }
    function testSignerRotationRevokesOldObserver() public {
        feed.setQuoteSigner(address(0xCAFE));
        vm.prank(observer);
        vm.expectRevert(AirdropObservedV4UsdFeed.InvalidObservation.selector);
        feed.observe(0, 9990, 988, keccak256("block"), 1e18, keccak256("evidence"));
    }
}
