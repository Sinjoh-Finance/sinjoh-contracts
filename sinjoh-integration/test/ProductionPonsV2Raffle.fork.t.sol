// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IPonsV2LaunchFactory} from "router/src/interfaces/IPonsV2.sol";
import {PonsV2LaunchPrediction} from "router/src/libraries/PonsV2LaunchPrediction.sol";
import {RaffleTypes} from "raffle/src/RaffleTypes.sol";
import {SinjohRaffleRewards} from "raffle/src/SinjohRaffleRewards.sol";
import {RaffleTree} from "raffle/test/RaffleTree.sol";
import {MockArbSys} from "raffle/test/mocks/MockArbSys.sol";
import {MockRandomness} from "raffle/test/mocks/MockRandomness.sol";

interface Vm {
    function createSelectFork(string calldata urlOrAlias) external returns (uint256);
    function envOr(string calldata name, string calldata defaultValue) external returns (string memory);
    function etch(address target, bytes calldata code) external;
    function deal(address account, uint256 newBalance) external;
    function prank(address sender) external;
    function warp(uint256 newTimestamp) external;
}

// ---------------------------------------------------------------------------
// Deployed-contract surfaces, declared locally so this test exercises the LIVE
// bytecode on mainnet rather than any locally compiled source. The structs
// mirror the audited agnostic router's ABI.
// ---------------------------------------------------------------------------

struct AgnosticAssetRef {
    uint8 kind; // 0 NATIVE, 1 FIXED_ERC20, 2 SUBJECT
    address token;
}

struct AgnosticRoute {
    address adapter;
    bytes routeData;
}

struct AgnosticNormalization {
    AgnosticAssetRef asset;
    AgnosticRoute route;
    address priceGuard;
    uint128 maxAmountInPerCall;
}

struct AgnosticAllocation {
    address destination;
    uint16 bps;
    bool isSink;
    bool creatorMayRepoint;
    bytes sinkConfig;
}

struct AgnosticBucket {
    AgnosticAssetRef output;
    uint16 bps;
    AgnosticRoute route;
    address priceGuard;
    uint128 maxAmountInPerCall;
    AgnosticAllocation[] allocations;
}

struct AgnosticRouterConfig {
    address creator;
    address protocolFeeRecipient;
    address weth;
    address launchpadAdapter;
    AgnosticNormalization[] normalizations;
    AgnosticBucket[] buckets;
}

interface IAgnosticRouterFactory {
    function predictLaunchpadAddress(address creator, bytes32 userSalt) external view returns (address);
    function deployForLaunchpad(address creator, bytes32 userSalt, AgnosticRouterConfig calldata config)
        external
        returns (address router);
}

interface IAgnosticRouter {
    function sync(address asset) external returns (uint256 gross, uint256 fee);
    function processBucket(
        uint8 bucketId,
        address inputAsset,
        uint256 amountIn,
        uint256 callerMinOut,
        bytes calldata guardData
    ) external returns (uint256 amountOut);
    function fundSink(uint8 bucketId, uint8 allocationId, uint256 amount) external;
    function bucketInputOwed(uint8 bucketId, address asset) external view returns (uint256);
    function sinkOwed(uint16 key, address asset) external view returns (uint256);
    function allocationKey(uint8 bucketId, uint8 allocationId) external pure returns (uint16);
    function subject() external view returns (address);
    function launchpadAdapter() external view returns (address);
}

interface IPonsV2AdapterFactoryLive {
    function predictAddress(address creator, bytes32 userSalt) external view returns (address);
    function deploy(address creator, address router, bytes32 userSalt) external returns (address adapter);
}

interface IPonsV2AdapterLive {
    function launch(
        IPonsV2LaunchFactory.TokenParams calldata params,
        uint256 launchConfigId,
        address pairToken,
        uint256 developerBuy,
        uint256 minTokensOut,
        address[] calldata snipeTaxExemptions
    ) external payable returns (address token, address curve);
    function collect() external returns (uint256[] memory amounts);
    function forward(address asset) external returns (uint256 amount);
}

