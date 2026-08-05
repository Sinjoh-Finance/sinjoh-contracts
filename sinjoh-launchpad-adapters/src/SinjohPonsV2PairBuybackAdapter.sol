// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ISinjohSwapAdapter } from "sinjoh-fee-router/src/interfaces/ISinjohSwapAdapter.sol";
import { ISinjohPriceGuard } from "sinjoh-fee-router/src/interfaces/ISinjohPriceGuard.sol";
import { IPonsV2BondingCurve, IPonsV2LaunchFactory, IWETH } from "./interfaces/IPonsV2.sol";
import { SafeTransferLib } from "./libraries/SafeTransferLib.sol";
import { SinjohSignedFloor } from "./libraries/SinjohSignedFloor.sol";

/// @dev Minimal transcription of the Uniswap v4 PoolManager surface this
/// adapter touches, verified against the singleton at
/// 0x8366a39CC670B4001A1121B8F6A443A643e40951 on Robinhood Chain mainnet.
/// `Currency` and `IHooks` are address-backed user-defined types upstream, and
/// `BalanceDelta` is an int256 packing (amount0 << 128 | amount1), so plain
/// `address`/`int256` declarations here are ABI-identical.
interface IPonsV4PoolManager {
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

    function sync(address currency) external;

    function settle() external payable returns (uint256 paid);

    function take(address currency, address to, uint256 amount) external;
}

/// @dev SwapRouter02 exact-input surface of the pons v3 DEX router, the same
/// interface the shared SinjohSimpleSwapAdapter executes against on mainnet.
interface IPonsV3SwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params)
        external
        payable
        returns (uint256 amountOut);
}

