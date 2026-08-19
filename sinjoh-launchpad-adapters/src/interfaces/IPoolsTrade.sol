// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @dev Minimal transcriptions of the pools.trade (Uniswap liquidity-launcher)
/// surfaces the Sinjoh adapters touch, verified against the deployed, verified
/// source on Robinhood Chain mainnet (see POOLS-TRADE-FINDINGS.md):
///
///   LiquidityLauncher v3.2.0   0x0000FffFBE8efE702c8703aE3477FF5dE3d319C0
///   UERC20Factory v2.0.0       0x000000e200088D55C39a11F609E5F667729ad49b
///   InstantLaunchStrategy      0x23f8209572b4a1C2AD88A42749E830791Fb027f1 (creator fee)
///                              0xAD44D55E7f8337C3cE113fBb591486E85be104b2 (no creator fee)
///   FeeSplitter                0xeFF166AAf189323c58dc27eD1206EB2C37FaACDf / 0x222D6d…4359
///   UERC20BeneficiaryVault     0xd35E9CA72F64C7F93BE30fad67524323396B36D7
///   LBPStrategy v3.1.1         0x05d552391067389EE44fec3924157ed33F976000
///   CCA factory                0x000000001F26a0044BaA66024e7b6599c61963F8
///   TokenSplitter v3.2.0       0x4F5E3FBb9745358A92Da5674305FAb8D2B8a73cE
///   Uniswap v4 PoolManager     0x8366a39CC670B4001A1121B8F6A443A643e40951
///   Uniswap v4 PositionManager 0x58daec3116aae6D93017bAAea7749052E8a04fA7
///
/// Upstream `Currency` and `IHooks` are address-backed user-defined types and
/// `PoolId` is a bytes32 wrapper, so plain `address`/`bytes32` declarations
/// here are ABI-identical.

/// @dev `UERC20Metadata` from uerc20-factory. `extraData` is emitted and stored
/// on-chain but not rendered into the tokenURI JSON.
struct PTTokenMetadata {
    string description;
    string website;
    string image;
    bytes extraData;
}

/// @dev `Distribution` from liquidity-launcher. `amount` is uint128 upstream.
struct PTDistribution {
    address strategy;
    uint128 amount;
    bytes configData;
}

interface IPTLiquidityLauncher {
    function multicall(bytes[] calldata data) external payable returns (bytes[] memory results);

    function createToken(
        address factory,
        string calldata name,
        string calldata symbol,
        uint8 decimals,
        uint128 initialSupply,
        address recipient,
        bytes calldata tokenData
    ) external payable returns (address tokenAddress);

    function distributeToken(address token, PTDistribution calldata distribution, bytes32 salt)
        external
        payable;

    function getGraffiti(address originalCreator) external pure returns (bytes32 graffiti);
}

interface IPTUERC20Factory {
    function getUERC20Address(
        string memory name,
        string memory symbol,
        uint8 decimals,
        address creator,
        bytes32 graffiti
    ) external view returns (address);
}

/// @dev `InstantLaunchConfig` from InstantLaunchStrategy: the abi-encoded
/// `configData` of an instant distribution.
struct PTInstantLaunchConfig {
    address feeBeneficiary;
}

interface IPTInstantLaunchStrategy {
    function launcher() external view returns (address);
    function positionManager() external view returns (address);
    function poolManager() external view returns (address);
    function feeSplitter() external view returns (address);
    /// @dev Zero on the no-creator-fee variant.
    function beneficiaryVault() external view returns (address);
    function initialTick() external view returns (int24);
    // solhint-disable-next-line func-name-mixedcase
    function LP_FEE() external view returns (uint24);
    // solhint-disable-next-line func-name-mixedcase
    function TICK_SPACING() external view returns (int24);
    // solhint-disable-next-line func-name-mixedcase
    function TOTAL_SUPPLY() external view returns (uint256);
}

interface IPTFeeSplitter {
    /// @notice Permissionless: collects a locked position's accrued v4 fees and
    /// pushes the immutable splits.
    function collectFees(uint256[] calldata tokenIds) external;
    function positionManager() external view returns (address);
}

interface IPTBeneficiaryVault {
    /// @notice Pays the position's attributed amounts to the caller, which must
    /// be the owner of the beneficiary ("FEEB") NFT for `tokenId`. A zero
    /// attributed amount pays nothing and does not revert.
    function claim(uint256 tokenId, uint256 minCurrency0Amount, uint256 minCurrency1Amount) external;
    /// @dev solady ERC721: reverts for a nonexistent token.
    function ownerOf(uint256 tokenId) external view returns (address);
    function positionManager() external view returns (address);
}

