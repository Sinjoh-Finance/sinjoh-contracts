// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { DeltaV3SinglePoolRoute } from "../../src/yield-banks/adapters/DeltaV3SinglePoolRoute.sol";
import { MockDeltaV3Factory } from "../mocks/MockDeltaIntegrations.sol";
import { MockYieldBankAsset } from "../mocks/MockYieldBankIntegrations.sol";

interface IMockV3SwapCallback {
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data)
        external;
}

contract MockRouteV3Pool {
    address public immutable factory;
    address public immutable token0;
    address public immutable token1;
    uint24 public constant fee = 3_000;
    bool public partialFill;
    bool public omitCallback;
    bool public overchargeCallback;
    bool public malformedDeltas;

    constructor(address factory_, address token0_, address token1_) {
        factory = factory_;
        token0 = token0_;
        token1 = token1_;
    }

    function setBehavior(bool partialFill_, bool omitCallback_) external {
        partialFill = partialFill_;
        omitCallback = omitCallback_;
    }

    function setAdversarial(bool overchargeCallback_, bool malformedDeltas_) external {
        overchargeCallback = overchargeCallback_;
        malformedDeltas = malformedDeltas_;
    }

    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160,
        bytes calldata
    ) external returns (int256 amount0, int256 amount1) {
        require(zeroForOne && amountSpecified > 0, "direction");
        uint256 supplied = uint256(amountSpecified);
        uint256 consumed = partialFill ? supplied - 1 : supplied;
        uint256 output = consumed * 2;
        amount0 = int256(overchargeCallback ? supplied + 1 : consumed);
        amount1 = malformedDeltas ? int256(output) : -int256(output);
        if (!omitCallback) {
            IMockV3SwapCallback(msg.sender).uniswapV3SwapCallback(amount0, amount1, "");
        }
        MockYieldBankAsset(token1).mint(recipient, output);
    }
}

contract DeltaV3SinglePoolRouteTest is Test {
    MockYieldBankAsset private input;
    MockYieldBankAsset private output;
    MockDeltaV3Factory private factory;
    MockRouteV3Pool private pool;
    DeltaV3SinglePoolRoute private route;

    function setUp() external {
        input = new MockYieldBankAsset("Input", "IN");
        output = new MockYieldBankAsset("Output", "OUT");
        factory = new MockDeltaV3Factory();
        pool = new MockRouteV3Pool(address(factory), address(input), address(output));
        factory.setPool(address(input), address(output), pool.fee(), address(pool));
        route = new DeltaV3SinglePoolRoute(
            address(pool),
            address(factory),
            address(input),
            address(output),
            address(pool).codehash,
            address(factory).codehash
        );
        input.mint(address(this), 10e18);
        input.approve(address(route), type(uint256).max);
    }

    function testExactInputSwapMeasuresCallbackPaymentAndReceiverOutput() external {
        uint256 outputAmount = route.convert(1e18, 2e18, address(this), "");
        assertEq(outputAmount, 2e18);
        assertEq(input.balanceOf(address(pool)), 1e18);
        assertEq(input.balanceOf(address(route)), 0);
        assertEq(output.balanceOf(address(this)), 2e18);
    }

    function testRejectsPartialFillInsteadOfLeavingInputInRoute() external {
        pool.setBehavior(true, false);
        vm.expectRevert(
            abi.encodeWithSelector(DeltaV3SinglePoolRoute.InexactTransfer.selector, 1e18, 1e18 - 1)
        );
        route.convert(1e18, 1, address(this), "");
    }

    function testRejectsPoolThatDoesNotInvokeCallback() external {
        pool.setBehavior(false, true);
        vm.expectRevert(
            abi.encodeWithSelector(DeltaV3SinglePoolRoute.InvalidCallback.selector, address(pool))
        );
        route.convert(1e18, 1, address(this), "");
    }

    function testRejectsUnsolicitedCallback() external {
        vm.expectRevert(
            abi.encodeWithSelector(DeltaV3SinglePoolRoute.InvalidCallback.selector, address(this))
        );
        route.uniswapV3SwapCallback(1, -1, "");
    }

    function testRejectsCallbackThatRequestsMoreThanExactInput() external {
        pool.setAdversarial(true, false);
        vm.expectRevert(DeltaV3SinglePoolRoute.InvalidConfiguration.selector);
        route.convert(1e18, 1, address(this), "");
    }

    function testRejectsMalformedSwapDeltaSigns() external {
        pool.setAdversarial(false, true);
        vm.expectRevert(DeltaV3SinglePoolRoute.InvalidConfiguration.selector);
        route.convert(1e18, 1, address(this), "");
    }

    function testRejectsOutputBelowCallerMinimum() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                DeltaV3SinglePoolRoute.InsufficientOutput.selector, 2e18 + 1, 2e18
            )
        );
        route.convert(1e18, 2e18 + 1, address(this), "");
    }
}
