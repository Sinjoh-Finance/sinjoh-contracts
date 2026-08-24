// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
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

interface IMintableInvariantAsset {
    function mint(address recipient, uint256 amount) external;
}

contract LiquidityHandler {
    MockProjectToken public immutable subject;
    MockERC20 public immutable quote;
    ProjectLiquidityManagerV2 public immutable manager;
    MockV3PositionManager public immutable v3PositionManager;
    bytes32 public immutable id;
    uint256 public totalQuoteFeesCollected;
    uint256 public totalSubjectFeesCollected;
    bytes internal _config;

    constructor(
        MockProjectToken subject_,
        MockERC20 quote_,
        ProjectLiquidityManagerV2 manager_,
        MockV3PositionManager v3PositionManager_,
        MockSwapAdapter adapter,
        MockPriceGuard guard
    ) {
        subject = subject_;
        quote = quote_;
        manager = manager_;
        v3PositionManager = v3PositionManager_;
        id = manager.accountId(address(this), address(subject));
        quote.approve(address(manager), type(uint256).max);
        _config = abi.encode(
            ProjectLiquidityManagerV2.FundingConfig({
                config: ProjectLiquidityManagerV2.Config({
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
                }),
                integrationApprovalProof: new bytes32[](0)
            })
        );
    }

    function fund(uint96 rawAmount) external {
        uint256 amount = uint256(rawAmount) % 1e24 + 1;
        quote.mint(address(this), amount);
        manager.fund(subject.projectId(), address(subject), address(quote), amount, _config);
    }

    function mint(uint96 rawNotional) external {
        (uint256 pendingQuote,,,,) = manager.accountFinancials(id);
        if (pendingQuote < 100) return;
        uint256 notional = uint256(rawNotional) % (pendingQuote - 99) + 100;
        manager.mint(address(this), address(subject), notional, 1, "");
    }

    function collectFees(uint96 rawQuoteAmount, uint96 rawSubjectAmount) external {
        (,, uint256 tokenId,,) = manager.accountFinancials(id);
        if (tokenId == 0) return;
        uint256 quoteAmount = uint256(rawQuoteAmount) % 1e18 + 1;
        uint256 subjectAmount = uint256(rawSubjectAmount) % 1e18 + 1;
        address token0 = v3PositionManager.token0(tokenId);
        uint256 amount0 = token0 == address(quote) ? quoteAmount : subjectAmount;
        uint256 amount1 = token0 == address(quote) ? subjectAmount : quoteAmount;
        IMintableInvariantAsset(token0).mint(address(v3PositionManager), amount0);
        IMintableInvariantAsset(v3PositionManager.token1(tokenId))
            .mint(address(v3PositionManager), amount1);
        // Both values are capped below 1e18 and therefore fit uint128.
        // forge-lint: disable-next-line(unsafe-typecast)
        v3PositionManager.setFees(tokenId, uint128(amount0), uint128(amount1));
        manager.collect(address(this), address(subject));
        totalQuoteFeesCollected += quoteAmount;
        totalSubjectFeesCollected += subjectAmount;
    }
}

contract ProjectLiquidityManagerV2InvariantTest is Test {
    MockRegistry internal registry;
    MockProjectToken internal subject;
    MockERC20 internal quote;
    ProjectLiquidityManagerV2 internal manager;
    LiquidityHandler internal handler;
    bytes32 internal id;

    function setUp() public {
        registry = new MockRegistry();
        subject = new MockProjectToken(address(registry), address(this), 0);
        quote = new MockERC20("Quote", "Q");
        MockPriceGuard guard = new MockPriceGuard();
        MockSwapAdapter adapter = new MockSwapAdapter();
        MockV3Pool pool = new MockV3Pool();
        MockV3Factory factory = new MockV3Factory();
        factory.setPool(address(pool));
        MockV3PositionManager v3PositionManager = new MockV3PositionManager();
        MockPermit2 permit2 = new MockPermit2();
        MockV4PositionManager v4PositionManager = new MockV4PositionManager(permit2);
        MockV4StateView stateView = new MockV4StateView();
        bytes32 approvalRoot = _swapApprovalLeaf(address(adapter), address(guard));
        manager = new ProjectLiquidityManagerV2(
            address(registry),
            address(subject),
            address(factory),
            address(v3PositionManager),
            address(v4PositionManager),
            address(stateView),
            address(permit2),
            address(0xFEE1),
            approvalRoot
        );
        handler = new LiquidityHandler(subject, quote, manager, v3PositionManager, adapter, guard);
        subject.mint(address(adapter), type(uint128).max);
        id = handler.id();
        targetContract(address(handler));
    }

    function _swapApprovalLeaf(address adapter, address guard) private view returns (bytes32) {
        bytes32 inner = keccak256(
            abi.encode(
                keccak256("SINJOH_V2_SWAP_INTEGRATION_APPROVAL"),
                block.chainid,
                adapter,
                adapter.codehash,
                guard,
                guard.codehash
            )
        );
        return keccak256(bytes.concat(inner));
    }

    function invariantLiquidLiabilitiesNeverExceedBalances() public view {
        assertTrue(manager.totalLiability(address(quote)) <= quote.balanceOf(address(manager)));
        assertTrue(manager.totalLiability(address(subject)) <= subject.balanceOf(address(manager)));
    }

    function invariantAggregateEqualsDetailedAccountCredits() public view {
        (uint256 pendingQuote, uint256 pendingSubject,,,) = manager.accountFinancials(id);
        assertEq(
            manager.totalLiability(address(quote)),
            pendingQuote + manager.protocolOwed(address(quote))
        );
        assertEq(
            manager.totalLiability(address(subject)),
            pendingSubject + manager.protocolOwed(address(subject))
        );
    }

    function invariantProtocolFeesEqualOnePercentOfCumulativeCollections() public view {
        assertEq(
            manager.protocolOwed(address(quote)),
            handler.totalQuoteFeesCollected() * manager.PROTOCOL_FEE_BPS() / manager.BPS()
        );
        assertEq(
            manager.protocolOwed(address(subject)),
            handler.totalSubjectFeesCollected() * manager.PROTOCOL_FEE_BPS() / manager.BPS()
        );
    }

    function invariantProjectBindingNeverChanges() public view {
        assertEq(manager.registry(), address(registry));
        assertEq(manager.subject(), address(subject));
        assertEq(manager.projectId(), subject.projectId());
    }
}
