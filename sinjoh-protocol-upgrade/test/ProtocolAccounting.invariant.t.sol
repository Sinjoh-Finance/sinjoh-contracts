// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AddressGovernanceController } from "../src/governance/AddressGovernanceController.sol";
import { IGovernanceController } from "../src/interfaces/IGovernanceController.sol";
import { SinjohStakingEngine } from "../src/SinjohStakingEngine.sol";
import { DynamicFundingBands } from "../src/DynamicFundingBands.sol";
import { StakingEngine } from "../src/StakingEngine.sol";
import { YieldBasket } from "../src/YieldBasket.sol";
import { InvariantTestBase, TestBase } from "./TestBase.sol";
import { MockERC20, MockFundable, MockTwapOracle, MockYieldAdapter } from "./mocks/Mocks.sol";

contract AirdropFundingHandler is TestBase {
    MockERC20 public immutable token;
    SinjohStakingEngine public immutable distributor;
    uint256 public scheduleId;

    constructor(MockERC20 token_, SinjohStakingEngine distributor_, StakingEngine staking_) {
        token = token_;
        distributor = distributor_;
        token_.mint(address(this), 1e18);
        token_.approve(address(staking_), 1e18);
        staking_.stake(1e18, 0);
        token_.approve(address(distributor_), type(uint256).max);
    }

    function setSchedule(uint256 scheduleId_) external {
        if (scheduleId != 0) return;
        scheduleId = scheduleId_;
    }

    function fund(uint96 rawAmount) external {
        uint256 amount = uint256(rawAmount) + 1;
        token.mint(address(this), amount);
        distributor.fund(address(token), amount, abi.encode(scheduleId));
    }

    function execute() external {
        SinjohStakingEngine.DistributionSchedule memory schedule =
            distributor.getSchedule(scheduleId);
        if (schedule.pendingRewards == 0) return;
        if (block.timestamp < schedule.nextEpoch) vm.warp(schedule.nextEpoch);
        vm.roll(block.number + 1);
        distributor.executeEpoch(scheduleId);
    }

    function claimLatest() external {
        SinjohStakingEngine.DistributionSchedule memory schedule =
            distributor.getSchedule(scheduleId);
        uint64 epochId = schedule.latestEpochId;
        if (epochId == 0 || distributor.claimed(scheduleId, epochId, address(this))) return;
        SinjohStakingEngine.Epoch memory epoch = distributor.getEpoch(scheduleId, epochId);
        if (block.timestamp > epoch.claimDeadline) return;
        uint64[] memory epochIds = new uint64[](1);
        epochIds[0] = epochId;
        distributor.claim(scheduleId, epochIds);
    }

    function sweepLatest() external {
        SinjohStakingEngine.DistributionSchedule memory schedule =
            distributor.getSchedule(scheduleId);
        uint64 epochId = schedule.latestEpochId;
        if (epochId == 0) return;
        SinjohStakingEngine.Epoch memory epoch = distributor.getEpoch(scheduleId, epochId);
        if (epoch.claimedAmount == epoch.fundedAmount) return;
        if (block.timestamp <= epoch.claimDeadline) vm.warp(uint256(epoch.claimDeadline) + 1);
        distributor.sweepUnclaimed(scheduleId, epochId);
    }
}

contract BasketFundingHandler is TestBase {
    MockERC20 public immutable token;
    YieldBasket public basket;
    MockERC20 public reward;
    MockYieldAdapter public adapter;
    MockFundable public sink;

    constructor(MockERC20 token_) {
        token = token_;
    }

    function initialize(
        YieldBasket basket_,
        MockERC20 reward_,
        MockYieldAdapter adapter_,
        MockFundable sink_
    ) external {
        if (address(basket) != address(0)) return;
        basket = basket_;
        reward = reward_;
        adapter = adapter_;
        sink = sink_;
        token.approve(address(basket_), type(uint256).max);
        adapter_.setBasket(address(basket_));
        basket_.configureAdapter(adapter_, 10_000, 30 minutes, address(sink_), "");
        address[] memory rewards = new address[](1);
        rewards[0] = address(reward_);
        basket_.setAdapterRewardTokens(adapter_, rewards);
    }

    function fund(uint96 rawAmount) external {
        uint256 amount = uint256(rawAmount) + 1;
        token.mint(address(this), amount);
        basket.fund(address(token), amount, "");
    }

    function allocate(uint96 rawAmount) external {
        uint256 idle = basket.idlePrincipal();
        if (idle == 0) return;
        YieldBasket.AdapterConfig memory config = basket.getAdapterConfig(address(adapter));
        uint256 capacity = basket.managedPrincipal() - config.principalAllocated;
        uint256 amount = uint256(rawAmount) + 1;
        if (amount > idle) amount = idle;
        if (amount > capacity) amount = capacity;
        if (amount != 0) basket.allocate(adapter, uint128(amount));
    }

    function withdraw(uint96 rawShares) external {
        YieldBasket.AdapterConfig memory config = basket.getAdapterConfig(address(adapter));
        if (config.sharesHeld == 0) return;
        uint256 shares = uint256(rawShares) % config.sharesHeld + 1;
        basket.withdrawFromAdapter(adapter, shares);
    }

    function harvest(uint96 rawAmount) external {
        uint256 amount = uint256(rawAmount) + 1;
        adapter.setNextReward(amount);
        vm.warp(block.timestamp + 30 minutes);
        basket.harvest(adapter);
    }
}

