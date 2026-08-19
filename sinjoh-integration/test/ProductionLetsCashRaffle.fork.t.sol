// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {ILetsCashFactory} from "adapters/src/interfaces/ILetsCash.sol";
import {RaffleTypes} from "raffle/src/RaffleTypes.sol";
import {SinjohRaffleRewards} from "raffle/src/SinjohRaffleRewards.sol";
import {RaffleTree} from "raffle/test/RaffleTree.sol";
import {MockArbSys} from "raffle/test/mocks/MockArbSys.sol";
import {MockRandomness} from "raffle/test/mocks/MockRandomness.sol";

interface VmLetsCashRaffle {
    function createSelectFork(string calldata urlOrAlias) external returns (uint256);
    function envOr(string calldata name, string calldata defaultValue) external returns (string memory);
    function etch(address target, bytes calldata code) external;
    function deal(address account, uint256 newBalance) external;
}

struct LetsCashAssetRef {
    uint8 kind;
    address token;
}

struct LetsCashRoute {
    address adapter;
    bytes routeData;
}

struct LetsCashNormalization {
    LetsCashAssetRef asset;
    LetsCashRoute route;
    address priceGuard;
    uint128 maxAmountInPerCall;
}

struct LetsCashAllocation {
    address destination;
    uint16 bps;
    bool isSink;
    bool creatorMayRepoint;
    bytes sinkConfig;
}

struct LetsCashBucket {
    LetsCashAssetRef output;
    uint16 bps;
    LetsCashRoute route;
    address priceGuard;
    uint128 maxAmountInPerCall;
    LetsCashAllocation[] allocations;
}

struct LetsCashRouterConfig {
    address creator;
    address protocolFeeRecipient;
    address weth;
    address launchpadAdapter;
    LetsCashNormalization[] normalizations;
    LetsCashBucket[] buckets;
}

struct LetsCashAirdropConfig {
    uint128 minPayout;
    uint16 maxBatchSize;
    uint16 minConfirmations;
    address[] exclusions;
}

interface ILetsCashRouterFactoryLive {
    function predictLaunchpadAddress(address creator, bytes32 userSalt) external view returns (address);
    function deployForLaunchpad(address creator, bytes32 userSalt, LetsCashRouterConfig calldata config)
        external
        returns (address router);
}

interface ILetsCashRouterLive {
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

interface ILetsCashAdapterFactoryLive {
    function predictAddress(address creator, bytes32 userSalt) external view returns (address);
    function deploy(address creator, address router, bytes32 userSalt) external returns (address adapter);
}

interface ILetsCashAdapterLive {
    function activate(address token, bytes32 poolId, uint256 configId) external;
    function collect() external returns (uint256[] memory amounts);
    function forward(address asset) external returns (uint256 amount);
    function feeRoutingIntact() external view returns (bool);
}

interface ILetsCashRaffleFactoryLive {
    function deployRaffle(bytes32 userSalt, RaffleTypes.Config calldata config) external returns (address raffle);
    function predictRaffle(address creator, bytes32 userSalt, bytes32 configHash) external view returns (address raffle);
    function hashConfig(RaffleTypes.Config calldata config) external pure returns (bytes32);
}

interface IERC20LetsCashFork {
    function balanceOf(address account) external view returns (uint256);
}

interface ILetsCashAirdropDistributorLive {
    function accountId(address funder, address subject, address asset) external pure returns (bytes32);
    function accountFinancials(bytes32 id)
        external
        view
        returns (
            uint256 totalFunded,
            uint256 totalPaid,
            uint256 latestRootSum,
            uint64 latestEpochId,
            uint64 latestSnapshotBlock
        );
}

/// @notice Full production rehearsal for the LetsCash holder-raffle path:
/// deterministic raffle/router/adapter deployment, live upstream launch,
/// activation and binding, creator-fee collection, WETH funding of both the
/// raffle and holder-airdrop sinks, and a complete random draw and payout.
/// Every external state change is confined to the local Robinhood mainnet fork.
contract ProductionLetsCashRaffleForkTest {
    VmLetsCashRaffle internal constant vm = VmLetsCashRaffle(address(uint160(uint256(keccak256("hevm cheat code")))));

    address internal constant FACTORY = 0x5bd1Fbe78a78fe8236fa00CF48fbEBA74ae34661;
    address internal constant HOOK = 0x75A54357D9C78a2Db19004a5FDc76c50F9242AEC;
    address internal constant POOL_MANAGER = 0x8366a39CC670B4001A1121B8F6A443A643e40951;
    address internal constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;
    address internal constant ROUTER_FACTORY = 0xA1F721a697Dd03a45f264F53bCBFd121212318eD;
    address internal constant ADAPTER_FACTORY = 0x81f50D1695eeB6976b53f5dCc9E785Ff06C183DC;
    address internal constant RAFFLE_FACTORY = 0xD030064fB83d14C97c22A6B63bF376552eBA7112;
    address internal constant AIRDROP_DISTRIBUTOR = 0xA1d65242D367501D9A261389a69005e584F4786a;
    address internal constant PROTOCOL_RECIPIENT = address(0xFEE1);
    address internal constant ARBSYS = address(0x64);
    uint256 internal constant CONFIG_ID = 1_000;
    bytes32 internal constant USER_SALT = keccak256("PROD_LETSCASH_RAFFLE_ROUTE");
    bytes32 internal constant RAFFLE_SALT = keccak256("PROD_LETSCASH_RAFFLE");

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
        vm.deal(address(this), 10 ether);
    }

