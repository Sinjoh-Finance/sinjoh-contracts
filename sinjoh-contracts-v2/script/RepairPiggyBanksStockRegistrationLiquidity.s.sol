// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Script } from "forge-std/Script.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { IPriceHub } from "../src/yield-banks/interfaces/IPriceHub.sol";
import { IYieldBankV3Pool } from "../src/yield-banks/interfaces/IYieldBankV3.sol";
import { IDeltaPositionBuilder } from "../src/yield-banks/interfaces/IDeltaPositionBuilder.sol";
import { DeltaV3SinglePoolRoute } from "../src/yield-banks/adapters/DeltaV3SinglePoolRoute.sol";
import {
    StockInfrastructureBuilder
} from "../src/yield-banks/stock/StockInfrastructureBuilder.sol";

interface IRegistrationRepairWETH {
    function deposit() external payable;
}

interface IRegistrationRepairNFT {
    function transferFrom(address, address, uint256) external;
}

/// @notice Adds permanent in-range liquidity to the already-live Stock registration pool.
contract RepairPiggyBanksStockRegistrationLiquidity is Script {
    address constant DEPLOYER = 0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49;
    address constant GOVERNANCE = 0x7C15804A2d7F5981035895CAb953e5E76393E1B8;
    address constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;
    address constant USDG = 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168;
    address constant CASH_POOL = 0x52e65B17fB6E5BA00Ed806f37Afcd2DaA50271Ca;
    address constant CASH_FACTORY = 0x1f7d7550B1b028f7571E69A784071F0205FD2EfA;
    address constant PRICE_HUB = 0xF83C528b5Fe315A224eEA98E084644e24d39C20A;
    address constant POOL = 0x8c2D9C7220a6B7109A98CD7d53dB9d1925F212eF;
    address constant FACTORY = 0x5a29C1206E19aF84b81D99ea7FD975719EFE5561;
    address constant MANAGER = 0xA9dB54cc423E4bE034eF2002b3Aa4baBF44fC23B;
    address constant BUILDER = 0xb8027834B0c8d75c10276FD17Cd0E9fB26449A60;

    function run() external returns (uint256 tokenId) {
        require(block.chainid == 4663, "wrong chain");
        require(IYieldBankV3Pool(POOL).factory() == FACTORY, "pool changed");
        require(StockInfrastructureBuilder(BUILDER).positionManager() == MANAGER, "manager changed");
        require(StockInfrastructureBuilder(BUILDER).uniFactory() == FACTORY, "factory changed");
        (, int24 tick,,,,,) = IYieldBankV3Pool(POOL).slot0();

        vm.startBroadcast(DEPLOYER);
        IRegistrationRepairWETH(WETH).deposit{ value: 0.01 ether }();
        DeltaV3SinglePoolRoute route = new DeltaV3SinglePoolRoute(
            CASH_POOL, CASH_FACTORY, WETH, USDG, CASH_POOL.codehash, CASH_FACTORY.codehash
        );
        (uint256 wethPrice,, IPriceHub.FailureReason wf) = IPriceHub(PRICE_HUB).quoteUsd18(WETH);
        (uint256 usdgPrice,, IPriceHub.FailureReason uf) = IPriceHub(PRICE_HUB).quoteUsd18(USDG);
        require(
            wf == IPriceHub.FailureReason.NONE && uf == IPriceHub.FailureReason.NONE,
            "price unavailable"
        );
        uint256 minimum = Math.mulDiv(Math.mulDiv(0.005 ether, wethPrice, 1 ether), 1e6, usdgPrice)
            * 9900 / 10000;
        IERC20(WETH).approve(address(route), 0.005 ether);
        uint256 cash = route.convert(0.005 ether, minimum, DEPLOYER, "");
        IERC20(WETH).approve(BUILDER, 0.005 ether);
        IERC20(USDG).approve(BUILDER, cash);
        IDeltaPositionBuilder.Rung[] memory rungs = new IDeltaPositionBuilder.Rung[](1);
        rungs[0] = IDeltaPositionBuilder.Rung(
            TickMath.MIN_TICK, TickMath.MAX_TICK, 0.005 ether, cash, 1, 1
        );
        uint256[] memory ids = StockInfrastructureBuilder(BUILDER)
            .mintLadder(POOL, rungs, tick - 1, tick + 1, block.timestamp + 15 minutes);
        tokenId = ids[0];
        IRegistrationRepairNFT(MANAGER).transferFrom(DEPLOYER, GOVERNANCE, tokenId);
        vm.stopBroadcast();
    }
}
