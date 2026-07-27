// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { TestBase } from "./TestBase.sol";
import { SqrtPriceMath } from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";
import { MockPriceGuard } from "./mocks/MockPriceGuard.sol";
import { MockSwapAdapter } from "./mocks/MockSwapAdapter.sol";
import {
    MockPermit2,
    MockV3Factory,
    MockV3Pool,
    MockV3PositionManager,
    MockV4PositionManager,
    MockV4StateView
} from "./mocks/MockUniswap.sol";
import { SinjohLiquidityManager } from "../src/SinjohLiquidityManager.sol";

contract SinjohLiquidityManagerTest is TestBase {
    address internal constant TREASURY = address(0x7007);
    address internal constant FUNDER_B = address(0xB002);
    address internal constant PROTOCOL_RECIPIENT = address(0xFEE1);

    MockERC20 internal subject;
    MockERC20 internal quote;
    MockPriceGuard internal guard;
    MockSwapAdapter internal adapter;
    MockV3Pool internal v3Pool;
    MockV3Factory internal v3Factory;
    MockV3PositionManager internal v3PositionManager;
    MockPermit2 internal permit2;
    MockV4PositionManager internal v4PositionManager;
    MockV4StateView internal v4StateView;
    SinjohLiquidityManager internal manager;

    function setUp() public {
        subject = new MockERC20("Subject", "SUB");
        quote = new MockERC20("Quote", "Q");
        guard = new MockPriceGuard();
        adapter = new MockSwapAdapter();
        v3Pool = new MockV3Pool();
        v3Factory = new MockV3Factory();
        v3Factory.setPool(address(v3Pool));
        v3PositionManager = new MockV3PositionManager();
        permit2 = new MockPermit2();
        v4PositionManager = new MockV4PositionManager(permit2);
        v4StateView = new MockV4StateView();
        manager = new SinjohLiquidityManager(
            address(v3Factory),
            address(v3PositionManager),
            address(v4PositionManager),
            address(v4StateView),
            address(permit2),
            PROTOCOL_RECIPIENT
        );

        quote.mint(address(this), 1_000_000);
        quote.approve(address(manager), type(uint256).max);
        subject.mint(address(adapter), 1_000_000);
    }

    function testSeparateTransferCannotCreateCredit() public {
        quote.transfer(address(manager), 500);
        bytes32 id = _fundV3(10_000, SinjohLiquidityManager.FeeMode.RECYCLE);
        (uint256 pendingQuote,,,,) = manager.accountFinancials(id);
        assertEq(pendingQuote, 10_000);
        assertEq(manager.totalLiability(address(quote)), 10_000);
        assertEq(quote.balanceOf(address(manager)), 10_500);
    }

    function testFeeOnTransferFundingRevertsWithoutCredit() public {
        quote.setFeeBps(100);
        vm.expectPartialRevert(SinjohLiquidityManager.UnexpectedBalanceDelta.selector);
        manager.fund(address(subject), address(quote), 10_000, abi.encode(_v3Config()));
        bytes32 id = manager.accountId(address(this), address(subject));
        (uint256 pendingQuote,,,, bool configured) = manager.accountFinancials(id);
        assertEq(pendingQuote, 0);
        assertTrue(!configured);
        assertEq(quote.balanceOf(address(manager)), 0);
    }

    function testSelfFeeRecipientIsRejectedBeforeFunding() public {
        SinjohLiquidityManager.Config memory config = _v3Config();
        config.feeMode = SinjohLiquidityManager.FeeMode.TREASURY;
        config.feeRecipient = address(manager);

        vm.expectPartialRevert(SinjohLiquidityManager.InvalidConfiguration.selector);
        manager.fund(address(subject), address(quote), 10_000, abi.encode(config));
    }

    function testV3MintsOnceThenIncreasesAndKeepsResidualCredit() public {
        bytes32 id = _fundV3(20_000, SinjohLiquidityManager.FeeMode.RECYCLE);
        guard.setMinimum(5_000);

        (uint256 tokenId,) = manager.mint(address(this), address(subject), 10_000, 1, "");
        (uint256 pendingQuote, uint256 pendingSubject, uint256 storedTokenId,,) =
            manager.accountFinancials(id);
        assertEq(tokenId, storedTokenId);
        assertEq(v3PositionManager.mintCalls(), 1);
        assertTrue(pendingQuote > 10_000);
        assertTrue(pendingSubject < 5_000);

        manager.mint(address(this), address(subject), 10_000, 5_000, "");
        (,, storedTokenId,,) = manager.accountFinancials(id);
        assertEq(storedTokenId, tokenId);
        assertEq(v3PositionManager.mintCalls(), 1);
        assertEq(v3PositionManager.increaseCalls(), 1);
    }

    function testV3AcceptsPonsDirectMintAfterCanonicalOwnershipCheck() public {
        v3PositionManager.setUseSafeMintCallback(false);
        bytes32 id = _fundV3(10_000, SinjohLiquidityManager.FeeMode.RECYCLE);

        (uint256 tokenId,) = manager.mint(address(this), address(subject), 10_000, 5_000, "");

        (,, uint256 storedTokenId,,) = manager.accountFinancials(id);
        assertEq(storedTokenId, tokenId);
        assertEq(v3PositionManager.ownerOf(tokenId), address(manager));
    }

    function testWeakCallerMinimumAndManipulatedSpotCannotBypassGuard() public {
        bytes32 id = _fundV3(10_000, SinjohLiquidityManager.FeeMode.RECYCLE);
        guard.setMinimum(5_001);

        vm.expectPartialRevert(SinjohLiquidityManager.InsufficientOutput.selector);
        manager.mint(address(this), address(subject), 10_000, 1, "");
        (uint256 pendingQuote, uint256 pendingSubject,,,) = manager.accountFinancials(id);
        assertEq(pendingQuote, 10_000);
        assertEq(pendingSubject, 0);

        guard.setMinimum(5_000);
        guard.setManipulated(true);
        vm.expectRevert();
        manager.mint(address(this), address(subject), 10_000, 5_000, "");
        (pendingQuote, pendingSubject,,,) = manager.accountFinancials(id);
        assertEq(pendingQuote, 10_000);
        assertEq(pendingSubject, 0);
    }

    function testMintSlippageRevertsBothAssetTransitions() public {
        bytes32 id = _fundV3(10_000, SinjohLiquidityManager.FeeMode.RECYCLE);
        guard.setMinimum(5_000);
        v3PositionManager.setUseBps(9_000);

        vm.expectRevert();
        manager.mint(address(this), address(subject), 10_000, 5_000, "");

        (uint256 pendingQuote, uint256 pendingSubject, uint256 tokenId,,) =
            manager.accountFinancials(id);
        assertEq(pendingQuote, 10_000);
        assertEq(pendingSubject, 0);
        assertEq(tokenId, 0);
        assertEq(manager.totalLiability(address(quote)), 10_000);
        assertEq(manager.totalLiability(address(subject)), 0);
    }

    function testTwoFundersNeverShareCreditsOrPositions() public {
        bytes32 idA = _fundV3(10_000, SinjohLiquidityManager.FeeMode.RECYCLE);
        quote.mint(FUNDER_B, 10_000);
        vm.prank(FUNDER_B);
        quote.approve(address(manager), type(uint256).max);
        vm.prank(FUNDER_B);
        manager.fund(address(subject), address(quote), 10_000, abi.encode(_v3Config()));
        bytes32 idB = manager.accountId(FUNDER_B, address(subject));

        manager.mint(address(this), address(subject), 10_000, 5_000, "");
        vm.prank(address(0xCA11));
        manager.mint(FUNDER_B, address(subject), 10_000, 5_000, "");

        (,, uint256 positionA,,) = manager.accountFinancials(idA);
        (,, uint256 positionB,,) = manager.accountFinancials(idB);
        assertTrue(positionA != 0 && positionB != 0 && positionA != positionB);
    }

    function testFeeCollectionDoesNotDecreasePrincipalAndCanDeliver() public {
        bytes32 id = _fundV3(10_000, SinjohLiquidityManager.FeeMode.TREASURY);
        (uint256 tokenId,) = manager.mint(address(this), address(subject), 10_000, 5_000, "");
        uint128 principalBefore = v3PositionManager.liquidity(tokenId);

        address token0 = v3PositionManager.token0(tokenId);
        address token1 = v3PositionManager.token1(tokenId);
        MockERC20(token0).mint(address(v3PositionManager), 100);
        MockERC20(token1).mint(address(v3PositionManager), 200);
        v3PositionManager.setFees(tokenId, 100, 200);
        manager.collect(address(this), address(subject));

        assertEq(v3PositionManager.liquidity(tokenId), principalBefore);
        uint256 quoteGross = token0 == address(quote) ? 100 : 200;
        uint256 subjectGross = token0 == address(subject) ? 100 : 200;
        uint256 quoteProtocolFee = quoteGross * manager.PROTOCOL_FEE_BPS() / manager.BPS();
        uint256 subjectProtocolFee = subjectGross * manager.PROTOCOL_FEE_BPS() / manager.BPS();
        uint256 quoteFee = quoteGross - quoteProtocolFee;
        uint256 subjectFee = subjectGross - subjectProtocolFee;
        assertEq(manager.feeOwed(TREASURY, address(quote)), quoteFee);
        assertEq(manager.feeOwed(TREASURY, address(subject)), subjectFee);
        assertEq(manager.protocolOwed(address(quote)), quoteProtocolFee);
        assertEq(manager.protocolOwed(address(subject)), subjectProtocolFee);

        manager.sendFee(TREASURY, address(quote), quoteFee);
        manager.sendProtocolFee(address(quote), quoteProtocolFee);
        assertEq(quote.balanceOf(TREASURY), quoteFee);
        assertEq(quote.balanceOf(PROTOCOL_RECIPIENT), quoteProtocolFee);
        assertEq(manager.feeOwed(TREASURY, address(quote)), 0);
        assertEq(manager.protocolOwed(address(quote)), 0);
        (,,, uint48 lastMint, bool configured) = manager.accountFinancials(id);
        assertTrue(configured && lastMint != 0);
    }

    function testV4HookRejectionLeavesAllCreditsUnchanged() public {
        bytes32 id = _fundV4Token(10_000);
        v4PositionManager.setRejectHook(true);

        vm.expectRevert();
        manager.mint(address(this), address(subject), 10_000, 5_000, "");
        (uint256 pendingQuote, uint256 pendingSubject, uint256 tokenId,,) =
            manager.accountFinancials(id);
        assertEq(pendingQuote, 10_000);
        assertEq(pendingSubject, 0);
        assertEq(tokenId, 0);
    }

    function testV4MintsOnceAndIncreasesThroughPermit2() public {
        bytes32 id = _fundV4Token(20_000);
        (uint256 tokenId,) = manager.mint(address(this), address(subject), 10_000, 5_000, "");
        manager.mint(address(this), address(subject), 10_000, 5_000, "");

        (,, uint256 storedTokenId,,) = manager.accountFinancials(id);
        assertEq(storedTokenId, tokenId);
        assertEq(v4PositionManager.mintCalls(), 1);
        assertEq(v4PositionManager.increaseCalls(), 1);
        assertTrue(v4PositionManager.positionLiquidity(tokenId) > 0);
    }

    function testV4MaximumInputsUseProtocolCompatibleRoundingUp() public {
        _fundV4Token(10_000);
        (, uint128 liquidity) = manager.mint(address(this), address(subject), 10_000, 5_000, "");

        uint160 sqrtPrice = v4StateView.sqrtPriceX96();
        uint160 sqrtLower = TickMath.getSqrtPriceAtTick(TickMath.minUsableTick(60));
        uint160 sqrtUpper = TickMath.getSqrtPriceAtTick(TickMath.maxUsableTick(60));
        uint256 expected0 = SqrtPriceMath.getAmount0Delta(sqrtPrice, sqrtUpper, liquidity, true);
        uint256 expected1 = SqrtPriceMath.getAmount1Delta(sqrtLower, sqrtPrice, liquidity, true);

        assertEq(v4PositionManager.lastAmount0Max(), expected0);
        assertEq(v4PositionManager.lastAmount1Max(), expected1);
    }

    function testNativeV4ExcessReturnsToSameAccountLedger() public {
        SinjohLiquidityManager.Config memory config = _v4Config(address(0));
        vm.deal(address(this), 10 ether);
        manager.fund{ value: 10 ether }(address(subject), address(0), 10 ether, abi.encode(config));
        bytes32 id = manager.accountId(address(this), address(subject));
        v4PositionManager.setUseBps(9_000);
        subject.mint(address(adapter), 10 ether);

        manager.mint(address(this), address(subject), 10 ether, 5 ether, "");

        (uint256 pendingQuote, uint256 pendingSubject,,,) = manager.accountFinancials(id);
        assertTrue(pendingQuote > 0);
        assertTrue(pendingSubject > 0);
        assertEq(address(manager).balance, manager.totalLiability(address(0)));
        assertTrue(subject.balanceOf(address(manager)) >= manager.totalLiability(address(subject)));
    }

    function _fundV3(uint256 amount, SinjohLiquidityManager.FeeMode mode)
        internal
        returns (bytes32 id)
    {
        SinjohLiquidityManager.Config memory config = _v3Config();
        config.feeMode = mode;
        config.feeRecipient =
            mode == SinjohLiquidityManager.FeeMode.TREASURY ? TREASURY : address(0);
        manager.fund(address(subject), address(quote), amount, abi.encode(config));
        id = manager.accountId(address(this), address(subject));
    }

    function _fundV4Token(uint256 amount) internal returns (bytes32 id) {
        manager.fund(
            address(subject), address(quote), amount, abi.encode(_v4Config(address(quote)))
        );
        id = manager.accountId(address(this), address(subject));
    }

    function _v3Config() internal view returns (SinjohLiquidityManager.Config memory config) {
        config = SinjohLiquidityManager.Config({
            venue: SinjohLiquidityManager.Venue.UNISWAP_V3,
            quoteAsset: address(quote),
            poolFee: 3_000,
            tickSpacing: 60,
            hooks: address(0),
            swapAdapter: address(adapter),
            priceGuard: address(guard),
            swapRouteData: hex"01",
            quoteSwapBps: 5_000,
            maxMintSlippageBps: 500,
            minNotionalPerMint: 100,
            maxNotionalPerMint: type(uint128).max,
            minMintInterval: 0,
            feeMode: SinjohLiquidityManager.FeeMode.RECYCLE,
            feeRecipient: address(0)
        });
    }

    function _v4Config(address quoteAsset)
        internal
        view
        returns (SinjohLiquidityManager.Config memory config)
    {
        config = SinjohLiquidityManager.Config({
            venue: SinjohLiquidityManager.Venue.UNISWAP_V4,
            quoteAsset: quoteAsset,
            poolFee: 3_000,
            tickSpacing: 60,
            hooks: address(0),
            swapAdapter: address(adapter),
            priceGuard: address(guard),
            swapRouteData: hex"01",
            quoteSwapBps: 5_000,
            maxMintSlippageBps: 500,
            minNotionalPerMint: 100,
            maxNotionalPerMint: type(uint128).max,
            minMintInterval: 0,
            feeMode: SinjohLiquidityManager.FeeMode.RECYCLE,
            feeRecipient: address(0)
        });
    }
}
