// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Base64 } from "@openzeppelin/contracts/utils/Base64.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { IDeltaPositionBuilder } from "../interfaces/IDeltaPositionBuilder.sol";
import {
    IYieldBankV3Pool,
    IYieldBankV3Factory,
    IYieldBankV3PositionManager
} from "../interfaces/IYieldBankV3.sol";
import { IntegrationBinding } from "../libraries/IntegrationBinding.sol";

interface IStockInfrastructureMint {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }
    function mint(MintParams calldata params)
        external
        payable
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
}

/// @notice Source-verifiable V3 position builder for a separately approved infrastructure graph.
/// @dev Canonical pools and actual position-manager mints; no simulated liquidity responses.
/// Existing LP positions continue using their original factory/manager/builder.
contract StockInfrastructureBuilder is IDeltaPositionBuilder, ReentrancyGuard {
    using SafeERC20 for IERC20;
    address public immutable positionManager;
    address public immutable uniFactory;
    address public immutable weth;
    bytes32 public immutable managerCodeHash;
    bytes32 public immutable factoryCodeHash;
    error InvalidConfiguration();
    error InexactTransfer();

    constructor(address factory_, address manager_, address weth_) {
        if (
            factory_.code.length == 0 || manager_.code.length == 0 || weth_.code.length == 0
                || IYieldBankV3PositionManager(manager_).factory() != factory_
                || IYieldBankV3PositionManager(manager_).WETH9() != weth_
        ) revert InvalidConfiguration();
        uniFactory = factory_;
        positionManager = manager_;
        weth = weth_;
        managerCodeHash = manager_.codehash;
        factoryCodeHash = factory_.codehash;
    }

    function mintLadder(
        address pool,
        Rung[] calldata rungs,
        int24 minTick,
        int24 maxTick,
        uint256 deadline
    ) external payable nonReentrant returns (uint256[] memory tokenIds) {
        IntegrationBinding.requireBound(positionManager, managerCodeHash);
        IntegrationBinding.requireBound(uniFactory, factoryCodeHash);
        if (
            msg.value != 0 || rungs.length == 0 || rungs.length > 64 || deadline < block.timestamp
                || deadline > block.timestamp + 30 minutes || minTick > maxTick
        ) revert InvalidConfiguration();
        IYieldBankV3Pool market = IYieldBankV3Pool(pool);
        address token0 = market.token0();
        address token1 = market.token1();
        uint24 fee = market.fee();
        (uint160 sqrtPrice, int24 tick,,,,, bool unlocked) = market.slot0();
        if (
            (token0 != weth && token1 != weth) || market.factory() != uniFactory
                || IYieldBankV3Factory(uniFactory).getPool(token0, token1, fee) != pool
                || sqrtPrice == 0 || !unlocked || tick < minTick || tick > maxTick
        ) revert InvalidConfiguration();
        uint256 amount0;
        uint256 amount1;
        for (uint256 i; i < rungs.length; ++i) {
            if (
                rungs[i].tickLower >= rungs[i].tickUpper
                    || (rungs[i].amount0 == 0 && rungs[i].amount1 == 0)
            ) revert InvalidConfiguration();
            amount0 += rungs[i].amount0;
            amount1 += rungs[i].amount1;
        }
        uint256 before0 = IERC20(token0).balanceOf(address(this));
        uint256 before1 = IERC20(token1).balanceOf(address(this));
        if (amount0 != 0) IERC20(token0).safeTransferFrom(msg.sender, address(this), amount0);
        if (amount1 != 0) IERC20(token1).safeTransferFrom(msg.sender, address(this), amount1);
        if (
            IERC20(token0).balanceOf(address(this)) != before0 + amount0
                || IERC20(token1).balanceOf(address(this)) != before1 + amount1
        ) revert InexactTransfer();
        IERC20(token0).forceApprove(positionManager, amount0);
        IERC20(token1).forceApprove(positionManager, amount1);
        tokenIds = new uint256[](rungs.length);
        for (uint256 i; i < rungs.length; ++i) {
            Rung calldata rung = rungs[i];
            (uint256 id, uint128 liquidity,,) = IStockInfrastructureMint(positionManager)
                .mint(
                    IStockInfrastructureMint.MintParams(
                        token0,
                        token1,
                        fee,
                        rung.tickLower,
                        rung.tickUpper,
                        rung.amount0,
                        rung.amount1,
                        rung.amount0Min,
                        rung.amount1Min,
                        msg.sender,
                        deadline
                    )
                );
            if (liquidity == 0) revert InvalidConfiguration();
            tokenIds[i] = id;
        }
        IERC20(token0).forceApprove(positionManager, 0);
        IERC20(token1).forceApprove(positionManager, 0);
        uint256 refund0 = IERC20(token0).balanceOf(address(this)) - before0;
        uint256 refund1 = IERC20(token1).balanceOf(address(this)) - before1;
        if (refund0 != 0) IERC20(token0).safeTransfer(msg.sender, refund0);
        if (refund1 != 0) IERC20(token1).safeTransfer(msg.sender, refund1);
        if (
            IERC20(token0).balanceOf(address(this)) != before0
                || IERC20(token1).balanceOf(address(this)) != before1
        ) revert InexactTransfer();
    }
}

/// @notice Minimal self-contained metadata for the infrastructure's ordinary V3 LP NFTs.
contract StockInfrastructurePositionDescriptor {
    function tokenURI(address, uint256 id) external pure returns (string memory) {
        return string.concat(
            "data:application/json;base64,",
            Base64.encode(
                bytes(
                    string.concat(
                        '{"name":"Sinjoh V3 liquidity #',
                        Strings.toString(id),
                        '","description":"Uniswap V3 liquidity position in the Sinjoh Stock infrastructure. This is not a Piggy Banks NFT."}'
                    )
                )
            )
        );
    }
}
