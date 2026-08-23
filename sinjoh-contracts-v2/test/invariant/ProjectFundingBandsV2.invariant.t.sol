// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { Vm } from "forge-std/Vm.sol";
import { FundingBandDestination, FundingBandState } from "../../src/bands/FundingBandTypes.sol";
import { ProjectFundingBandsV2 } from "../../src/bands/ProjectFundingBandsV2.sol";
import { MockProjectToken } from "../mocks/MockProjectToken.sol";
import { MockProjectController } from "../mocks/MockTreasuryIntegrations.sol";
import { MockBasketAsset, MockBasketModule } from "../mocks/MockBasketIntegrations.sol";
import {
    MockFundingBandGuard,
    MockFundingBandPositionAdapter
} from "../mocks/MockFundingBandIntegrations.sol";
import { FundingBandsTestBase } from "../FundingBandsTestBase.sol";

contract ProjectFundingBandsV2Handler {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    ProjectFundingBandsV2 public immutable bands;
    MockProjectToken public immutable subject;
    MockBasketAsset public immutable quote;
    MockProjectController public immutable projectController;
    MockFundingBandGuard public immutable guard;
    MockFundingBandPositionAdapter public immutable positionAdapter;
    MockBasketModule public immutable router;
    uint256 public observationNonce;

    constructor(
        ProjectFundingBandsV2 bands_,
        MockProjectToken subject_,
        MockBasketAsset quote_,
        MockProjectController projectController_,
        MockFundingBandGuard guard_,
        MockFundingBandPositionAdapter positionAdapter_,
        MockBasketModule router_
    ) {
        bands = bands_;
        subject = subject_;
        quote = quote_;
        projectController = projectController_;
        guard = guard_;
        positionAdapter = positionAdapter_;
        router = router_;
    }

    function increase(uint96 rawAmount) external {
        (ProjectFundingBandsV2.Band memory band,) = bands.bandStatus(1);
        if (band.state != FundingBandState.ACTIVE) return;
        uint128 amount = uint128(uint256(rawAmount % 1_000e18) + 1);
        subject.mint(address(this), amount);
        require(subject.transfer(address(bands), amount), "transfer");
        _observe(band.lowerMarketCapUsdE8 - 1);
        try projectController.execute(
            address(bands), abi.encodeCall(bands.increaseBand, (1, amount, bytes("")))
        ) { }
            catch { }
    }

    function arm() external {
        (ProjectFundingBandsV2.Band memory band,) = bands.bandStatus(1);
        if (band.state != FundingBandState.ACTIVE) return;
        _observe(band.upperMarketCapUsdE8);
        try bands.armSettlement(1, "") { } catch { }
    }

    function disarm() external {
        (ProjectFundingBandsV2.Band memory band,) = bands.bandStatus(1);
        if (band.state != FundingBandState.ARMED) return;
        _observe(band.upperMarketCapUsdE8 - 1);
        try bands.disarmSettlement(1, "") { } catch { }
    }

    function settle(uint96 rawQuote, bool failDelivery) external {
        (ProjectFundingBandsV2.Band memory band,) = bands.bandStatus(1);
        if (band.state != FundingBandState.ARMED) return;
        uint256 quoteAmount = uint256(rawQuote % 1_000_000e18) + 1;
        vm.warp(block.timestamp + bands.confirmationPeriod());
        _observe(band.upperMarketCapUsdE8);
        router.setFailFunding(failDelivery);
        positionAdapter.configureSettlement(0, quoteAmount);
        quote.mint(address(positionAdapter), quoteAmount);
        try bands.settle(1, "") { } catch { }
    }

    function retry(bool failDelivery) external {
        (ProjectFundingBandsV2.Band memory band,) = bands.bandStatus(1);
        if (band.state != FundingBandState.SETTLED_PENDING_DELIVERY) return;
        router.setFailFunding(failDelivery);
        try bands.retryDelivery(1) { } catch { }
    }

    function _observe(uint256 marketCap) private {
        guard.setObservation(
            marketCap,
            uint48(vm.getBlockTimestamp()),
            keccak256(abi.encode("observation", ++observationNonce)),
            int24(100),
            int24(200)
        );
    }
}

contract ProjectFundingBandsV2InvariantTest is FundingBandsTestBase {
    ProjectFundingBandsV2Handler private handler;

    function setUp() public {
        _setUpFundingBands();
        _createBand(100e18, FundingBandDestination.ROUTER);
        handler = new ProjectFundingBandsV2Handler(
            bands, subject, quote, projectController, guard, positionAdapter, router
        );
        targetContract(address(handler));
    }

    function invariantPositionCustodyAndLiquidityMatchWhileLive() public view {
        (ProjectFundingBandsV2.Band memory band,) = bands.bandStatus(1);
        if (band.state == FundingBandState.ACTIVE || band.state == FundingBandState.ARMED) {
            assertEq(IERC721(bands.positionManager()).ownerOf(band.positionId), address(bands));
            assertEq(positionAdapter.positionLiquidity(band.positionId), band.liquidity);
            assertEq(band.committedSubject, band.liquidity + band.subjectResidual);
        }
    }

    function invariantEveryLiabilityIsFullyBacked() public view {
        uint256 subjectLiabilities = bands.reservedSubjectResidual()
            + bands.totalDeliveryOwed(address(subject)) + bands.protocolOwed(address(subject));
        uint256 quoteLiabilities =
            bands.totalDeliveryOwed(address(quote)) + bands.protocolOwed(address(quote));
        assertGe(subject.balanceOf(address(bands)), subjectLiabilities);
        assertGe(quote.balanceOf(address(bands)), quoteLiabilities);
    }

    function invariantLiveIndexMatchesLifecycle() public view {
        (ProjectFundingBandsV2.Band memory band,) = bands.bandStatus(1);
        bool live = band.state == FundingBandState.ACTIVE || band.state == FundingBandState.ARMED;
        assertEq(bands.liveBandCount(), live ? 1 : 0);
        uint256[] memory ids = bands.liveBandIds();
        if (live) assertEq(ids[0], 1);
    }

    function invariantSettledPositionCannotBeReplayed() public view {
        (ProjectFundingBandsV2.Band memory band,) = bands.bandStatus(1);
        if (
            band.state == FundingBandState.SETTLED_PENDING_DELIVERY
                || band.state == FundingBandState.DELIVERED
        ) {
            assertEq(band.liquidity, 0);
            assertEq(positionAdapter.positionLiquidity(band.positionId), 0);
        }
    }

    function invariantAdapterAndSinkAllowancesReturnToZero() public view {
        assertEq(subject.allowance(address(bands), address(positionAdapter)), 0);
        assertEq(subject.allowance(address(bands), address(treasury)), 0);
        assertEq(quote.allowance(address(bands), address(treasury)), 0);
        assertEq(subject.allowance(address(bands), address(router)), 0);
        assertEq(quote.allowance(address(bands), address(router)), 0);
    }

    function invariantProjectIdentityAndReferenceSupplyNeverChange() public view {
        assertEq(bands.registry(), address(registry));
        assertEq(bands.subject(), address(subject));
        assertEq(bands.projectId(), subject.projectId());
        assertEq(bands.controller(), address(projectController));
        assertEq(bands.referenceSupply(), referenceSupply);
        assertEq(guard.referenceSupply(), referenceSupply);
    }

    function invariantFeeRemainderIsAlwaysBelowDenominator() public view {
        assertLt(bands.feeRemainder(), 10_000);
    }
}
