// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import {
    FundingBandConfig,
    FundingBandDestination,
    FundingBandState,
    FundingBandsDeploymentConfig,
    FundingBandsMarketConfig,
    FundingBandsProjectConfig
} from "../../src/bands/FundingBandTypes.sol";
import {
    FundingBandV3IntegrationConfig,
    FundingBandV3IntegrationFactory
} from "../../src/bands/FundingBandV3IntegrationFactory.sol";
import { ProjectFundingBandsV2 } from "../../src/bands/ProjectFundingBandsV2.sol";
import {
    UniswapV3FundingBandMarketCapGuard
} from "../../src/bands/UniswapV3FundingBandMarketCapGuard.sol";
import {
    UniswapV3FundingBandPositionAdapter
} from "../../src/bands/UniswapV3FundingBandPositionAdapter.sol";
import { MockRegistry } from "../mocks/MockRegistry.sol";
import { MockProjectToken } from "../mocks/MockProjectToken.sol";
import { MockProjectController } from "../mocks/MockTreasuryIntegrations.sol";
import { MockBasketAsset, MockBasketModule } from "../mocks/MockBasketIntegrations.sol";
import {
    MockV3BandFactory,
    MockV3BandPool,
    MockV3BandPositionManager
} from "../mocks/MockUniswapV3BandPosition.sol";

