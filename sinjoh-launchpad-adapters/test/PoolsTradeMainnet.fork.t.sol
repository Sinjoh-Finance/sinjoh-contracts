// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { TestBase } from "./TestBase.sol";
import { SinjohFeeRouter } from "sinjoh-fee-router/src/SinjohFeeRouter.sol";
import { SinjohFeeRouterFactory } from "sinjoh-fee-router/src/SinjohFeeRouterFactory.sol";
import { RouterTypes } from "sinjoh-fee-router/src/RouterTypes.sol";
import { SinjohPoolsTradeInstantAdapter } from "../src/SinjohPoolsTradeInstantAdapter.sol";
import {
    SinjohPoolsTradeInstantAdapterFactory
} from "../src/SinjohPoolsTradeInstantAdapterFactory.sol";
import { SinjohPoolsTradeLBPAdapter } from "../src/SinjohPoolsTradeLBPAdapter.sol";
import { SinjohPoolsTradeLBPAdapterFactory } from "../src/SinjohPoolsTradeLBPAdapterFactory.sol";
import {
    SinjohPoolsTradeBuybackPriceGuard
} from "../src/SinjohPoolsTradeBuybackAdapter.sol";
import { SinjohPoolsTradeSubjectPriceGuard } from "../src/SinjohPoolsTradeSubjectPriceGuard.sol";
import {
    IPTPoolManager,
    PTLiquidityAllocationBracket,
    PTPositionDefinition,
    PTSplit,
    PTTokenMetadata
} from "../src/interfaces/IPoolsTrade.sol";

interface IERC20Fork {
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

interface ICCABid {
    function submitBid(uint256 maxPriceQ96, uint128 amount, address owner, bytes calldata hookData)
        external
        payable
        returns (uint256 bidId);
    function currencyRaised() external view returns (uint256);
}

/// @dev Stands in for the ArbSys precompile on the fork. The deployed
/// pools.trade contracts read block numbers through `arbBlockNumber()`
/// (BlockNumberish probed the precompile at construction on the live chain),
/// and foundry forks cannot execute the real precompile — so the fork installs
/// this at address(100) and `vm.roll` drives auction time.
contract MockArbSys {
    function arbBlockNumber() external view returns (uint256) {
        return block.number;
    }
}

/// @dev Trades against the real v4 singleton to accrue LP fees on a launch
/// pool: exact-in buys with native and exact-in sells of the token.
contract V4TradeHelper {
    address public immutable poolManager;

    constructor(address poolManager_) {
        poolManager = poolManager_;
    }

    receive() external payable { }

    function buy(IPTPoolManager.PoolKey calldata key, uint256 amountIn) external payable {
        IPTPoolManager(poolManager).unlock(abi.encode(true, key, amountIn));
    }

    function sell(IPTPoolManager.PoolKey calldata key, uint256 amountIn) external {
        IPTPoolManager(poolManager).unlock(abi.encode(false, key, amountIn));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == poolManager, "not pool manager");
        (bool isBuy, IPTPoolManager.PoolKey memory key, uint256 amountIn) =
            abi.decode(data, (bool, IPTPoolManager.PoolKey, uint256));

        int256 delta = IPTPoolManager(poolManager)
            .swap(
                key,
                IPTPoolManager.SwapParams({
                    zeroForOne: isBuy,
                    amountSpecified: -int256(amountIn),
                    sqrtPriceLimitX96: isBuy
                        ? uint160(4_295_128_740)
                        : uint160(1_461_446_703_485_210_103_287_273_052_203_988_822_378_723_970_341)
                }),
                ""
            );
        int256 amount0 = delta >> 128;
        int256 amount1 = int256(int128(delta));

        if (isBuy) {
            // Native in (amount0 negative), token out (amount1 positive).
            IPTPoolManager(poolManager).settle{ value: uint256(-amount0) }();
            IPTPoolManager(poolManager).take(key.currency1, address(this), uint256(amount1));
        } else {
            // Token in (amount1 negative), native out (amount0 positive).
            IPTPoolManager(poolManager).sync(key.currency1);
            (bool ok,) = key.currency1
                .call(abi.encodeWithSignature("transfer(address,uint256)", poolManager, uint256(-amount1)));
            require(ok, "transfer failed");
            IPTPoolManager(poolManager).settle();
            IPTPoolManager(poolManager).take(address(0), address(this), uint256(amount0));
        }
        return "";
    }
}

