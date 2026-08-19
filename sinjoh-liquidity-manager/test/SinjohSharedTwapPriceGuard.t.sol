// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

import { SinjohSharedV3TwapPriceGuard } from "../src/SinjohSharedV3TwapPriceGuard.sol";
import { TestBase } from "./TestBase.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";
import { MockV3ExecutionFactory, MockV3OraclePool } from "./mocks/MockSwapInfrastructure.sol";

contract SinjohSharedTwapPriceGuardTest is TestBase {
    uint24 internal constant FEE = 10_000;
    uint32 internal constant WINDOW = 900;
    uint16 internal constant SPOT_DEVIATION_BPS = 1_000;
    uint16 internal constant SLIPPAGE_BPS = 750;
    uint48 internal constant VALIDITY = 300;

    MockERC20 internal subject;
    MockERC20 internal quote;
    MockV3ExecutionFactory internal factory;
    MockV3OraclePool internal pool;
    SinjohSharedV3TwapPriceGuard internal guard;

    function setUp() public {
        subject = new MockERC20("Subject", "SUBJ");
        quote = new MockERC20("Quote", "QUOTE");
        factory = new MockV3ExecutionFactory();
        address token0 = address(subject) < address(quote) ? address(subject) : address(quote);
        address token1 = address(subject) < address(quote) ? address(quote) : address(subject);
        pool = new MockV3OraclePool(address(factory), token0, token1, FEE);
        factory.setPool(address(pool));
        guard = new SinjohSharedV3TwapPriceGuard(
            address(factory), FEE, WINDOW, SPOT_DEVIATION_BPS, SLIPPAGE_BPS, VALIDITY, 1 ether
        );
    }

    function testBoundsOutputToTwapMinusConfiguredSlippage() public view {
        (uint256 minOut, uint48 validUntil) = guard.minimumOutput(
            address(subject), address(quote), address(subject), 10 ether, bytes32(0), ""
        );

        // A flat 1:1 TWAP less the 7.5% bound.
        assertEq(minOut, 9.25 ether);
        assertEq(validUntil, uint48(block.timestamp) + VALIDITY);
    }

    function testPricesTheReverseDirectionOfTheSamePair() public view {
        (uint256 minOut,) = guard.minimumOutput(
            address(subject), address(subject), address(quote), 10 ether, bytes32(0), ""
        );

        assertEq(minOut, 9.25 ether);
    }

    /// @dev One guard serves many launches, so a second unrelated subject must
    /// price against its own pool without any per-launch deployment.
    function testServesASecondSubjectWithoutRedeployment() public {
        MockERC20 otherSubject = new MockERC20("Other", "OTHR");
        address token0 =
            address(otherSubject) < address(quote) ? address(otherSubject) : address(quote);
        address token1 =
            address(otherSubject) < address(quote) ? address(quote) : address(otherSubject);
        MockV3OraclePool otherPool = new MockV3OraclePool(address(factory), token0, token1, FEE);
        factory.setPool(address(otherPool));

        (uint256 minOut,) = guard.minimumOutput(
            address(otherSubject), address(quote), address(otherSubject), 4 ether, bytes32(0), ""
        );

        assertEq(minOut, 3.7 ether);
    }

    function testRejectsAPairThatDoesNotIncludeTheSubject() public {
        MockERC20 unrelated = new MockERC20("Unrelated", "UNRL");

        vm.expectPartialRevert(SinjohSharedV3TwapPriceGuard.InvalidRoute.selector);
        guard.minimumOutput(
            address(subject), address(quote), address(unrelated), 10 ether, bytes32(0), ""
        );
    }

    /// @dev Caller-supplied guard data would be a channel for influencing the
    /// bound, so anything non-empty is refused.
    function testRejectsCallerSuppliedGuardData() public {
        vm.expectPartialRevert(SinjohSharedV3TwapPriceGuard.InvalidAmount.selector);
        guard.minimumOutput(
            address(subject), address(quote), address(subject), 10 ether, bytes32(0), hex"01"
        );
    }

    function testRejectsAmountsOutsideTheQuotableRange() public {
        vm.expectPartialRevert(SinjohSharedV3TwapPriceGuard.InvalidAmount.selector);
        guard.minimumOutput(address(subject), address(quote), address(subject), 0, bytes32(0), "");

        vm.expectPartialRevert(SinjohSharedV3TwapPriceGuard.InvalidAmount.selector);
        guard.minimumOutput(
            address(subject),
            address(quote),
            address(subject),
            uint256(type(uint128).max) + 1,
            bytes32(0),
            ""
        );
    }

    /// @dev The route hash cannot be pinned by a shared guard. It must not be
    /// usable to steer the quote either, so every value produces one answer.
    function testIgnoresTheRouteHashRatherThanTrustingIt() public view {
        (uint256 pinned,) = guard.minimumOutput(
            address(subject), address(quote), address(subject), 10 ether, bytes32(0), ""
        );
        (uint256 arbitrary,) = guard.minimumOutput(
            address(subject),
            address(quote),
            address(subject),
            10 ether,
            keccak256("some other route"),
            ""
        );

        assertEq(pinned, arbitrary);
    }

    function testRefusesWhenNoCanonicalPoolExists() public {
        factory.setPool(address(0));

        vm.expectPartialRevert(SinjohSharedV3TwapPriceGuard.PoolNotFound.selector);
        guard.minimumOutput(
            address(subject), address(quote), address(subject), 10 ether, bytes32(0), ""
        );
    }

    function testRefusesWhileThePoolKeepsNoHistory() public {
        pool.setCardinality(1);

        vm.expectPartialRevert(SinjohSharedV3TwapPriceGuard.OracleNotReady.selector);
        guard.minimumOutput(
            address(subject), address(quote), address(subject), 10 ether, bytes32(0), ""
        );
    }

    /// @dev Uniswap reverts when the buffer does not reach back a full window.
    /// The guard must surface that as a refusal, never as a shorter average.
    function testRefusesWhenTheWindowIsNotYetCovered() public {
        pool.setObserveReverts(true);

        vm.expectPartialRevert(SinjohSharedV3TwapPriceGuard.OracleNotReady.selector);
        guard.minimumOutput(
            address(subject), address(quote), address(subject), 10 ether, bytes32(0), ""
        );
    }

    /// @dev This is the anti-sandwich check: spot dislocated from the TWAP
    /// means someone is moving the pool right now.
    function testRefusesToQuoteWhileSpotIsDislocatedFromTheTwap() public {
        pool.setTicks(2_000, 0);

        vm.expectPartialRevert(SinjohSharedV3TwapPriceGuard.ExcessivePriceDeviation.selector);
        guard.minimumOutput(
            address(subject), address(quote), address(subject), 10 ether, bytes32(0), ""
        );
    }

    function testAnchorsTheMintVenuePriceToTheTwap() public {
        guard.validatePoolPrice(
            address(subject), address(quote), address(subject), TickMath.getSqrtPriceAtTick(0)
        );

        vm.expectPartialRevert(SinjohSharedV3TwapPriceGuard.ExcessivePriceDeviation.selector);
        guard.validatePoolPrice(
            address(subject), address(quote), address(subject), TickMath.getSqrtPriceAtTick(2_000)
        );
    }

    function testPrimingGrowsTheObservationBufferOfTheCanonicalPool() public {
        pool.setCardinality(1);

        address primed = guard.prime(address(quote), address(subject), 600);

        assertEq(primed, address(pool));
        assertEq(pool.cardinalityNext(), 600);
    }

    function testPrimingRejectsABufferTooSmallForAnyTwap() public {
        vm.expectPartialRevert(SinjohSharedV3TwapPriceGuard.InvalidConfiguration.selector);
        guard.prime(address(quote), address(subject), 1);
    }

    function testRejectsUnusableDeploymentParameters() public {
        // A fee tier the canonical factory does not enable.
        vm.expectPartialRevert(SinjohSharedV3TwapPriceGuard.InvalidConfiguration.selector);
        new SinjohSharedV3TwapPriceGuard(
            address(factory), 1234, WINDOW, SPOT_DEVIATION_BPS, SLIPPAGE_BPS, VALIDITY, 1 ether
        );

        // A slippage bound looser than the contract's ceiling.
        vm.expectPartialRevert(SinjohSharedV3TwapPriceGuard.InvalidConfiguration.selector);
        new SinjohSharedV3TwapPriceGuard(
            address(factory), FEE, WINDOW, SPOT_DEVIATION_BPS, 2_001, VALIDITY, 1 ether
        );

        // A quote that stays valid longer than the ceiling.
        vm.expectPartialRevert(SinjohSharedV3TwapPriceGuard.InvalidConfiguration.selector);
        new SinjohSharedV3TwapPriceGuard(
            address(factory), FEE, WINDOW, SPOT_DEVIATION_BPS, SLIPPAGE_BPS, 301, 1 ether
        );

        // No slippage bound at all, which is the testnet guard's behaviour.
        vm.expectPartialRevert(SinjohSharedV3TwapPriceGuard.InvalidConfiguration.selector);
        new SinjohSharedV3TwapPriceGuard(
            address(factory), FEE, WINDOW, SPOT_DEVIATION_BPS, 0, VALIDITY, 1 ether
        );

        vm.expectPartialRevert(SinjohSharedV3TwapPriceGuard.InvalidAddress.selector);
        new SinjohSharedV3TwapPriceGuard(
            address(0xdead), FEE, WINDOW, SPOT_DEVIATION_BPS, SLIPPAGE_BPS, VALIDITY, 1 ether
        );
    }
}
