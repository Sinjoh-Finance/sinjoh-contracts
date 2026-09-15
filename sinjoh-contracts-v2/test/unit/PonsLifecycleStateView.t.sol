// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;
import {Test} from "forge-std/Test.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {IPonsV2LaunchFactory} from "sinjoh-launchpad-adapters/src/interfaces/IPonsV2.sol";
import {PonsLifecycleStateView} from "../../src/yield-banks/airdrop/PonsLifecycleStateView.sol";
contract LifeCurveFixture {
    uint256 public realQuoteReserve=100 ether;
    uint256 public phantomQuote=100 ether;
    uint256 public tokenReserve=200 ether;
    function set(uint256 q,uint256 t) external{realQuoteReserve=q;tokenReserve=t;}
    function getReserves() external view returns(uint256,uint256){return(realQuoteReserve+phantomQuote,tokenReserve);}
}
contract LifeFactoryFixture {
    IPonsV2LaunchFactory.LaunchedToken launch;
    address public poolManager=address(this);
    address public memeHook=address(this);
    constructor(address curve){launch.token=address(this);launch.curve=curve;launch.exists=true;launch.tickSpacing=200;}
    function setPhase(uint8 phase) external{launch.phase=phase;launch.sweptQuote=100 ether;launch.sweptTokens=200 ether;}
    function setPair(address pair) external{launch.pairToken=pair;}
    function getLaunchedToken(address) external view returns(IPonsV2LaunchFactory.LaunchedToken memory){return launch;}
}
contract LifeCanonicalFixture {
    address public poolManager;
    constructor(address manager){poolManager=manager;}
    function getSlot0(PoolId) external pure returns(uint160,int24,uint24,uint24){return(uint160(1<<96),0,10,20);}
    function getLiquidity(PoolId) external pure returns(uint128){return 300 ether;}
}
contract PonsLifecycleStateViewTest is Test {
    LifeCurveFixture curve;
    LifeFactoryFixture factory;
    LifeCanonicalFixture canonical;
    PonsLifecycleStateView state;
    PoolId id;
    function setUp() public {
        curve=new LifeCurveFixture();factory=new LifeFactoryFixture(address(curve));canonical=new LifeCanonicalFixture(address(factory));
        state=new PonsLifecycleStateView(address(factory),address(factory),address(canonical));
        id=state.poolId();
    }
    function testCurveUsesVirtualReservesForPriceButRealReservesForLiquidity() public {
        (uint160 sqrt,int24 tick,,)=state.getSlot0(id);assertEq(sqrt,1<<96);assertEq(tick,0);
        uint128 liquidity=state.getLiquidity(id);assertGt(liquidity,141 ether);assertLt(liquidity,142 ether);
        curve.set(0,200 ether);assertEq(state.getLiquidity(id),0);
        (sqrt,tick,,)=state.getSlot0(id);assertGt(sqrt,1<<96);assertGt(tick,0);
    }
    function testSweepPreservesThePreGraduationPrice() public {
        (uint160 beforeSqrt,,,)=state.getSlot0(id);uint128 beforeLiquidity=state.getLiquidity(id);
        factory.setPhase(1);curve.set(0,0);
        (uint160 afterSqrt,,,)=state.getSlot0(id);assertEq(beforeSqrt,afterSqrt);assertEq(beforeLiquidity,state.getLiquidity(id));
    }
    function testGraduatedMarketDelegatesToCanonicalPoolState() public {
        factory.setPhase(2);curve.set(0,0);
        (uint160 sqrt,int24 tick,uint24 protocol,uint24 lp)=state.getSlot0(id);
        assertEq(sqrt,1<<96);assertEq(tick,0);assertEq(protocol,10);assertEq(lp,20);assertEq(state.getLiquidity(id),300 ether);
    }
    function testRescuedMarketCannotProvidePricesOrLiquidity() public {
        factory.setPhase(3);vm.expectRevert(PonsLifecycleStateView.InvalidMarket.selector);state.getSlot0(id);
        vm.expectRevert(PonsLifecycleStateView.InvalidMarket.selector);state.getLiquidity(id);
    }
    function testWrongPoolCannotBorrowAnotherSubjectsState() public {
        vm.expectRevert(PonsLifecycleStateView.InvalidMarket.selector);state.getSlot0(PoolId.wrap(keccak256("wrong")));
    }
    function testZeroTokenReserveFailsClosed() public {curve.set(100 ether,0);vm.expectRevert(PonsLifecycleStateView.InvalidMarket.selector);state.getSlot0(id);}
    function testFactoryCodeChangeStopsObservations() public {vm.etch(address(factory),hex"00");vm.expectRevert();state.getSlot0(id);}
    function testCurveCodeChangeStopsObservations() public {vm.etch(address(curve),hex"00");vm.expectRevert();state.getLiquidity(id);}
    function testCanonicalViewCodeChangeStopsObservations() public {factory.setPhase(2);vm.etch(address(canonical),hex"00");vm.expectRevert();state.getSlot0(id);}
    function testReverseCurrencyOrderInvertsCurvePrice() public {
        factory.setPair(address(type(uint160).max));
        PonsLifecycleStateView reversed=new PonsLifecycleStateView(address(factory),address(factory),address(canonical));
        assertTrue(reversed.subjectIsToken0());curve.set(100 ether,100 ether);
        (,int24 tick,,)=reversed.getSlot0(reversed.poolId());assertGt(tick,0);
        vm.expectRevert(PonsLifecycleStateView.InvalidMarket.selector);state.getSlot0(id);
    }
    function testRescuedOrMismatchedMarketCannotBeConfigured() public {
        factory.setPhase(3);vm.expectRevert(PonsLifecycleStateView.InvalidMarket.selector);new PonsLifecycleStateView(address(factory),address(factory),address(canonical));
        factory.setPhase(0);vm.expectRevert(PonsLifecycleStateView.InvalidMarket.selector);new PonsLifecycleStateView(address(factory),address(curve),address(canonical));
    }
}
