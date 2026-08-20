// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AddressGovernanceController } from "../src/governance/AddressGovernanceController.sol";
import { IGovernanceController } from "../src/interfaces/IGovernanceController.sol";
import { AirdropDistributorV2 } from "../src/AirdropDistributorV2.sol";
import { DynamicFundingBands } from "../src/DynamicFundingBands.sol";
import { StakingEngine } from "../src/StakingEngine.sol";
import { YieldBasket } from "../src/YieldBasket.sol";
import { InvariantTestBase } from "./TestBase.sol";
import { MockERC20, MockTwapOracle } from "./mocks/Mocks.sol";

contract AirdropFundingHandler {
    MockERC20 public immutable token;
    AirdropDistributorV2 public immutable distributor;
    uint256 public immutable scheduleId;

    constructor(MockERC20 token_, AirdropDistributorV2 distributor_, uint256 scheduleId_) {
        token = token_;
        distributor = distributor_;
        scheduleId = scheduleId_;
        token_.approve(address(distributor_), type(uint256).max);
    }

    function fund(uint96 rawAmount) external {
        uint256 amount = uint256(rawAmount) + 1;
        token.mint(address(this), amount);
        distributor.fund(address(token), amount, abi.encode(scheduleId));
    }
}

contract BasketFundingHandler {
    MockERC20 public immutable token;
    YieldBasket public immutable basket;

    constructor(MockERC20 token_, YieldBasket basket_) {
        token = token_;
        basket = basket_;
        token_.approve(address(basket_), type(uint256).max);
    }

    function fund(uint96 rawAmount) external {
        uint256 amount = uint256(rawAmount) + 1;
        token.mint(address(this), amount);
        basket.fund(address(token), amount, "");
    }
}

contract BandFundingHandler {
    MockERC20 public immutable subject;
    MockERC20 public immutable funding;
    DynamicFundingBands public immutable bands;

    constructor(MockERC20 subject_, MockERC20 funding_, DynamicFundingBands bands_) {
        subject = subject_;
        funding = funding_;
        bands = bands_;
        funding_.approve(address(bands_), type(uint256).max);
    }

    function create(uint96 rawAmount) external {
        uint128 amount = uint128(rawAmount) + 1;
        funding.mint(address(this), amount);
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
}

contract ProtocolAccountingInvariantTest is InvariantTestBase {
    address private constant GUARDIAN = address(0xBEEF);
    address private constant PROTOCOL = address(0xFEE);

    MockERC20 private airdropToken;
    AirdropDistributorV2 private distributor;
    MockERC20 private basketToken;
    YieldBasket private basket;
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
        distributor = new AirdropDistributorV2(controller, GUARDIAN, staking, PROTOCOL);
        uint256 scheduleId = distributor.createSchedule(
            AirdropDistributorV2.ScheduleInput({
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
        AirdropFundingHandler airdropHandler =
            new AirdropFundingHandler(airdropToken, distributor, scheduleId);
        _targetedContracts.push(address(airdropHandler));

        basketToken = new MockERC20();
        basket = new YieldBasket(controller, GUARDIAN, IERC20(address(basketToken)));
        BasketFundingHandler basketHandler = new BasketFundingHandler(basketToken, basket);
        _targetedContracts.push(address(basketHandler));

        subject = new MockERC20();
        bandToken = new MockERC20();
        MockTwapOracle oracle = new MockTwapOracle();
        bands = new DynamicFundingBands(controller, GUARDIAN, oracle, 1 hours, PROTOCOL);
        BandFundingHandler bandHandler = new BandFundingHandler(subject, bandToken, bands);
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
        assertEq(basket.managedPrincipal(), basketToken.balanceOf(address(basket)));
        assertEq(basket.idlePrincipal(), basket.managedPrincipal());
    }

    function invariantEveryDynamicBandIsPrefunded() public view {
        assertEq(bands.committedByAsset(address(bandToken)), bandToken.balanceOf(address(bands)));
        assertEq(bands.totalCommitted(), bands.committedByAsset(address(bandToken)));
        assertEq(
            bands.committedBySubject(address(subject), address(bandToken)),
            bands.committedByAsset(address(bandToken))
        );
    }
}
