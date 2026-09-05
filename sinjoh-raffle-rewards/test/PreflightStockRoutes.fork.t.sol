// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { TestBase } from "./TestBase.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";
import { MockCompliantGuard } from "./mocks/MockCompliantGuard.sol";
import { PreflightStockRoutes } from "../script/PreflightStockRoutes.s.sol";
import { StockRouteManifest } from "../script/StockRouteManifest.sol";
import { RaffleTypes } from "../src/RaffleTypes.sol";
import { SinjohRaffleRewards } from "../src/SinjohRaffleRewards.sol";
import { SinjohRaffleRewardsFactory } from "../src/SinjohRaffleRewardsFactory.sol";

/// @notice Proves the deployment gate both passes and fails for the right reasons.
/// @dev These run the gate against a compliant guard on a route whose pool is genuinely ready,
/// and against deliberately invalid guard inputs, and require the outcomes to differ.
contract PreflightStockRoutesForkTest is TestBase {
    address internal constant PRODUCTION_FACTORY = 0x9931324D98137b9D567B6ec32e1a10f148E6e9e3;
    address internal constant PRODUCTION_RANDOMNESS = 0xD16BCD59ca33C1e85578Aa5d60a02C4E2231c491;
    uint256 internal constant EXPECTED_CERTIFIED_ROUTE_COUNT = 25;
    uint256 internal constant MSTR_INDEX = 22;
    uint24 internal constant MSTR_FEE = 10_000;

    bool internal forked;
    PreflightStockRoutes internal preflight;

    function setUp() public {
        string memory url = vm.envOr("RH_RPC_URL", string(""));
        if (bytes(url).length == 0) return;
        vm.createSelectFork(url);
        forked = true;
        preflight = new PreflightStockRoutes();
    }

    /// Every route the UI can put into a newly deployed raffle clears its real production guard
    /// and a real swap through the production adapter at that route's launch-time cap.
    function testForkProductionManifestPassesEveryCertifiedRouteAtItsCap() public {
        if (!forked) return;
        assertEq(preflight.checkProduction(), 0);
    }

    /// The deployed 64-route generation must accept the complete current manifest, preserve every
    /// immutable tuple exactly, and bind the finished clone to a real contract subject.
    function testForkProductionFactoryDeploysAndBindsCompleteCertifiedManifest() public {
        if (!forked) return;

        StockRouteManifest.Route[] memory routes = StockRouteManifest.routes();
        assertEq(routes.length, EXPECTED_CERTIFIED_ROUTE_COUNT);
        RaffleTypes.StockReward[] memory rewards = new RaffleTypes.StockReward[](routes.length);
        for (uint256 i; i < routes.length; ++i) {
            rewards[i] = RaffleTypes.StockReward({
                asset: routes[i].asset,
                swapAdapter: StockRouteManifest.SWAP_ADAPTER,
                priceGuard: StockRouteManifest.guardFor(routes[i].fee),
                routeData: StockRouteManifest.routeData(routes[i].fee),
                guardData: ""
            });
        }

        RaffleTypes.Config memory config = RaffleTypes.Config({
            creator: address(this),
            attestor: address(this),
            randomness: PRODUCTION_RANDOMNESS,
            prizeAsset: StockRouteManifest.WETH,
            protocolFeeRecipient: address(this),
            taxRecipient: address(0),
            tokensPerTicket: 1 ether,
            maxTicketsPerHolder: 0,
            minPrize: 0.001 ether,
            maxPrize: 0.01 ether,
            prizeBps: 10_000,
            recipientTaxBps: 0,
            recycleTaxBps: 0,
            minConfirmations: 1,
            winnersPerRound: 1,
            minRoundInterval: 3_600,
            weightWindowBlocks: 0,
            randomnessTimeout: 7_200,
            claimWindow: 604_800,
            basis: RaffleTypes.TicketBasis.SNAPSHOT,
            exclusions: new address[](0),
            stockRewards: rewards
        });

        SinjohRaffleRewards raffle = SinjohRaffleRewards(
            payable(SinjohRaffleRewardsFactory(PRODUCTION_FACTORY)
                    .deployRaffle(keccak256("production-full-stock-manifest-bind"), config))
        );
        assertTrue(raffle.initialized());
        assertEq(raffle.configHash(), keccak256(abi.encode(config)));
        assertEq(raffle.stockRewardCount(), routes.length);

        for (uint256 i; i < routes.length; ++i) {
            RaffleTypes.StockReward memory actual = raffle.stockReward(i);
            assertEq(actual.asset, routes[i].asset);
            assertEq(actual.swapAdapter, StockRouteManifest.SWAP_ADAPTER);
            assertEq(actual.priceGuard, StockRouteManifest.guardFor(routes[i].fee));
            assertEq(
                keccak256(actual.routeData), keccak256(StockRouteManifest.routeData(routes[i].fee))
            );
            assertEq(keccak256(actual.guardData), keccak256(bytes("")));
        }

        MockERC20 subject = new MockERC20("Production binding subject", "BIND");
        raffle.bind(address(subject));
        assertEq(raffle.subject(), address(subject));
    }

    /// A guard built for a different fee tier prices a pool the route will never swap in. Nothing
    /// on-chain compares the two, so this is the gate's job.
    function testForkPreflightRejectsAFeeTierMismatch() public {
        if (!forked) return;
        MockCompliantGuard wrongTier = new MockCompliantGuard(StockRouteManifest.V3_FACTORY, 500);
        assertTrue(preflight.checkRoute(MSTR_INDEX, address(wrongTier), 0.01 ether) != 0);
    }

    function testForkPreflightRejectsAMissingGuard() public {
        if (!forked) return;
        assertTrue(preflight.checkRoute(MSTR_INDEX, address(0), 0.01 ether) != 0);
    }
}
