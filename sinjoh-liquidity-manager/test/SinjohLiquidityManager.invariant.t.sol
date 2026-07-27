// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { InvariantTestBase } from "./TestBase.sol";
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

contract LiquidityHandler {
    MockERC20 public immutable subject;
    MockERC20 public immutable quote;
    SinjohLiquidityManager public immutable manager;
    bytes32 public immutable id;
    bytes internal _config;

    constructor(
        MockERC20 subject_,
        MockERC20 quote_,
        SinjohLiquidityManager manager_,
        MockSwapAdapter adapter,
        MockPriceGuard guard
    ) {
        subject = subject_;
        quote = quote_;
        manager = manager_;
        id = manager.accountId(address(this), address(subject));
        quote.approve(address(manager), type(uint256).max);
        _config = abi.encode(
            SinjohLiquidityManager.Config({
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
            })
        );
    }

    function fund(uint96 rawAmount) external {
        uint256 amount = uint256(rawAmount) % 1e24 + 1;
        quote.mint(address(this), amount);
        manager.fund(address(subject), address(quote), amount, _config);
    }

    function mint(uint96 rawNotional) external {
        (uint256 pendingQuote,,,,) = manager.accountFinancials(id);
        if (pendingQuote < 100) return;
        uint256 notional = uint256(rawNotional) % (pendingQuote - 99) + 100;
        manager.mint(address(this), address(subject), notional, 1, "");
    }
}

contract SinjohLiquidityManagerInvariantTest is InvariantTestBase {
    MockERC20 internal subject;
    MockERC20 internal quote;
    SinjohLiquidityManager internal manager;
    LiquidityHandler internal handler;
    bytes32 internal id;

    function setUp() public {
        subject = new MockERC20("Subject", "SUB");
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
        manager = new SinjohLiquidityManager(
            address(factory),
            address(v3PositionManager),
            address(v4PositionManager),
            address(stateView),
            address(permit2),
            address(0xFEE1)
        );
        handler = new LiquidityHandler(subject, quote, manager, adapter, guard);
        subject.mint(address(adapter), type(uint128).max);
        id = handler.id();
        _targetedContracts.push(address(handler));
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
}
