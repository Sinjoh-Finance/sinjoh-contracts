// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { RaffleTypes } from "../../src/raffle/RaffleTypes.sol";
import { ProjectRaffleV2 } from "../../src/raffle/ProjectRaffleV2.sol";
import { ProjectRouterV2 } from "../../src/router/ProjectRouterV2.sol";
import { RouterAction, RouterActionType } from "../../src/router/RouterTypes.sol";
import { MockRouterSink } from "../mocks/MockRouterIntegrations.sol";
import { MockRaffleRandomness } from "../mocks/MockRaffleIntegrations.sol";
import { RouterTestBase } from "../RouterTestBase.sol";

contract ProjectRouterRaffleV2IntegrationTest is RouterTestBase {
    ProjectRaffleV2 private raffle;

    function setUp() public {
        _setUpRouterDependencies();
        MockRaffleRandomness randomness = new MockRaffleRandomness();
        ProjectRaffleV2 implementation = new ProjectRaffleV2();
        raffle = ProjectRaffleV2(payable(Clones.clone(address(implementation))));
        raffle.initialize(
            address(registry), address(token), bytes32(uint256(1)), _config(randomness)
        );
        raffleSink = MockRouterSink(payable(address(raffle)));
    }

    function testRouterFundsExactRegisteredRaffleThroughStandardProjectABI() public {
        RouterAction memory action = RouterAction({
            actionType: RouterActionType.FUND_RAFFLE,
            allocationBps: 10_000,
            recipient: address(raffle),
            adapter: address(0),
            priceGuard: address(0),
            actionConfig: bytes("")
        });
        ProjectRouterV2 router = _deployRouter(_singleRoute(address(assetA), action), bytes32(0));

        _fund(router, address(assetA), 10_000);
        _execute(router, address(assetA), type(uint256).max);

        assertEq(assetA.balanceOf(address(raffle)), 9_900);
        assertEq(raffle.availablePool(), 9_801);
        assertEq(raffle.protocolOwed(), 99);
        assertEq(router.pending(address(assetA)), 0);
        assertEq(assetA.allowance(address(router), address(raffle)), 0);
    }

    function _config(MockRaffleRandomness randomness)
        private
        view
        returns (RaffleTypes.Config memory config)
    {
        config = RaffleTypes.Config({
            creator: CREATOR,
            attestor: address(this),
            randomness: address(randomness),
            prizeAsset: address(assetA),
            protocolFeeRecipient: FEE_RECIPIENT,
            taxRecipient: address(0),
            tokensPerTicket: 10e18,
            maxTicketsPerHolder: 0,
            minPrize: 1,
            maxPrize: 0,
            prizeBps: 10_000,
            recipientTaxBps: 0,
            recycleTaxBps: 0,
            minConfirmations: 2,
            winnersPerRound: 1,
            minRoundInterval: 600,
            weightWindowBlocks: 0,
            randomnessTimeout: 900,
            claimWindow: 3_600,
            basis: RaffleTypes.TicketBasis.SNAPSHOT,
            exclusions: new address[](0),
            stockRewards: new RaffleTypes.StockReward[](0)
        });
    }
}
