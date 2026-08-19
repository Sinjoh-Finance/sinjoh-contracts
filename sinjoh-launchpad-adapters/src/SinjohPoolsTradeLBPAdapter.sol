// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ISinjohLaunchpadAdapter } from "./interfaces/ISinjohLaunchpadAdapter.sol";
import {
    IPTAuction,
    IPTAuctionFactory,
    IPTLBPStrategy,
    IPTLiquidityLauncher,
    IPTPoolManager,
    IPTPositionManager,
    IPTUERC20Factory,
    IWETH9,
    PTAuctionParameters,
    PTDistribution,
    PTLiquidityAllocationBracket,
    PTMigratorParameters,
    PTPoolParameters,
    PTPositionDefinition,
    PTSplit,
    PTTokenMetadata
} from "./interfaces/IPoolsTrade.sol";
import { SafeTransferLib } from "./libraries/SafeTransferLib.sol";

interface ISinjohFeeRouterLBP {
    function launchpadAdapter() external view returns (address);
    function bind(address subject) external;
}

interface ISinjohPoolsTradeLBPAdapterFactory {
    function registerSubject(address subject) external;
}

/// @notice Launches on pools.trade's LBPStrategy — a continuous clearing
/// auction that migrates into a Uniswap v4 pool at the clearing price — and
/// forwards every creator revenue stream to one immutable `SinjohFeeRouter`.
///
/// The LBP shape pays creators three ways, and the adapter is the named
/// recipient of all three so no value can bypass the router:
///
///  1. the non-LP share of the raise, swept to `recipient` at migration
///     (native or the ERC20 auction currency);
///  2. the migrated v4 LP position NFTs, minted to `positionRecipient`, whose
///     trading fees `collect` pulls for as long as the pool trades;
///  3. unsold auction tokens, claimable by `tokensRecipient` after the
///     auction ends.
///
/// A failed migration recovers the raise and the LP reserve to `recipient` —
/// this adapter — so even the failure path lands in the router.
///
/// Side allocations (team, airdrop wallets) ride the same launch through the
/// pinned TokenSplitter as typed `(recipient, amount)` legs; they are supply
/// the creator chose not to route through Sinjoh and never touch the adapter.
///
/// The adapter performs no accounting, allocation, or protocol-fee charging.
/// The 1% Sinjoh fee is charged exactly once, later, when `router.sync(asset)`
/// turns a forwarded balance into router liabilities.
contract SinjohPoolsTradeLBPAdapter is ISinjohLaunchpadAdapter {
    using SafeTransferLib for address;

    error AlreadyInitialized();
    error AlreadyLaunched();
    error NotLaunched();
    error AlreadyMigrated();
    error Unauthorized();
    error WrongChain(uint256 actual);
    error InvalidAddress();
    error UnsupportedAsset(address asset);
    error Reentrancy();
    error PredictionOccupied(address predicted);
    error LaunchReturnedWrongToken(address expected, address actual);
    error RouterDidNotNameAdapter(address named);
    error InvalidLaunchParams();
    error PositionRecipientOverrideForbidden(uint256 index);
    error TooManyPositionDefinitions(uint256 count);
    error SplitTotalMismatch(uint256 expected, uint256 actual);
    error InitializerMismatch(address initializer);
    error TooManyMerkleLegs(uint256 count);
    error InvalidMerkleLeg(uint256 index);
    error PositionNotOwned(uint256 tokenId);
    error PositionPoolMismatch(uint256 tokenId);
    error TooManyPositions();
    error UnexpectedBalanceDelta(address asset, uint256 expected, uint256 actual);

    event Initialized(address indexed router, address indexed creator);
    event Launched(
        address indexed subject,
        address indexed initializer,
        address indexed currency,
        uint64 migrationBlock
    );
    event Migrated(address indexed subject, bool success, uint256 positionCount);
    event PositionRegistered(uint256 indexed tokenId);
    event Collected(
        address indexed subject, address indexed asset, uint256 amount, address indexed caller
    );
    event Forwarded(
        address indexed asset, address indexed router, uint256 amount, address indexed caller
    );

    /// @dev v4-periphery Actions constants used by the fee-collection plan.
    uint256 internal constant ACTION_DECREASE_LIQUIDITY = 0x01;
    uint256 internal constant ACTION_TAKE_PAIR = 0x11;

    /// @dev CCA errors treated as "nothing to sweep" rather than failures.
    bytes4 private constant AUCTION_IS_NOT_OVER_SELECTOR = bytes4(keccak256("AuctionIsNotOver()"));
    bytes4 private constant CANNOT_SWEEP_TOKENS_SELECTOR = bytes4(keccak256("CannotSweepTokens()"));

    /// @dev Bounds `collect`'s per-call position loop. The strategy's planner
    /// mints one position per definition plus one full-range fallback, and the
    /// launch caps definitions well below this.
    uint256 internal constant MAX_POSITIONS = 32;
    uint256 internal constant MAX_POSITION_DEFINITIONS = 16;
    uint256 internal constant MAX_MERKLE_LEGS = 8;

    address public immutable launcher;
    address public immutable tokenFactory;
    address public immutable lbpStrategy;
    address public immutable tokenSplitter;
    address public immutable merkleClaimFactory;
    address public immutable initializerFactory;
    address public immutable positionManager;
    address public immutable poolManager;
    address public immutable weth;
    uint256 public immutable deploymentChainId;
    address public immutable factory;

    address public router;
    address public creator;
    address public subject;
    /// @notice The auction currency; zero for native ETH.
    address public currency;
    /// @notice The continuous clearing auction deployed for this launch.
    address public initializer;
    /// @notice The pool parameters the launch committed to; the migrated key
    /// may fall back from a zero hook to the strategy-hooked key.
    PTPoolParameters public committedPool;
    /// @notice The migrated v4 pool key, resolved from the minted positions.
    IPTPoolManager.PoolKey public poolKey;
    uint256[] public positionTokenIds;
    bool public initialized;
    bool public launched;
    bool public migrated;
    /// @notice True when the strategy's migration failed internally: the raise
    /// and LP reserve were refunded to this adapter and no pool was created.
    bool public migrationFailed;

    uint256 private _reentrancyState;

    struct LBPLaunchParams {
        string name;
        string symbol;
        PTTokenMetadata metadata;
        uint128 totalSupply;
        /// @dev Amount distributed through the LBPStrategy: the auction supply
        /// plus `reservedTokenAmountForLP`. The remainder of `totalSupply` is
        /// split across `splits`.
        uint128 auctionAmount;
        address currency;
        uint64 startBlock;
        uint64 endBlock;
        uint64 claimBlock;
        uint256 auctionPriceTickSpacing;
        address validationHook;
        uint256 floorPrice;
        uint128 requiredCurrencyRaised;
        bytes auctionStepsData;
        uint64 migrationBlock;
        uint128 reservedTokenAmountForLP;
        uint24 poolFee;
        int24 poolTickSpacing;
        address poolHook;
        PTPositionDefinition[] positionDefinitions;
        PTLiquidityAllocationBracket[] lpAllocationSchedule;
        PTSplit[] splits;
        MerkleLeg[] merkleLegs;
        bytes32 distributionSalt;
    }

    /// @notice One airdrop allocation: the launch deploys and funds a
    /// MerkleClaim (Uniswap's audited merkle distributor) holding `amount` of
    /// the supply, claimable by proof against `merkleRoot`. After `endTime`
    /// (0 disables the deadline) the (creator-trusted) `owner` can withdraw
    /// what went unclaimed.
    struct MerkleLeg {
        uint128 amount;
        bytes32 merkleRoot;
        address owner;
        uint256 endTime;
    }

    constructor(
        address launcher_,
        address tokenFactory_,
        address lbpStrategy_,
        address tokenSplitter_,
        address merkleClaimFactory_,
        address weth_,
        uint256 chainId_,
        address factory_
    ) {
        if (
            launcher_.code.length == 0 || tokenFactory_.code.length == 0
                || lbpStrategy_.code.length == 0 || tokenSplitter_.code.length == 0
                || merkleClaimFactory_.code.length == 0 || weth_.code.length == 0
        ) revert InvalidAddress();
        if (chainId_ != block.chainid) revert WrongChain(block.chainid);

        IPTLBPStrategy strat = IPTLBPStrategy(lbpStrategy_);
        address initializerFactory_ = strat.initializerFactory();
        address positionManager_ = strat.positionManager();
        address poolManager_ = strat.poolManager();
        if (
            initializerFactory_.code.length == 0 || positionManager_.code.length == 0
                || poolManager_.code.length == 0
        ) revert InvalidAddress();
        if (IPTPositionManager(positionManager_).poolManager() != poolManager_) {
            revert InvalidAddress();
        }

        launcher = launcher_;
        tokenFactory = tokenFactory_;
        lbpStrategy = lbpStrategy_;
        tokenSplitter = tokenSplitter_;
        merkleClaimFactory = merkleClaimFactory_;
        initializerFactory = initializerFactory_;
        positionManager = positionManager_;
        poolManager = poolManager_;
        weth = weth_;
        deploymentChainId = chainId_;
        factory = factory_;
        initialized = true;
    }

    modifier nonReentrant() {
        if (_reentrancyState == 2) revert Reentrancy();
        _reentrancyState = 2;
        _;
        _reentrancyState = 1;
    }

    /// @dev Accepts native value from the migration sweep, the failure-branch
    /// recovery, and native-side position fees. Receiving ETH grants no
    /// accounting claim on it; only `collect` and `forward` move value onward.
    receive() external payable { }

    function initialize(address router_, address creator_) external {
        if (initialized) revert AlreadyInitialized();
        initialized = true;
        if (
            router_.code.length == 0 || creator_ == address(0) || router_ == address(this)
                || creator_ == address(this) || router_ == creator_
        ) {
            revert InvalidAddress();
        }
        router = router_;
        creator = creator_;
        emit Initialized(router_, creator_);
    }

    // ------------------------------------------------------------------
    // Launch
    // ------------------------------------------------------------------

    /// @notice The token address this adapter's launch will deploy.
    function predictSubject(string calldata name, string calldata symbol)
        public
        view
        returns (address)
    {
        return IPTUERC20Factory(tokenFactory)
            .getUERC20Address(
                name,
                symbol,
                18,
                launcher,
                IPTLiquidityLauncher(launcher).getGraffiti(address(this))
            );
    }

    /// @notice Creates the token, starts its auction, and (optionally) splits
    /// side allocations, all in one launcher `multicall`.
    ///
    /// @dev Everything recipient-shaped is forced to this adapter: the raise
    /// recipient, the LP position recipient, and the unsold-tokens recipient.
    /// Per-position recipient overrides are refused outright — one non-zero
    /// override would route that position's fee stream around the router
    /// permanently. Auction economics (blocks, floor, steps, brackets, pool
    /// shape) are the creator's to choose and the strategy's to validate.
    function launch(LBPLaunchParams calldata params)
        external
        nonReentrant
        returns (address token, address auction)
    {
        _assertChain();
        if (msg.sender != creator) revert Unauthorized();
        if (launched) revert AlreadyLaunched();
        address router_ = router;
        if (router_ == address(0)) revert InvalidAddress();
        address named = ISinjohFeeRouterLBP(router_).launchpadAdapter();
        if (named != address(this)) revert RouterDidNotNameAdapter(named);
        launched = true;

        _validateLaunchParams(params);

        address predicted = predictSubject(params.name, params.symbol);
        if (predicted.code.length != 0) revert PredictionOccupied(predicted);

        (PTMigratorParameters memory migratorParams, bytes memory auctionParams) =
            _buildDistributionParams(params, predicted);

        token = _launchViaLauncher(params, predicted, migratorParams, auctionParams);

        auction = _verifyInitializer(params, token, migratorParams, auctionParams);

        subject = token;
        currency = params.currency;
        initializer = auction;
        committedPool = PTPoolParameters({
            fee: params.poolFee, tickSpacing: params.poolTickSpacing, hook: params.poolHook
        });
        emit Launched(token, auction, params.currency, params.migrationBlock);

        ISinjohPoolsTradeLBPAdapterFactory(factory).registerSubject(token);
        ISinjohFeeRouterLBP(router_).bind(token);
    }

    function _validateLaunchParams(LBPLaunchParams calldata params) private view {
        if (params.auctionAmount == 0 || params.auctionAmount > params.totalSupply) {
            revert InvalidLaunchParams();
        }
        if (
            params.reservedTokenAmountForLP == 0
                || params.reservedTokenAmountForLP >= params.auctionAmount
        ) revert InvalidLaunchParams();
        if (params.currency != address(0) && params.currency.code.length == 0) {
            revert InvalidLaunchParams();
        }
        if (params.positionDefinitions.length > MAX_POSITION_DEFINITIONS) {
            revert TooManyPositionDefinitions(params.positionDefinitions.length);
        }
        for (uint256 i = 0; i < params.positionDefinitions.length; i++) {
            // A single override re-routes that position's LP fee stream away
            // from the router forever; the default recipient is this adapter.
            if (params.positionDefinitions[i].overridePositionRecipient != address(0)) {
                revert PositionRecipientOverrideForbidden(i);
            }
        }
        if (params.merkleLegs.length > MAX_MERKLE_LEGS) {
            revert TooManyMerkleLegs(params.merkleLegs.length);
        }
        uint256 sideTotal;
        for (uint256 i = 0; i < params.splits.length; i++) {
            sideTotal += params.splits[i].amount;
        }
        for (uint256 i = 0; i < params.merkleLegs.length; i++) {
            MerkleLeg calldata leg = params.merkleLegs[i];
            // A leg whose owner is this adapter would eventually feed unclaimed
            // airdrop tokens back through `forward` as if they were creator
            // fees; the withdrawal authority must stay outside the fee route.
            if (
                leg.amount == 0 || leg.merkleRoot == bytes32(0) || leg.owner == address(0)
                    || leg.owner == address(this)
            ) revert InvalidMerkleLeg(i);
            sideTotal += leg.amount;
        }
        if (sideTotal != uint256(params.totalSupply) - params.auctionAmount) {
            revert SplitTotalMismatch(uint256(params.totalSupply) - params.auctionAmount, sideTotal);
        }
    }

    function _buildDistributionParams(LBPLaunchParams calldata params, address predicted)
        private
        view
        returns (PTMigratorParameters memory migratorParams, bytes memory auctionParams)
    {
        migratorParams = PTMigratorParameters({
            token: predicted,
            currency: params.currency,
            migrationBlock: params.migrationBlock,
            reservedTokenAmountForLP: params.reservedTokenAmountForLP,
            recipient: address(this),
            positionRecipient: address(this),
            poolParameters: PTPoolParameters({
                fee: params.poolFee, tickSpacing: params.poolTickSpacing, hook: params.poolHook
            }),
            positionDefinitions: abi.encode(params.positionDefinitions),
            lpAllocationSchedule: abi.encode(params.lpAllocationSchedule)
        });
        auctionParams = abi.encode(
            PTAuctionParameters({
                currency: params.currency,
                tokensRecipient: address(this),
                fundsRecipient: lbpStrategy,
                startBlock: params.startBlock,
                endBlock: params.endBlock,
                claimBlock: params.claimBlock,
                tickSpacing: params.auctionPriceTickSpacing,
                validationHook: params.validationHook,
                floorPrice: params.floorPrice,
                requiredCurrencyRaised: params.requiredCurrencyRaised,
                auctionStepsData: params.auctionStepsData
            })
        );
    }

    function _launchViaLauncher(
        LBPLaunchParams calldata params,
        address predicted,
        PTMigratorParameters memory migratorParams,
        bytes memory auctionParams
    ) private returns (address token) {
        bool hasSplits = params.splits.length != 0;
        uint256 merkleCount = params.merkleLegs.length;
        bytes[] memory calls = new bytes[]((hasSplits ? 3 : 2) + merkleCount);
        calls[0] = abi.encodeCall(
            IPTLiquidityLauncher.createToken,
            (
                tokenFactory,
                params.name,
                params.symbol,
                18,
                params.totalSupply,
                launcher,
                abi.encode(params.metadata)
            )
        );
        calls[1] = abi.encodeCall(
            IPTLiquidityLauncher.distributeToken,
            (
                predicted,
                PTDistribution({
                    strategy: lbpStrategy,
                    amount: params.auctionAmount,
                    configData: abi.encode(migratorParams, auctionParams)
                }),
                params.distributionSalt
            )
        );
        uint256 next = 2;
        if (hasSplits) {
            uint256 splitTotal;
            for (uint256 i = 0; i < params.splits.length; i++) {
                splitTotal += params.splits[i].amount;
            }
            calls[next++] = abi.encodeCall(
                IPTLiquidityLauncher.distributeToken,
                (
                    predicted,
                    PTDistribution({
                        strategy: tokenSplitter,
                        // Bounded by _validateLaunchParams: side totals sum to
                        // totalSupply - auctionAmount, both uint128.
                        // forge-lint: disable-next-line(unsafe-typecast)
                        amount: uint128(splitTotal),
                        configData: abi.encode(params.splits)
                    }),
                    params.distributionSalt
                )
            );
        }
        for (uint256 i = 0; i < merkleCount; i++) {
            MerkleLeg calldata leg = params.merkleLegs[i];
            calls[next++] = abi.encodeCall(
                IPTLiquidityLauncher.distributeToken,
                (
                    predicted,
                    PTDistribution({
                        strategy: merkleClaimFactory,
                        amount: leg.amount,
                        configData: abi.encode(leg.merkleRoot, leg.owner, leg.endTime)
                    }),
                    // Per-leg salt: the merkle factory CREATE2s each
                    // distributor from (salt, initcode), and two identical
                    // legs under one salt would collide.
                    keccak256(abi.encode(params.distributionSalt, i))
                )
            );
        }
        bytes[] memory results = IPTLiquidityLauncher(launcher).multicall(calls);
        token = abi.decode(results[0], (address));
        if (token != predicted || token.code.length == 0) {
            revert LaunchReturnedWrongToken(predicted, token);
        }
    }

    /// @dev Predicts the auction address exactly as the strategy derives it,
    /// then reads back every recipient binding the fee route depends on. The
    /// prediction failing any read-back means the deployed auction is not the
    /// one this launch configured, and the launch must not stand.
    function _verifyInitializer(
        LBPLaunchParams calldata params,
        address token,
        PTMigratorParameters memory migratorParams,
        bytes memory auctionParams
    ) private view returns (address auction) {
        bytes32 launcherSalt = keccak256(abi.encode(address(this), params.distributionSalt));
        bytes32 initializerSalt = keccak256(abi.encode(launcherSalt, migratorParams));
        auction = IPTAuctionFactory(initializerFactory)
            .getAddress(
                token,
                uint256(params.auctionAmount) - params.reservedTokenAmountForLP,
                auctionParams,
                initializerSalt,
                lbpStrategy
            );
        if (auction.code.length == 0) revert InitializerMismatch(auction);
        IPTAuction cca = IPTAuction(auction);
        if (
            cca.token() != token || cca.currency() != params.currency
                || cca.tokensRecipient() != address(this) || cca.fundsRecipient() != lbpStrategy
        ) revert InitializerMismatch(auction);
        // Registered with the strategy under the same parameters.
        if (IPTLBPStrategy(lbpStrategy).initializers(auction).migrationBlock == 0) {
            revert InitializerMismatch(auction);
        }
    }

    // ------------------------------------------------------------------
    // Migration
    // ------------------------------------------------------------------

    /// @notice Runs the strategy's permissionless migration and records what it
    /// minted. Callable by anyone once `migrationBlock` is reached; the
    /// strategy enforces the timing and one-shot-ness.
    ///
    /// @dev Every position minted by a successful migration belongs to this
    /// adapter — the launch forced `positionRecipient` here and refused
    /// per-position overrides — so the minted set is exactly the tokenId range
    /// the position manager advanced by, filtered by ownership. Zero new
    /// positions means the strategy's internal `tryMigrate` failed and the
    /// raise plus LP reserve were refunded to this adapter instead; that
    /// terminal state is recorded so interfaces can stop waiting for a pool.
    function migrate() external nonReentrant returns (bool success) {
        _assertChain();
        if (!launched) revert NotLaunched();
        if (migrated) revert AlreadyMigrated();

        IPTPositionManager posm = IPTPositionManager(positionManager);
        uint256 before = posm.nextTokenId();
        IPTLBPStrategy(lbpStrategy).migrate(initializer);
        uint256 minted = posm.nextTokenId() - before;
        if (minted > MAX_POSITIONS) revert TooManyPositions();

        migrated = true;
        for (uint256 i = 0; i < minted; i++) {
            uint256 tokenId = before + i;
            if (posm.ownerOf(tokenId) != address(this)) continue;
            positionTokenIds.push(tokenId);
            emit PositionRegistered(tokenId);
        }

        success = positionTokenIds.length != 0;
        if (success) {
            (IPTPoolManager.PoolKey memory key,) = posm.getPoolAndPositionInfo(positionTokenIds[0]);
            poolKey = key;
        } else {
            migrationFailed = true;
        }
        emit Migrated(subject, success, positionTokenIds.length);
    }

    /// @notice Recovery path for a migration executed directly on the strategy
    /// rather than through `migrate()`: registers positions this adapter
    /// already owns. Permissionless; every id is verified against ownership
    /// and the committed pool before it is accepted.
    function registerPositions(uint256[] calldata tokenIds) external nonReentrant {
        _assertChain();
        if (!launched) revert NotLaunched();
        IPTPositionManager posm = IPTPositionManager(positionManager);

        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            if (posm.ownerOf(tokenId) != address(this)) revert PositionNotOwned(tokenId);
            for (uint256 j = 0; j < positionTokenIds.length; j++) {
                if (positionTokenIds[j] == tokenId) revert PositionNotOwned(tokenId);
            }
            (IPTPoolManager.PoolKey memory key,) = posm.getPoolAndPositionInfo(tokenId);
            _requireSubjectPool(key, tokenId);
            if (positionTokenIds.length >= MAX_POSITIONS) revert TooManyPositions();
            positionTokenIds.push(tokenId);
            if (poolKey.currency1 == address(0) && poolKey.currency0 == address(0)) {
                poolKey = key;
            }
            migrated = true;
            emit PositionRegistered(tokenId);
        }
    }

    /// @dev A position belongs to this launch when its pool pairs the subject
    /// with the committed currency under the committed fee and spacing, and
    /// carries either the committed hook or — for a zero-hook launch — the
    /// strategy-hook fallback the migration may have resolved to.
    function _requireSubjectPool(IPTPoolManager.PoolKey memory key, uint256 tokenId) private view {
        address subject_ = subject;
        address currency_ = currency;
        (address expected0, address expected1) =
            currency_ < subject_ ? (currency_, subject_) : (subject_, currency_);
        PTPoolParameters memory committed = committedPool;
        bool hookOk = committed.hook == address(0)
            ? (key.hooks == address(0) || key.hooks == lbpStrategy)
            : key.hooks == committed.hook;
        if (
            key.currency0 != expected0 || key.currency1 != expected1 || key.fee != committed.fee
                || key.tickSpacing != committed.tickSpacing || !hookOk
        ) revert PositionPoolMismatch(tokenId);
    }

    // ------------------------------------------------------------------
    // Collect and forward
    // ------------------------------------------------------------------

    /// @notice Pulls everything the launchpad currently owes: unsold auction
    /// tokens once the auction ends, and the held positions' accrued LP fees
    /// once the pool exists. Native proceeds are wrapped to WETH.
    /// Permissionless.
    ///
    /// @dev The migration sweep itself needs no pulling — the strategy pushes
    /// the raise share and any refund to this adapter during `migrate`. The
    /// auction sweep tolerates exactly its two benign refusals: not over yet,
    /// and already swept. Anything else is a real upstream failure and
    /// propagates.
    function collect() external nonReentrant returns (uint256[] memory amounts) {
        _assertChain();
        if (!launched) revert NotLaunched();

        address subject_ = subject;
        address currencyAsset = _currencyAsset();
        uint256 subjectBefore = subject_.safeBalanceOf(address(this));
        uint256 currencyBefore = currencyAsset.safeBalanceOf(address(this));

        _trySweepUnsoldTokens();
        _collectPositionFees();

        // The whole native balance wraps, not just this call's delta: the
        // migration pushes its sweep and any failure refund here as raw value,
        // and wrapping it is what first makes it forwardable.
        uint256 nativeAmount = address(this).balance;
        if (nativeAmount != 0) {
            IWETH9(weth).deposit{ value: nativeAmount }();
        }

        amounts = new uint256[](2);
        amounts[0] = subject_.safeBalanceOf(address(this)) - subjectBefore;
        amounts[1] = currencyAsset.safeBalanceOf(address(this)) - currencyBefore;

        emit Collected(subject_, subject_, amounts[0], msg.sender);
        emit Collected(subject_, currencyAsset, amounts[1], msg.sender);
    }

    function _trySweepUnsoldTokens() private {
        try IPTAuction(initializer).sweepUnsoldTokens() { }
        catch (bytes memory reason) {
            if (
                _hasSelector(reason, AUCTION_IS_NOT_OVER_SELECTOR)
                    || _hasSelector(reason, CANNOT_SWEEP_TOKENS_SELECTOR)
            ) return;
            _bubble(reason);
        }
    }

    /// @dev One PositionManager plan: a zero-liquidity decrease per held
    /// position credits each position's accrued fees as deltas, and a single
    /// TAKE_PAIR sweeps both currency sides here. A zero-fee position
    /// contributes nothing and nothing reverts, so keeper polling stays safe.
    function _collectPositionFees() private {
        uint256 count = positionTokenIds.length;
        if (count == 0) return;

        bytes memory actions = new bytes(count + 1);
        bytes[] memory params = new bytes[](count + 1);
        for (uint256 i = 0; i < count; i++) {
            // Bounded: action constants fit a byte.
            // forge-lint: disable-next-line(unsafe-typecast)
            actions[i] = bytes1(uint8(ACTION_DECREASE_LIQUIDITY));
            params[i] = abi.encode(positionTokenIds[i], 0, 0, 0, "");
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        actions[count] = bytes1(uint8(ACTION_TAKE_PAIR));
        IPTPoolManager.PoolKey memory key = poolKey;
        params[count] = abi.encode(key.currency0, key.currency1, address(this));

        IPTPositionManager(positionManager)
            .modifyLiquidities(abi.encode(actions, params), block.timestamp);
    }

    /// @notice Forwards this adapter's full balance of `asset` to the router.
    /// Permissionless. Unsupported assets are deliberately stranded rather
    /// than sweepable.
    function forward(address asset) external nonReentrant returns (uint256 amount) {
        _assertChain();
        if (!_isIntakeAsset(asset)) revert UnsupportedAsset(asset);

        address router_ = router;
        amount = asset.safeBalanceOf(address(this));
        if (amount == 0) return 0;

        uint256 routerBefore = asset.safeBalanceOf(router_);
        asset.safeTransfer(router_, amount);

        uint256 remaining = asset.safeBalanceOf(address(this));
        if (remaining != 0) revert UnexpectedBalanceDelta(asset, amount, amount - remaining);
        uint256 received = asset.safeBalanceOf(router_) - routerBefore;
        if (received != amount) revert UnexpectedBalanceDelta(asset, amount, received);

        emit Forwarded(asset, router_, amount, msg.sender);
    }

    // ------------------------------------------------------------------
    // Views
    // ------------------------------------------------------------------

    /// @notice The LBP shape pays in both pool assets: the subject (unsold
    /// auction tokens, token-side LP fees, reserve refunds) and the auction
    /// currency (raise share, currency-side LP fees), the latter as WETH for a
    /// native launch.
    function intakeAssets() external view returns (address[] memory assets) {
        assets = new address[](2);
        assets[0] = subject;
        assets[1] = _currencyAsset();
    }

    function positionCount() external view returns (uint256) {
        return positionTokenIds.length;
    }

    /// @notice Operational alarm: every registered LP position must still be
    /// owned by this adapter. The adapter never transfers them, so `false`
    /// means an upstream assumption broke and interfaces must mark future fee
    /// flow inactive.
    function feeRoutingIntact() external view returns (bool) {
        if (!launched) return false;
        IPTPositionManager posm = IPTPositionManager(positionManager);
        for (uint256 i = 0; i < positionTokenIds.length; i++) {
            if (posm.ownerOf(positionTokenIds[i]) != address(this)) return false;
        }
        return true;
    }

    function _currencyAsset() private view returns (address) {
        address currency_ = currency;
        return currency_ == address(0) ? weth : currency_;
    }

    function _isIntakeAsset(address asset) private view returns (bool) {
        if (!launched) return false;
        return asset == subject || asset == _currencyAsset();
    }

    // ------------------------------------------------------------------
    // Internals
    // ------------------------------------------------------------------

    function _hasSelector(bytes memory reason, bytes4 selector) private pure returns (bool) {
        if (reason.length < 4) return false;
        // Truncation is the point: this reads the error selector off the front
        // of the revert data, and the length is checked immediately above.
        // forge-lint: disable-next-line(unsafe-typecast)
        return bytes4(reason) == selector;
    }

    function _bubble(bytes memory reason) private pure {
        if (reason.length == 0) revert();
        assembly {
            revert(add(reason, 0x20), mload(reason))
        }
    }

    function _assertChain() private view {
        if (block.chainid != deploymentChainId) revert WrongChain(block.chainid);
    }
}
