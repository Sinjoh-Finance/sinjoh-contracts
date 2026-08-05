// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { RouterTypes } from "router/src/RouterTypes.sol";
import { SinjohFeeRouter } from "router/src/SinjohFeeRouter.sol";
import { SinjohFeeRouterFactory } from "router/src/SinjohFeeRouterFactory.sol";
import { IPonsV2LaunchFactory } from "router/src/interfaces/IPonsV2.sol";
import { PonsV2LaunchPrediction } from "router/src/libraries/PonsV2LaunchPrediction.sol";
import { RaffleTypes } from "raffle/src/RaffleTypes.sol";
import { SinjohRaffleRewards } from "raffle/src/SinjohRaffleRewards.sol";
import { SinjohRaffleRewardsFactory } from "raffle/src/SinjohRaffleRewardsFactory.sol";
import { RaffleTree } from "raffle/test/RaffleTree.sol";
import { MockArbSys } from "raffle/test/mocks/MockArbSys.sol";
import { MockRandomness } from "raffle/test/mocks/MockRandomness.sol";

interface Vm {
    function createSelectFork(string calldata urlOrAlias) external returns (uint256);
    function envOr(string calldata name, string calldata defaultValue)
        external
        returns (string memory);
    function etch(address target, bytes calldata code) external;
    function deal(address account, uint256 newBalance) external;
    function prank(address sender) external;
    function warp(uint256 newTimestamp) external;
}

interface IWETHLifecycle {
    function balanceOf(address account) external view returns (uint256);
}

interface IPonsV2CurveLifecycle {
    function buy(uint256 quoteIn, uint256 minTokensOut, address recipient)
        external
        payable
        returns (uint256 tokensOut);
    function snipeTaxSeconds() external view returns (uint256);
}

interface IERC20Lifecycle {
    function balanceOf(address account) external view returns (uint256);
}