contract ProjectFundingBandsV3AutoDeploymentTest is Test {
    bytes32 private constant BAND_INTEGRATION_DOMAIN =
        keccak256("SINJOH_V2_FUNDING_BAND_INTEGRATION");

    struct System {
        MockProjectToken subject;
        MockBasketAsset quote;
        MockProjectController controller;
        MockV3BandPool pool;
        MockV3BandPositionManager positionManager;
        ProjectFundingBandsV2 bands;
        address predictedBands;
        address predictedGuard;
        address predictedAdapter;
        bytes32 approvalLeaf;
    }

    function testConstructorAtomicallyMaterializesPredictedProductionIntegrations() public {
        System memory system = _deploySystem();

        assertEq(address(system.bands), system.predictedBands);
        assertEq(address(system.bands.marketCapGuard()), system.predictedGuard);
        assertEq(address(system.bands.positionAdapter()), system.predictedAdapter);
        assertEq(system.bands.integrationApprovalLeaf(), system.approvalLeaf);
        assertEq(
            UniswapV3FundingBandMarketCapGuard(system.predictedGuard).bandsContract(),
            address(system.bands)
        );
        assertEq(
            UniswapV3FundingBandPositionAdapter(system.predictedAdapter).bandsContract(),
            address(system.bands)
        );
    }

    function testProductionGuardAndAdapterCompleteFundingBandJourney() public {
        System memory system = _deploySystem();
        uint128 lower = 2_000_000e8;
        uint128 upper = 4_000_000e8;
        uint128 inventory = 100e18;
        assertTrue(system.subject.transfer(address(system.bands), inventory));
        bytes memory result = system.controller
            .execute(
                address(system.bands),
                abi.encodeCall(
                    system.bands.createBand,
                    (
                        FundingBandConfig({
                            lowerMarketCapUsdE8: lower,
                            upperMarketCapUsdE8: upper,
                            subjectAmount: inventory,
                            destination: FundingBandDestination.CREATOR,
                            destinationConfig: ""
                        }),
                        bytes("")
                    )
                )
            );
        uint256 bandId = abi.decode(result, (uint256));
        UniswapV3FundingBandMarketCapGuard guard =
            UniswapV3FundingBandMarketCapGuard(address(system.bands.marketCapGuard()));
        (int24 effectiveLower, int24 effectiveUpper) = guard.effectiveTicks(lower, upper);
        int24 spacing = system.pool.tickSpacing();
        bool subjectIsToken0 = address(system.subject) < address(system.quote);
        int24 quoteSideTick = subjectIsToken0 ? effectiveUpper + spacing : effectiveLower - spacing;

        system.pool.setCurrentTick(quoteSideTick);
        system.bands.armSettlement(bandId, "");
        vm.warp(block.timestamp + 15 minutes);
        system.pool
            .setCurrentTick(subjectIsToken0 ? quoteSideTick + spacing : quoteSideTick - spacing);
        uint128 grossQuote = 1_000e18;
        system.positionManager
            .setSettlement(subjectIsToken0 ? 0 : grossQuote, subjectIsToken0 ? grossQuote : 0);
        system.quote.mint(address(system.positionManager), grossQuote);
        system.bands.settle(bandId, "");

        (ProjectFundingBandsV2.Band memory band,) = system.bands.bandStatus(bandId);
        assertEq(uint8(band.state), uint8(FundingBandState.DELIVERED));
        assertEq(system.quote.balanceOf(address(this)), 990e18);
        assertEq(system.bands.protocolOwed(address(system.quote)), 10e18);
        assertEq(system.bands.positionAdapter().positionLiquidity(band.positionId), 0);
    }

    function _deploySystem() private returns (System memory system) {
        MockRegistry registry = new MockRegistry();
        system.subject = new MockProjectToken(address(registry), address(this), 1_000_000e18);
        system.quote = new MockBasketAsset("Quote USD", "QUSD");
        system.controller = new MockProjectController(system.subject.projectId());
        MockBasketModule treasury = new MockBasketModule(
            address(registry), address(system.subject), system.subject.projectId(), 0, address(0)
        );
        MockV3BandFactory v3Factory = new MockV3BandFactory();
        address token0 = address(system.subject) < address(system.quote)
            ? address(system.subject)
            : address(system.quote);
        address token1 = address(system.subject) < address(system.quote)
            ? address(system.quote)
            : address(system.subject);
        system.pool = new MockV3BandPool(address(v3Factory), token0, token1, 3_000, 60);
        v3Factory.setPool(token0, token1, 3_000, address(system.pool));
        system.positionManager = new MockV3BandPositionManager(address(v3Factory));
        FundingBandV3IntegrationFactory factory = new FundingBandV3IntegrationFactory(
            address(v3Factory), address(system.positionManager)
        );

        system.predictedBands = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        FundingBandV3IntegrationConfig memory integration = FundingBandV3IntegrationConfig({
            bandsContract: system.predictedBands,
            subject: address(system.subject),
            quoteAsset: address(system.quote),
            canonicalPool: address(system.pool),
            referenceSupply: system.subject.totalSupply(),
            twapWindow: 15 minutes,
            quoteUsdOracle: address(0),
            tickReferenceQuoteUsdE8: 1e8,
            maximumOracleAge: 5 minutes
        });
        (system.predictedGuard, system.predictedAdapter) = factory.predict(integration);
        system.approvalLeaf = _approvalLeaf(
            address(system.pool), address(system.quote), address(system.positionManager)
        );
        FundingBandsDeploymentConfig memory deployment;
        deployment.project = FundingBandsProjectConfig({
            registry: address(registry),
            subject: address(system.subject),
            creator: address(this),
            controller: address(system.controller),
            treasury: address(treasury),
            router: address(0),
            airdrop: address(0),
            raffle: address(0),
            protocolFeeRecipient: address(0xFEE)
        });
        deployment.market = FundingBandsMarketConfig({
            canonicalPool: address(system.pool),
            quoteAsset: address(system.quote),
            referenceSupply: system.subject.totalSupply(),
            integrationApprovalRoot: system.approvalLeaf,
            marketCapGuard: address(0),
            positionAdapter: address(0),
            v3IntegrationFactory: address(factory),
            twapWindow: 15 minutes,
            quoteUsdOracle: address(0),
            tickReferenceQuoteUsdE8: 1e8,
            confirmationPeriod: 15 minutes,
            maximumObservationAge: 5 minutes,
            integrationApprovalProof: new bytes32[](0)
        });
        system.bands = new ProjectFundingBandsV2(abi.encode(deployment));
    }

    function _approvalLeaf(address pool, address quote, address positionManager)
        private
        view
        returns (bytes32)
    {
        bytes32 inner = keccak256(
            abi.encode(
                BAND_INTEGRATION_DOMAIN,
                block.chainid,
                pool.codehash,
                quote,
                keccak256(type(UniswapV3FundingBandMarketCapGuard).runtimeCode),
                keccak256(type(UniswapV3FundingBandPositionAdapter).runtimeCode),
                positionManager.codehash
            )
        );
        return keccak256(bytes.concat(inner));
    }
}
