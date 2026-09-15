// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;
import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPonsV2LaunchFactory, IPonsV2BondingCurve} from "sinjoh-launchpad-adapters/src/interfaces/IPonsV2.sol";
import {PonsLifecycleAllocationRoute} from "../../src/yield-banks/airdrop/PonsLifecycleAllocationRoute.sol";
import {PonsLifecycleStateView, IPonsObservedCurve} from "../../src/yield-banks/airdrop/PonsLifecycleStateView.sol";
import {DeltaV3SinglePoolRoute} from "../../src/yield-banks/adapters/DeltaV3SinglePoolRoute.sol";
interface IGraduationWETH { function deposit() external payable; }

contract AirdropGraduationForkTest is Test {
    address constant WETH=0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;
    IPonsV2LaunchFactory constant FACTORY=IPonsV2LaunchFactory(0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e);
    string fixture;
    receive() external payable {}
    function setUp() public {
        string memory rpc=vm.envOr("ROBINHOOD_MAINNET_RPC_URL",string(""));
        if(bytes(rpc).length==0)vm.skip(true);
        fixture=vm.readFile("deployments/airdrop-research/routes.json");
        vm.createSelectFork(rpc,vm.parseJsonUint(fixture,".block"));
    }
    function testVladchillRouteSurvivesGraduation() public { _transition(54,false); }
    function testBlackberryRouteSurvivesGraduation() public { _transition(55,false); }
    function testDropRouteSurvivesGraduation() public { _transition(56,false); }
    function testReadyCurveCompletesBothGraduationPhases() public { _transition(56,true); }
    function testStockPairedCurveAndItsPriceViewSurviveGraduation() public {
        address subject=vm.parseJsonAddress(fixture,".rows[57].subject");
        address pairPool=vm.parseJsonAddress(fixture,".rows[57].pool");
        address v3Factory=0x1f7d7550B1b028f7571E69A784071F0205FD2EfA;
        IPonsV2LaunchFactory.LaunchedToken memory launch=FACTORY.getLaunchedToken(subject);
        PonsLifecycleStateView state=new PonsLifecycleStateView(address(FACTORY),subject,0xF3334192D15450CdD385c8B70e03f9A6bD9E673b);
        PonsLifecycleAllocationRoute buy=new PonsLifecycleAllocationRoute(address(FACTORY),WETH,subject,true);
        PonsLifecycleAllocationRoute sell=new PonsLifecycleAllocationRoute(address(FACTORY),WETH,subject,false);
        DeltaV3SinglePoolRoute bridge=new DeltaV3SinglePoolRoute(pairPool,v3Factory,WETH,launch.pairToken,pairPool.codehash,v3Factory.codehash);
        vm.deal(address(this),20 ether);IGraduationWETH(WETH).deposit{value:20 ether}();
        IERC20(WETH).approve(address(bridge),20 ether);
        uint256 quote=bridge.convert(20 ether,launch.graduationThreshold*3,address(this),"");
        uint256 small=quote/20000;
        IERC20(launch.pairToken).approve(address(buy),small);
        uint256 held=buy.convert(small,1,address(this),"");
        IERC20(launch.pairToken).approve(launch.curve,quote-small);
        IPonsV2BondingCurve(launch.curve).buy(quote-small,1,address(0xBEEF));
        IERC20(launch.pairToken).approve(launch.curve,0);
        assertEq(FACTORY.getLaunchedToken(subject).phase,1);
        (uint160 beforeSqrt,,,)=state.getSlot0(state.poolId());
        IERC20(subject).approve(address(sell),held);
        assertGt(sell.convert(held,1,address(this),""),0);
        assertEq(FACTORY.getLaunchedToken(subject).phase,2);
        (uint160 afterSqrt,,,)=state.getSlot0(state.poolId());
        assertApproxEqRel(uint256(beforeSqrt),uint256(afterSqrt),0.01 ether);
        assertGt(state.getLiquidity(state.poolId()),0);
        assertEq(IERC20(subject).balanceOf(address(this)),0);
        assertEq(IERC20(launch.pairToken).balanceOf(address(buy)),0);
        assertEq(IERC20(launch.pairToken).allowance(address(buy),launch.curve),0);
    }
    function testOversizedCurveFillRevertsWithoutChangingPrincipalOrPhase() public {
        address subject=vm.parseJsonAddress(fixture,".rows[56].subject");
        IPonsV2LaunchFactory.LaunchedToken memory launch=FACTORY.getLaunchedToken(subject);
        PonsLifecycleAllocationRoute buy=new PonsLifecycleAllocationRoute(address(FACTORY),WETH,subject,true);
        uint256 amount=launch.graduationThreshold*3;
        vm.deal(address(this),amount);IGraduationWETH(WETH).deposit{value:amount}();
        IERC20(WETH).approve(address(buy),amount);
        uint256 curveTokens=IERC20(subject).balanceOf(launch.curve);
        vm.expectRevert();buy.convert(amount,1,address(this),"");
        assertEq(IERC20(WETH).balanceOf(address(this)),amount);
        assertEq(IERC20(subject).balanceOf(address(this)),0);
        assertEq(IERC20(subject).balanceOf(launch.curve),curveTokens);
        assertEq(FACTORY.getLaunchedToken(subject).phase,0);
        assertEq(address(buy).balance,0);
    }
    function _transition(uint256 index,bool deferSweep) private {
        address subject=vm.parseJsonAddress(fixture,string.concat(".rows[",vm.toString(index),"].subject"));
        IPonsV2LaunchFactory.LaunchedToken memory launch=FACTORY.getLaunchedToken(subject);
        assertEq(launch.phase,0);assertEq(launch.pairToken,address(0));
        PonsLifecycleStateView state=new PonsLifecycleStateView(address(FACTORY),subject,0xF3334192D15450CdD385c8B70e03f9A6bD9E673b);
        (uint160 initialSqrt,,,)=state.getSlot0(state.poolId());
        assertGt(initialSqrt,0);assertGt(state.getLiquidity(state.poolId()),0);
        PonsLifecycleAllocationRoute buy=new PonsLifecycleAllocationRoute(address(FACTORY),WETH,subject,true);
        PonsLifecycleAllocationRoute sell=new PonsLifecycleAllocationRoute(address(FACTORY),WETH,subject,false);
        vm.deal(address(this),launch.graduationThreshold*3+0.002 ether);
        IGraduationWETH(WETH).deposit{value:0.001 ether}();
        IERC20(WETH).approve(address(buy),0.001 ether);
        uint256 held=buy.convert(0.001 ether,1,address(this),"");
        assertGt(held,0);
        // A separate buyer crosses the real curve. No subject balances or curve storage are fabricated.
        // The deferred case models the factory call failing during the crossing buy; the next route retries it.
        bytes memory graduateCall=abi.encodeWithSignature("graduate(address)",subject);
        if(deferSweep)vm.mockCallRevert(address(FACTORY),graduateCall,abi.encodeWithSignature("Error(string)","temporary failure"));
        IPonsV2BondingCurve(launch.curve).buy{value:launch.graduationThreshold*3}(launch.graduationThreshold*3,1,address(0xBEEF));
        if(deferSweep){vm.clearMockedCalls();assertEq(FACTORY.getLaunchedToken(subject).phase,0);assertTrue(IPonsV2BondingCurve(launch.curve).readyToGraduate());}
        else assertEq(FACTORY.getLaunchedToken(subject).phase,1);
        (uint160 crossingSqrt,,,)=state.getSlot0(state.poolId());
        assertGt(crossingSqrt,0);assertGt(state.getLiquidity(state.poolId()),0);
        IERC20(subject).approve(address(sell),held);
        uint256 returned=sell.convert(held,1,address(this),"");
        assertGt(returned,0);assertEq(FACTORY.getLaunchedToken(subject).phase,2);
        (uint160 poolSqrt,,,)=state.getSlot0(state.poolId());
        assertGt(poolSqrt,0);assertGt(state.getLiquidity(state.poolId()),0);
        // The small holder's exit moves price, but graduation itself preserves curve pricing.
        assertApproxEqRel(uint256(poolSqrt),uint256(crossingSqrt),0.01 ether);
        assertEq(IERC20(subject).balanceOf(address(this)),0);
        // The original entry route also trades the newly created pool without redeployment.
        IERC20(WETH).approve(address(buy),returned);
        uint256 again=buy.convert(returned,1,address(this),"");
        assertGt(again,0);assertEq(IERC20(subject).balanceOf(address(this)),again);
        assertEq(address(buy).balance,0);assertEq(address(sell).balance,0);
        assertEq(IERC20(subject).balanceOf(address(sell)),0);
        assertEq(IERC20(WETH).allowance(address(buy),launch.curve),0);
        assertEq(IERC20(subject).allowance(address(sell),launch.curve),0);
    }
}
