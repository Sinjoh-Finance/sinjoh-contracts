// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { SinjohRevenueCollector } from "../src/SinjohRevenueCollector.sol";
import { InvariantTestBase } from "./TestBase.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";

contract RevenueCollectorHandler {
    SinjohRevenueCollector public immutable collector;
    MockERC20 public immutable token;

    uint256 public totalMinted;

    constructor(SinjohRevenueCollector collector_, MockERC20 token_) {
        collector = collector_;
        token = token_;
    }

    function depositAndForward(uint256 rawAmount) external {
        uint256 amount = (rawAmount % 1_000_000 ether) + 1;
        totalMinted += amount;
        token.mint(address(collector), amount);
        collector.forwardAll(address(token));
    }
}

contract SinjohRevenueCollectorInvariantTest is InvariantTestBase {
    address internal constant GOVERNANCE = address(0xA11CE);
    address internal constant PROCESSOR = address(0xBEEF);

    SinjohRevenueCollector internal collector;
    MockERC20 internal token;
    RevenueCollectorHandler internal handler;

    function setUp() public {
        collector = new SinjohRevenueCollector(GOVERNANCE, PROCESSOR);
        token = new MockERC20();
        handler = new RevenueCollectorHandler(collector, token);
        _targetedContracts.push(address(handler));
    }

    function invariantEveryMintedTokenIsDeliveredExactly() public view {
        assertEq(token.balanceOf(address(collector)), 0);
        assertEq(token.balanceOf(PROCESSOR), handler.totalMinted());
        assertEq(token.totalSupply(), handler.totalMinted());
    }

    function invariantProcessorRemainsFixed() public view {
        assertEq(collector.processor(), PROCESSOR);
        assertEq(collector.owner(), GOVERNANCE);
    }
}
