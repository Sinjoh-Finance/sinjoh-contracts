// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { SqrtPriceMath } from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { IProjectFundable } from "../../src/interfaces/IProjectFundable.sol";
import { ProjectIds } from "../../src/libraries/ProjectIds.sol";
import { SinjohV2Constants } from "../../src/libraries/SinjohV2Constants.sol";
import { ProjectLiquidityManagerV2 } from "../../src/liquidity/ProjectLiquidityManagerV2.sol";
import { MockProjectToken } from "../mocks/MockProjectToken.sol";
import { MockRegistry } from "../mocks/MockRegistry.sol";
import { MockERC20 } from "../mocks/liquidity/MockERC20.sol";
import { MockPriceGuard } from "../mocks/liquidity/MockPriceGuard.sol";
import { MockSwapAdapter } from "../mocks/liquidity/MockSwapAdapter.sol";
import {
    MockPermit2,
    MockV3Factory,
    MockV3Pool,
    MockV3PositionManager,
    MockV4PositionManager,
    MockV4StateView
} from "../mocks/liquidity/MockUniswap.sol";

interface IMintableLiquidityAsset {
    function mint(address recipient, uint256 amount) external;
}

contract PartialProjectIdentityLiquidityAsset is MockERC20 {
    address public immutable registry;

    constructor(address registry_) MockERC20("Partial Identity", "PARTIAL") {
        registry = registry_;
    }
}

