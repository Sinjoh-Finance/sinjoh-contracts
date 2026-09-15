// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IPriceHub} from "../interfaces/IPriceHub.sol";
import {IYieldBankV3Pool} from "../interfaces/IYieldBankV3.sol";
import {IDeltaPositionBuilder} from "../interfaces/IDeltaPositionBuilder.sol";
import {DeltaV3SinglePoolRoute} from "../adapters/DeltaV3SinglePoolRoute.sol";

interface ISeedWeth { function deposit() external payable; }
interface ISeedPool { function initialize(uint160) external; }

/// @notice One-use atomic bootstrap funded solely by the deployment account.
/// There are no callable asset-management methods or permissions over a bank.
/// Prices, swap proceeds, approvals and mint deadline are resolved in the same
/// transaction, so an earlier dry-run cannot freeze them into deployment calldata.
contract AirdropInfrastructureSeed {
    using SafeERC20 for IERC20;
    uint256 public immutable positionId;
    error InvalidSeed();

    constructor(
        address pool,
        address referencePool,
        IDeltaPositionBuilder builder,
        DeltaV3SinglePoolRoute route,
        IPriceHub hub,
        address governance,
        address refund
    ) payable {
        address weth = route.inputAsset();
        address cashToken = route.outputAsset();
        if (
            msg.value != 0.01 ether || governance == address(0) || refund == address(0)
                || address(route.pool()) != referencePool || builder.weth() != weth
                || IYieldBankV3Pool(pool).token0() != weth
                || IYieldBankV3Pool(pool).token1() != cashToken
                || IYieldBankV3Pool(pool).factory() != builder.uniFactory()
                || IYieldBankV3Pool(pool).fee() != 100
                || IYieldBankV3Pool(pool).liquidity() != 0
                || IERC20Metadata(weth).decimals() != 18
                || IERC20Metadata(cashToken).decimals() != 6
        ) revert InvalidSeed();
        (uint160 initial,,,,,,) = IYieldBankV3Pool(pool).slot0();
        if (initial != 0) revert InvalidSeed();
        (uint256 wethPrice,, IPriceHub.FailureReason wf) = hub.quoteUsd18(weth);
        (uint256 cashPrice,, IPriceHub.FailureReason cf) = hub.quoteUsd18(cashToken);
        if (wf != IPriceHub.FailureReason.NONE || cf != IPriceHub.FailureReason.NONE) {
            revert InvalidSeed();
        }
        // The deployed registration pair is WETH (18) / USDG (6).
        uint256 minimum = Math.mulDiv(
            Math.mulDiv(0.005 ether, wethPrice, 1 ether), 1e6, cashPrice
        ) * 9900 / 10000;
        ISeedWeth(weth).deposit{value: msg.value}();
        IERC20(weth).forceApprove(address(route), 0.005 ether);
        uint256 cash = route.convert(0.005 ether, minimum, address(this), "");
        IERC20(weth).forceApprove(address(route), 0);
        (uint160 sqrtPrice, int24 tick,,,,,) = IYieldBankV3Pool(referencePool).slot0();
        ISeedPool(pool).initialize(sqrtPrice);
        IERC20(weth).forceApprove(address(builder), 0.005 ether);
        IERC20(cashToken).forceApprove(address(builder), cash);
        IDeltaPositionBuilder.Rung[] memory rungs = new IDeltaPositionBuilder.Rung[](1);
        rungs[0] = IDeltaPositionBuilder.Rung(tick - 1000, tick + 1000, 0.005 ether, cash, 1, 1);
        uint256[] memory ids = builder.mintLadder(pool, rungs, tick - 1, tick + 1, block.timestamp);
        if (ids.length != 1 || IYieldBankV3Pool(pool).liquidity() == 0) revert InvalidSeed();
        positionId = ids[0];
        IERC20(weth).forceApprove(address(builder), 0);
        IERC20(cashToken).forceApprove(address(builder), 0);
        IERC721(builder.positionManager()).transferFrom(address(this), governance, ids[0]);
        uint256 remainder = IERC20(weth).balanceOf(address(this));
        if (remainder != 0) IERC20(weth).safeTransfer(refund, remainder);
        remainder = IERC20(cashToken).balanceOf(address(this));
        if (remainder != 0) IERC20(cashToken).safeTransfer(refund, remainder);
    }
}
