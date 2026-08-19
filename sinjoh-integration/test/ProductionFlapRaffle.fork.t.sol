// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

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
// bytecode on mainnet — including the real SinjohRaffleRewardsFactory, which
// the Pons v2 rehearsal predates. Enums are declared as uint8, which is their
// canonical ABI type, so every selector matches the deployed contracts.
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
}

/// @dev Mirrors IFlapPortalTypes.NewTokenV6Params with enums as their
/// canonical uint8 ABI type. Field order is load-bearing.
struct FlapNewTokenV6Params {
    string name;
    string symbol;
    string meta;
    uint8 dexThresh; // 1 = FOUR_FIFTHS
    bytes32 salt;
    uint8 migratorType; // 1 = V2_MIGRATOR
    address quoteToken;
    uint256 quoteAmt;
    address beneficiary;
    bytes permitData;
    bytes32 extensionID;
    bytes extensionData;
    uint8 dexId; // 0 = DEX0
    uint8 lpFeeProfile; // 0 = STANDARD
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
    uint8 tokenVersion; // 6 = TOKEN_TAXED_V3
}

interface IFlapAdapterFactoryLive {
    function predictAddress(address creator, bytes32 userSalt) external view returns (address);
    function deploy(address creator, address router, bytes32 userSalt) external returns (address adapter);
}

interface IFlapAdapterLive {
    function launch(
        FlapNewTokenV6Params calldata params,
        bytes32 expectedPortalConfigHash,
        uint16 expectedFlapFeeRate,
        uint256 minDeveloperBuyOut
    ) external payable returns (address token);
    function portalConfigHash() external view returns (bytes32);
    function predictSubject(bytes32 salt) external view returns (address);
    function collect() external returns (uint256[] memory amounts);
    function forward(address asset) external returns (uint256 amount);
}

interface IFlapPortalTrade {
    struct ExactInputParams {
        address inputToken;
        address outputToken;
        uint256 inputAmount;
        uint256 minOutputAmount;
        bytes permitData;
    }

    function swapExactInput(ExactInputParams calldata params) external payable returns (uint256 outputAmount);
}

interface IRaffleFactoryLive {
    function deployRaffle(bytes32 userSalt, RaffleTypes.Config calldata config) external returns (address raffle);
    function predictRaffle(address creator, bytes32 userSalt, bytes32 configHash) external view returns (address raffle);
    function hashConfig(RaffleTypes.Config calldata config) external pure returns (bytes32);
}

interface IERC20Fork {
    function balanceOf(address account) external view returns (uint256);
}