contract BandFundingHandler is TestBase {
    MockERC20 public immutable subject;
    MockERC20 public immutable funding;
    DynamicFundingBands public immutable bands;
    MockTwapOracle public immutable oracle;

    constructor(
        MockERC20 subject_,
        MockERC20 funding_,
        DynamicFundingBands bands_,
        MockTwapOracle oracle_
    ) {
        subject = subject_;
        funding = funding_;
        bands = bands_;
        oracle = oracle_;
        funding_.approve(address(bands_), type(uint256).max);
    }

    function create(uint96 rawAmount) external {
        uint128 amount = uint128(rawAmount) + 1;
        funding.mint(address(this), amount);
        oracle.setPrice(100e18);
        DynamicFundingBands.BandInput memory input = DynamicFundingBands.BandInput({
            subject: address(subject),
            fundingAsset: address(funding),
            amount: 0,
            lowerPriceE18: 110e18,
            upperPriceE18: 130e18,
            activationDelay: 1 hours,
            lifetime: 7 days,
            confirmationPeriod: 5 minutes,
            twapWindow: 5 minutes,
            minimumDistanceBps: 500,
            recipient: address(0xA11CE),
            refundRecipient: address(this)
        });
        bands.fund(address(funding), amount, abi.encode(input));
    }

    function activate(uint256 rawBandId) external {
        uint256 bandId = _bandId(rawBandId);
        if (bandId == 0) return;
        DynamicFundingBands.FundingBand memory band = bands.getBand(bandId);
        if (band.status != DynamicFundingBands.BandStatus.PENDING) return;
        if (block.timestamp >= band.expiryTime) return;
        if (block.timestamp < band.activationTime) vm.warp(band.activationTime);
        bands.activate(bandId);
    }

    function observe(uint256 rawBandId) external {
        uint256 bandId = _bandId(rawBandId);
        if (bandId == 0) return;
        DynamicFundingBands.FundingBand memory band = bands.getBand(bandId);
        if (
            band.status != DynamicFundingBands.BandStatus.ACTIVE
                && band.status != DynamicFundingBands.BandStatus.ARMED
        ) return;
        if (block.timestamp >= band.expiryTime) return;
        vm.warp(block.timestamp + 1);
        oracle.setPrice(120e18);
        bands.observe(bandId);
    }

    function redeem(uint256 rawBandId) external {
        uint256 bandId = _bandId(rawBandId);
        if (bandId == 0) return;
        DynamicFundingBands.FundingBand memory band = bands.getBand(bandId);
        if (band.status != DynamicFundingBands.BandStatus.ARMED) return;
        uint256 executableAt = uint256(band.qualifyingSince) + band.confirmationPeriod;
        if (executableAt >= band.expiryTime) return;
        if (block.timestamp < executableAt) vm.warp(executableAt);
        if (block.timestamp <= band.lastOracleUpdatedAt) {
            vm.warp(uint256(band.lastOracleUpdatedAt) + 1);
        }
        oracle.setPrice(120e18);
        bands.redeem(bandId);
    }

    function cancel(uint256 rawBandId) external {
        uint256 bandId = _bandId(rawBandId);
        if (bandId == 0) return;
        if (bands.bandStatus(bandId) == DynamicFundingBands.BandStatus.PENDING) {
            bands.cancelPending(bandId);
        }
    }

    function expire(uint256 rawBandId) external {
        uint256 bandId = _bandId(rawBandId);
        if (bandId == 0) return;
        DynamicFundingBands.FundingBand memory band = bands.getBand(bandId);
        if (
            band.status != DynamicFundingBands.BandStatus.PENDING
                && band.status != DynamicFundingBands.BandStatus.ACTIVE
                && band.status != DynamicFundingBands.BandStatus.ARMED
        ) return;
        if (block.timestamp < band.expiryTime) vm.warp(band.expiryTime);
        bands.expire(bandId);
    }

    function _bandId(uint256 rawBandId) private view returns (uint256) {
        uint256 count = bands.bandCount();
        return count == 0 ? 0 : rawBandId % count + 1;
    }
}

