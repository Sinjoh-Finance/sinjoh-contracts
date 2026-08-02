// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @dev Minimal, live Robinhood-chain Flap interfaces. Enum order and struct
/// layout are transcribed from the verified Portal v5.15.2 implementation.
interface IFlapPortalTypes {
    enum DexThreshType {
        TWO_THIRDS,
        FOUR_FIFTHS,
        HALF,
        _95_PERCENT,
        _81_PERCENT,
        _1_PERCENT
    }

    enum TokenVersion {
        TOKEN_LEGACY_MINT_NO_PERMIT,
        TOKEN_LEGACY_MINT_NO_PERMIT_DUPLICATE,
        TOKEN_V2_PERMIT,
        TOKEN_GOPLUS,
        TOKEN_TAXED,
        TOKEN_TAXED_V2,
        TOKEN_TAXED_V3,
        TOKEN_V3_PERMIT
    }

    enum MigratorType {
        V3_MIGRATOR,
        V2_MIGRATOR,
        V4_UNI_MIGRATOR,
        PCS_INFINITY_CL_MIGRATOR
    }

    enum V3LPFeeProfile {
        LP_FEE_PROFILE_STANDARD,
        LP_FEE_PROFILE_LOW,
        LP_FEE_PROFILE_HIGH
    }

    enum DEXId {
        DEX0,
        DEX1,
        DEX2
    }

    struct NewTokenV6Params {
        string name;
        string symbol;
        string meta;
        DexThreshType dexThresh;
        bytes32 salt;
        MigratorType migratorType;
        address quoteToken;
        uint256 quoteAmt;
        address beneficiary;
        bytes permitData;
        bytes32 extensionID;
        bytes extensionData;
        DEXId dexId;
        V3LPFeeProfile lpFeeProfile;
        uint16 buyTaxRate;
        uint16 sellTaxRate;
        uint64 taxDuration;
        uint64 antiFarmerDuration;
        uint16 mktBps;
        uint16 deflationBps;
        uint16 dividendBps;
        uint16 lpBps;
        uint256 minimumShareBalance;
        address dividendToken;
        address commissionReceiver;
        TokenVersion tokenVersion;
    }
}

interface IFlapPortal is IFlapPortalTypes {
    function newTokenV6(NewTokenV6Params calldata params) external payable returns (address token);
}

interface IFlapTaxTokenV3 {
    function taxProcessor() external view returns (address);
    function quoteToken() external view returns (address);
    function buyTaxRate() external view returns (uint16);
    function sellTaxRate() external view returns (uint16);
}

interface IFlapTaxProcessor {
    struct FeeConfig {
        uint16 marketBps;
        uint16 deflationBps;
        uint16 lpBps;
        uint16 dividendBps;
        uint16 feeRate;
        bool isWeth;
    }

    function dispatch() external;
    function taxToken() external view returns (address);
    function portal() external view returns (address);
    function owner() external view returns (address);
    function getQuoteToken() external view returns (address);
    function weth() external view returns (address);
    function marketAddress() external view returns (address);
    function commissionReceiver() external view returns (address);
    function commissionBps() external view returns (uint16);
    function feeConfig() external view returns (FeeConfig memory);
}

interface IFlapWeth {
    function deposit() external payable;
}
