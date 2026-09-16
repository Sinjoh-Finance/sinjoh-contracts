// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IStateView} from "@uniswap/v4-periphery/src/interfaces/IStateView.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IMarketHub, IMarketToken} from "./ExecutionMarketV3Feed.sol";

/// @notice Current pool price for isolated, owner-directed Airdrop positions.
/// @dev This is an execution reference, not an independent fair-value oracle.
/// Consumers must enforce owner-signed minimum outputs and isolate each bank's
/// principal. Do not use this feed to issue shared vault shares, credit or collateral.
contract ExecutionMarketV4Feed {
    using PoolIdLibrary for PoolKey;
    uint8 public constant decimals = 18;
    string public constant description = "Sinjoh execution market V4 / USD";
    address public immutable subject;
    address public immutable quoteAsset;
    IMarketHub public immutable priceHub;
    IStateView public immutable stateView;
    PoolId public immutable poolId;
    address public immutable poolManager;
    address public immutable hook;
    bytes32 public immutable subjectHash;
    bytes32 public immutable quoteHash;
    bytes32 public immutable hubHash;
    bytes32 public immutable viewHash;
    bytes32 public immutable managerHash;
    bytes32 public immutable hookHash;
    uint128 public immutable minimumLiquidity;
    uint256 public immutable subjectScale;
    uint256 public immutable quoteScale;
    bool public immutable subjectIsToken0;
    error InvalidConfiguration();
    error PriceUnavailable();

    constructor(address subject_, address quote_, address view_, address hub_, PoolKey memory key, uint128 minimum_) {
        if (subject_.code.length == 0 || quote_.code.length == 0 || view_.code.length == 0
            || hub_.code.length == 0 || subject_ == quote_ || minimum_ == 0) revert InvalidConfiguration();
        address t0 = Currency.unwrap(key.currency0);
        address t1 = Currency.unwrap(key.currency1);
        address normalizedQuote = quote_;
        if (t0 == address(0)) {
            if (quote_ != 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73) revert InvalidConfiguration();
            normalizedQuote = address(0);
        }
        if (t0 >= t1 || !((t0 == subject_ && t1 == normalizedQuote) || (t1 == subject_ && t0 == normalizedQuote))) revert InvalidConfiguration();
        uint8 sd = IMarketToken(subject_).decimals();
        uint8 qd = IMarketToken(quote_).decimals();
        if (sd > 18 || qd > 18) revert InvalidConfiguration();
        address manager = address(IStateView(view_).poolManager());
        if (manager.code.length == 0 || (address(key.hooks) != address(0) && address(key.hooks).code.length == 0)) revert InvalidConfiguration();
        subject = subject_; quoteAsset = quote_; priceHub = IMarketHub(hub_); stateView = IStateView(view_);
        poolManager = manager; poolId = key.toId(); hook = address(key.hooks);
        subjectHash = subject_.codehash; quoteHash = quote_.codehash; hubHash = hub_.codehash;
        viewHash = view_.codehash; managerHash = manager.codehash; hookHash = address(key.hooks).codehash;
        minimumLiquidity = minimum_; subjectScale = 10 ** sd; quoteScale = 10 ** qd; subjectIsToken0 = t0 == subject_;
        (uint160 sqrt,,,) = stateView.getSlot0(poolId);
        if (sqrt == 0 || stateView.getLiquidity(poolId) < minimum_) revert InvalidConfiguration();
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        if (subject.codehash != subjectHash || quoteAsset.codehash != quoteHash || address(priceHub).codehash != hubHash
            || address(stateView).codehash != viewHash || poolManager.codehash != managerHash
            || (hook != address(0) && hook.codehash != hookHash)) revert PriceUnavailable();
        (uint160 sqrt,,,) = stateView.getSlot0(poolId);
        if (sqrt == 0 || stateView.getLiquidity(poolId) < minimumLiquidity) revert PriceUnavailable();
        uint256 units;
        if (sqrt <= type(uint128).max) {
            uint256 ratio = uint256(sqrt) * sqrt;
            units = subjectIsToken0 ? Math.mulDiv(ratio, subjectScale, 1 << 192) : Math.mulDiv(1 << 192, subjectScale, ratio);
        } else {
            uint256 ratio = Math.mulDiv(sqrt, sqrt, 1 << 64);
            units = subjectIsToken0 ? Math.mulDiv(ratio, subjectScale, 1 << 128) : Math.mulDiv(1 << 128, subjectScale, ratio);
        }
        (uint256 quote, uint48 at, uint8 failure) = priceHub.quoteUsd18(quoteAsset);
        if (failure != 0 || quote == 0 || at == 0 || at > block.timestamp) revert PriceUnavailable();
        uint256 value = Math.mulDiv(units, quote, quoteScale);
        if (value == 0) revert PriceUnavailable();
        uint80 round = SafeCast.toUint80(block.timestamp);
        return (round, SafeCast.toInt256(value), block.timestamp, block.timestamp, round);
    }
}
