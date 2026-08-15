// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { PoolId, PoolIdLibrary } from "@uniswap/v4-core/src/types/PoolId.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { IPositionManager } from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import { LiquidityAmounts } from "@uniswap/v4-periphery/src/libraries/LiquidityAmounts.sol";
import { IAllowanceTransfer } from "permit2/src/interfaces/IAllowanceTransfer.sol";

import { FundingBandMath } from "./FundingBandMath.sol";
import { FundingBandV4 } from "./FundingBandV4.sol";
import { IChainlinkAggregatorV3 } from "./interfaces/IChainlinkAggregatorV3.sol";
import { ISinjohFeeRouterView } from "./interfaces/ISinjohFeeRouterView.sol";
import { ISinjohFundingBandPriceGuard } from "./interfaces/ISinjohFundingBandPriceGuard.sol";
import { ISinjohLaunchVerifier } from "./interfaces/ISinjohLaunchVerifier.sol";
import { IUniswapV3PositionManager } from "./interfaces/IUniswapV3PositionManager.sol";

interface IV4StateView {
    function poolManager() external view returns (address);

    function getSlot0(PoolId poolId)
        external
        view
        returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee);
}

interface IV4PositionManagerState {
    function poolManager() external view returns (address);
}

interface IV4FundingBandArmGuard {
    function validateArm(
        ISinjohLaunchVerifier.VerifiedLaunch calldata launch,
        int24 boundaryTick,
        bool subjectIsToken0,
        bytes calldata guardData
    ) external view;
}

interface IWETH is IERC20 {
    function deposit() external payable;
}

interface ISinjohFundingBandsEscrowState {
    function isPrepared(address subject) external view returns (bool);
}