interface IPTPositionManager {
    function nextTokenId() external view returns (uint256);
    function ownerOf(uint256 tokenId) external view returns (address);
    function poolManager() external view returns (address);
    /// @param unlockData `abi.encode(bytes actions, bytes[] params)`.
    function modifyLiquidities(bytes calldata unlockData, uint256 deadline) external payable;
    function getPoolAndPositionInfo(uint256 tokenId)
        external
        view
        returns (IPTPoolManager.PoolKey memory poolKey, uint256 info);
    function getPositionLiquidity(uint256 tokenId) external view returns (uint128 liquidity);
}

interface IPTPoolManager {
    struct PoolKey {
        address currency0;
        address currency1;
        uint24 fee;
        int24 tickSpacing;
        address hooks;
    }

    struct SwapParams {
        bool zeroForOne;
        int256 amountSpecified;
        uint160 sqrtPriceLimitX96;
    }

    function unlock(bytes calldata data) external returns (bytes memory);

    function swap(PoolKey memory key, SwapParams memory params, bytes calldata hookData)
        external
        returns (int256 swapDelta);

    function settle() external payable returns (uint256 paid);

    /// @dev ERC20 settlement is the singleton's sync -> transfer -> settle
    /// sequence; native settlement carries value on `settle` alone.
    function sync(address currency) external;

    function take(address currency, address to, uint256 amount) external;

    /// @dev Exposed by v4-core `Extsload`; used to read a pool's slot0 without
    /// the StateLibrary dependency.
    function extsload(bytes32 slot) external view returns (bytes32 value);
}

/// @dev `PoolParameters` from liquidity-launcher MigratorParams.
struct PTPoolParameters {
    uint24 fee;
    int24 tickSpacing;
    address hook;
}

/// @dev `PositionDefinition` from liquidity-launcher PositionPlannerTypes.
struct PTPositionDefinition {
    int24 offsetLower;
    int24 offsetUpper;
    uint24 weight;
    address overridePositionRecipient;
}

/// @dev `LiquidityAllocationBracket` from liquidity-launcher MigratorParams.
struct PTLiquidityAllocationBracket {
    uint128 lowerThreshold;
    uint24 rate;
}

/// @dev `MigratorParameters` from liquidity-launcher MigratorParams.
/// `positionDefinitions` is `abi.encode(PTPositionDefinition[])` and
/// `lpAllocationSchedule` is `abi.encode(PTLiquidityAllocationBracket[])`.
struct PTMigratorParameters {
    address token;
    address currency;
    uint64 migrationBlock;
    uint128 reservedTokenAmountForLP;
    address recipient;
    address positionRecipient;
    PTPoolParameters poolParameters;
    bytes positionDefinitions;
    bytes lpAllocationSchedule;
}

interface IPTLBPStrategy {
    /// @notice Permissionless once `migrationBlock` is reached. On internal
    /// failure the raise and LP reserve are recovered to the configured
    /// `recipient` and `MigrationFailed` is emitted instead of reverting.
    function migrate(address initializer) external;
    function initializers(address initializer) external view returns (PTMigratorParameters memory);
    function registeredPoolIds(bytes32 poolId) external view returns (address initializer);
    function poolManager() external view returns (address);
    function positionManager() external view returns (address);
    function initializerFactory() external view returns (address);
}

/// @dev `AuctionParameters` from continuous-clearing-auction: the abi-encoded
/// `initializerParams` half of an LBP distribution's `configData`.
struct PTAuctionParameters {
    address currency;
    address tokensRecipient;
    address fundsRecipient;
    uint64 startBlock;
    uint64 endBlock;
    uint64 claimBlock;
    uint256 tickSpacing;
    address validationHook;
    uint256 floorPrice;
    uint128 requiredCurrencyRaised;
    bytes auctionStepsData;
}

interface IPTAuctionFactory {
    function getAddress(
        address token,
        uint256 amount,
        bytes calldata configData,
        bytes32 salt,
        address sender
    ) external view returns (address distributor);
}

interface IPTAuction {
    /// @notice Sweeps unsold tokens to the configured tokens recipient, which
    /// must be the caller. Reverts `AuctionIsNotOver()` before `endBlock` and
    /// `CannotSweepTokens()` once already swept.
    function sweepUnsoldTokens() external;
    function token() external view returns (address);
    function currency() external view returns (address);
    function tokensRecipient() external view returns (address);
    function fundsRecipient() external view returns (address);
    function endBlock() external view returns (uint64);
}

/// @dev `Split` from liquidity-launcher ITokenSplitter: one leg of a
/// TokenSplitter distribution's `configData` (`abi.encode(Split[])`).
struct PTSplit {
    address recipient;
    uint256 amount;
}

interface IWETH9 {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
}
