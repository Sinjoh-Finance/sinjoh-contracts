// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

interface IMarketPool {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function liquidity() external view returns (uint128);
    function slot0() external view returns (uint160,int24,uint16,uint16,uint16,uint8,bool);
}
interface IMarketHub { function quoteUsd18(address) external view returns (uint256,uint48,uint8); }
interface IMarketToken { function decimals() external view returns (uint8); }

/// @notice Current pool price for isolated, owner-directed Airdrop positions.
/// @dev This is an execution reference, not an independent fair-value oracle.
/// Consumers must enforce owner-signed minimum outputs and isolate each bank's
/// principal. Do not use this feed to issue shared vault shares, credit or collateral.
contract ExecutionMarketV3Feed {
    uint8 public constant decimals = 18;
    string public constant description = "Sinjoh execution market / USD";
    address public immutable subject;
    address public immutable quoteAsset;
    IMarketPool public immutable pool;
    IMarketHub public immutable priceHub;
    uint128 public immutable minimumLiquidity;
    uint256 public immutable subjectScale;
    uint256 public immutable quoteScale;
    bool public immutable subjectIsToken0;
    bytes32 public immutable subjectHash;
    bytes32 public immutable quoteHash;
    bytes32 public immutable poolHash;
    bytes32 public immutable hubHash;
    error InvalidConfiguration();
    error PriceUnavailable();

    constructor(address subject_,address quote_,address pool_,address hub_,uint128 minimum_) {
        if (subject_.code.length==0 || quote_.code.length==0 || pool_.code.length==0 || hub_.code.length==0 || subject_==quote_ || minimum_==0) revert InvalidConfiguration();
        address t0=IMarketPool(pool_).token0();address t1=IMarketPool(pool_).token1();
        if (!((t0==subject_&&t1==quote_)||(t1==subject_&&t0==quote_))) revert InvalidConfiguration();
        uint8 sd=IMarketToken(subject_).decimals();uint8 qd=IMarketToken(quote_).decimals();
        if(sd>18||qd>18)revert InvalidConfiguration();
        subject=subject_;quoteAsset=quote_;pool=IMarketPool(pool_);priceHub=IMarketHub(hub_);minimumLiquidity=minimum_;
        subjectScale=10**sd;quoteScale=10**qd;subjectIsToken0=t0==subject_;
        subjectHash=subject_.codehash;quoteHash=quote_.codehash;poolHash=pool_.codehash;hubHash=hub_.codehash;
    }
    function latestRoundData() external view returns (uint80,int256,uint256,uint256,uint80) {
        if(subject.codehash!=subjectHash||quoteAsset.codehash!=quoteHash||address(pool).codehash!=poolHash||address(priceHub).codehash!=hubHash)revert PriceUnavailable();
        (uint160 sqrt,,,,,,bool unlocked)=pool.slot0();
        if(sqrt==0||!unlocked||pool.liquidity()<minimumLiquidity)revert PriceUnavailable();
        uint256 units;
        if(sqrt<=type(uint128).max){
            uint256 ratio=uint256(sqrt)*sqrt;
            units=subjectIsToken0?Math.mulDiv(ratio,subjectScale,1<<192):Math.mulDiv(1<<192,subjectScale,ratio);
        }else{
            uint256 ratio=Math.mulDiv(sqrt,sqrt,1<<64);
            units=subjectIsToken0?Math.mulDiv(ratio,subjectScale,1<<128):Math.mulDiv(1<<128,subjectScale,ratio);
        }
        (uint256 quote,uint48 at,uint8 failure)=priceHub.quoteUsd18(quoteAsset);
        if(failure!=0||quote==0||at==0||at>block.timestamp)revert PriceUnavailable();
        uint256 value=Math.mulDiv(units,quote,quoteScale);
        if(value==0)revert PriceUnavailable();
        // The quote asset's own hub enforces its freshness and market policy.
        // This timestamp describes a current pool observation, not a stored publisher update.
        uint80 round=SafeCast.toUint80(block.timestamp);
        return (round,SafeCast.toInt256(value),block.timestamp,block.timestamp,round);
    }
}