/// @notice The full Sinjoh protocol stack driven end-to-end against the real
/// pools.trade deployment on Robinhood Chain mainnet: the real launcher,
/// strategies, splitter, vault, v4 singleton, and the real deployed Sinjoh
/// adapter factories, sell adapter, and subject guard — with a real
/// `SinjohFeeRouter` doing the accounting.
///
/// Requires network access. Run with:
///   forge test --match-path 'test/PoolsTradeMainnet.fork.t.sol'
contract PoolsTradeMainnetForkTest is TestBase {
    // pools.trade stack (POOLS-TRADE-FINDINGS.md).
    address constant POOL_MANAGER = 0x8366a39CC670B4001A1121B8F6A443A643e40951;
    address constant POSITION_MANAGER = 0x58daec3116aae6D93017bAAea7749052E8a04fA7;
    address constant FEE_SPLITTER = 0xeFF166AAf189323c58dc27eD1206EB2C37FaACDf;
    address constant BENEFICIARY_VAULT = 0xd35E9CA72F64C7F93BE30fad67524323396B36D7;
    address constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;

    // Live Sinjoh deployments (mainnet-deployments.json).
    address constant INSTANT_FACTORY = 0xCD82f610b3949cfc8a787C9AdeC70cA2Af71b635;
    address constant LBP_FACTORY = 0x6A4D50D9469fed073c4445Dc4050cd29d1BE25D7;
    address constant BUYBACK_ADAPTER = 0x3B479157D9c566c00F885BDFfFC22D33193714C2;
    address constant SELL_ADAPTER = 0x192f324A9BF64C4c9f46aFF77d1A3C8d06c635a5;
    address constant SUBJECT_GUARD = 0x4c75DB11b1Eb18251E84A98049918D534176b5a2;

    uint256 constant CHAIN_ID = 4663;
    bytes32 constant USER_SALT = keccak256("sinjoh-poolstrade-fork");
    uint256 constant SIGNER_KEY = 0xA11CE;

    string constant DEFAULT_RPC = "https://rpc.mainnet.chain.robinhood.com";

    address constant PROTOCOL_RECIPIENT = address(0x1001);
    address constant WALLET = address(0x2002);
    address constant TEAM_WALLET = address(0x7EA5);

    SinjohFeeRouterFactory routerFactory;
    SinjohPoolsTradeBuybackPriceGuard buybackGuard;
    V4TradeHelper trader;
    address signer;

    address creator = address(0xC4EA704);
    address keeper = address(0xBEEF);

    function setUp() public {
        vm.createSelectFork(vm.envOr("ROBINHOOD_RPC_URL", DEFAULT_RPC));
        vm.etch(address(100), address(new MockArbSys()).code);

        routerFactory = new SinjohFeeRouterFactory(address(new SinjohFeeRouter()));
        signer = vm.addr(SIGNER_KEY);
        buybackGuard =
            new SinjohPoolsTradeBuybackPriceGuard(WETH, WETH.codehash, signer);
        trader = new V4TradeHelper(POOL_MANAGER);

        vm.deal(creator, 1_000 ether);
        vm.deal(address(trader), 1_000 ether);
        vm.deal(keeper, 10 ether);
    }

    function _metadata() internal pure returns (PTTokenMetadata memory) {
        return PTTokenMetadata({
            description: "sinjoh fork acceptance",
            website: "https://sinjoh.example",
            image: "ipfs://image",
            extraData: ""
        });
    }

    function _personalDigest(bytes32 digest) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", digest));
    }

    // ------------------------------------------------------------------
    // Instant launch lifecycle
    // ------------------------------------------------------------------

    function _instantConfig(address launchpadAdapter)
        internal
        view
        returns (RouterTypes.Config memory config)
    {
        RouterTypes.Allocation[] memory walletAllocation = new RouterTypes.Allocation[](1);
        walletAllocation[0] = RouterTypes.Allocation({
            destination: WALLET,
            bps: 10_000,
            isSink: false,
            creatorMayRepoint: true,
            sinkConfig: ""
        });

        RouterTypes.Bucket[] memory buckets = new RouterTypes.Bucket[](2);
        // Identity WETH bucket straight to a wallet.
        buckets[0] = RouterTypes.Bucket({
            output: RouterTypes.AssetRef(RouterTypes.AssetKind.FIXED_ERC20, WETH),
            bps: 6_000,
            route: RouterTypes.Route(address(0), ""),
            priceGuard: address(0),
            maxAmountInPerCall: type(uint128).max,
            allocations: walletAllocation
        });
        // Buyback bucket: WETH into the subject through the live singleton
        // buyback adapter, floored by a keeper-signed minimum.
        buckets[1] = RouterTypes.Bucket({
            output: RouterTypes.AssetRef(RouterTypes.AssetKind.SUBJECT, address(0)),
            bps: 4_000,
            route: RouterTypes.Route(BUYBACK_ADAPTER, ""),
            priceGuard: address(buybackGuard),
            maxAmountInPerCall: type(uint128).max,
            allocations: walletAllocation
        });

        config = RouterTypes.Config({
            creator: creator,
            protocolFeeRecipient: PROTOCOL_RECIPIENT,
            weth: WETH,
            launchpadAdapter: launchpadAdapter,
            normalizations: new RouterTypes.Normalization[](0),
            buckets: buckets
        });
    }

    function test_instantLaunchLifecycle() public {
        SinjohPoolsTradeInstantAdapterFactory adapterFactory =
            SinjohPoolsTradeInstantAdapterFactory(INSTANT_FACTORY);
        address predictedAdapter = adapterFactory.predictAddress(creator, USER_SALT);
        address predictedRouter = routerFactory.predictLaunchpadAddress(creator, USER_SALT);

        vm.prank(creator);
        address routerAddress = routerFactory
            .deployForLaunchpad(creator, USER_SALT, _instantConfig(predictedAdapter));
        assertEq(routerAddress, predictedRouter);
        vm.prank(creator);
        address adapterAddress = adapterFactory.deploy(creator, routerAddress, USER_SALT);
        assertEq(adapterAddress, predictedAdapter);

        SinjohFeeRouter router = SinjohFeeRouter(payable(routerAddress));
        SinjohPoolsTradeInstantAdapter adapter =
            SinjohPoolsTradeInstantAdapter(payable(adapterAddress));

        // Launch on the real launcher with a real developer buy.
        vm.prank(creator);
        (address token, uint256 tokenId) = adapter.launch{ value: 0.5 ether }(
            "Sinjoh Fork Instant", "SJFI", _metadata(), USER_SALT, 0.5 ether, 1
        );

        assertEq(router.subject(), token);
        assertTrue(IERC20Fork(token).balanceOf(creator) > 0);
        assertTrue(adapter.feeRoutingIntact());

        // Real trades against the fresh pool accrue real LP fees.
        IPTPoolManager.PoolKey memory key = IPTPoolManager.PoolKey({
            currency0: address(0),
            currency1: token,
            fee: adapter.lpFee(),
            tickSpacing: adapter.poolTickSpacing(),
            hooks: address(0)
        });
        trader.buy{ value: 20 ether }(key, 20 ether);
        trader.sell(key, IERC20Fork(token).balanceOf(address(trader)) / 2);
        trader.buy{ value: 5 ether }(key, 5 ether);

        // Collect: splitter collection plus the vault claim, wrapped to WETH.
        vm.prank(keeper);
        uint256[] memory amounts = adapter.collect();
        assertEq(amounts.length, 1);
        assertTrue(amounts[0] > 0);

        vm.prank(keeper);
        uint256 forwarded = adapter.forward(WETH);
        assertEq(forwarded, amounts[0]);

        // Sync and the identity bucket.
        vm.prank(keeper);
        (uint256 gross, uint256 fee) = router.sync(WETH);
        assertEq(gross, forwarded);
        assertTrue(fee > 0);

        uint256 identityShare = router.bucketInputOwed(0, WETH);
        assertTrue(identityShare > 0);
        vm.prank(keeper);
        router.processBucket(0, WETH, identityShare, 0, "");

        // The buyback bucket converts WETH into the subject through the live
        // singleton adapter under a keeper-signed floor.
        uint256 buybackShare = router.bucketInputOwed(1, WETH);
        assertTrue(buybackShare > 0);
        bytes memory guardData = _signedFloor(routerAddress, token, buybackShare);
        uint256 subjectBefore = IERC20Fork(token).balanceOf(routerAddress);
        vm.prank(keeper);
        uint256 bought = router.processBucket(1, WETH, buybackShare, 0, guardData);
        assertTrue(bought > 0);
        assertEq(IERC20Fork(token).balanceOf(routerAddress) - subjectBefore, bought);

        // A follow-up collect keeps working — and finds the fees the buyback
        // swap itself just accrued on the locked position.
        vm.prank(keeper);
        amounts = adapter.collect();
        assertTrue(amounts[0] > 0);
    }

    function _signedFloor(address routerAddress, address token, uint256 amountIn)
        internal
        returns (bytes memory)
    {
        uint256 minimum = 1;
        uint48 validAfter = uint48(block.timestamp - 1);
        uint48 validUntil = uint48(block.timestamp + 4 minutes);
        bytes32 digest = buybackGuard.floorDigest(
            routerAddress,
            token,
            WETH,
            token,
            amountIn,
            keccak256(""),
            minimum,
            validAfter,
            validUntil
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_KEY, _personalDigest(digest));
        return abi.encode(minimum, validAfter, validUntil, abi.encodePacked(r, s, v));
    }

    // ------------------------------------------------------------------
    // LBP launch lifecycle
    // ------------------------------------------------------------------

    uint256 constant AUCTION_TICK = 1 << 66;
    /// @dev Roughly 1% of the launch pool's token depth: small enough that
    /// spot-quoted slippage stays inside the guard's haircut.
    uint128 constant SUBJECT_SYNC_CAP = 2_000_000e18;
    uint128 constant TOTAL_SUPPLY = 1_000_000_000e18;
    uint128 constant AUCTION_AMOUNT = 800_000_000e18;
    uint128 constant LP_RESERVE = 200_000_000e18;
    uint128 constant TEAM_SPLIT = 50_000_000e18;
    uint128 constant MERKLE_LEG = 150_000_000e18;

    function _lbpConfig(address launchpadAdapter)
        internal
        view
        returns (RouterTypes.Config memory config)
    {
        RouterTypes.Allocation[] memory walletAllocation = new RouterTypes.Allocation[](1);
        walletAllocation[0] = RouterTypes.Allocation({
            destination: WALLET,
            bps: 10_000,
            isSink: false,
            creatorMayRepoint: true,
            sinkConfig: ""
        });

        RouterTypes.Bucket[] memory buckets = new RouterTypes.Bucket[](1);
        buckets[0] = RouterTypes.Bucket({
            output: RouterTypes.AssetRef(RouterTypes.AssetKind.FIXED_ERC20, WETH),
            bps: 10_000,
            route: RouterTypes.Route(address(0), ""),
            priceGuard: address(0),
            maxAmountInPerCall: type(uint128).max,
            allocations: walletAllocation
        });

        // The subject is a real intake asset on the LBP shape; the live sell
        // adapter and subject guard normalize it. The per-call cap is load-
        // bearing, not hygiene: unsold auction tokens can dwarf pool depth,
        // and an unbounded sync would be refused by the guard for exactly the
        // price impact the haircut exists to prevent. The keeper syncs in
        // chunks instead.
        RouterTypes.Normalization[] memory normalizations = new RouterTypes.Normalization[](1);
        normalizations[0] = RouterTypes.Normalization({
            asset: RouterTypes.AssetRef(RouterTypes.AssetKind.SUBJECT, address(0)),
            route: RouterTypes.Route(SELL_ADAPTER, ""),
            priceGuard: SUBJECT_GUARD,
            maxAmountInPerCall: SUBJECT_SYNC_CAP
        });

        config = RouterTypes.Config({
            creator: creator,
            protocolFeeRecipient: PROTOCOL_RECIPIENT,
            weth: WETH,
            launchpadAdapter: launchpadAdapter,
            normalizations: normalizations,
            buckets: buckets
        });
    }

    function _lbpParams()
        internal
        view
        returns (SinjohPoolsTradeLBPAdapter.LBPLaunchParams memory params)
    {
        uint64 start = uint64(block.number + 5);
        uint64 end = start + 40;

        params.name = "Sinjoh Fork LBP";
        params.symbol = "SJFL";
        params.metadata = _metadata();
        params.totalSupply = TOTAL_SUPPLY;
        params.auctionAmount = AUCTION_AMOUNT;
        params.currency = address(0);
        params.startBlock = start;
        params.endBlock = end;
        params.claimBlock = end;
        params.auctionPriceTickSpacing = AUCTION_TICK;
        params.validationHook = address(0);
        params.floorPrice = AUCTION_TICK;
        params.requiredCurrencyRaised = 0.01 ether;
        // One linear step: 250_000 mps per block for 40 blocks sells the full
        // auction supply across the window.
        params.auctionStepsData =
            abi.encodePacked(bytes8(uint64((uint256(250_000) << 40) | 40)));
        params.migrationBlock = end + 3;
        params.reservedTokenAmountForLP = LP_RESERVE;
        params.poolFee = 3000;
        params.poolTickSpacing = 60;
        params.poolHook = address(0);
        params.positionDefinitions = new PTPositionDefinition[](1);
        params.positionDefinitions[0] = PTPositionDefinition({
            offsetLower: -887_272,
            offsetUpper: 887_272,
            weight: 10_000_000,
            overridePositionRecipient: address(0)
        });
        params.lpAllocationSchedule = new PTLiquidityAllocationBracket[](1);
        params.lpAllocationSchedule[0] =
            PTLiquidityAllocationBracket({ lowerThreshold: 0, rate: 2_500_000 });
        params.splits = new PTSplit[](1);
        params.splits[0] = PTSplit({ recipient: TEAM_WALLET, amount: TEAM_SPLIT });
        params.merkleLegs = new SinjohPoolsTradeLBPAdapter.MerkleLeg[](1);
        params.merkleLegs[0] = SinjohPoolsTradeLBPAdapter.MerkleLeg({
            amount: MERKLE_LEG,
            merkleRoot: keccak256("sinjoh-fork-airdrop"),
            owner: creator,
            endTime: 0
        });
        params.distributionSalt = USER_SALT;
    }

    function test_lbpLaunchLifecycle() public {
        SinjohPoolsTradeLBPAdapterFactory adapterFactory =
            SinjohPoolsTradeLBPAdapterFactory(LBP_FACTORY);
        address predictedAdapter = adapterFactory.predictAddress(creator, USER_SALT);

        vm.prank(creator);
        address routerAddress =
            routerFactory.deployForLaunchpad(creator, USER_SALT, _lbpConfig(predictedAdapter));
        vm.prank(creator);
        address adapterAddress = adapterFactory.deploy(creator, routerAddress, USER_SALT);
        assertEq(adapterAddress, predictedAdapter);

        SinjohFeeRouter router = SinjohFeeRouter(payable(routerAddress));
        SinjohPoolsTradeLBPAdapter adapter = SinjohPoolsTradeLBPAdapter(payable(adapterAddress));

        SinjohPoolsTradeLBPAdapter.LBPLaunchParams memory params = _lbpParams();
        vm.prank(creator);
        (address token, address auction) = adapter.launch(params);

        assertEq(router.subject(), token);
        assertEq(adapterFactory.adapterForSubject(token), address(adapter));
        // Supply conservation across the composition: auction supply, LP
        // reserve, team split, merkle leg.
        assertEq(
            IERC20Fork(token).balanceOf(auction), uint256(AUCTION_AMOUNT) - LP_RESERVE
        );
        assertEq(IERC20Fork(token).balanceOf(TEAM_WALLET), TEAM_SPLIT);
        // The merkle distributor holds its leg; everything else is accounted,
        // so the remainder proves the funding.
        assertEq(
            IERC20Fork(token).totalSupply()
                - IERC20Fork(token).balanceOf(auction)
                - IERC20Fork(token).balanceOf(0x05d552391067389EE44fec3924157ed33F976000)
                - IERC20Fork(token).balanceOf(TEAM_WALLET),
            MERKLE_LEG
        );

        // Bid through the real continuous clearing auction.
        vm.roll(params.startBlock + 1);
        vm.deal(address(this), 100 ether);
        ICCABid(auction).submitBid{ value: 2 ether }(AUCTION_TICK * 4, 2 ether, address(this), "");

        // Migrate at the committed block.
        vm.roll(params.migrationBlock);
        vm.prank(keeper);
        bool success = adapter.migrate();
        assertTrue(success);
        assertTrue(adapter.positionCount() > 0);
        assertTrue(address(adapter).balance > 0);

        // First collect: wraps the migration sweep, and sweeps unsold tokens
        // (the auction is over).
        vm.prank(keeper);
        uint256[] memory amounts = adapter.collect();
        uint256 unsold = amounts[0];
        uint256 raiseShare = amounts[1];
        assertTrue(raiseShare > 0);

        vm.prank(keeper);
        adapter.forward(WETH);
        vm.prank(keeper);
        (uint256 gross,) = router.sync(WETH);
        assertEq(gross, raiseShare);

        // Trade the migrated pool to accrue position fees, then collect them.
        (address c0, address c1, uint24 fee, int24 tickSpacing, address hooks) = adapter.poolKey();
        IPTPoolManager.PoolKey memory key = IPTPoolManager.PoolKey({
            currency0: c0,
            currency1: c1,
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: hooks
        });
        trader.buy{ value: 10 ether }(key, 10 ether);
        trader.sell(key, IERC20Fork(token).balanceOf(address(trader)) / 2);

        vm.prank(keeper);
        amounts = adapter.collect();
        assertTrue(amounts[0] > 0 || unsold > 0);

        // Forward the subject and normalize it through the live sell adapter
        // under the live subject guard — the seam the whole LBP shape needs.
        // Each sync is bounded by the config cap; the keeper loops.
        vm.prank(keeper);
        uint256 forwardedSubject = adapter.forward(token);
        assertTrue(forwardedSubject > SUBJECT_SYNC_CAP);
        uint256 spot = SinjohPoolsTradeSubjectPriceGuard(SUBJECT_GUARD)
            .spotQuote(token, SUBJECT_SYNC_CAP);
        vm.prank(keeper);
        (uint256 subjectGross,) = router.sync(token, spot * 80 / 100);
        assertEq(subjectGross, SUBJECT_SYNC_CAP);

        // A second chunk normalizes at the moved price.
        spot = SinjohPoolsTradeSubjectPriceGuard(SUBJECT_GUARD).spotQuote(token, SUBJECT_SYNC_CAP);
        vm.prank(keeper);
        (subjectGross,) = router.sync(token, spot * 80 / 100);
        assertEq(subjectGross, SUBJECT_SYNC_CAP);

        // The normalized WETH reached the bucket ledger.
        assertTrue(router.bucketInputOwed(0, WETH) > 0);
        assertTrue(adapter.feeRoutingIntact());
    }
}