    function testForkProductionLetsCashLaunchFundsAndSettlesARaffle() public {
        if (!forked) return;

        address predictedAdapter = ILetsCashAdapterFactoryLive(ADAPTER_FACTORY).predictAddress(address(this), USER_SALT);
        address predictedRouter =
            ILetsCashRouterFactoryLive(ROUTER_FACTORY).predictLaunchpadAddress(address(this), USER_SALT);
        address[] memory exclusions = _exclusions(predictedAdapter, predictedRouter);

        RaffleTypes.Config memory raffleConfig = _raffleConfig(exclusions);
        bytes32 raffleHash = ILetsCashRaffleFactoryLive(RAFFLE_FACTORY).hashConfig(raffleConfig);
        address predictedRaffle =
            ILetsCashRaffleFactoryLive(RAFFLE_FACTORY).predictRaffle(address(this), RAFFLE_SALT, raffleHash);
        SinjohRaffleRewards raffle = SinjohRaffleRewards(
            payable(ILetsCashRaffleFactoryLive(RAFFLE_FACTORY).deployRaffle(RAFFLE_SALT, raffleConfig))
        );
        _require(address(raffle) == predictedRaffle, "raffle prediction failed");
        for (uint256 i; i < exclusions.length; ++i) {
            _require(raffle.isExcluded(exclusions[i]), "protocol holder not excluded");
        }

        address router = ILetsCashRouterFactoryLive(ROUTER_FACTORY)
            .deployForLaunchpad(address(this), USER_SALT, _routerConfig(predictedAdapter, address(raffle)));
        _require(router == predictedRouter, "router prediction failed");
        address adapter = ILetsCashAdapterFactoryLive(ADAPTER_FACTORY).deploy(address(this), router, USER_SALT);
        _require(adapter == predictedAdapter, "adapter prediction failed");

        ILetsCashFactory.TokenParams memory params = _tokenParams();
        (bytes32 tokenSalt, address predictedToken) =
            ILetsCashFactory(FACTORY).mineSalt(params, CONFIG_ID, address(this), 1, 200_000);
        _require(predictedToken != address(0), "token salt mining failed");
        address[] memory recipients = new address[](1);
        recipients[0] = adapter;
        uint16[] memory shares = new uint16[](1);
        shares[0] = 10_000;
        uint256 launchFee = ILetsCashFactory(FACTORY).launchFee();
        (address subject, bytes32 poolId) = ILetsCashFactory(FACTORY).launchWithFeeSplit{value: launchFee + 0.01 ether}(
            params, CONFIG_ID, 0.01 ether, 1, tokenSalt, recipients, shares
        );
        _require(subject == predictedToken, "launched token mismatch");

        ILetsCashAdapterLive(adapter).activate(subject, poolId, CONFIG_ID);
        _require(ILetsCashRouterLive(router).subject() == subject, "router was not bound");
        _require(ILetsCashAdapterLive(adapter).feeRoutingIntact(), "fee route is not intact");
        raffle.bind(subject);

        uint256[] memory collected = ILetsCashAdapterLive(adapter).collect();
        _require(collected[0] != 0, "adapter collected no creator fees");
        uint256 forwarded = ILetsCashAdapterLive(adapter).forward(WETH);
        _require(forwarded == collected[0], "adapter did not forward all WETH");
        ILetsCashRouterLive(router).sync(WETH);
        uint256 bucketInput = ILetsCashRouterLive(router).bucketInputOwed(0, WETH);
        _require(bucketInput != 0, "router sync produced no raffle input");
        ILetsCashRouterLive(router).processBucket(0, WETH, bucketInput, 0, "");
        uint16 allocationKey = ILetsCashRouterLive(router).allocationKey(0, 0);
        uint256 sinkPending = ILetsCashRouterLive(router).sinkOwed(allocationKey, WETH);
        _require(sinkPending != 0, "router produced no raffle liability");
        ILetsCashRouterLive(router).fundSink(0, 0, sinkPending);
        _require(raffle.availablePool() != 0, "raffle prize pool was not funded");
        uint16 airdropKey = ILetsCashRouterLive(router).allocationKey(0, 1);
        uint256 airdropPending = ILetsCashRouterLive(router).sinkOwed(airdropKey, WETH);
        _require(airdropPending != 0, "router produced no airdrop liability");
        ILetsCashRouterLive(router).fundSink(0, 1, airdropPending);
        bytes32 airdropAccount = ILetsCashAirdropDistributorLive(AIRDROP_DISTRIBUTOR).accountId(router, subject, WETH);
        (uint256 airdropFunded,,,,) =
            ILetsCashAirdropDistributorLive(AIRDROP_DISTRIBUTOR).accountFinancials(airdropAccount);
        _require(airdropFunded != 0, "airdrop account was not funded");

        uint256 tickets = raffle.ticketsFor(IERC20LetsCashFork(subject).balanceOf(address(this)));
        _require(tickets != 0, "creator received no raffle tickets");
        RaffleTypes.Leaf[] memory leaves = new RaffleTypes.Leaf[](1);
        leaves[0] = RaffleTypes.Leaf({holder: address(this), tickets: tickets});
        uint64 snapshotBlock = uint64(block.number - 4);
        bytes32 snapshotHash = keccak256(abi.encode("PROD_LETSCASH_SNAPSHOT", snapshotBlock));
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

        uint256 beforeBalance = IERC20LetsCashFork(WETH).balanceOf(address(this));
        uint256 paid = raffle.claim(1, 0, leaves[0], proofs[0]);
        _require(paid != 0, "winner received no reward");
        _require(
            IERC20LetsCashFork(WETH).balanceOf(address(this)) - beforeBalance == paid, "reward balance delta mismatch"
        );
        _require(IERC20LetsCashFork(WETH).balanceOf(address(raffle)) >= raffle.liabilities(), "raffle became insolvent");
    }