/// @notice Converts WETH into a pons v2 launch token in whichever market the
/// launch currently has — the bonding curve before graduation, or the
/// graduated Uniswap v4 pool once seeded — for native-quote and custom-pair
/// launches alike.
///
/// One singleton serves every launch. The factory's immutable per-launch
/// record supplies the market; the only routed choice is the v3 fee tier of
/// the WETH-to-pair hop a custom-pair launch needs, frozen into the bucket's
/// immutable `routeData` at launch: empty for a native launch, one abi-encoded
/// uint24 for a custom pair. The price guard's floor spans the whole path —
/// WETH in, launch token out — so slippage on either hop of a custom-pair
/// buyback surfaces as a missed floor and the swap fails atomically.
contract SinjohPonsV2PairBuybackAdapter is ISinjohSwapAdapter {
    using SafeTransferLib for address;

    error InvalidAddress();
    error InvalidAmount();
    error InvalidRoute();
    error DependencyChanged();
    error UnknownLaunch(address token);
    error NoMarket(uint8 phase);
    error InvalidCallback();
    error Reentrancy();
    error InvalidSwapDelta();
    error InsufficientOutput(uint256 minimum, uint256 actual);
    error UnexpectedBalance();

    /// @dev `GraduationPhase` values from the factory's launch record.
    uint8 internal constant PHASE_NOT_GRADUATED = 0;
    uint8 internal constant PHASE_POOL_CREATED = 2;

    /// @dev TickMath.MIN_SQRT_PRICE + 1 and MAX_SQRT_PRICE - 1: the loosest
    /// valid limits for each direction. The price guard floors the output, so
    /// the limits only need to be reachable, not protective.
    uint160 internal constant MIN_SQRT_PRICE_LIMIT = 4_295_128_740;
    uint160 internal constant MAX_SQRT_PRICE_LIMIT =
        1_461_446_703_485_210_103_287_273_052_203_988_822_378_723_970_341;

    address public immutable launchFactory;
    address public immutable poolManager;
    address public immutable weth;
    address public immutable v3SwapRouter;
    /// @dev Immutable on the factory; read once here. Every pool graduated
    /// through the pinned factory carries this hook in its v4 pool key.
    address public immutable memeHook;
    bytes32 public immutable launchFactoryCodehash;
    bytes32 public immutable poolManagerCodehash;
    bytes32 public immutable wethCodehash;
    bytes32 public immutable v3SwapRouterCodehash;
    bytes32 public immutable memeHookCodehash;

    uint256 private _active;

    constructor(
        address launchFactory_,
        address poolManager_,
        address weth_,
        address v3SwapRouter_,
        bytes32 launchFactoryCodehash_,
        bytes32 poolManagerCodehash_,
        bytes32 wethCodehash_,
        bytes32 v3SwapRouterCodehash_
    ) {
        if (
            launchFactory_.code.length == 0 || poolManager_.code.length == 0
                || weth_.code.length == 0 || v3SwapRouter_.code.length == 0
                || launchFactory_.codehash != launchFactoryCodehash_
                || poolManager_.codehash != poolManagerCodehash_
                || weth_.codehash != wethCodehash_
                || v3SwapRouter_.codehash != v3SwapRouterCodehash_
        ) revert InvalidAddress();
        // The factory names the singleton its graduated pools live in. Pinning
        // a manager the pinned factory does not use would derive pool keys for
        // pools that do not exist.
        if (IPonsV2LaunchFactory(launchFactory_).poolManager() != poolManager_) {
            revert InvalidAddress();
        }
        address memeHook_ = IPonsV2LaunchFactory(launchFactory_).memeHook();
        if (memeHook_.code.length == 0) revert InvalidAddress();

        launchFactory = launchFactory_;
        poolManager = poolManager_;
        weth = weth_;
        v3SwapRouter = v3SwapRouter_;
        memeHook = memeHook_;
        launchFactoryCodehash = launchFactoryCodehash_;
        poolManagerCodehash = poolManagerCodehash_;
        wethCodehash = wethCodehash_;
        v3SwapRouterCodehash = v3SwapRouterCodehash_;
        memeHookCodehash = memeHook_.codehash;
    }

    /// @dev Accepts the WETH unwrap and the pool manager's native refunds.
    /// Value never rests here: `swap` asserts the native balance returns to
    /// exactly what it was.
    receive() external payable { }

    /// @param routeData Empty for a native-quote launch. For a custom-pair
    /// launch, exactly one abi-encoded nonzero uint24: the v3 fee tier of the
    /// pair asset's WETH pool, chosen at launch and frozen with the route.
    ///
    /// @dev Near the graduation threshold the curve fills a crossing buy only
    /// partially and refunds the rest, which leaves this adapter holding
    /// residual value and trips `UnexpectedBalance`. That is deliberate: the
    /// router debits the full input from its ledger and the guard floored the
    /// full amount, so a partial fill must fail atomically. The caller retries
    /// with a smaller `amountIn`, or waits out the (permissionless,
    /// `createGraduatedPool`) seeding step and buys from the v4 pool.
    function swap(
        address assetIn,
        address assetOut,
        uint256 amountIn,
        uint256 minAmountOut,
        bytes calldata routeData
    ) external payable {
        if (_active != 0) revert Reentrancy();
        if (
            msg.value != 0 || assetIn != weth || assetOut == address(0) || assetOut == weth
                || amountIn == 0 || minAmountOut == 0
                || amountIn > uint256(uint128(type(int128).max))
        ) revert InvalidAmount();
        if (
            launchFactory.codehash != launchFactoryCodehash
                || poolManager.codehash != poolManagerCodehash || weth.codehash != wethCodehash
                || v3SwapRouter.codehash != v3SwapRouterCodehash
                || memeHook.codehash != memeHookCodehash
        ) revert DependencyChanged();

        IPonsV2LaunchFactory.LaunchedToken memory launch =
            IPonsV2LaunchFactory(launchFactory).getLaunchedToken(assetOut);
        if (!launch.exists || launch.token != assetOut) revert UnknownLaunch(assetOut);

        bool native = launch.pairToken == address(0);
        uint24 pairHopFee = 0;
        if (native) {
            if (routeData.length != 0) revert InvalidRoute();
        } else {
            if (routeData.length != 32) revert InvalidRoute();
            pairHopFee = abi.decode(routeData, (uint24));
            if (pairHopFee == 0) revert InvalidRoute();
        }

        uint256 inputBefore = weth.safeBalanceOf(address(this));
        uint256 outputBefore = assetOut.safeBalanceOf(address(this));
        uint256 nativeBefore = address(this).balance;
        uint256 pairBefore = native ? 0 : launch.pairToken.safeBalanceOf(address(this));

        weth.safeTransferFrom(msg.sender, address(this), amountIn);

        if (native) {
            IWETH(weth).withdraw(amountIn);
            if (launch.phase == PHASE_NOT_GRADUATED) {
                IPonsV2BondingCurve(launch.curve).buy{ value: amountIn }(
                    amountIn, minAmountOut, address(this)
                );
            } else if (launch.phase == PHASE_POOL_CREATED) {
                _active = 1;
                IPonsV4PoolManager(poolManager)
                    .unlock(
                        abi.encode(
                            address(0),
                            assetOut,
                            launch.poolFee,
                            launch.tickSpacing,
                            amountIn,
                            minAmountOut
                        )
                    );
                _active = 0;
            } else {
                revert NoMarket(launch.phase);
            }
        } else {
            // Hop one: WETH into the pair asset through its pinned v3 pool —
            // the reverse of the direction the router's intake normalization
            // trades. The intermediate minimum is 1 because the guard's floor
            // binds the final launch-token output for the full WETH input; a
            // sandwich on this hop shrinks that output and reverts below.
            uint256 pairReceived;
            {
                weth.safeApprove(v3SwapRouter, amountIn);
                IPonsV3SwapRouter(v3SwapRouter)
                    .exactInputSingle(
                        IPonsV3SwapRouter.ExactInputSingleParams({
                        tokenIn: weth,
                        tokenOut: launch.pairToken,
                        fee: pairHopFee,
                        recipient: address(this),
                        amountIn: amountIn,
                        amountOutMinimum: 1,
                        sqrtPriceLimitX96: 0
                    })
                    );
                weth.safeApprove(v3SwapRouter, 0);
                pairReceived = launch.pairToken.safeBalanceOf(address(this)) - pairBefore;
                if (pairReceived == 0 || pairReceived > uint256(uint128(type(int128).max))) {
                    revert InvalidSwapDelta();
                }
            }

            // Hop two: the pair asset into the launch token on whichever
            // market the launch currently has.
            if (launch.phase == PHASE_NOT_GRADUATED) {
                launch.pairToken.safeApprove(launch.curve, pairReceived);
                IPonsV2BondingCurve(launch.curve).buy(pairReceived, minAmountOut, address(this));
                launch.pairToken.safeApprove(launch.curve, 0);
            } else if (launch.phase == PHASE_POOL_CREATED) {
                _active = 1;
                IPonsV4PoolManager(poolManager)
                    .unlock(
                        abi.encode(
                            launch.pairToken,
                            assetOut,
                            launch.poolFee,
                            launch.tickSpacing,
                            pairReceived,
                            minAmountOut
                        )
                    );
                _active = 0;
            } else {
                revert NoMarket(launch.phase);
            }
        }

        uint256 received = assetOut.safeBalanceOf(address(this)) - outputBefore;
        if (received == 0 || received < minAmountOut) {
            revert InsufficientOutput(minAmountOut, received);
        }
        assetOut.safeTransfer(msg.sender, received);
        if (
            weth.safeBalanceOf(address(this)) != inputBefore
                || address(this).balance != nativeBefore
                || (!native && launch.pairToken.safeBalanceOf(address(this)) != pairBefore)
        ) revert UnexpectedBalance();
    }

    /// @dev The pool manager echoes the data `swap` passed to `unlock`, so its
    /// contents are self-authenticated by the `_active` gate: no one else can
    /// reach this while a swap is in flight, and outside one it reverts.
    /// `quote` is the zero address for a native pool and the pair asset for a
    /// custom-pair pool; the currency pair sorts by address, which fixes the
    /// swap direction and the settlement leg.
    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != poolManager || _active != 1) revert InvalidCallback();
        (
            address quote,
            address token,
            uint24 poolFee,
            int24 tickSpacing,
            uint256 amountIn,
            uint256 minimumOut
        ) = abi.decode(data, (address, address, uint24, int24, uint256, uint256));

        // Native sorts first as the zero address; an ERC20 pair sorts by
        // address against the token. Fee, spacing, and hook reproduce the key
        // the factory builds in `createGraduatedPool` from the same record.
        bool quoteIsCurrency0 = quote < token;
        (address currency0, address currency1) =
            quoteIsCurrency0 ? (quote, token) : (token, quote);
        int256 delta = IPonsV4PoolManager(poolManager)
            .swap(
                IPonsV4PoolManager.PoolKey({
                currency0: currency0,
                currency1: currency1,
                fee: poolFee,
                tickSpacing: tickSpacing,
                hooks: memeHook
            }),
                IPonsV4PoolManager.SwapParams({
                zeroForOne: quoteIsCurrency0,
                // `swap` bounds both legs to int128.max, so the negation fits.
                // forge-lint: disable-next-line(unsafe-typecast)
                amountSpecified: -int256(amountIn),
                sqrtPriceLimitX96: quoteIsCurrency0 ? MIN_SQRT_PRICE_LIMIT : MAX_SQRT_PRICE_LIMIT
            }),
                ""
            );
        // amount0 rides the upper 128 bits of the packed delta, amount1 the
        // lower. Truncation is the decoding.
        int256 amount0 = delta >> 128;
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 amount1 = int128(delta);
        int256 inputDelta = quoteIsCurrency0 ? amount0 : amount1;
        int256 outputDelta = quoteIsCurrency0 ? amount1 : amount0;
        if (inputDelta >= 0 || outputDelta <= 0) revert InvalidSwapDelta();

        // Sign-checked immediately above, so both fit their unsigned targets.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 amountSpent = uint256(-inputDelta);
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 amountOut = uint256(outputDelta);
        // The router debits the full requested input from its liability
        // ledger, so a partial fill (price limit reached) must fail here
        // rather than surface as a balance mismatch upstream.
        if (amountSpent != amountIn) revert InvalidSwapDelta();
        // `swap` re-checks what actually arrived; this earlier check reports
        // the pool's own answer before value moves.
        if (amountOut < minimumOut) revert InsufficientOutput(minimumOut, amountOut);

        if (quote == address(0)) {
            if (IPonsV4PoolManager(poolManager).settle{ value: amountSpent }() != amountSpent) {
                revert InvalidSwapDelta();
            }
        } else {
            // ERC20 settlement: declare the currency, move the tokens, settle
            // the declared balance — the v4 singleton's sync/transfer/settle
            // sequence.
            IPonsV4PoolManager(poolManager).sync(quote);
            quote.safeTransfer(poolManager, amountSpent);
            if (IPonsV4PoolManager(poolManager).settle() != amountSpent) {
                revert InvalidSwapDelta();
            }
        }
        IPonsV4PoolManager(poolManager).take(token, address(this), amountOut);
        return "";
    }
}