/// @notice The complete Pons v2 raffle lifecycle against real mainnet state, in
/// the exact order a production launch flow must perform it:
///
///   1. predict the router address (config-independent);
///   2. predict the launch's token and curve from that;
///   3. build the raffle configuration around the predicted curve;
///   4. deploy the raffle, then the router naming the raffle as its sink;
///   5. launch through the real Pons factory and check every prediction;
///   6. bind, trade, sweep, claim, sync, process, fund;
///   7. commit a round excluding the curve, draw, and pay a real holder.
///
/// @dev Steps 1-4 are the ordering this rehearsal exists to prove: three
/// mutually referential addresses (router -> curve -> raffle -> router) resolve
/// because the router's address ignores its configuration and the curve is
/// CREATE2-derived. The raffle-as-sink call in step 6 is the last copied
/// interface boundary that had only ever met a mock.
///
/// The revenue path here is the router-direct one from this branch; the
/// deployed `SinjohPonsV2Adapter` replaces the launch/sweep/claim leg with an
/// adapter-owned equivalent and forwards to the same router `sync`, so steps 6b
/// onward — and everything raffle-side — are identical under both.
/// Set `RH_RPC_URL` to run.
contract PonsV2RaffleLifecycleForkTest {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    address internal constant PONS_V2_FACTORY = 0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e;
    address internal constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;
    address internal constant SWAP_ADAPTER = 0xc9F600ebaf9EE1F4a24568D2e4Af9E8df1e07D7B;
    address internal constant ARBSYS = address(0x64);

    address internal constant PROTOCOL_RECIPIENT = address(0xFEE1);
    address internal constant TRADER = address(0x7ade);
    uint64 internal constant SNAPSHOT_OFFSET = 4;

    error AssertionFailed(string reason);

    bool internal forked;
    SinjohRaffleRewardsFactory internal raffleFactory;
    SinjohFeeRouterFactory internal routerFactory;
    MockRandomness internal randomness;
    MockArbSys internal arbSys;

    function setUp() public {
        string memory url = vm.envOr("RH_RPC_URL", string(""));
        if (bytes(url).length == 0) return;
        vm.createSelectFork(url);
        forked = true;

        raffleFactory = new SinjohRaffleRewardsFactory(block.chainid);
        routerFactory = new SinjohFeeRouterFactory(address(new SinjohFeeRouter()));
        randomness = new MockRandomness();
        MockArbSys implementation = new MockArbSys();
        vm.etch(ARBSYS, address(implementation).code);
        arbSys = MockArbSys(ARBSYS);
    }

    function testForkFullPonsV2RaffleLifecycle() public {
        if (!forked) return;
        IPonsV2LaunchFactory pons = IPonsV2LaunchFactory(PONS_V2_FACTORY);

        // 1. The router's clone address depends only on (creator, salt), never
        //    on its configuration — the property that breaks the address cycle.
        address predictedRouter =
            routerFactory.predictPonsAddress(address(this), bytes32("LIFECYCLE"));

        // 2. Predict the launch, initiated by the yet-undeployed router.
        IPonsV2LaunchFactory.TokenParams memory params = IPonsV2LaunchFactory.TokenParams({
            name: "Sinjoh Lifecycle",
            symbol: "LIFE",
            logo: "",
            description: "",
            socials: IPonsV2LaunchFactory.Socials({
                twitter: "", telegram: "", discord: "", website: "", farcaster: ""
            }),
            creatorFeeRecipient: predictedRouter,
            creatorTaxBps: 250,
            buybackEnabled: false,
            expectedEconomics: pons.previewLaunchEconomics(0, address(0)),
            salt: bytes32("SINJOH_LIFECYCLE")
        });
        (address predictedToken, address predictedCurve) =
            PonsV2LaunchPrediction.predict(PONS_V2_FACTORY, params, 0, address(0), predictedRouter);

        // 3. The raffle configuration is built around the predicted curve.
        SinjohRaffleRewards raffle = SinjohRaffleRewards(
            payable(
                raffleFactory.deployRaffle(
                    bytes32("LIFECYCLE_RAFFLE"), _raffleConfig(_exclusions(pons, predictedCurve))
                )
            )
        );
        _require(raffle.isExcluded(predictedCurve), "curve not excluded");

        // 4. The router deploys at the predicted address and names the raffle
        //    as its sink.
        SinjohFeeRouter router = SinjohFeeRouter(
            payable(
                routerFactory.deployPons(
                    address(this), bytes32("LIFECYCLE"), _routerConfig(address(raffle))
                )
            )
        );
        _require(address(router) == predictedRouter, "router address prediction failed");

        // 5. Launch through the real factory; every prediction must hold.
        vm.deal(address(this), 1 ether);
        (address subject, address curve) = router.launchPonsV2Token{ value: pons.launchFee() }(
            PONS_V2_FACTORY, params, 0, address(0), new address[](0)
        );
        _require(subject == predictedToken, "token prediction failed");
        _require(curve == predictedCurve, "curve prediction failed");

        // 6. Bind, trade past the snipe window, and drive the revenue home.
        raffle.bind(subject);
        vm.warp(block.timestamp + IPonsV2CurveLifecycle(curve).snipeTaxSeconds() + 1);
        vm.deal(TRADER, 2 ether);
        vm.prank(TRADER);
        uint256 tokensOut = IPonsV2CurveLifecycle(curve).buy{ value: 1 ether }(1 ether, 1, TRADER);
        _require(tokensOut != 0, "buy produced no tokens");

        router.sweepPonsV2CurveFees();
        uint256 claimed = router.claimPonsV2Fees();
        _require(claimed != 0, "no revenue claimed");
        router.sync(WETH);
        uint256 owed = router.bucketInputOwed(0, WETH);
        _require(owed != 0, "sync produced no bucket input");
        router.processBucket(0, WETH, owed, 0, "");
        uint256 sinkOwed = router.sinkOwed(SinjohFeeRouter(payable(router)).allocationKey(0, 0), WETH);
        _require(sinkOwed != 0, "no sink liability");

        // The raffle-as-sink boundary, against the real raffle.
        router.fundSink(0, 0, sinkOwed);
        uint256 pool = raffle.availablePool();
        _require(pool != 0, "raffle pool not funded");

        // 7. Snapshot the real holder set — the trader; the curve is excluded —
        //    commit, draw, and pay.
        uint256 tickets = raffle.ticketsFor(IERC20Lifecycle(subject).balanceOf(TRADER));
        _require(tickets != 0, "trader holds no tickets");
        RaffleTypes.Leaf[] memory leaves = new RaffleTypes.Leaf[](1);
        leaves[0] = RaffleTypes.Leaf({ holder: TRADER, tickets: tickets });

        uint64 snapshotBlock = uint64(block.number - SNAPSHOT_OFFSET);
        bytes32 snapshotHash = keccak256(abi.encode("LIFECYCLE_SNAPSHOT", snapshotBlock));
        arbSys.setBlockNumber(block.number);
        arbSys.setBlockHash(snapshotBlock, snapshotHash);

        (bytes32 root, uint256 totalTickets, RaffleTypes.ProofElement[][] memory proofs) =
        RaffleTree.build(
            RaffleTree.Params({
                raffle: address(raffle),
                chainId: block.chainid,
                roundId: 1,
                snapshotBlock: snapshotBlock
            }),
            leaves
        );
        uint256 prize = raffle.commitRound(1, snapshotBlock, snapshotHash, root, totalTickets);
        _require(prize != 0, "no prize reserved");

        (, bytes32 requestId,,,,,,,,,) = raffle.rounds(1);
        randomness.deliver(requestId, uint256(blockhash(block.number - 1)));

        uint256 traderBefore = IWETHLifecycle(WETH).balanceOf(TRADER);
        uint256 paid = raffle.claim(1, 0, leaves[0], proofs[0]);
        _require(paid != 0, "winner paid nothing");
        _require(
            IWETHLifecycle(WETH).balanceOf(TRADER) - traderBefore == paid, "payout delta mismatch"
        );
        _require(
            IWETHLifecycle(WETH).balanceOf(address(raffle)) >= raffle.liabilities(),
            "raffle insolvent"
        );
    }

    function _exclusions(IPonsV2LaunchFactory pons, address predictedCurve)
        private
        view
        returns (address[] memory sorted)
    {
        address[] memory raw = new address[](5);
        raw[0] = predictedCurve;
        raw[1] = PONS_V2_FACTORY;
        raw[2] = pons.poolManager();
        raw[3] = pons.buybackVault();
        raw[4] = pons.memeHook();
        // Insertion sort: the raffle requires strictly ascending, unique.
        sorted = raw;
        for (uint256 i = 1; i < sorted.length; ++i) {
            address value = sorted[i];
            uint256 j = i;
            while (j > 0 && sorted[j - 1] > value) {
                sorted[j] = sorted[j - 1];
                --j;
            }
            sorted[j] = value;
        }
    }

    function _raffleConfig(address[] memory exclusions)
        private
        view
        returns (RaffleTypes.Config memory config)
    {
        config = RaffleTypes.Config({
            creator: address(this),
            attestor: address(this),
            randomness: address(randomness),
            prizeAsset: WETH,
            protocolFeeRecipient: PROTOCOL_RECIPIENT,
            taxRecipient: address(this),
            tokensPerTicket: 10_000e18,
            maxTicketsPerHolder: 50,
            minPrize: 1,
            maxPrize: 0,
            prizeBps: 500,
            recipientTaxBps: 700,
            recycleTaxBps: 300,
            minConfirmations: 1,
            winnersPerRound: 1,
            minRoundInterval: 600,
            weightWindowBlocks: 900,
            randomnessTimeout: 7_200,
            claimWindow: 604_800,
            basis: RaffleTypes.TicketBasis.MIN_BALANCE,
            exclusions: exclusions,
            stockRewards: new RaffleTypes.StockReward[](0)
        });
    }

    function _routerConfig(address raffleSink)
        private
        view
        returns (RouterTypes.Config memory config)
    {
        RouterTypes.Allocation[] memory allocations = new RouterTypes.Allocation[](1);
        allocations[0] = RouterTypes.Allocation({
            destination: raffleSink,
            bps: 10_000,
            isSink: true,
            creatorMayRepoint: false,
            sinkConfig: ""
        });
        RouterTypes.Bucket[] memory buckets = new RouterTypes.Bucket[](1);
        buckets[0] = RouterTypes.Bucket({
            output: RouterTypes.AssetRef(RouterTypes.AssetKind.FIXED_ERC20, WETH),
            bps: 10_000,
            route: RouterTypes.Route(address(0), ""),
            allocations: allocations
        });
        config = RouterTypes.Config({
            creator: address(this),
            protocolFeeRecipient: PROTOCOL_RECIPIENT,
            weth: WETH,
            subjectToWeth: RouterTypes.Route(SWAP_ADAPTER, abi.encode(uint24(10_000))),
            buckets: buckets
        });
    }

    function _require(bool condition, string memory reason) private pure {
        if (!condition) revert AssertionFailed(reason);
    }
}