    function _exclusions(address adapter, address router) private pure returns (address[] memory sorted) {
        sorted = new address[](5);
        sorted[0] = adapter;
        sorted[1] = router;
        sorted[2] = FACTORY;
        sorted[3] = POOL_MANAGER;
        sorted[4] = HOOK;
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
            tokensPerTicket: 1e18,
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

    function _routerConfig(address adapter, address raffleSink)
        private
        view
        returns (LetsCashRouterConfig memory config)
    {
        LetsCashAllocation[] memory allocations = new LetsCashAllocation[](2);
        allocations[0] = LetsCashAllocation({
            destination: raffleSink, bps: 5_000, isSink: true, creatorMayRepoint: false, sinkConfig: ""
        });
        allocations[1] = LetsCashAllocation({
            destination: AIRDROP_DISTRIBUTOR,
            bps: 5_000,
            isSink: true,
            creatorMayRepoint: false,
            sinkConfig: _airdropConfig(adapter)
        });
        LetsCashBucket[] memory buckets = new LetsCashBucket[](1);
        buckets[0] = LetsCashBucket({
            output: LetsCashAssetRef(1, WETH),
            bps: 10_000,
            route: LetsCashRoute(address(0), ""),
            priceGuard: address(0),
            maxAmountInPerCall: type(uint128).max,
            allocations: allocations
        });
        config = LetsCashRouterConfig({
            creator: address(this),
            protocolFeeRecipient: PROTOCOL_RECIPIENT,
            weth: WETH,
            launchpadAdapter: adapter,
            normalizations: new LetsCashNormalization[](0),
            buckets: buckets
        });
    }

    function _airdropConfig(address adapter) private view returns (bytes memory) {
        address[] memory exclusions = new address[](6);
        exclusions[0] = address(this);
        exclusions[1] = adapter;
        exclusions[2] = ILetsCashRouterFactoryLive(ROUTER_FACTORY).predictLaunchpadAddress(address(this), USER_SALT);
        exclusions[3] = FACTORY;
        exclusions[4] = HOOK;
        exclusions[5] = POOL_MANAGER;
        for (uint256 i = 1; i < exclusions.length; ++i) {
            address value = exclusions[i];
            uint256 j = i;
            while (j > 0 && exclusions[j - 1] > value) {
                exclusions[j] = exclusions[j - 1];
                --j;
            }
            exclusions[j] = value;
        }
        return abi.encode(
            LetsCashAirdropConfig({minPayout: 1, maxBatchSize: 16, minConfirmations: 2, exclusions: exclusions})
        );
    }

    function _tokenParams() private view returns (ILetsCashFactory.TokenParams memory params) {
        params = ILetsCashFactory.TokenParams({
            name: "Sinjoh LetsCash Raffle Rehearsal",
            symbol: "LCASHRF",
            logo: "ipfs://sinjoh-letscash-raffle",
            description: "Fork-only LetsCash raffle lifecycle proof",
            metadataURI: "ipfs://sinjoh-letscash-raffle-metadata",
            socials: ILetsCashFactory.Socials({
                telegram: "", twitter: "sinjoh", discord: "", website: "https://sinjoh.com", extra: ""
            }),
            creator: address(this)
        });
    }

    function _require(bool condition, string memory reason) private pure {
        if (!condition) revert AssertionFailed(reason);
    }
}