/// @notice Amount-aware signed floor for pons v2 buybacks on any pair.
///
/// @dev Unlike the Flap guards there is no on-chain quote to cross-check the
/// signature against: the bonding curve exposes no quote view, and the
/// graduated pool is Uniswap v4 under the pons meme hook, which implements no
/// oracle — quoting it requires the unlock flow, which cannot run from a view
/// context. The floor is therefore entirely the signer's, bounded by the
/// five-minute validity window, and spans the full WETH-to-token path
/// including a custom pair's v3 hop. That is the documented posture for
/// graduated v2 pools (see PONS-V2-FINDINGS.md): price protection is
/// caller-supplied.
contract SinjohPonsV2PairBuybackPriceGuard is ISinjohPriceGuard {
    uint48 public constant MAXIMUM_VALIDITY = 5 minutes;
    bytes32 public constant FLOOR_TYPEHASH = keccak256(
        "SinjohPonsV2BuybackFloor(uint256 chainId,address guard,address router,address subject,address assetIn,address assetOut,uint256 amountIn,bytes32 routeHash,uint256 minimum,uint48 validAfter,uint48 validUntil)"
    );

    error InvalidAddress();
    error InvalidAmount();
    error InvalidRoute();
    error DependencyChanged();
    error UnknownLaunch(address token);

    address public immutable launchFactory;
    address public immutable weth;
    bytes32 public immutable launchFactoryCodehash;
    bytes32 public immutable wethCodehash;
    address public immutable quoteSigner;

    constructor(
        address launchFactory_,
        address weth_,
        bytes32 launchFactoryCodehash_,
        bytes32 wethCodehash_,
        address quoteSigner_
    ) {
        if (
            launchFactory_.code.length == 0 || weth_.code.length == 0 || launchFactory_ == weth_
                || launchFactory_.codehash != launchFactoryCodehash_
                || weth_.codehash != wethCodehash_ || quoteSigner_ == address(0)
        ) revert InvalidAddress();
        launchFactory = launchFactory_;
        weth = weth_;
        launchFactoryCodehash = launchFactoryCodehash_;
        wethCodehash = wethCodehash_;
        quoteSigner = quoteSigner_;
    }

    function floorDigest(
        address router,
        address subject,
        address assetIn,
        address assetOut,
        uint256 amountIn,
        bytes32 routeHash,
        uint256 signedMinimum,
        uint48 validAfter,
        uint48 validUntil
    ) public view returns (bytes32) {
        return keccak256(
            abi.encode(
                FLOOR_TYPEHASH,
                block.chainid,
                address(this),
                router,
                subject,
                assetIn,
                assetOut,
                amountIn,
                routeHash,
                signedMinimum,
                validAfter,
                validUntil
            )
        );
    }

    function minimumOutput(
        address subject,
        address assetIn,
        address assetOut,
        uint256 amountIn,
        bytes32 routeDataHash,
        bytes calldata guardData
    ) external view returns (uint256 minimum, uint48 validUntil) {
        if (subject == address(0) || subject != assetOut || assetIn != weth || amountIn == 0) {
            revert InvalidAmount();
        }
        if (launchFactory.codehash != launchFactoryCodehash || weth.codehash != wethCodehash) {
            revert DependencyChanged();
        }
        // Mirror the adapter's launch checks so a route that clears this guard
        // is one the adapter will actually execute: a native launch carries no
        // route data, a custom-pair launch carries its frozen v3 fee tier.
        IPonsV2LaunchFactory.LaunchedToken memory launch =
            IPonsV2LaunchFactory(launchFactory).getLaunchedToken(subject);
        if (!launch.exists || launch.token != subject) revert UnknownLaunch(subject);
        if (launch.pairToken == address(0)) {
            if (routeDataHash != keccak256("")) revert InvalidRoute();
        } else {
            if (routeDataHash == keccak256("")) revert InvalidRoute();
        }

        (
            uint256 signedMinimum,
            uint48 validAfter,
            uint48 signedValidUntil,
            bytes memory signature
        ) = abi.decode(guardData, (uint256, uint48, uint48, bytes));
        if (signedMinimum == 0) revert InvalidAmount();
        SinjohSignedFloor.validate(
            floorDigest(
                msg.sender,
                subject,
                assetIn,
                assetOut,
                amountIn,
                routeDataHash,
                signedMinimum,
                validAfter,
                signedValidUntil
            ),
            quoteSigner,
            validAfter,
            signedValidUntil,
            MAXIMUM_VALIDITY,
            signature
        );
        minimum = signedMinimum;
        validUntil = signedValidUntil;
    }
}
