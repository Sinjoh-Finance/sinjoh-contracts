// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IStateView} from "@uniswap/v4-periphery/src/interfaces/IStateView.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId,PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IPonsV2LaunchFactory} from "sinjoh-launchpad-adapters/src/interfaces/IPonsV2.sol";
import {IntegrationBinding} from "../libraries/IntegrationBinding.sol";

interface IPonsObservedCurve {
    function getReserves() external view returns(uint256,uint256);
    function realQuoteReserve() external view returns(uint256);
    function phantomQuote() external view returns(uint256);
}

/// @notice One immutable Pons market's observable state across curve, sweep and V4 phases.
/// @dev This is a spot-state adapter, never a standalone price oracle. A trusted history
/// observer must cover curve AND factory events as well as V4 events before publishing a
/// TWAP. Virtual curve reserves determine price; only real reserves support the liquidity floor.
contract PonsLifecycleStateView {
    using PoolIdLibrary for PoolKey;
    using SafeCast for uint256;
    IPonsV2LaunchFactory public immutable factory;
    address public immutable subject;
    address public immutable curve;
    address public immutable pairToken;
    uint24 public immutable poolFee;
    int24 public immutable tickSpacing;
    address public immutable poolManager;
    IStateView public immutable canonicalView;
    PoolId public immutable poolId;
    bool public immutable subjectIsToken0;
    bytes32 public immutable factoryHash;
    bytes32 public immutable curveHash;
    bytes32 public immutable viewHash;
    error InvalidMarket();

    constructor(address factory_,address subject_,address view_){
        if(factory_.code.length==0||subject_.code.length==0||view_.code.length==0)revert InvalidMarket();
        factory=IPonsV2LaunchFactory(factory_);subject=subject_;canonicalView=IStateView(view_);
        IPonsV2LaunchFactory.LaunchedToken memory launch=factory.getLaunchedToken(subject_);
        if(!launch.exists||launch.token!=subject_||launch.curve.code.length==0||launch.phase>2)revert InvalidMarket();
        poolManager=factory.poolManager();
        if(poolManager!=address(canonicalView.poolManager()))revert InvalidMarket();
        curve=launch.curve;pairToken=launch.pairToken;poolFee=launch.poolFee;tickSpacing=launch.tickSpacing;factoryHash=factory_.codehash;curveHash=launch.curve.codehash;viewHash=view_.codehash;
        bool first=subject_<launch.pairToken;subjectIsToken0=first;
        PoolKey memory key=PoolKey(Currency.wrap(first?subject_:launch.pairToken),Currency.wrap(first?launch.pairToken:subject_),launch.poolFee,launch.tickSpacing,IHooks(factory.memeHook()));
        poolId=key.toId();
    }
    function getSlot0(PoolId id) external view returns(uint160 sqrtPriceX96,int24 tick,uint24 protocolFee,uint24 lpFee){
        IPonsV2LaunchFactory.LaunchedToken memory launch=_market(id);
        if(launch.phase==2)return canonicalView.getSlot0(id);
        (uint256 quoteReserve,uint256 tokenReserve,)=_reserves(launch);
        uint256 r0=subjectIsToken0?tokenReserve:quoteReserve;
        uint256 r1=subjectIsToken0?quoteReserve:tokenReserve;
        if(r0==0||r1==0)revert InvalidMarket();
        // Q128 followed by sqrt avoids overflowing a Q192 ratio for inverted low-priced
        // tokens. The final tick is rounded down, matching canonical V4 tick semantics.
        sqrtPriceX96=(Math.sqrt(Math.mulDiv(r1,1<<128,r0))<<32).toUint160();
        if(sqrtPriceX96<TickMath.MIN_SQRT_PRICE||sqrtPriceX96>=TickMath.MAX_SQRT_PRICE)revert InvalidMarket();
        tick=TickMath.getTickAtSqrtPrice(sqrtPriceX96);
        return(sqrtPriceX96,tick,0,0);
    }
    function getLiquidity(PoolId id) external view returns(uint128){
        IPonsV2LaunchFactory.LaunchedToken memory launch=_market(id);
        if(launch.phase==2)return canonicalView.getLiquidity(id);
        (,uint256 tokens,uint256 realQuote)=_reserves(launch);
        return Math.sqrt(Math.mulDiv(realQuote,tokens,1)).toUint128();
    }
    function _market(PoolId id) private view returns(IPonsV2LaunchFactory.LaunchedToken memory launch){
        if(PoolId.unwrap(id)!=PoolId.unwrap(poolId))revert InvalidMarket();
        IntegrationBinding.requireBound(address(factory),factoryHash);
        IntegrationBinding.requireBound(curve,curveHash);
        IntegrationBinding.requireBound(address(canonicalView),viewHash);
        launch=factory.getLaunchedToken(subject);
        if(!launch.exists||launch.token!=subject||launch.curve!=curve||launch.pairToken!=pairToken||launch.poolFee!=poolFee||launch.tickSpacing!=tickSpacing||launch.phase>2)revert InvalidMarket();
    }
    function _reserves(IPonsV2LaunchFactory.LaunchedToken memory launch) private view returns(uint256 quote,uint256 tokens,uint256 realQuote){
        if(launch.phase==0){(quote,tokens)=IPonsObservedCurve(curve).getReserves();realQuote=IPonsObservedCurve(curve).realQuoteReserve();}
        else {realQuote=launch.sweptQuote;tokens=launch.sweptTokens;quote=realQuote+IPonsObservedCurve(curve).phantomQuote();}
    }
}