contract ProjectLiquidityManagerV2Test is Test {
    address internal constant TREASURY = address(0x7007);
    address internal constant FUNDER_B = address(0xB002);
    address internal constant PROTOCOL_RECIPIENT = address(0xFEE1);

    MockRegistry internal registry;
    MockProjectToken internal subject;
    MockERC20 internal quote;
    MockPriceGuard internal guard;
    MockSwapAdapter internal adapter;
    MockV3Pool internal v3Pool;
    MockV3Factory internal v3Factory;
    MockV3PositionManager internal v3PositionManager;
    MockPermit2 internal permit2;
    MockV4PositionManager internal v4PositionManager;
    MockV4StateView internal v4StateView;
    ProjectLiquidityManagerV2 internal manager;

    function setUp() public {
        registry = new MockRegistry();
        subject = new MockProjectToken(address(registry), address(this), 0);
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
        manager = new ProjectLiquidityManagerV2(
            address(registry),
            address(subject),
            address(v3Factory),
            address(v3PositionManager),
            address(v4PositionManager),
            address(v4StateView),
            address(permit2),
            PROTOCOL_RECIPIENT,
            _swapApprovalLeaf()
        );

        quote.mint(address(this), 1_000_000);
        quote.approve(address(manager), type(uint256).max);
        subject.mint(address(adapter), 1_000_000);
    }

    function testPublishesImmutableProjectIdentityAndCommonFundingSelector() public view {
        assertEq(manager.registry(), address(registry));
        assertEq(manager.subject(), address(subject));
        assertEq(manager.projectId(), subject.projectId());
        assertEq(ProjectLiquidityManagerV2.fund.selector, IProjectFundable.fund.selector);
    }

    function testAcceptsOrdinaryExternalErc20SubjectWithoutProjectIdentitySelectors() public {
        MockERC20 externalSubject = new MockERC20("Ordinary Pons", "PONS");
        externalSubject.mint(address(this), 1_000_000e18);

        ProjectLiquidityManagerV2 externalManager = new ProjectLiquidityManagerV2(
            address(registry),
            address(externalSubject),
            address(v3Factory),
            address(v3PositionManager),
            address(v4PositionManager),
            address(v4StateView),
            address(permit2),
            PROTOCOL_RECIPIENT,
            _swapApprovalLeaf()
        );

        assertEq(externalManager.subject(), address(externalSubject));
        assertEq(
            externalManager.projectId(),
            ProjectIds.derive(block.chainid, address(registry), address(externalSubject))
        );
    }

    function testRejectsExternalSubjectThatPartiallyDeclaresProjectIdentity() public {
        PartialProjectIdentityLiquidityAsset partialAsset =
            new PartialProjectIdentityLiquidityAsset(address(registry));
        partialAsset.mint(address(this), 1_000_000e18);

        vm.expectPartialRevert(ProjectLiquidityManagerV2.InvalidSubject.selector);
        new ProjectLiquidityManagerV2(
            address(registry),
            address(partialAsset),
            address(v3Factory),
            address(v3PositionManager),
            address(v4PositionManager),
            address(v4StateView),
            address(permit2),
            PROTOCOL_RECIPIENT,
            _swapApprovalLeaf()
        );
    }

    function testRejectsSubjectThatDeclaresWrongProjectIdentity() public {
        MockRegistry otherRegistry = new MockRegistry();
        MockProjectToken wrongSubject =
            new MockProjectToken(address(otherRegistry), address(this), 1_000_000e18);

        vm.expectPartialRevert(ProjectLiquidityManagerV2.InvalidSubject.selector);
        new ProjectLiquidityManagerV2(
            address(registry),
            address(wrongSubject),
            address(v3Factory),
            address(v3PositionManager),
            address(v4PositionManager),
            address(v4StateView),
            address(permit2),
            PROTOCOL_RECIPIENT,
            _swapApprovalLeaf()
        );
    }

    function testFundingRejectsWrongProjectOrSubjectBeforeTransfer() public {
        bytes32 canonicalProjectId = subject.projectId();
        vm.expectPartialRevert(ProjectLiquidityManagerV2.InvalidFundingIdentity.selector);
        manager.fund(
            bytes32(uint256(1)), address(subject), address(quote), 10_000, _fundingData(_v3Config())
        );
        vm.expectPartialRevert(ProjectLiquidityManagerV2.InvalidFundingIdentity.selector);
        manager.fund(
            canonicalProjectId, address(quote), address(quote), 10_000, _fundingData(_v3Config())
        );
        assertEq(quote.balanceOf(address(manager)), 0);
    }

    function testBurnAddressCannotReceiveProtocolOrProjectFees() public {
        vm.expectRevert(ProjectLiquidityManagerV2.InvalidAddress.selector);
        new ProjectLiquidityManagerV2(
            address(registry),
            address(subject),
            address(v3Factory),
            address(v3PositionManager),
            address(v4PositionManager),
            address(v4StateView),
            address(permit2),
            SinjohV2Constants.BURN_ADDRESS,
            _swapApprovalLeaf()
        );

        ProjectLiquidityManagerV2.Config memory config = _v3Config();
        config.feeMode = ProjectLiquidityManagerV2.FeeMode.CREATOR;
        config.feeRecipient = SinjohV2Constants.BURN_ADDRESS;
        bytes32 canonicalProjectId = subject.projectId();
        vm.expectRevert(ProjectLiquidityManagerV2.InvalidConfiguration.selector);
        manager.fund(
            canonicalProjectId, address(subject), address(quote), 10_000, _fundingData(config)
        );
    }

    function testSeparateTransferCannotCreateCredit() public {
        assertTrue(quote.transfer(address(manager), 500));
        bytes32 id = _fundV3(10_000, ProjectLiquidityManagerV2.FeeMode.RECYCLE);
        (uint256 pendingQuote,,,,) = manager.accountFinancials(id);
        assertEq(pendingQuote, 10_000);
        assertEq(manager.totalLiability(address(quote)), 10_000);
        assertEq(quote.balanceOf(address(manager)), 10_500);
    }

    function testFirstFundingFreezesConfigAndStatusIsOneCallDiscoverable() public {
        ProjectLiquidityManagerV2.Config memory config = _v3Config();
        _fund(config, 100);
        _fund(config, 100);
        bytes32 id = manager.projectAccountId(address(this));
        ProjectLiquidityManagerV2.Account memory status = manager.accountStatus(id);
        assertTrue(status.configured);
        assertEq(status.funder, address(this));
        assertEq(status.subject, address(subject));
        assertEq(status.pendingQuote, 200);
        assertEq(status.configHash, keccak256(_fundingData(config)));

        config.quoteSwapBps = 4_999;
        bytes32 canonicalProjectId = subject.projectId();
        vm.expectRevert(ProjectLiquidityManagerV2.ConfigurationMismatch.selector);
        manager.fund(
            canonicalProjectId, address(subject), address(quote), 100, _fundingData(config)
        );
        assertEq(manager.accountStatus(id).pendingQuote, 200);
    }

    function testMissingPoolLeavesExactCreditForPermissionlessRetry() public {
        bytes32 id = _fundV3(10_000, ProjectLiquidityManagerV2.FeeMode.RECYCLE);
        v3Factory.setPool(address(0));
        vm.expectRevert(ProjectLiquidityManagerV2.PoolNotInitialized.selector);
        manager.mint(address(this), address(subject), 10_000, 5_000, "");
        ProjectLiquidityManagerV2.Account memory status = manager.accountStatus(id);
        assertEq(status.pendingQuote, 10_000);
        assertEq(status.pendingSubject, 0);
        assertEq(status.positionId, 0);
        assertEq(manager.totalLiability(address(quote)), 10_000);
    }

    function testUnsolicitedPositionNftIsAlwaysRejected() public {
        vm.expectRevert(ProjectLiquidityManagerV2.UnexpectedNFT.selector);
        manager.onERC721Received(address(this), address(this), 1, "");
    }

    function testFeeOnTransferFundingRevertsWithoutCredit() public {
        quote.setFeeBps(100);
        bytes32 canonicalProjectId = subject.projectId();
        vm.expectPartialRevert(ProjectLiquidityManagerV2.UnexpectedBalanceDelta.selector);
        manager.fund(
            canonicalProjectId, address(subject), address(quote), 10_000, _fundingData(_v3Config())
        );
        bytes32 id = manager.accountId(address(this), address(subject));
        (uint256 pendingQuote,,,, bool configured) = manager.accountFinancials(id);
        assertEq(pendingQuote, 0);
        assertTrue(!configured);
        assertEq(quote.balanceOf(address(manager)), 0);
    }

    function testSelfFeeRecipientIsRejectedBeforeFunding() public {
        ProjectLiquidityManagerV2.Config memory config = _v3Config();
        config.feeMode = ProjectLiquidityManagerV2.FeeMode.TREASURY;
        config.feeRecipient = address(manager);

        bytes32 canonicalProjectId = subject.projectId();
        vm.expectPartialRevert(ProjectLiquidityManagerV2.InvalidConfiguration.selector);
        manager.fund(
            canonicalProjectId, address(subject), address(quote), 10_000, _fundingData(config)
        );
    }

    function testV3MintsOnceThenIncreasesAndKeepsResidualCredit() public {
        bytes32 id = _fundV3(20_000, ProjectLiquidityManagerV2.FeeMode.RECYCLE);
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
        assertEq(quote.allowance(address(manager), address(adapter)), 0);
        assertEq(quote.allowance(address(manager), address(v3PositionManager)), 0);
        assertEq(subject.allowance(address(manager), address(v3PositionManager)), 0);
    }

    function testV3AcceptsPonsDirectMintAfterCanonicalOwnershipCheck() public {
        v3PositionManager.setUseSafeMintCallback(false);
        bytes32 id = _fundV3(10_000, ProjectLiquidityManagerV2.FeeMode.RECYCLE);

        (uint256 tokenId,) = manager.mint(address(this), address(subject), 10_000, 5_000, "");

        (,, uint256 storedTokenId,,) = manager.accountFinancials(id);
        assertEq(storedTokenId, tokenId);
        assertEq(v3PositionManager.ownerOf(tokenId), address(manager));
    }

    function testWeakCallerMinimumAndManipulatedSpotCannotBypassGuard() public {
        bytes32 id = _fundV3(10_000, ProjectLiquidityManagerV2.FeeMode.RECYCLE);
        guard.setMinimum(5_001);

        vm.expectPartialRevert(ProjectLiquidityManagerV2.InsufficientOutput.selector);
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
        bytes32 id = _fundV3(10_000, ProjectLiquidityManagerV2.FeeMode.RECYCLE);
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
        bytes32 idA = _fundV3(10_000, ProjectLiquidityManagerV2.FeeMode.RECYCLE);
        quote.mint(FUNDER_B, 10_000);
        vm.startPrank(FUNDER_B);
        quote.approve(address(manager), type(uint256).max);
        ProjectLiquidityManagerV2.Config memory config = _v3Config();
        manager.fund(
            subject.projectId(), address(subject), address(quote), 10_000, _fundingData(config)
        );
        vm.stopPrank();
        bytes32 idB = manager.accountId(FUNDER_B, address(subject));

        manager.mint(address(this), address(subject), 10_000, 5_000, "");
        vm.prank(address(0xCA11));
        manager.mint(FUNDER_B, address(subject), 10_000, 5_000, "");

        (,, uint256 positionA,,) = manager.accountFinancials(idA);
        (,, uint256 positionB,,) = manager.accountFinancials(idB);
        assertTrue(positionA != 0 && positionB != 0 && positionA != positionB);
    }

    function testFeeCollectionDoesNotDecreasePrincipalAndCanDeliver() public {
        bytes32 id = _fundV3(10_000, ProjectLiquidityManagerV2.FeeMode.TREASURY);
        (uint256 tokenId,) = manager.mint(address(this), address(subject), 10_000, 5_000, "");
        uint128 principalBefore = v3PositionManager.liquidity(tokenId);

        address token0 = v3PositionManager.token0(tokenId);
        address token1 = v3PositionManager.token1(tokenId);
        IMintableLiquidityAsset(token0).mint(address(v3PositionManager), 100);
        IMintableLiquidityAsset(token1).mint(address(v3PositionManager), 200);
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

    function testSplitFeeCollectionsCarryProtocolFeeRemaindersPerAsset() public {
        _fundV3(10_000, ProjectLiquidityManagerV2.FeeMode.TREASURY);
        (uint256 tokenId,) = manager.mint(address(this), address(subject), 10_000, 5_000, "");

        address token0 = v3PositionManager.token0(tokenId);
        address token1 = v3PositionManager.token1(tokenId);
        IMintableLiquidityAsset(token0).mint(address(v3PositionManager), 50);
        IMintableLiquidityAsset(token1).mint(address(v3PositionManager), 50);
        v3PositionManager.setFees(tokenId, 50, 50);
        manager.collect(address(this), address(subject));

        assertEq(manager.protocolOwed(address(quote)), 0);
        assertEq(manager.protocolOwed(address(subject)), 0);
        assertEq(manager.protocolFeeRemainder(address(quote)), 5_000);
        assertEq(manager.protocolFeeRemainder(address(subject)), 5_000);

        IMintableLiquidityAsset(token0).mint(address(v3PositionManager), 50);
        IMintableLiquidityAsset(token1).mint(address(v3PositionManager), 50);
        v3PositionManager.setFees(tokenId, 50, 50);
        manager.collect(address(this), address(subject));

        assertEq(manager.feeOwed(TREASURY, address(quote)), 99);
        assertEq(manager.feeOwed(TREASURY, address(subject)), 99);
        assertEq(manager.protocolOwed(address(quote)), 1);
        assertEq(manager.protocolOwed(address(subject)), 1);
        assertEq(manager.protocolFeeRemainder(address(quote)), 0);
        assertEq(manager.protocolFeeRemainder(address(subject)), 0);
    }

    function testProtocolFeeCannotBeAvoidedBySplittingAcrossAccounts() public {
        _fundV3(10_000, ProjectLiquidityManagerV2.FeeMode.TREASURY);
        (uint256 firstTokenId,) = manager.mint(address(this), address(subject), 10_000, 5_000, "");

        ProjectLiquidityManagerV2.Config memory config = _v3Config();
        config.feeMode = ProjectLiquidityManagerV2.FeeMode.TREASURY;
        config.feeRecipient = TREASURY;
        quote.mint(FUNDER_B, 10_000);
        vm.startPrank(FUNDER_B);
        quote.approve(address(manager), type(uint256).max);
        manager.fund(
            subject.projectId(), address(subject), address(quote), 10_000, _fundingData(config)
        );
        vm.stopPrank();
        (uint256 secondTokenId,) = manager.mint(FUNDER_B, address(subject), 10_000, 5_000, "");

        _setQuoteFees(firstTokenId, 50);
        manager.collect(address(this), address(subject));
        assertEq(manager.protocolOwed(address(quote)), 0);
        assertEq(manager.protocolFeeRemainder(address(quote)), 5_000);

        _setQuoteFees(secondTokenId, 50);
        manager.collect(FUNDER_B, address(subject));
        assertEq(manager.protocolOwed(address(quote)), 1);
        assertEq(manager.protocolFeeRemainder(address(quote)), 0);
        assertEq(manager.feeOwed(TREASURY, address(quote)), 99);
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
        assertEq(quote.allowance(address(manager), address(adapter)), 0);
        assertEq(quote.allowance(address(manager), address(permit2)), 0);
        assertEq(subject.allowance(address(manager), address(permit2)), 0);
        assertEq(permit2.allowance(address(manager), address(quote), address(v4PositionManager)), 0);
        assertEq(
            permit2.allowance(address(manager), address(subject), address(v4PositionManager)), 0
        );
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
        ProjectLiquidityManagerV2.Config memory config = _v4Config(address(0));
        vm.deal(address(this), 10 ether);
        manager.fund{ value: 10 ether }(
            subject.projectId(), address(subject), address(0), 10 ether, _fundingData(config)
        );
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

    function _fundV3(uint256 amount, ProjectLiquidityManagerV2.FeeMode mode)
        internal
        returns (bytes32 id)
    {
        ProjectLiquidityManagerV2.Config memory config = _v3Config();
        config.feeMode = mode;
        config.feeRecipient =
            mode == ProjectLiquidityManagerV2.FeeMode.TREASURY ? TREASURY : address(0);
        _fund(config, amount);
        id = manager.accountId(address(this), address(subject));
    }

    function _setQuoteFees(uint256 tokenId, uint256 amount) internal {
        quote.mint(address(v3PositionManager), amount);
        if (v3PositionManager.token0(tokenId) == address(quote)) {
            v3PositionManager.setFees(tokenId, amount, 0);
        } else {
            v3PositionManager.setFees(tokenId, 0, amount);
        }
    }

    function _fundV4Token(uint256 amount) internal returns (bytes32 id) {
        _fund(_v4Config(address(quote)), amount);
        id = manager.accountId(address(this), address(subject));
    }

    function _v3Config() internal view returns (ProjectLiquidityManagerV2.Config memory config) {
        config = ProjectLiquidityManagerV2.Config({
            venue: ProjectLiquidityManagerV2.Venue.UNISWAP_V3,
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
            feeMode: ProjectLiquidityManagerV2.FeeMode.RECYCLE,
            feeRecipient: address(0)
        });
    }

    function _fund(ProjectLiquidityManagerV2.Config memory config, uint256 amount) internal {
        manager.fund(
            subject.projectId(), address(subject), config.quoteAsset, amount, _fundingData(config)
        );
    }

    function _fundingData(ProjectLiquidityManagerV2.Config memory config)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(
            ProjectLiquidityManagerV2.FundingConfig({
                config: config, integrationApprovalProof: new bytes32[](0)
            })
        );
    }

    function _swapApprovalLeaf() internal view returns (bytes32) {
        bytes32 inner = keccak256(
            abi.encode(
                keccak256("SINJOH_V2_SWAP_INTEGRATION_APPROVAL"),
                block.chainid,
                address(adapter),
                address(adapter).codehash,
                address(guard),
                address(guard).codehash
            )
        );
        return keccak256(bytes.concat(inner));
    }

    function _v4Config(address quoteAsset)
        internal
        view
        returns (ProjectLiquidityManagerV2.Config memory config)
    {
        config = ProjectLiquidityManagerV2.Config({
            venue: ProjectLiquidityManagerV2.Venue.UNISWAP_V4,
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
            feeMode: ProjectLiquidityManagerV2.FeeMode.RECYCLE,
            feeRecipient: address(0)
        });
    }
}