/// @notice The production FLAP raffle launch, end to end, against the
/// contracts actually deployed on Robinhood Chain mainnet — including the
/// live SinjohRaffleRewardsFactory (0xD030064f…), so this rehearsal also
/// proves the deployed factory's clones behave exactly like the audited
/// source the Pons v2 rehearsal compiled locally.
///
/// @dev This is the flow the UI performs for a Flap launch with a raffle:
///
///   1. predict the adapter        (flapAdapterFactory.predictAddress)
///   2. predict the router         (routerFactory.predictLaunchpadAddress)
///   3. predict the token          (CREATE2 from the mined vanity salt)
///   4. deploy the raffle          (LIVE factory; exclusions = Portal, the
///                                  predicted Flap V2 pair, the V2 liquidity
///                                  manager, the buyback adapter, the adapter
///                                  factory, and the adapter — the list
///                                  raffleExclusionsForFlapLaunch builds)
///   5. deploy the router          (launchpadAdapter = adapter, sink = raffle)
///   6. deploy the adapter         (factory wires it to the router)
///   7. launch through the adapter (binds the router atomically)
///   8. bind the raffle            (raffle creator, once)
///   9. trade -> collect -> forward -> sync -> process -> fundSink
///  10. commit, draw, claim: a real holder is paid from real launch revenue.
///
/// Set `RH_RPC_URL` to run.
contract ProductionFlapRaffleForkTest {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    // Deployed Sinjoh infrastructure (mainnet-deployments.json).
    address internal constant AGNOSTIC_ROUTER_FACTORY = 0xA1F721a697Dd03a45f264F53bCBFd121212318eD;
    address internal constant FLAP_ADAPTER_FACTORY = 0x77748D07CAD323A7f6EFa54968aCF69de743be61;
    address internal constant FLAP_BUYBACK_ADAPTER = 0xf7d40EcD8cB38a43e898775bc382DB73B35B5574;
    address internal constant FLAP_V2_LIQUIDITY_MANAGER = 0x4E330772F12955E752aa4Fd2ba6191d8bD7d782E;
    address internal constant RAFFLE_FACTORY = 0xD030064fB83d14C97c22A6B63bF376552eBA7112;
    // Live Flap + chain constants.
    address internal constant PORTAL = 0x26605f322f7fF986f381bB9A6e3f5DAb0bEaEb09;
    address internal constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;
    address internal constant V2_FACTORY = 0x8bcEaA40B9AcdfAedF85AdF4FF01F5Ad6517937f;
    bytes32 internal constant V2_PAIR_INIT_CODE_HASH =
        0x96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f;
    bytes32 internal constant REVIEWED_PORTAL_CONFIG_HASH =
        0xb789978b5db7d4d20b60a96ac19d9b9f4a667f2182a2d833a3dfb02459fbb713;
    uint16 internal constant FLAP_FEE_RATE = 300;
    address internal constant ARBSYS = address(0x64);

    // A vanity salt already mined against the live Portal's CREATE2 domain
    // (sinjoh-launchpad-adapters' mainnet fork test); the resulting token
    // address is still unoccupied on mainnet.
    bytes32 internal constant TOKEN_SALT = 0x3b26f5b3439bcb21fcc5112fc947d6d66a9d4bff284314d6d39e99b121f22ab5;
    address internal constant PREDICTED_TOKEN = 0xB16B82bF5F5AA6E6cABC57402DA37E9308997777;

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

    function testForkProductionFlapLaunchFundsAndSettlesARaffle() public {
        if (!forked) return;
        _require(PREDICTED_TOKEN.code.length == 0, "vanity token address already occupied");

        // 1-3. Every address the raffle's immutable exclusions need exists
        // before anything deploys.
        address predictedAdapter =
            IFlapAdapterFactoryLive(FLAP_ADAPTER_FACTORY).predictAddress(address(this), bytes32("PROD_FLAP_ADAPTER"));
        address predictedRouter = IAgnosticRouterFactory(AGNOSTIC_ROUTER_FACTORY)
            .predictLaunchpadAddress(address(this), bytes32("PROD_FLAP_ROUTER"));
        address predictedPair = _predictFlapV2Pair(PREDICTED_TOKEN);

        // 4. The raffle deploys from the LIVE factory around addresses that do
        // not exist yet.
        RaffleTypes.Config memory config = _raffleConfig(_exclusions(predictedPair, predictedAdapter));
        address predictedRaffle = IRaffleFactoryLive(RAFFLE_FACTORY)
            .predictRaffle(
                address(this), bytes32("PROD_FLAP_RAFFLE"), IRaffleFactoryLive(RAFFLE_FACTORY).hashConfig(config)
            );
        SinjohRaffleRewards raffle = SinjohRaffleRewards(
            payable(IRaffleFactoryLive(RAFFLE_FACTORY).deployRaffle(bytes32("PROD_FLAP_RAFFLE"), config))
        );
        _require(address(raffle) == predictedRaffle, "raffle prediction failed");
        _require(raffle.isExcluded(PORTAL), "portal not excluded");
        _require(raffle.isExcluded(predictedPair), "predicted V2 pair not excluded");

        // 5-6. Router names the adapter and the raffle sink; adapter wires to
        // the router.
        address router = IAgnosticRouterFactory(AGNOSTIC_ROUTER_FACTORY)
            .deployForLaunchpad(
                address(this), bytes32("PROD_FLAP_ROUTER"), _routerConfig(predictedAdapter, address(raffle))
            );
        _require(router == predictedRouter, "router prediction failed");
        address adapter =
            IFlapAdapterFactoryLive(FLAP_ADAPTER_FACTORY).deploy(address(this), router, bytes32("PROD_FLAP_ADAPTER"));
        _require(adapter == predictedAdapter, "adapter prediction failed");
        _require(IFlapAdapterLive(adapter).predictSubject(TOKEN_SALT) == PREDICTED_TOKEN, "token prediction failed");

        // 7. Launch through the deployed adapter; it binds the router
        // atomically.
        bytes32 portalConfig = IFlapAdapterLive(adapter).portalConfigHash();
        _require(portalConfig == REVIEWED_PORTAL_CONFIG_HASH, "portal config drifted");
        address subject = IFlapAdapterLive(adapter).launch(_params(adapter), portalConfig, FLAP_FEE_RATE, 0);
        _require(subject == PREDICTED_TOKEN, "launched token mismatch");
        _require(IAgnosticRouter(router).subject() == subject, "adapter did not bind router");

        // 8. The raffle binds to the launched token.
        raffle.bind(subject);

        // 9. Real revenue: taxed trades through the live Portal, then the
        // permissionless pipeline into the raffle sink.
        vm.deal(TRADER, 3 ether);
        vm.prank(TRADER);
        uint256 tokensOut = IFlapPortalTrade(PORTAL).swapExactInput{value: 1 ether}(
            IFlapPortalTrade.ExactInputParams({
                inputToken: address(0), outputToken: subject, inputAmount: 1 ether, minOutputAmount: 1, permitData: ""
            })
        );
        _require(tokensOut != 0, "buy produced no tokens");

        uint256[] memory collected = IFlapAdapterLive(adapter).collect();
        _require(collected[0] != 0, "adapter collected nothing");
        uint256 forwarded = IFlapAdapterLive(adapter).forward(WETH);
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

        // 10. A committed round pays a real holder from that revenue. The
        // launchpad-held supply (Portal) is excluded, so the trader's tickets
        // are the whole tree.
        uint256 tickets = raffle.ticketsFor(IERC20Fork(subject).balanceOf(TRADER));
        _require(tickets != 0, "trader holds no tickets");
        _require(
            raffle.ticketsFor(IERC20Fork(subject).balanceOf(PORTAL)) == 0 || raffle.isExcluded(PORTAL),
            "launchpad could enter the raffle"
        );
        RaffleTypes.Leaf[] memory leaves = new RaffleTypes.Leaf[](1);
        leaves[0] = RaffleTypes.Leaf({holder: TRADER, tickets: tickets});

        uint64 snapshotBlock = uint64(block.number - 4);
        bytes32 snapshotHash = keccak256(abi.encode("PROD_FLAP_SNAPSHOT", snapshotBlock));
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

        uint256 before = IERC20Fork(WETH).balanceOf(TRADER);
        uint256 paid = raffle.claim(1, 0, leaves[0], proofs[0]);
        _require(paid != 0, "winner paid nothing");
        _require(IERC20Fork(WETH).balanceOf(TRADER) - before == paid, "payout delta mismatch");
        _require(IERC20Fork(WETH).balanceOf(address(raffle)) >= raffle.liabilities(), "raffle insolvent");
    }

    /// @dev The exact set lib/raffle-config.ts#raffleExclusionsForFlapLaunch
    /// builds in the UI: every Flap contract that holds the subject — the
    /// Portal (pre-graduation supply), the CREATE2-predicted V2 pair
    /// (post-graduation liquidity), the V2 liquidity manager and buyback
    /// adapter (transient balances), the adapter factory, and the adapter.
    function _exclusions(address predictedPair, address adapter) private pure returns (address[] memory sorted) {
        address[] memory raw = new address[](6);
        raw[0] = PORTAL;
        raw[1] = predictedPair;
        raw[2] = FLAP_V2_LIQUIDITY_MANAGER;
        raw[3] = FLAP_BUYBACK_ADAPTER;
        raw[4] = FLAP_ADAPTER_FACTORY;
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

    function _predictFlapV2Pair(address subject) private pure returns (address) {
        (address token0, address token1) = subject < WETH ? (subject, WETH) : (WETH, subject);
        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff", V2_FACTORY, keccak256(abi.encodePacked(token0, token1)), V2_PAIR_INIT_CODE_HASH
                        )
                    )
                )
            )
        );
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
            maxTicketsPerHolder: 0,
            minPrize: 1,
            maxPrize: 0,
            prizeBps: 10_000,
            recipientTaxBps: 700,
            recycleTaxBps: 300,
            minConfirmations: 1,
            winnersPerRound: 1,
            minRoundInterval: 3_600,
            weightWindowBlocks: 900,
            randomnessTimeout: 3_600,
            claimWindow: 604_800,
            basis: RaffleTypes.TicketBasis.MIN_BALANCE,
            exclusions: exclusions,
            stockRewards: new RaffleTypes.StockReward[](0)
        });
    }

    function _params(address adapter) private pure returns (FlapNewTokenV6Params memory params) {
        params.name = "Sinjoh Flap Raffle Rehearsal";
        params.symbol = "FRAFFLE";
        params.meta = "ipfs://sinjoh-flap-raffle-rehearsal";
        params.dexThresh = 1; // FOUR_FIFTHS
        params.salt = TOKEN_SALT;
        params.migratorType = 1; // V2_MIGRATOR
        params.quoteToken = address(0);
        params.quoteAmt = 0;
        params.beneficiary = adapter;
        params.permitData = "";
        params.extensionID = bytes32(0);
        params.extensionData = "";
        params.dexId = 0; // DEX0
        params.lpFeeProfile = 0; // STANDARD
        params.buyTaxRate = 300;
        params.sellTaxRate = 1_000;
        params.taxDuration = 365 days;
        params.antiFarmerDuration = 1 days;
        params.mktBps = 10_000;
        params.deflationBps = 0;
        params.dividendBps = 0;
        params.lpBps = 0;
        params.minimumShareBalance = 0;
        params.dividendToken = address(0);
        params.commissionReceiver = adapter;
        params.tokenVersion = 6; // TOKEN_TAXED_V3
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