interface IPonsV2CurveProd {
    function buy(uint256 quoteIn, uint256 minTokensOut, address recipient) external payable returns (uint256 tokensOut);
    function snipeTaxSeconds() external view returns (uint256);
}

interface IWETHProd {
    function balanceOf(address account) external view returns (uint256);
}

interface IRaffleFactoryLive {
    function deployRaffle(bytes32 userSalt, RaffleTypes.Config calldata config) external returns (address raffle);
    function predictRaffle(address creator, bytes32 userSalt, bytes32 configHash) external view returns (address raffle);
    function hashConfig(RaffleTypes.Config calldata config) external pure returns (bytes32);
}

interface IERC20Prod {
    function balanceOf(address account) external view returns (uint256);
}

/// @notice The production raffle launch, end to end, against the contracts that
/// are actually deployed on Robinhood Chain mainnet: the agnostic fee-router
/// factory, the live raffle factory, the Pons v2 adapter factory, and the live
/// Pons v2 launchpad. No Sinjoh contract is compiled locally: the raffle comes
/// from the deployed factory's clone of the deployed implementation, so what
/// this exercises is the runtime a real launch gets.
///
/// @dev This is the flow an integrating UI performs, in this exact order:
///
///   1. predict the adapter        (adapterFactory.predictAddress)
///   2. predict the router         (routerFactory.predictLaunchpadAddress)
///   3. predict token + curve      (PonsV2LaunchPrediction, deployer = adapter)
///   4. deploy the raffle          (exclusions built around the predicted curve)
///   5. deploy the router          (launchpadAdapter = adapter, sink = raffle)
///   6. deploy the adapter         (factory wires it to the router)
///   7. launch through the adapter (predictions must all hold; adapter binds router)
///   8. bind the raffle            (raffle creator, once)
///   9. trade -> collect -> forward -> sync -> process -> fundSink
///  10. commit, draw, claim: a real holder is paid from real launch revenue.
///
/// Set `RH_RPC_URL` to run.
contract ProductionPonsV2RaffleForkTest {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    // Deployed Sinjoh infrastructure (mainnet-deployments.json).
    address internal constant AGNOSTIC_ROUTER_FACTORY = 0xA1F721a697Dd03a45f264F53bCBFd121212318eD;
    address internal constant PONS_V2_ADAPTER_FACTORY = 0xdb02cC8bbEb1F4B0A98f974a8768c08370d1a821;
    address internal constant RAFFLE_FACTORY = 0xD030064fB83d14C97c22A6B63bF376552eBA7112;
    // Live Pons v2 + chain constants.
    address internal constant PONS_V2_FACTORY = 0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e;
    address internal constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;
    address internal constant ARBSYS = address(0x64);

    address internal constant PROTOCOL_RECIPIENT = address(0xFEE1);
    address internal constant TRADER = address(0x7ade);

    error AssertionFailed(string reason);

    bool internal forked;
    MockRandomness internal randomness;
    MockArbSys internal arbSys;

    function setUp() public {
        string memory url = vm.envOr("RH_RPC_URL", string(""));
        if (bytes(url).length == 0) return;
        vm.createSelectFork(url);
        forked = true;
        randomness = new MockRandomness();
        MockArbSys implementation = new MockArbSys();
        vm.etch(ARBSYS, address(implementation).code);
        arbSys = MockArbSys(ARBSYS);
    }

    function testForkProductionLaunchFundsAndSettlesARaffle() public {
        if (!forked) return;
        IPonsV2LaunchFactory pons = IPonsV2LaunchFactory(PONS_V2_FACTORY);

        // 1-2. Both clone addresses ignore their configuration.
        address predictedAdapter =
            IPonsV2AdapterFactoryLive(PONS_V2_ADAPTER_FACTORY).predictAddress(address(this), bytes32("PROD_ADAPTER"));
        address predictedRouter = IAgnosticRouterFactory(AGNOSTIC_ROUTER_FACTORY)
            .predictLaunchpadAddress(address(this), bytes32("PROD_ROUTER"));

        // 3. The launch, initiated by the yet-undeployed adapter.
        IPonsV2LaunchFactory.TokenParams memory params = IPonsV2LaunchFactory.TokenParams({
            name: "Sinjoh Production Rehearsal",
            symbol: "PROD",
            logo: "",
            description: "",
            socials: IPonsV2LaunchFactory.Socials({twitter: "", telegram: "", discord: "", website: "", farcaster: ""}),
            creatorFeeRecipient: predictedAdapter,
            creatorTaxBps: 250,
            buybackEnabled: false,
            expectedEconomics: pons.previewLaunchEconomics(0, address(0)),
            salt: bytes32("SINJOH_PROD_REHEARSAL")
        });
        (address predictedToken, address predictedCurve) =
            PonsV2LaunchPrediction.predict(PONS_V2_FACTORY, params, 0, address(0), predictedAdapter);

        // 4. The raffle is configured around addresses that do not exist yet,
        //    and deploys from the LIVE factory at its predicted address.
        RaffleTypes.Config memory config = _raffleConfig(_exclusions(pons, predictedCurve, predictedAdapter));
        address predictedRaffle = IRaffleFactoryLive(RAFFLE_FACTORY)
            .predictRaffle(address(this), bytes32("PROD_RAFFLE"), IRaffleFactoryLive(RAFFLE_FACTORY).hashConfig(config));
        SinjohRaffleRewards raffle = SinjohRaffleRewards(
            payable(IRaffleFactoryLive(RAFFLE_FACTORY).deployRaffle(bytes32("PROD_RAFFLE"), config))
        );
        _require(address(raffle) == predictedRaffle, "raffle prediction failed");
        _require(raffle.isExcluded(predictedCurve), "predicted curve not excluded");

        // 5-6. Router names the adapter and the raffle sink; adapter wires to
        // the router. Both land on their predictions.
        address router = IAgnosticRouterFactory(AGNOSTIC_ROUTER_FACTORY)
            .deployForLaunchpad(address(this), bytes32("PROD_ROUTER"), _routerConfig(predictedAdapter, address(raffle)));
        _require(router == predictedRouter, "router prediction failed");
        address adapter =
            IPonsV2AdapterFactoryLive(PONS_V2_ADAPTER_FACTORY).deploy(address(this), router, bytes32("PROD_ADAPTER"));
        _require(adapter == predictedAdapter, "adapter prediction failed");

        // 7. Launch through the deployed adapter implementation.
        vm.deal(address(this), 1 ether);
        (address subject, address curve) =
            IPonsV2AdapterLive(adapter).launch{value: pons.launchFee()}(params, 0, address(0), 0, 0, new address[](0));
        _require(subject == predictedToken, "token prediction failed");
        _require(curve == predictedCurve, "curve prediction failed");
        _require(IAgnosticRouter(router).subject() == subject, "adapter did not bind router");
        _require(raffle.isExcluded(curve), "curve not excluded");

        // 8. The raffle binds to the launched token.
        raffle.bind(subject);

        // 9. Real revenue: a taxed trade, then the permissionless pipeline.
        vm.warp(block.timestamp + IPonsV2CurveProd(curve).snipeTaxSeconds() + 1);
        vm.deal(TRADER, 2 ether);
        vm.prank(TRADER);
        uint256 tokensOut = IPonsV2CurveProd(curve).buy{value: 1 ether}(1 ether, 1, TRADER);
        _require(tokensOut != 0, "buy produced no tokens");

        IPonsV2AdapterLive(adapter).collect();
        uint256 forwarded = IPonsV2AdapterLive(adapter).forward(WETH);
        _require(forwarded != 0, "adapter forwarded nothing");
        IAgnosticRouter(router).sync(WETH);
        uint256 owed = IAgnosticRouter(router).bucketInputOwed(0, WETH);
        _require(owed != 0, "sync produced no bucket input");
        IAgnosticRouter(router).processBucket(0, WETH, owed, 0, "");
        uint16 key = IAgnosticRouter(router).allocationKey(0, 0);
        uint256 sinkPending = IAgnosticRouter(router).sinkOwed(key, WETH);
        _require(sinkPending != 0, "no sink liability");
        IAgnosticRouter(router).fundSink(0, 0, sinkPending);
        _require(raffle.availablePool() != 0, "raffle pool not funded");

        // 10. A committed round pays a real holder from that revenue.
        uint256 tickets = raffle.ticketsFor(IERC20Prod(subject).balanceOf(TRADER));
        _require(tickets != 0, "trader holds no tickets");
        RaffleTypes.Leaf[] memory leaves = new RaffleTypes.Leaf[](1);
        leaves[0] = RaffleTypes.Leaf({holder: TRADER, tickets: tickets});

        uint64 snapshotBlock = uint64(block.number - 4);
        bytes32 snapshotHash = keccak256(abi.encode("PROD_SNAPSHOT", snapshotBlock));
        arbSys.setBlockNumber(block.number);
        arbSys.setBlockHash(snapshotBlock, snapshotHash);
        (bytes32 root, uint256 totalTickets, RaffleTypes.ProofElement[][] memory proofs) = RaffleTree.build(
            RaffleTree.Params({
                raffle: address(raffle), chainId: block.chainid, roundId: 1, snapshotBlock: snapshotBlock
            }),
            leaves
        );
        raffle.commitRound(1, snapshotBlock, snapshotHash, root, totalTickets);
        (, bytes32 requestId,,,,,,,,,) = raffle.rounds(1);
        randomness.deliver(requestId, uint256(blockhash(block.number - 1)));

        uint256 before = IWETHProd(WETH).balanceOf(TRADER);
        uint256 paid = raffle.claim(1, 0, leaves[0], proofs[0]);
        _require(paid != 0, "winner paid nothing");
        _require(IWETHProd(WETH).balanceOf(TRADER) - before == paid, "payout delta mismatch");
        _require(IWETHProd(WETH).balanceOf(address(raffle)) >= raffle.liabilities(), "raffle insolvent");
    }

    /// @dev The adapter is included as a recommended exclusion: it never holds
    /// the subject in normal operation, but a donated balance would otherwise
    /// make a fee contract a raffle entrant.
    function _exclusions(IPonsV2LaunchFactory pons, address predictedCurve, address adapter)
        private
        view
        returns (address[] memory sorted)
    {
        address[] memory raw = new address[](6);
        raw[0] = predictedCurve;
        raw[1] = PONS_V2_FACTORY;
        raw[2] = pons.poolManager();
        raw[3] = pons.buybackVault();
        raw[4] = pons.memeHook();
        raw[5] = adapter;
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

    function _raffleConfig(address[] memory exclusions) private view returns (RaffleTypes.Config memory config) {
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
            prizeBps: 10_000,
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

    function _routerConfig(address adapter, address raffleSink)
        private
        view
        returns (AgnosticRouterConfig memory config)
    {
        AgnosticAllocation[] memory allocations = new AgnosticAllocation[](1);
        allocations[0] = AgnosticAllocation({
            destination: raffleSink, bps: 10_000, isSink: true, creatorMayRepoint: false, sinkConfig: ""
        });
        AgnosticBucket[] memory buckets = new AgnosticBucket[](1);
        buckets[0] = AgnosticBucket({
            output: AgnosticAssetRef(1, WETH),
            bps: 10_000,
            route: AgnosticRoute(address(0), ""),
            priceGuard: address(0),
            maxAmountInPerCall: type(uint128).max,
            allocations: allocations
        });
        config = AgnosticRouterConfig({
            creator: address(this),
            protocolFeeRecipient: PROTOCOL_RECIPIENT,
            weth: WETH,
            launchpadAdapter: adapter,
            normalizations: new AgnosticNormalization[](0),
            buckets: buckets
        });
    }

    function _require(bool condition, string memory reason) private pure {
        if (!condition) revert AssertionFailed(reason);
    }
}
