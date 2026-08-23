// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { Test } from "forge-std/Test.sol";
import {
    UniswapV3FundingBandPositionAdapter
} from "../../src/bands/UniswapV3FundingBandPositionAdapter.sol";
import { MockERC20 } from "../mocks/liquidity/MockERC20.sol";
import {
    MockV3BandFactory,
    MockV3BandPool,
    MockV3BandPositionManager
} from "../mocks/MockUniswapV3BandPosition.sol";

contract UniswapV3FundingBandPositionAdapterTest is Test, IERC721Receiver {
    MockERC20 private subject;
    MockERC20 private quote;
    MockV3BandFactory private factory;
    MockV3BandPool private pool;
    MockV3BandPositionManager private manager;
    UniswapV3FundingBandPositionAdapter private adapter;

    function setUp() public {
        subject = new MockERC20("Subject", "SUB");
        quote = new MockERC20("Quote", "USD");
        factory = new MockV3BandFactory();
        address token0 = address(subject) < address(quote) ? address(subject) : address(quote);
        address token1 = address(subject) < address(quote) ? address(quote) : address(subject);
        pool = new MockV3BandPool(address(factory), token0, token1, 3_000, 10);
        factory.setPool(token0, token1, 3_000, address(pool));
        manager = new MockV3BandPositionManager(address(factory));
        adapter = new UniswapV3FundingBandPositionAdapter(
            address(this),
            address(subject),
            address(quote),
            address(pool),
            address(factory),
            address(manager)
        );
        pool.setCurrentTick(address(subject) == token0 ? int24(0) : int24(300));
        subject.mint(address(this), 1_000);
        subject.approve(address(adapter), type(uint256).max);
    }

    function testOpenIncreaseAndFullExitUseOnlyBoundBandsAndCanonicalPosition() public {
        (uint256 positionId, uint128 liquidity, uint256 residual) = adapter.open(1, 100, 100, 200);
        assertEq(positionId, 1);
        assertEq(liquidity, 90);
        assertEq(residual, 10);
        assertEq(manager.ownerOf(positionId), address(this));
        assertEq(adapter.positionBand(positionId), 1);
        assertEq(adapter.positionLiquidity(positionId), 90);
        assertEq(subject.allowance(address(adapter), address(manager)), 0);

        (uint128 added, uint256 increaseResidual) = adapter.increase(positionId, 50);
        assertEq(added, 45);
        assertEq(increaseResidual, 5);
        assertEq(adapter.positionLiquidity(positionId), 135);
        assertEq(subject.allowance(address(adapter), address(manager)), 0);

        uint128 settlementSubject = 5;
        uint128 settlementQuote = 200;
        if (address(subject) < address(quote)) {
            manager.setSettlement(settlementSubject, settlementQuote);
        } else {
            manager.setSettlement(settlementQuote, settlementSubject);
        }
        quote.mint(address(manager), settlementQuote);
        manager.approve(address(adapter), positionId);
        pool.setCurrentTick(address(subject) < address(quote) ? int24(200) : int24(99));
        uint256 subjectBefore = subject.balanceOf(address(this));
        uint256 quoteBefore = quote.balanceOf(address(this));
        (address[] memory assets, uint256[] memory amounts) =
            adapter.exitAll(positionId, address(this));

        assertLt(uint160(assets[0]), uint160(assets[1]));
        assertEq(amounts[0], assets[0] == address(subject) ? settlementSubject : settlementQuote);
        assertEq(amounts[1], assets[1] == address(subject) ? settlementSubject : settlementQuote);
        assertEq(subject.balanceOf(address(this)) - subjectBefore, settlementSubject);
        assertEq(quote.balanceOf(address(this)) - quoteBefore, settlementQuote);
        assertEq(adapter.positionLiquidity(positionId), 0);
        assertEq(adapter.positionBand(positionId), 0);
        vm.expectRevert();
        manager.ownerOf(positionId);
    }

    function testRejectsWrongCallerTicksAndFeeOnTransferInventory() public {
        vm.prank(address(0xBEEF));
        vm.expectPartialRevert(UniswapV3FundingBandPositionAdapter.OnlyBands.selector);
        adapter.open(1, 100, 100, 200);

        vm.expectPartialRevert(UniswapV3FundingBandPositionAdapter.InvalidTicks.selector);
        adapter.open(1, 100, 101, 200);

        subject.setFeeBps(100);
        vm.expectPartialRevert(UniswapV3FundingBandPositionAdapter.InexactAssetReceipt.selector);
        adapter.open(1, 100, 100, 200);
    }

    function testRejectsPositionThatIsNotOneSidedSubjectInventory() public {
        pool.setCurrentTick(150);
        vm.expectPartialRevert(UniswapV3FundingBandPositionAdapter.PositionNotOneSided.selector);
        adapter.open(1, 100, 100, 200);
    }

    function testRejectsExitUntilPositionIsFullyOnQuoteSide() public {
        (uint256 positionId,,) = adapter.open(1, 100, 100, 200);
        manager.approve(address(adapter), positionId);

        vm.expectPartialRevert(UniswapV3FundingBandPositionAdapter.PositionNotConverted.selector);
        adapter.exitAll(positionId, address(this));
    }

    function onERC721Received(address, address, uint256, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return IERC721Receiver.onERC721Received.selector;
    }
}
