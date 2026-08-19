// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ISinjohLaunchpadAdapter } from "./interfaces/ISinjohLaunchpadAdapter.sol";
import {
    IPTBeneficiaryVault,
    IPTFeeSplitter,
    IPTInstantLaunchStrategy,
    IPTLiquidityLauncher,
    IPTPoolManager,
    IPTPositionManager,
    IPTUERC20Factory,
    IWETH9,
    PTDistribution,
    PTInstantLaunchConfig,
    PTTokenMetadata
} from "./interfaces/IPoolsTrade.sol";
import { SafeTransferLib } from "./libraries/SafeTransferLib.sol";

interface ISinjohFeeRouter {
    function launchpadAdapter() external view returns (address);
    function bind(address subject) external;
}

/// @notice Launches on pools.trade's InstantLaunchStrategy and forwards its
/// creator fees to one immutable `SinjohFeeRouter`.
///
/// An instant launch has no curve and no graduation: the strategy LPs the whole
/// fixed supply single-sided into a hookless native-ETH Uniswap v4 pool and
/// permanently locks the position in the FeeSplitter. Creator revenue is the
/// vault's share of the position's native LP fees, attributed to the launch's
/// position tokenId and claimable only by the owner of the beneficiary ("FEEB")
/// ERC-721 — which is this adapter, so it can originate the claim.
///
/// The same bytecode serves both deployed strategy variants. On the
/// no-creator-fee variant (`beneficiaryVault() == 0`) no FEEB NFT exists and no
/// value ever reaches the creator, so `collect` is a permanent no-op and the
/// intake asset set is empty; the launch itself is still supported.
///
/// The adapter performs no accounting, allocation, or protocol-fee charging.
/// The 1% Sinjoh fee is charged exactly once, later, when `router.sync(asset)`
/// turns a forwarded balance into router liabilities.
contract SinjohPoolsTradeInstantAdapter is ISinjohLaunchpadAdapter {
    using SafeTransferLib for address;

    error AlreadyInitialized();
    error AlreadyLaunched();
    error NotLaunched();
    error Unauthorized();
    error WrongChain(uint256 actual);
    error InvalidAddress();
    error UnsupportedAsset(address asset);
    error Reentrancy();
    error InvalidDeveloperBuy();
    error NativeValueMismatch(uint256 expected, uint256 actual);
    error PredictionOccupied(address predicted);
    error LaunchReturnedWrongToken(address expected, address actual);
    error PositionNotLocked(uint256 tokenId, address owner);
    error BeneficiaryNotAdapter(uint256 tokenId, address owner);
    error RouterDidNotNameAdapter(address named);
    error InvalidCallback();
    error InvalidSwapDelta();
    error InsufficientOutput(uint256 minimum, uint256 actual);
    error UnexpectedBalanceDelta(address asset, uint256 expected, uint256 actual);

    event Initialized(address indexed router, address indexed creator);
    event Launched(address indexed subject, uint256 indexed positionTokenId, bool creatorFees);
    event DeveloperBuyDelivered(
        address indexed subject, address indexed creator, uint256 nativeIn, uint256 tokensOut
    );
    event Collected(
        address indexed subject, address indexed asset, uint256 amount, address indexed caller
    );
    event Forwarded(
        address indexed asset, address indexed router, uint256 amount, address indexed caller
    );

    /// @dev TickMath.MIN_SQRT_PRICE + 1: the loosest valid limit for an
    /// exact-input buy of currency1. The developer buy floors its own output,
    /// so the limit only needs to be reachable, not protective.
    uint160 internal constant MIN_SQRT_PRICE_LIMIT = 4_295_128_740;

    address public immutable launcher;
    address public immutable tokenFactory;
    address public immutable strategy;
    address public immutable feeSplitter;
    /// @dev Zero on the no-creator-fee strategy variant.
    address public immutable beneficiaryVault;
    address public immutable positionManager;
    address public immutable poolManager;
    address public immutable weth;
    uint256 public immutable deploymentChainId;
    /// @dev The strategy accepts exactly this supply on every launch.
    uint128 public immutable launchSupply;
    /// @dev Static pool parameters of every launch pool this strategy creates;
    /// the developer buy rebuilds the pool key from them.
    uint24 public immutable lpFee;
    int24 public immutable poolTickSpacing;

    address public router;
    address public creator;
    address public subject;
    /// @notice The v4 position tokenId of the locked launch position; keys both
    /// the FeeSplitter collection and the vault claim.
    uint256 public positionTokenId;
    bool public initialized;
    bool public launched;

    uint256 private _reentrancyState;
    uint256 private _active;

    constructor(
        address launcher_,
        address tokenFactory_,
        address strategy_,
        address weth_,
        uint256 chainId_
    ) {
        if (
            launcher_.code.length == 0 || tokenFactory_.code.length == 0
                || strategy_.code.length == 0 || weth_.code.length == 0
        ) revert InvalidAddress();
        if (chainId_ != block.chainid) revert WrongChain(block.chainid);

        IPTInstantLaunchStrategy strat = IPTInstantLaunchStrategy(strategy_);
        // The strategy names its own launcher; a launch through any other
        // launcher reverts `OnlyLauncher` upstream. Pinning a mismatched pair
        // would make every launch fail after the token was already minted.
        if (strat.launcher() != launcher_) revert InvalidAddress();

        address feeSplitter_ = strat.feeSplitter();
        address beneficiaryVault_ = strat.beneficiaryVault();
        address positionManager_ = strat.positionManager();
        address poolManager_ = strat.poolManager();
        if (
            feeSplitter_.code.length == 0 || positionManager_.code.length == 0
                || poolManager_.code.length == 0
        ) {
            revert InvalidAddress();
        }
        // The splitter collects through its own PositionManager and the vault
        // proves custody against its own; the strategy constructor enforces
        // both, re-asserted here so a mispinned strategy cannot pass silently.
        if (IPTFeeSplitter(feeSplitter_).positionManager() != positionManager_) {
            revert InvalidAddress();
        }
        if (
            beneficiaryVault_ != address(0)
                && IPTBeneficiaryVault(beneficiaryVault_).positionManager() != positionManager_
        ) revert InvalidAddress();
        if (IPTPositionManager(positionManager_).poolManager() != poolManager_) {
            revert InvalidAddress();
        }

        uint256 totalSupply_ = strat.TOTAL_SUPPLY();
        if (totalSupply_ == 0 || totalSupply_ > type(uint128).max) revert InvalidAddress();

        launcher = launcher_;
        tokenFactory = tokenFactory_;
        strategy = strategy_;
        feeSplitter = feeSplitter_;
        beneficiaryVault = beneficiaryVault_;
        positionManager = positionManager_;
        poolManager = poolManager_;
        weth = weth_;
        deploymentChainId = chainId_;
        // Bounded immediately above.
        // forge-lint: disable-next-line(unsafe-typecast)
        launchSupply = uint128(totalSupply_);
        lpFee = strat.LP_FEE();
        poolTickSpacing = strat.TICK_SPACING();
        initialized = true;
    }

    modifier nonReentrant() {
        if (_reentrancyState == 2) revert Reentrancy();
        _reentrancyState = 2;
        _;
        _reentrancyState = 1;
    }

    /// @dev Accepts native value from the vault claim and the pool manager's
    /// refunds. Receiving ETH grants no accounting claim on it; only `collect`
    /// and `forward` move value onward.
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

    /// @notice The token address this adapter's launch will deploy. Exact: the
    /// UERC20 factory derives it from (name, symbol, decimals, launcher,
    /// graffiti) alone, and the graffiti hashes this adapter.
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

    /// @notice Creates the token and launches it into its v4 pool in one
    /// launcher `multicall`, with this adapter as the fee beneficiary, then
    /// performs the developer buy against the fresh pool in the same
    /// transaction — the pool is live from the launch call, and buying here is
    /// what makes the developer buy un-front-runnable.
    ///
    /// @dev `metadata` strings are token display data consumed by the UERC20
    /// factory, not an execution surface. `msg.value` must equal
    /// `developerBuy`. The launched supply and pool shape are fixed by the
    /// pinned strategy; nothing about them is caller-configurable.
    function launch(
        string calldata name,
        string calldata symbol,
        PTTokenMetadata calldata metadata,
        bytes32 distributionSalt,
        uint256 developerBuy,
        uint256 minTokensOut
    ) external payable nonReentrant returns (address token, uint256 tokenId) {
        _assertChain();
        if (msg.sender != creator) revert Unauthorized();
        if (launched) revert AlreadyLaunched();
        address router_ = router;
        if (router_ == address(0)) revert InvalidAddress();
        // The adapter's salt cannot commit to the router without creating a
        // circular dependency between the two predicted addresses, so the
        // binding is proved here instead: a router that did not name this
        // adapter will not accept its `bind`, and the launch must not happen.
        address named = ISinjohFeeRouter(router_).launchpadAdapter();
        if (named != address(this)) revert RouterDidNotNameAdapter(named);
        if (developerBuy != 0 && minTokensOut == 0) revert InvalidDeveloperBuy();
        if (msg.value != developerBuy) revert NativeValueMismatch(developerBuy, msg.value);
        launched = true;

        address predicted = predictSubject(name, symbol);
        // A CREATE2 collision — same (name, symbol) from this adapter — would
        // revert deep inside the factory; refuse it legibly first.
        if (predicted.code.length != 0) revert PredictionOccupied(predicted);

        tokenId = IPTPositionManager(positionManager).nextTokenId();

        token = _launchViaLauncher(name, symbol, metadata, distributionSalt, predicted);

        bool creatorFees = beneficiaryVault != address(0);
        // The strategy locked the position and, on the creator-fee variant,
        // minted the FEEB NFT for the same tokenId. Both custody facts are what
        // the entire fee route rests on, so they are read back, not assumed.
        address positionOwner = IPTPositionManager(positionManager).ownerOf(tokenId);
        if (positionOwner != feeSplitter) revert PositionNotLocked(tokenId, positionOwner);
        if (creatorFees) {
            address beneficiary = IPTBeneficiaryVault(beneficiaryVault).ownerOf(tokenId);
            if (beneficiary != address(this)) revert BeneficiaryNotAdapter(tokenId, beneficiary);
        }

        subject = token;
        positionTokenId = tokenId;
        emit Launched(token, tokenId, creatorFees);

        ISinjohFeeRouter(router_).bind(token);

        if (developerBuy != 0) {
            _developerBuy(token, developerBuy, minTokensOut);
        }
    }

    /// @dev One launcher `multicall`: mint the full supply into the launcher,
    /// then distribute it through the pinned strategy with this adapter as the
    /// fee beneficiary. The distribution names the predicted token, and the
    /// factory's returned address is checked against the same prediction.
    function _launchViaLauncher(
        string calldata name,
        string calldata symbol,
        PTTokenMetadata calldata metadata,
        bytes32 distributionSalt,
        address predicted
    ) private returns (address token) {
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeCall(
            IPTLiquidityLauncher.createToken,
            (tokenFactory, name, symbol, 18, launchSupply, launcher, abi.encode(metadata))
        );
        calls[1] = abi.encodeCall(
            IPTLiquidityLauncher.distributeToken,
            (
                predicted,
                PTDistribution({
                    strategy: strategy,
                    amount: launchSupply,
                    configData: abi.encode(PTInstantLaunchConfig({ feeBeneficiary: address(this) }))
                }),
                distributionSalt
            )
        );
        bytes[] memory results = IPTLiquidityLauncher(launcher).multicall(calls);
        token = abi.decode(results[0], (address));
        if (token != predicted || token.code.length == 0) {
            revert LaunchReturnedWrongToken(predicted, token);
        }
    }

    /// @dev Buys the subject from its launch pool with the native value the
    /// creator sent, and forwards the output to the creator. The pool key is
    /// rebuilt from the strategy's immutable launch shape: native currency0,
    /// the subject as currency1, static fee and spacing, no hook.
    function _developerBuy(address token, uint256 developerBuy, uint256 minTokensOut) private {
        if (developerBuy > uint256(uint128(type(int128).max))) revert InvalidDeveloperBuy();
        address creator_ = creator;
        uint256 tokensBefore = token.safeBalanceOf(address(this));
        uint256 nativeBefore = address(this).balance - developerBuy;

        _active = 1;
        IPTPoolManager(poolManager).unlock(abi.encode(token, developerBuy, minTokensOut));
        _active = 0;

        uint256 tokensOut = token.safeBalanceOf(address(this)) - tokensBefore;
        if (tokensOut < minTokensOut) revert InsufficientOutput(minTokensOut, tokensOut);
        token.safeTransfer(creator_, tokensOut);
        // The swap must consume the full input: the creator paid exactly this
        // value in, and a partial fill would strand the difference here where
        // it has no accounting claim.
        if (address(this).balance != nativeBefore) {
            revert UnexpectedBalanceDelta(address(0), 0, address(this).balance - nativeBefore);
        }
        emit DeveloperBuyDelivered(token, creator_, developerBuy, tokensOut);
    }

    /// @dev The pool manager echoes the data `_developerBuy` passed to
    /// `unlock`, so its contents are self-authenticated by the `_active` gate:
    /// no one else can reach this while a buy is in flight, and outside one it
    /// reverts.
    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != poolManager || _active != 1) revert InvalidCallback();
        (address token, uint256 amountIn, uint256 minimumOut) =
            abi.decode(data, (address, uint256, uint256));

        int256 delta = IPTPoolManager(poolManager)
            .swap(
                IPTPoolManager.PoolKey({
                currency0: address(0),
                currency1: token,
                fee: lpFee,
                tickSpacing: poolTickSpacing,
                hooks: address(0)
            }),
                IPTPoolManager.SwapParams({
                zeroForOne: true,
                // `_developerBuy` bounds amountIn to int128.max, so the
                // negation fits.
                // forge-lint: disable-next-line(unsafe-typecast)
                amountSpecified: -int256(amountIn),
                sqrtPriceLimitX96: MIN_SQRT_PRICE_LIMIT
            }),
                ""
            );
        // amount0 rides the upper 128 bits of the packed delta, amount1 the
        // lower. Truncation is the decoding.
        int256 inputDelta = delta >> 128;
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 outputDelta = int128(delta);
        if (inputDelta >= 0 || outputDelta <= 0) revert InvalidSwapDelta();

        // Sign-checked immediately above, so both fit their unsigned targets.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 amountSpent = uint256(-inputDelta);
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 amountOut = uint256(outputDelta);
        if (amountSpent != amountIn) revert InvalidSwapDelta();
        if (amountOut < minimumOut) revert InsufficientOutput(minimumOut, amountOut);

        if (IPTPoolManager(poolManager).settle{ value: amountSpent }() != amountSpent) {
            revert InvalidSwapDelta();
        }
        IPTPoolManager(poolManager).take(token, address(this), amountOut);
        return "";
    }

    // ------------------------------------------------------------------
    // Collect and forward
    // ------------------------------------------------------------------

    /// @notice Collects the locked position's accrued fees through the
    /// FeeSplitter, claims this adapter's attributed vault balance, and wraps
    /// the native proceeds to WETH. Permissionless.
    ///
    /// @dev Two upstream steps, not one. Fees accrue inside the v4 position and
    /// only reach the vault when someone calls the splitter's permissionless
    /// `collectFees`; claiming without collecting would drain a vault balance
    /// that is usually zero while the real fees sat in the pool indefinitely.
    /// Neither step reverts on zero accrual, so no error absorption is needed —
    /// an upstream failure here is real and must propagate.
    ///
    /// On the no-creator-fee variant nothing is ever owed to this adapter, so
    /// this is a no-op returning an empty array, matching `intakeAssets()`.
    function collect() external nonReentrant returns (uint256[] memory amounts) {
        _assertChain();
        if (!launched) revert NotLaunched();

        address vault = beneficiaryVault;
        if (vault == address(0)) {
            emit Collected(subject, address(0), 0, msg.sender);
            return new uint256[](0);
        }

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = positionTokenId;
        IPTFeeSplitter(feeSplitter).collectFees(tokenIds);

        uint256 balanceBefore = address(this).balance;
        IPTBeneficiaryVault(vault).claim(positionTokenId, 0, 0);
        uint256 nativeAmount = address(this).balance - balanceBefore;
        if (nativeAmount != 0) {
            IWETH9(weth).deposit{ value: nativeAmount }();
        }

        amounts = new uint256[](1);
        amounts[0] = nativeAmount;
        emit Collected(subject, weth, nativeAmount, msg.sender);
    }

    /// @notice Forwards this adapter's full balance of `asset` to the router.
    /// Permissionless. Direct transfers of a supported asset are forwarded by
    /// the same path; unsupported assets are deliberately stranded rather than
    /// sweepable, because a generic sweep is an arbitrary-token execution
    /// surface.
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

    /// @notice The vault pays creator fees exclusively in native ETH, wrapped
    /// here to WETH; the subject is never a fee asset. Empty on the
    /// no-creator-fee variant, where nothing is ever owed.
    function intakeAssets() external view returns (address[] memory assets) {
        if (beneficiaryVault == address(0)) return new address[](0);
        assets = new address[](1);
        assets[0] = weth;
    }

    /// @notice Operational alarm over the mutable upstream custody facts the
    /// fee route rests on: the launch position stays locked in the FeeSplitter
    /// and the FEEB NFT stays with this adapter. Neither should be able to
    /// change — the splitter has no withdrawal path and the adapter never
    /// transfers the NFT — so `false` here means an upstream assumption broke
    /// and interfaces must mark future fee flow inactive.
    function feeRoutingIntact() external view returns (bool) {
        if (!launched) return false;
        uint256 tokenId = positionTokenId;
        if (IPTPositionManager(positionManager).ownerOf(tokenId) != feeSplitter) return false;
        address vault = beneficiaryVault;
        if (vault == address(0)) return true;
        return IPTBeneficiaryVault(vault).ownerOf(tokenId) == address(this);
    }

    function _isIntakeAsset(address asset) private view returns (bool) {
        if (!launched) return false;
        return beneficiaryVault != address(0) && asset == weth;
    }

    function _assertChain() private view {
        if (block.chainid != deploymentChainId) revert WrongChain(block.chainid);
    }
}