contract SinjohFundingBands is ReentrancyGuard {
    using PoolIdLibrary for PoolKey;
    using SafeERC20 for IERC20;

    uint256 private constant ROBINHOOD_CHAIN_ID = 4663;
    uint16 private constant BPS = 10_000;
    uint16 private constant PROTOCOL_FEE_BPS = 100;
    uint8 private constant MAX_BANDS = 10;
    uint16 private constant MAX_DYNAMIC_BYTES = 1_024;
    uint48 private constant DEADLINE_WINDOW = 300;
    uint48 public constant V4_SETTLEMENT_DELAY = 15 seconds;

    error WrongChain(uint256 actual);
    error InvalidAddress();
    error InvalidConfiguration();
    error InvalidLaunch();
    error InvalidOracleRound();
    error StaleOracleRound();
    error Unauthorized();
    error AccountExists();
    error AccountNotFound();
    error InvalidBand();
    error DuplicateBand();
    error InvalidAmount();
    error InvalidState();
    error InvalidPosition();
    error SettlementNotArmed();
    error SettlementConfirmationPending();
    error UnexpectedNFT();
    error UnexpectedBalanceDelta(address asset, uint256 expected, uint256 actual);
    error Insolvent(address asset);

    enum Destination {
        CREATOR,
        FEE_ROUTER
    }

    enum BandStatus {
        CONFIGURED,
        ACTIVE,
        SETTLED,
        DELIVERED
    }

    struct ProfileInput {
        address verifier;
        address priceGuard;
        bytes hookData;
    }

    struct Profile {
        ISinjohLaunchVerifier verifier;
        ISinjohFundingBandPriceGuard priceGuard;
        bytes hookData;
    }

    struct BandConfig {
        uint128 lowerMarketCapUsdE8;
        uint128 upperMarketCapUsdE8;
        Destination destination;
        address feeRouter;
    }

    struct BandFunding {
        uint8 bandId;
        uint128 amount;
    }

    struct Account {
        address creator;
        uint8 profileId;
        uint8 bandCount;
        uint8 subjectDecimals;
        uint256 ethUsdE8;
        uint48 oracleUpdatedAt;
        bool exists;
        ISinjohLaunchVerifier.VerifiedLaunch launch;
    }

    struct Band {
        uint128 lowerMarketCapUsdE8;
        uint128 upperMarketCapUsdE8;
        uint256 lowerWethPerSubjectX128;
        uint256 upperWethPerSubjectX128;
        int24 tickLower;
        int24 tickUpper;
        Destination destination;
        address recipient;
        BandStatus status;
        uint256 positionId;
        uint128 liquidity;
        uint256 subjectResidual;
        uint256 cumulativeRealizedWeth;
        uint256 protocolFeeCharged;
        uint48 settlementArmedAt;
    }

    event ProfileFrozen(uint8 indexed profileId, address indexed verifier, address indexed guard);
    event AccountCreated(
        bytes32 indexed accountId,
        address indexed subject,
        address indexed creator,
        uint8 profileId,
        ISinjohLaunchVerifier.Venue venue,
        address quoteAsset,
        uint256 launchSupply,
        uint8 subjectDecimals,
        uint256 ethUsdE8,
        uint48 oracleUpdatedAt
    );
    event BandConfigured(
        bytes32 indexed accountId,
        uint8 indexed bandId,
        uint128 lowerMarketCapUsdE8,
        uint128 upperMarketCapUsdE8,
        uint256 lowerWethPerSubjectX128,
        uint256 upperWethPerSubjectX128,
        int24 tickLower,
        int24 tickUpper,
        Destination destination,
        address recipient
    );
    event BandFunded(
        bytes32 indexed accountId,
        uint8 indexed bandId,
        uint256 deposited,
        uint256 invested,
        uint256 residual,
        uint256 indexed positionId,
        uint128 liquidityAdded
    );
    event BandSettled(
        bytes32 indexed accountId,
        uint8 indexed bandId,
        uint256 realizedWeth,
        uint256 protocolFee,
        uint256 netWeth,
        uint256 subjectProceeds
    );
    event BandSettlementArmed(
        bytes32 indexed accountId, uint8 indexed bandId, uint48 armedAt, uint48 executableAt
    );
    event BandSettlementDisarmed(bytes32 indexed accountId, uint8 indexed bandId);
    event ProceedsSent(
        bytes32 indexed accountId,
        uint8 indexed bandId,
        address indexed asset,
        address recipient,
        uint256 amount
    );
    event ProtocolFeeSent(address indexed recipient, uint256 amount, address indexed caller);

    address public immutable weth;
    IUniswapV3Factory public immutable v3Factory;
    IUniswapV3PositionManager public immutable v3PositionManager;
    IPositionManager public immutable v4PositionManager;
    address public immutable v4PoolManager;
    IV4StateView public immutable v4StateView;
    IAllowanceTransfer public immutable permit2;
    IChainlinkAggregatorV3 public immutable ethUsdOracle;
    bytes32 public immutable feeRouterCodehash;
    address public immutable protocolFeeRecipient;
    address public immutable launchEscrow;
    uint48 public immutable maxOracleAge;
    uint8 public immutable profileCount;

    mapping(uint8 profileId => Profile profile) private _profiles;
    mapping(address subject => Account account) private _accounts;
    mapping(address subject => mapping(uint8 bandId => Band band)) private _bands;
    mapping(
        address subject => mapping(uint8 bandId => mapping(address asset => uint256 amount))
    ) public proceedsOwed;
    mapping(address asset => uint256 amount) public totalLiability;
    uint256 public protocolOwed;

    bool private _expectingV3Position;
    uint256 private _receivedV3PositionId;

    constructor(
        address weth_,
        address v3Factory_,
        address v3PositionManager_,
        address v4PositionManager_,
        address v4StateView_,
        address permit2_,
        address ethUsdOracle_,
        bytes32 feeRouterCodehash_,
        address protocolFeeRecipient_,
        address launchEscrow_,
        uint48 maxOracleAge_,
        ProfileInput[] memory profiles_
    ) {
        if (block.chainid != ROBINHOOD_CHAIN_ID) {
            revert WrongChain(block.chainid);
        }
        if (
            weth_.code.length == 0 || v3Factory_.code.length == 0
                || v3PositionManager_.code.length == 0 || v4PositionManager_.code.length == 0
                || v4StateView_.code.length == 0 || permit2_.code.length == 0
                || ethUsdOracle_.code.length == 0 || feeRouterCodehash_ == bytes32(0)
                || protocolFeeRecipient_ == address(0) || protocolFeeRecipient_ == address(this)
                || launchEscrow_.code.length == 0 || maxOracleAge_ == 0 || profiles_.length == 0
                || profiles_.length > type(uint8).max
        ) revert InvalidAddress();

        weth = weth_;
        v3Factory = IUniswapV3Factory(v3Factory_);
        v3PositionManager = IUniswapV3PositionManager(v3PositionManager_);
        v4PositionManager = IPositionManager(v4PositionManager_);
        address positionManagerPool = IV4PositionManagerState(v4PositionManager_).poolManager();
        address stateViewPool = IV4StateView(v4StateView_).poolManager();
        if (
            positionManagerPool.code.length == 0 || positionManagerPool != stateViewPool
                || positionManagerPool == address(this)
        ) revert InvalidAddress();
        v4PoolManager = positionManagerPool;
        v4StateView = IV4StateView(v4StateView_);
        permit2 = IAllowanceTransfer(permit2_);
        ethUsdOracle = IChainlinkAggregatorV3(ethUsdOracle_);
        feeRouterCodehash = feeRouterCodehash_;
        protocolFeeRecipient = protocolFeeRecipient_;
        launchEscrow = launchEscrow_;
        maxOracleAge = maxOracleAge_;
        profileCount = uint8(profiles_.length);

        for (uint8 i; i < profiles_.length; ++i) {
            ProfileInput memory input = profiles_[i];
            if (
                input.verifier.code.length == 0 || input.priceGuard.code.length == 0
                    || input.verifier == address(this) || input.priceGuard == address(this)
                    || input.hookData.length > MAX_DYNAMIC_BYTES
            ) revert InvalidAddress();
            _profiles[i] = Profile({
                verifier: ISinjohLaunchVerifier(input.verifier),
                priceGuard: ISinjohFundingBandPriceGuard(input.priceGuard),
                hookData: input.hookData
            });
            emit ProfileFrozen(i, input.verifier, input.priceGuard);
        }
    }

    receive() external payable {
        if (msg.sender != v4PoolManager) {
            revert InvalidAddress();
        }
    }

    function create(
        address subject,
        uint8 profileId,
        BandConfig[] calldata configs,
        bytes calldata launchData,
        bytes calldata guardData
    ) external nonReentrant returns (bytes32 id) {
        if (
            subject.code.length == 0 || profileId >= profileCount
                || launchData.length > MAX_DYNAMIC_BYTES || guardData.length > MAX_DYNAMIC_BYTES
                || configs.length == 0 || configs.length > MAX_BANDS
        ) revert InvalidConfiguration();
        if (_accounts[subject].exists) revert AccountExists();
        bool escrowCaller = msg.sender == launchEscrow;
        if ((escrowCaller && launchData.length != 32) || (!escrowCaller && launchData.length != 0))
        {
            revert InvalidLaunch();
        }
        if (!escrowCaller && ISinjohFundingBandsEscrowState(launchEscrow).isPrepared(subject)) {
            revert Unauthorized();
        }

        Profile storage selectedProfile = _profiles[profileId];
        ISinjohLaunchVerifier.VerifiedLaunch memory launch =
            selectedProfile.verifier.verify(subject, launchData);
        if (
            launch.subject != subject
                || (launch.creatorAtLaunch != msg.sender && msg.sender != launchEscrow)
                || launch.creatorAtLaunch == address(0) || launch.launchSupply == 0
                || launch.tickSpacing <= 0
                || (launch.quoteAsset != weth && launch.quoteAsset != address(0))
        ) revert InvalidLaunch();
        _validateCanonicalLaunch(launch);

        uint256 supply = IERC20(subject).totalSupply();
        if (
            (escrowCaller && supply > launch.launchSupply)
                || (!escrowCaller && supply != launch.launchSupply)
        ) {
            revert InvalidLaunch();
        }
        uint8 subjectDecimals = IERC20Metadata(subject).decimals();
        if (subjectDecimals > 36) revert InvalidLaunch();
        (uint256 ethUsdE8, uint48 oracleUpdatedAt) =
            FundingBandMath.snapshotEthUsd(ethUsdOracle, maxOracleAge);

        Account storage account = _accounts[subject];
        account.creator = launch.creatorAtLaunch;
        account.profileId = profileId;
        account.bandCount = uint8(configs.length);
        account.subjectDecimals = subjectDecimals;
        account.ethUsdE8 = ethUsdE8;
        account.oracleUpdatedAt = oracleUpdatedAt;
        account.exists = true;
        account.launch = launch;

        bool subjectIsToken0 = _subjectIsToken0(launch);
        uint128 previousUpper;
        for (uint8 i; i < configs.length; ++i) {
            BandConfig calldata config = configs[i];
            if (
                config.lowerMarketCapUsdE8 >= config.upperMarketCapUsdE8
                    || (i != 0 && config.lowerMarketCapUsdE8 < previousUpper)
            ) revert InvalidBand();
            previousUpper = config.upperMarketCapUsdE8;
            address recipient = _validateDestination(config, launch.creatorAtLaunch, subject);
            FundingBandMath.ConvertedRange memory converted = FundingBandMath.convertRange(
                config.lowerMarketCapUsdE8,
                config.upperMarketCapUsdE8,
                launch.launchSupply,
                ethUsdE8,
                launch.tickSpacing,
                subjectIsToken0
            );
            int24 lowerBoundary = subjectIsToken0 ? converted.tickLower : converted.tickUpper;
            selectedProfile.priceGuard
                .validateBelow(launch, lowerBoundary, subjectIsToken0, guardData);

            _bands[subject][i] = Band({
                lowerMarketCapUsdE8: config.lowerMarketCapUsdE8,
                upperMarketCapUsdE8: config.upperMarketCapUsdE8,
                lowerWethPerSubjectX128: converted.lowerWethPerSubjectX128,
                upperWethPerSubjectX128: converted.upperWethPerSubjectX128,
                tickLower: converted.tickLower,
                tickUpper: converted.tickUpper,
                destination: config.destination,
                recipient: recipient,
                status: BandStatus.CONFIGURED,
                positionId: 0,
                liquidity: 0,
                subjectResidual: 0,
                cumulativeRealizedWeth: 0,
                protocolFeeCharged: 0,
                settlementArmedAt: 0
            });
        }

        id = _accountId(subject);
        emit AccountCreated(
            id,
            subject,
            launch.creatorAtLaunch,
            profileId,
            launch.venue,
            launch.quoteAsset,
            launch.launchSupply,
            subjectDecimals,
            ethUsdE8,
            oracleUpdatedAt
        );
        for (uint8 i; i < configs.length; ++i) {
            _emitBandConfigured(id, i, _bands[subject][i]);
        }
    }

    function fund(address subject, BandFunding[] calldata funding, bytes calldata guardData)
        external
        nonReentrant
        returns (uint256 totalReceived)
    {
        Account storage account = _accounts[subject];
        if (!account.exists) revert AccountNotFound();
        if (msg.sender != account.creator && msg.sender != launchEscrow) revert Unauthorized();
        if (
            funding.length == 0 || funding.length > MAX_BANDS
                || guardData.length > MAX_DYNAMIC_BYTES
        ) {
            revert InvalidConfiguration();
        }

        uint16 seen;
        uint256 requested;
        for (uint256 i; i < funding.length; ++i) {
            BandFunding calldata item = funding[i];
            if (item.bandId >= account.bandCount || item.amount == 0) revert InvalidBand();
            uint16 mask = uint16(1) << item.bandId;
            if (seen & mask != 0) revert DuplicateBand();
            seen |= mask;
            requested += item.amount;
        }

        uint256 beforeBalance = IERC20(subject).balanceOf(address(this));
        IERC20(subject).safeTransferFrom(msg.sender, address(this), requested);
        totalReceived = IERC20(subject).balanceOf(address(this)) - beforeBalance;
        if (totalReceived != requested) {
            revert UnexpectedBalanceDelta(subject, requested, totalReceived);
        }

        for (uint256 i; i < funding.length; ++i) {
            _fundBand(subject, account, funding[i], guardData);
        }
        _assertSolvent(subject);
    }

    /// @notice Records the first independent crossing observation for a v4 band.
    /// @dev Pons v2's v4 hook has no historical oracle. Requiring another onchain
    /// observation after a fixed delay prevents a one-transaction spot manipulation
    /// from both crossing and settling a band. Anyone may arm an objectively crossed band.
    function armSettlement(address subject, uint8 bandId, bytes calldata guardData)
        external
        nonReentrant
    {
        Account storage account = _accounts[subject];
        if (!account.exists) revert AccountNotFound();
        if (bandId >= account.bandCount || guardData.length > MAX_DYNAMIC_BYTES) {
            revert InvalidBand();
        }
        if (account.launch.venue != ISinjohLaunchVerifier.Venue.UNISWAP_V4) {
            revert InvalidState();
        }
        Band storage band = _bands[subject][bandId];
        if (band.status != BandStatus.ACTIVE || band.positionId == 0 || band.liquidity == 0) {
            revert InvalidState();
        }

        uint48 now48 = _timestamp48();
        uint48 armedAt = band.settlementArmedAt;
        if (armedAt != 0) revert InvalidState();
        bool subjectIsToken0 = _subjectIsToken0(account.launch);
        int24 upperBoundary = subjectIsToken0 ? band.tickUpper : band.tickLower;
        IV4FundingBandArmGuard(address(_profiles[account.profileId].priceGuard))
            .validateArm(account.launch, upperBoundary, subjectIsToken0, guardData);

        band.settlementArmedAt = now48;
        emit BandSettlementArmed(_accountId(subject), bandId, now48, now48 + V4_SETTLEMENT_DELAY);
    }

    /// @notice Invalidates an armed v4 band after price returns below its upper boundary.
    /// @dev Permissionless so the dedicated observer or any caller can reset the hold.
    function disarmSettlement(address subject, uint8 bandId, bytes calldata guardData)
        external
        nonReentrant
    {
        Account storage account = _accounts[subject];
        if (!account.exists) revert AccountNotFound();
        if (bandId >= account.bandCount || guardData.length > MAX_DYNAMIC_BYTES) {
            revert InvalidBand();
        }
        if (account.launch.venue != ISinjohLaunchVerifier.Venue.UNISWAP_V4) {
            revert InvalidState();
        }
        Band storage band = _bands[subject][bandId];
        if (
            band.status != BandStatus.ACTIVE || band.positionId == 0 || band.liquidity == 0
                || band.settlementArmedAt == 0
        ) revert InvalidState();
        bool subjectIsToken0 = _subjectIsToken0(account.launch);
        int24 upperBoundary = subjectIsToken0 ? band.tickUpper : band.tickLower;
        _profiles[account.profileId].priceGuard
            .validateBelow(account.launch, upperBoundary, subjectIsToken0, guardData);
        band.settlementArmedAt = 0;
        emit BandSettlementDisarmed(_accountId(subject), bandId);
    }

    function settle(address subject, uint8 bandId, bytes calldata guardData) external nonReentrant {
        Account storage account = _accounts[subject];
        if (!account.exists) revert AccountNotFound();
        if (bandId >= account.bandCount || guardData.length > MAX_DYNAMIC_BYTES) {
            revert InvalidBand();
        }
        Band storage band = _bands[subject][bandId];
        if (band.status != BandStatus.ACTIVE || band.positionId == 0 || band.liquidity == 0) {
            revert InvalidState();
        }
        if (account.launch.venue == ISinjohLaunchVerifier.Venue.UNISWAP_V4) {
            uint48 armedAt = band.settlementArmedAt;
            if (armedAt == 0) revert SettlementNotArmed();
            uint48 now48 = _timestamp48();
            if (now48 < armedAt + V4_SETTLEMENT_DELAY) {
                revert SettlementConfirmationPending();
            }
        }
        bool subjectIsToken0 = _subjectIsToken0(account.launch);
        int24 upperBoundary = subjectIsToken0 ? band.tickUpper : band.tickLower;
        _profiles[account.profileId].priceGuard
            .validateAbove(account.launch, upperBoundary, subjectIsToken0, guardData);

        uint256 wethBefore = IERC20(weth).balanceOf(address(this));
        uint256 subjectBefore = IERC20(subject).balanceOf(address(this));
        uint256 nativeBefore = address(this).balance;
        if (account.launch.venue == ISinjohLaunchVerifier.Venue.UNISWAP_V3) {
            _settleV3(band);
        } else {
            FundingBandV4.settle(
                v4PositionManager,
                _poolKey(account.launch),
                band.positionId,
                _profiles[account.profileId].hookData
            );
        }

        uint256 nativeReceived = address(this).balance - nativeBefore;
        if (nativeReceived != 0) IWETH(weth).deposit{ value: nativeReceived }();
        uint256 realizedWeth = IERC20(weth).balanceOf(address(this)) - wethBefore;
        uint256 subjectReceived = IERC20(subject).balanceOf(address(this)) - subjectBefore;

        uint256 subjectProceeds = subjectReceived + band.subjectResidual;
        band.subjectResidual = 0;
        band.cumulativeRealizedWeth += realizedWeth;
        uint256 cumulativeFee = band.cumulativeRealizedWeth * PROTOCOL_FEE_BPS / BPS;
        uint256 incrementalFee = cumulativeFee - band.protocolFeeCharged;
        band.protocolFeeCharged = cumulativeFee;
        band.liquidity = 0;
        band.settlementArmedAt = 0;
        band.status = BandStatus.SETTLED;

        uint256 netWeth = realizedWeth - incrementalFee;
        proceedsOwed[subject][bandId][weth] += netWeth;
        proceedsOwed[subject][bandId][subject] += subjectProceeds;
        protocolOwed += incrementalFee;
        totalLiability[weth] += realizedWeth;
        totalLiability[subject] += subjectReceived;
        _assertSolvent(weth);
        _assertSolvent(subject);
        emit BandSettled(
            _accountId(subject), bandId, realizedWeth, incrementalFee, netWeth, subjectProceeds
        );
    }

    function sendProceeds(address subject, uint8 bandId, address asset, uint256 amount)
        external
        nonReentrant
    {
        Account storage account = _accounts[subject];
        if (!account.exists || bandId >= account.bandCount) revert InvalidBand();
        Band storage band = _bands[subject][bandId];
        if (band.status != BandStatus.SETTLED && band.status != BandStatus.DELIVERED) {
            revert InvalidState();
        }
        if (asset != weth && asset != subject) revert InvalidAddress();
        uint256 owed = proceedsOwed[subject][bandId][asset];
        if (amount == 0 || amount > owed) revert InvalidAmount();

        proceedsOwed[subject][bandId][asset] = owed - amount;
        totalLiability[asset] -= amount;
        _sendExact(asset, band.recipient, amount);
        if (proceedsOwed[subject][bandId][weth] == 0 && proceedsOwed[subject][bandId][subject] == 0)
        {
            band.status = BandStatus.DELIVERED;
        }
        _assertSolvent(asset);
        emit ProceedsSent(_accountId(subject), bandId, asset, band.recipient, amount);
    }

    function sendProtocolFee(uint256 amount) external nonReentrant {
        if (amount == 0 || amount > protocolOwed) revert InvalidAmount();
        protocolOwed -= amount;
        totalLiability[weth] -= amount;
        _sendExact(weth, protocolFeeRecipient, amount);
        _assertSolvent(weth);
        emit ProtocolFeeSent(protocolFeeRecipient, amount, msg.sender);
    }

    function getProfile(uint8 profileId)
        external
        view
        returns (address verifier, address priceGuard, bytes32 hookDataHash)
    {
        if (profileId >= profileCount) revert InvalidConfiguration();
        Profile storage value = _profiles[profileId];
        return (address(value.verifier), address(value.priceGuard), keccak256(value.hookData));
    }

    function getAccount(address subject) external view returns (Account memory) {
        return _accounts[subject];
    }

    function getBand(address subject, uint8 bandId) external view returns (Band memory) {
        if (!_accounts[subject].exists || bandId >= _accounts[subject].bandCount) {
            revert InvalidBand();
        }
        return _bands[subject][bandId];
    }

    function onERC721Received(address, address, uint256 tokenId, bytes calldata)
        external
        returns (bytes4)
    {
        if (!_expectingV3Position || msg.sender != address(v3PositionManager)) {
            revert UnexpectedNFT();
        }
        _receivedV3PositionId = tokenId;
        return this.onERC721Received.selector;
    }

    function _fundBand(
        address subject,
        Account storage account,
        BandFunding calldata item,
        bytes calldata guardData
    ) private {
        Band storage band = _bands[subject][item.bandId];
        if (band.status != BandStatus.CONFIGURED && band.status != BandStatus.ACTIVE) {
            revert InvalidState();
        }
        bool subjectIsToken0 = _subjectIsToken0(account.launch);
        int24 lowerBoundary = subjectIsToken0 ? band.tickLower : band.tickUpper;
        _profiles[account.profileId].priceGuard
            .validateBelow(account.launch, lowerBoundary, subjectIsToken0, guardData);
        if (band.settlementArmedAt != 0) {
            band.settlementArmedAt = 0;
            emit BandSettlementDisarmed(_accountId(subject), item.bandId);
        }

        uint160 sqrtLower = TickMath.getSqrtPriceAtTick(band.tickLower);
        uint160 sqrtUpper = TickMath.getSqrtPriceAtTick(band.tickUpper);
        uint128 liquidity = subjectIsToken0
            ? LiquidityAmounts.getLiquidityForAmount0(sqrtLower, sqrtUpper, item.amount)
            : LiquidityAmounts.getLiquidityForAmount1(sqrtLower, sqrtUpper, item.amount);
        if (liquidity == 0) revert InvalidAmount();

        uint256 beforeBalance = IERC20(subject).balanceOf(address(this));
        uint256 tokenId;
        uint128 liquidityAdded;
        if (account.launch.venue == ISinjohLaunchVerifier.Venue.UNISWAP_V3) {
            (tokenId, liquidityAdded) = _fundV3(subject, account.launch, band, item.amount);
        } else {
            tokenId = FundingBandV4.fund(
                v4PositionManager,
                permit2,
                subject,
                _poolKey(account.launch),
                band.tickLower,
                band.tickUpper,
                band.positionId,
                item.amount,
                liquidity,
                _profiles[account.profileId].hookData
            );
            liquidityAdded = liquidity;
        }
        uint256 invested = beforeBalance - IERC20(subject).balanceOf(address(this));
        if (invested == 0 || invested > item.amount || liquidityAdded == 0) {
            revert UnexpectedBalanceDelta(subject, item.amount, invested);
        }
        uint256 residual = item.amount - invested;
        band.positionId = tokenId;
        band.liquidity += liquidityAdded;
        band.subjectResidual += residual;
        band.status = BandStatus.ACTIVE;
        totalLiability[subject] += residual;
        emit BandFunded(
            _accountId(subject),
            item.bandId,
            item.amount,
            invested,
            residual,
            tokenId,
            liquidityAdded
        );
    }

    function _fundV3(
        address subject,
        ISinjohLaunchVerifier.VerifiedLaunch storage launch,
        Band storage band,
        uint256 amount
    ) private returns (uint256 tokenId, uint128 liquidityAdded) {
        IERC20(subject).forceApprove(address(v3PositionManager), amount);
        bool created = band.positionId == 0;
        if (created) {
            address token0 = subject < weth ? subject : weth;
            address token1 = subject < weth ? weth : subject;
            _expectingV3Position = true;
            (tokenId, liquidityAdded,,) = v3PositionManager.mint(
                IUniswapV3PositionManager.MintParams({
                    token0: token0,
                    token1: token1,
                    fee: launch.poolFee,
                    tickLower: band.tickLower,
                    tickUpper: band.tickUpper,
                    amount0Desired: token0 == subject ? amount : 0,
                    amount1Desired: token1 == subject ? amount : 0,
                    amount0Min: 0,
                    amount1Min: 0,
                    recipient: address(this),
                    deadline: block.timestamp + DEADLINE_WINDOW
                })
            );
            _expectingV3Position = false;
            if (
                (_receivedV3PositionId != 0 && _receivedV3PositionId != tokenId)
                    || v3PositionManager.ownerOf(tokenId) != address(this)
            ) revert InvalidPosition();
            _receivedV3PositionId = 0;
        } else {
            tokenId = band.positionId;
            (liquidityAdded,,) = v3PositionManager.increaseLiquidity(
                IUniswapV3PositionManager.IncreaseLiquidityParams({
                    tokenId: tokenId,
                    amount0Desired: subject < weth ? amount : 0,
                    amount1Desired: subject < weth ? 0 : amount,
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: block.timestamp + DEADLINE_WINDOW
                })
            );
        }
        IERC20(subject).forceApprove(address(v3PositionManager), 0);
    }

    function _settleV3(Band storage band) private {
        v3PositionManager.decreaseLiquidity(
            IUniswapV3PositionManager.DecreaseLiquidityParams({
                tokenId: band.positionId,
                liquidity: band.liquidity,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp + DEADLINE_WINDOW
            })
        );
        v3PositionManager.collect(
            IUniswapV3PositionManager.CollectParams({
                tokenId: band.positionId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );
        v3PositionManager.burn(band.positionId);
    }

    function _validateCanonicalLaunch(ISinjohLaunchVerifier.VerifiedLaunch memory launch)
        private
        view
    {
        if (launch.venue == ISinjohLaunchVerifier.Venue.UNISWAP_V3) {
            if (
                launch.quoteAsset != weth || launch.pool.code.length == 0
                    || launch.hooks != address(0) || launch.poolId != bytes32(0)
                    || v3Factory.getPool(launch.subject, weth, launch.poolFee) != launch.pool
                    || IUniswapV3Pool(launch.pool).tickSpacing() != launch.tickSpacing
            ) revert InvalidLaunch();
            (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(launch.pool).slot0();
            if (sqrtPriceX96 == 0) revert InvalidLaunch();
        } else {
            if (launch.pool != address(0)) revert InvalidLaunch();
            PoolKey memory key = _poolKey(launch);
            PoolId poolId = key.toId();
            if (PoolId.unwrap(poolId) != launch.poolId) revert InvalidLaunch();
            (uint160 sqrtPriceX96,,,) = v4StateView.getSlot0(poolId);
            if (sqrtPriceX96 == 0) revert InvalidLaunch();
        }
    }

    function _validateDestination(BandConfig calldata config, address creator, address subject)
        private
        view
        returns (address recipient)
    {
        if (config.destination == Destination.CREATOR) {
            if (config.feeRouter != address(0)) revert InvalidConfiguration();
            return creator;
        }
        recipient = config.feeRouter;
        if (
            recipient.codehash != feeRouterCodehash
                || ISinjohFeeRouterView(recipient).creator() != creator
                || ISinjohFeeRouterView(recipient).subject() != subject
                || !ISinjohFeeRouterView(recipient).isIntakeAsset(weth)
                || !ISinjohFeeRouterView(recipient).isIntakeAsset(subject)
        ) revert InvalidConfiguration();
    }

    function _timestamp48() private view returns (uint48 value) {
        // Timestamp is deliberately bounded before storage in the compact band struct.
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp > type(uint48).max) revert InvalidState();
        // Checked immediately above.
        // forge-lint: disable-next-line(unsafe-typecast)
        value = uint48(block.timestamp);
    }

    function _poolKey(ISinjohLaunchVerifier.VerifiedLaunch memory launch)
        private
        pure
        returns (PoolKey memory key)
    {
        address token0 = launch.subject < launch.quoteAsset ? launch.subject : launch.quoteAsset;
        address token1 = launch.subject < launch.quoteAsset ? launch.quoteAsset : launch.subject;
        key = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: launch.poolFee,
            tickSpacing: launch.tickSpacing,
            hooks: IHooks(launch.hooks)
        });
    }

    function _subjectIsToken0(ISinjohLaunchVerifier.VerifiedLaunch memory launch)
        private
        pure
        returns (bool)
    {
        return launch.subject < launch.quoteAsset;
    }

    function _sendExact(address asset, address recipient, uint256 amount) private {
        uint256 senderBefore = IERC20(asset).balanceOf(address(this));
        uint256 recipientBefore = IERC20(asset).balanceOf(recipient);
        IERC20(asset).safeTransfer(recipient, amount);
        uint256 spent = senderBefore - IERC20(asset).balanceOf(address(this));
        uint256 received = IERC20(asset).balanceOf(recipient) - recipientBefore;
        if (spent != amount || received != amount) {
            revert UnexpectedBalanceDelta(asset, amount, received);
        }
    }

    function _assertSolvent(address asset) private view {
        if (IERC20(asset).balanceOf(address(this)) < totalLiability[asset]) {
            revert Insolvent(asset);
        }
    }

    function _accountId(address subject) private pure returns (bytes32) {
        return keccak256(abi.encode(subject));
    }

    function _emitBandConfigured(bytes32 id, uint8 bandId, Band storage value) private {
        emit BandConfigured(
            id,
            bandId,
            value.lowerMarketCapUsdE8,
            value.upperMarketCapUsdE8,
            value.lowerWethPerSubjectX128,
            value.upperWethPerSubjectX128,
            value.tickLower,
            value.tickUpper,
            value.destination,
            value.recipient
        );
    }
}
