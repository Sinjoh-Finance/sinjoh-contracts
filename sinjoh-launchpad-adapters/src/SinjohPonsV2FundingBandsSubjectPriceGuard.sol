// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { ISinjohPriceGuard } from "sinjoh-fee-router/src/interfaces/ISinjohPriceGuard.sol";
import { IPonsV2LaunchFactory } from "./interfaces/IPonsV2.sol";

interface IFundingBandsSubjectFloor {
    struct VerifiedLaunch {
        address creatorAtLaunch;
        address subject;
        uint8 venue;
        address quoteAsset;
        address pool;
        uint24 poolFee;
        int24 tickSpacing;
        address hooks;
        bytes32 poolId;
        uint256 launchSupply;
    }

    struct Account {
        address creator;
        uint8 profileId;
        uint8 bandCount;
        uint8 subjectDecimals;
        uint256 ethUsdE8;
        uint48 oracleUpdatedAt;
        bool exists;
        VerifiedLaunch launch;
    }

    struct Band {
        uint128 lowerMarketCapUsdE8;
        uint128 upperMarketCapUsdE8;
        uint256 lowerWethPerSubjectX128;
        uint256 upperWethPerSubjectX128;
        int24 tickLower;
        int24 tickUpper;
        uint8 destination;
        address recipient;
        uint8 status;
        uint256 positionId;
        uint128 liquidity;
        uint256 subjectResidual;
        uint256 cumulativeRealizedWeth;
        uint256 protocolFeeCharged;
        uint48 settlementArmedAt;
    }

    function getAccount(address subject) external view returns (Account memory);
    function getBand(address subject, uint8 bandId) external view returns (Band memory);
}

/// @notice Static, manipulation-resistant floor for subject proceeds returned
/// by Funding Bands. The price anchor is the highest settled band's immutable
/// lower boundary, not a same-transaction pool read.
contract SinjohPonsV2FundingBandsSubjectPriceGuard is ISinjohPriceGuard {
    uint256 private constant Q128 = 1 << 128;
    uint256 private constant BPS = 10_000;
    uint256 private constant EXECUTION_BPS = 9_500;
    uint8 private constant VENUE_UNISWAP_V4 = 1;
    uint8 private constant STATUS_SETTLED = 2;

    error InvalidAddress();
    error InvalidAmount();
    error InvalidRoute();
    error DependencyChanged();
    error InvalidFundingBandsAccount();
    error NoSettledBand();

    address public immutable launchFactory;
    address public immutable fundingBandsManager;
    address public immutable weth;
    bytes32 public immutable launchFactoryCodehash;
    bytes32 public immutable fundingBandsManagerCodehash;
    bytes32 public immutable wethCodehash;

    constructor(
        address launchFactory_,
        address fundingBandsManager_,
        address weth_,
        bytes32 launchFactoryCodehash_,
        bytes32 fundingBandsManagerCodehash_,
        bytes32 wethCodehash_
    ) {
        if (
            launchFactory_.code.length == 0 || fundingBandsManager_.code.length == 0
                || weth_.code.length == 0 || launchFactory_.codehash != launchFactoryCodehash_
                || fundingBandsManager_.codehash != fundingBandsManagerCodehash_
                || weth_.codehash != wethCodehash_
        ) revert InvalidAddress();
        launchFactory = launchFactory_;
        fundingBandsManager = fundingBandsManager_;
        weth = weth_;
        launchFactoryCodehash = launchFactoryCodehash_;
        fundingBandsManagerCodehash = fundingBandsManagerCodehash_;
        wethCodehash = wethCodehash_;
    }

    function minimumOutput(
        address subject,
        address assetIn,
        address assetOut,
        uint256 amountIn,
        bytes32 routeDataHash,
        bytes calldata guardData
    ) external view returns (uint256 minimum, uint48 validUntil) {
        if (
            subject == address(0) || subject != assetIn || assetOut != weth || amountIn == 0
                || amountIn > uint256(uint128(type(int128).max))
        ) revert InvalidAmount();
        if (routeDataHash != keccak256("") || guardData.length != 0) revert InvalidRoute();
        if (
            launchFactory.codehash != launchFactoryCodehash
                || fundingBandsManager.codehash != fundingBandsManagerCodehash
                || weth.codehash != wethCodehash
        ) revert DependencyChanged();

        IFundingBandsSubjectFloor manager = IFundingBandsSubjectFloor(fundingBandsManager);
        IFundingBandsSubjectFloor.Account memory account = manager.getAccount(subject);
        IPonsV2LaunchFactory.LaunchedToken memory launch =
            IPonsV2LaunchFactory(launchFactory).getLaunchedToken(subject);
        if (
            !account.exists || account.launch.subject != subject
                || account.launch.venue != VENUE_UNISWAP_V4
                || account.launch.quoteAsset != address(0) || !launch.exists
                || launch.token != subject || launch.pairToken != address(0) || launch.phase != 2
        ) revert InvalidFundingBandsAccount();

        uint256 referencePriceX128;
        for (uint8 i; i < account.bandCount; ++i) {
            IFundingBandsSubjectFloor.Band memory band = manager.getBand(subject, i);
            if (band.status >= STATUS_SETTLED && band.lowerWethPerSubjectX128 > referencePriceX128)
            {
                referencePriceX128 = band.lowerWethPerSubjectX128;
            }
        }
        if (referencePriceX128 == 0) revert NoSettledBand();
        minimum = _mulDiv(amountIn, referencePriceX128, Q128) * EXECUTION_BPS / BPS;
        if (minimum == 0) revert InvalidAmount();
        validUntil = type(uint48).max;
    }

    function _mulDiv(uint256 x, uint256 y, uint256 denominator)
        private
        pure
        returns (uint256 result)
    {
        unchecked {
            uint256 prod0;
            uint256 prod1;
            assembly ("memory-safe") {
                let mm := mulmod(x, y, not(0))
                prod0 := mul(x, y)
                prod1 := sub(sub(mm, prod0), lt(mm, prod0))
            }
            if (prod1 == 0) return prod0 / denominator;
            if (denominator <= prod1) revert InvalidAmount();
            uint256 remainder;
            assembly ("memory-safe") {
                remainder := mulmod(x, y, denominator)
                prod1 := sub(prod1, gt(remainder, prod0))
                prod0 := sub(prod0, remainder)
            }
            uint256 twos = denominator & (~denominator + 1);
            assembly ("memory-safe") {
                denominator := div(denominator, twos)
                prod0 := div(prod0, twos)
                twos := add(div(sub(0, twos), twos), 1)
            }
            prod0 |= prod1 * twos;
            uint256 inverse = (3 * denominator) ^ 2;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            result = prod0 * inverse;
        }
    }
}