contract ProtocolAccountingInvariantTest is InvariantTestBase {
    address private constant GUARDIAN = address(0xBEEF);
    address private constant PROTOCOL = address(0xFEE);

    MockERC20 private airdropToken;
    SinjohStakingEngine private distributor;
    MockERC20 private basketToken;
    YieldBasket private basket;
    MockERC20 private basketReward;
    MockYieldAdapter private basketAdapter;
    MockFundable private basketSink;
    MockERC20 private subject;
    MockERC20 private bandToken;
    DynamicFundingBands private bands;

    function setUp() public {
        AddressGovernanceController controller =
            new AddressGovernanceController(address(this), IGovernanceController.Mode.INDIVIDUAL);

        airdropToken = new MockERC20();
        StakingEngine.LockTier[] memory tiers = new StakingEngine.LockTier[](1);
        tiers[0] = StakingEngine.LockTier({
            duration: 30 days, rewardWeightBps: 10_000, governanceWeightBps: 10_000, enabled: true
        });
        StakingEngine staking =
            new StakingEngine(controller, GUARDIAN, IERC20(address(airdropToken)), tiers);
        distributor = new SinjohStakingEngine(controller, GUARDIAN, staking, PROTOCOL);
        AirdropFundingHandler airdropHandler =
            new AirdropFundingHandler(airdropToken, distributor, staking);
        vm.roll(block.number + 1);
        uint256 scheduleId = distributor.createSchedule(
            SinjohStakingEngine.ScheduleInput({
                rewardToken: address(airdropToken),
                interval: 30 minutes,
                claimPeriod: 1 days,
                permissionlessExecution: true,
                fixedExecutorReward: 0,
                executorRewardBps: 0,
                executorRewardCap: 0,
                unclaimedDestination: address(0xB0B)
            })
        );
        airdropHandler.setSchedule(scheduleId);
        _targetedContracts.push(address(airdropHandler));

        basketToken = new MockERC20();
        basketReward = new MockERC20();
        BasketFundingHandler basketHandler = new BasketFundingHandler(basketToken);
        AddressGovernanceController basketController = new AddressGovernanceController(
            address(basketHandler), IGovernanceController.Mode.INDIVIDUAL
        );
        basket = new YieldBasket(basketController, GUARDIAN, IERC20(address(basketToken)));
        basketAdapter = new MockYieldAdapter(address(basketToken), basketReward);
        basketSink = new MockFundable();
        basketHandler.initialize(basket, basketReward, basketAdapter, basketSink);
        _targetedContracts.push(address(basketHandler));

        subject = new MockERC20();
        bandToken = new MockERC20();
        MockTwapOracle oracle = new MockTwapOracle();
        bands = new DynamicFundingBands(controller, GUARDIAN, oracle, 1 hours, PROTOCOL);
        BandFundingHandler bandHandler = new BandFundingHandler(subject, bandToken, bands, oracle);
        _targetedContracts.push(address(bandHandler));
    }

    function invariantAirdropLiabilityIsFullyBacked() public view {
        assertEq(
            distributor.totalLiability(address(airdropToken)),
            airdropToken.balanceOf(address(distributor))
        );
    }

    function invariantAirdropFeeCannotBeSplitAvoided() public view {
        assertEq(
            distributor.cumulativeProtocolFee(address(airdropToken)),
            distributor.cumulativeGrossFunding(address(airdropToken)) / 100
        );
    }

    function invariantIdleBasketPrincipalEqualsMeasuredBalance() public view {
        YieldBasket.AdapterConfig memory config = basket.getAdapterConfig(address(basketAdapter));
        assertEq(basket.managedPrincipal(), basket.idlePrincipal() + config.principalAllocated);
        assertTrue(basketToken.balanceOf(address(basket)) >= basket.idlePrincipal());
        assertEq(
            basket.cumulativeRealizedYield(address(basketReward)),
            basketSink.funded(address(basketReward))
        );
        assertEq(basketReward.balanceOf(address(basket)), 0);
    }

    function invariantEveryDynamicBandIsPrefunded() public view {
        assertEq(bands.committedByAsset(address(bandToken)), bandToken.balanceOf(address(bands)));
        assertEq(bands.totalCommitted(), bands.committedByAsset(address(bandToken)));
        assertEq(
            bands.committedBySubject(address(subject), address(bandToken)),
            bands.committedByAsset(address(bandToken))
        );
    }

    function invariantDynamicBandFeeCannotBeSplitAvoided() public view {
        assertEq(
            bands.cumulativeProtocolFee(address(bandToken)),
            bands.cumulativeRedeemed(address(bandToken)) / 100
        );
    }
}
