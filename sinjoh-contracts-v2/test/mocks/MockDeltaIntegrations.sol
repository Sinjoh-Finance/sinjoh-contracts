// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { SqrtPriceMath } from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import { LiquidityAmounts } from "@uniswap/v4-periphery/src/libraries/LiquidityAmounts.sol";
import { IDeltaPositionBuilder } from "../../src/yield-banks/interfaces/IDeltaPositionBuilder.sol";
import { IYieldBankV3PositionManager } from "../../src/yield-banks/interfaces/IYieldBankV3.sol";
import { MockYieldBankAsset } from "./MockYieldBankIntegrations.sol";

interface IMockDeltaPositionManager is IYieldBankV3PositionManager {
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

contract MockDeltaV3Factory {
    mapping(bytes32 key => address pool) private _pools;

    function setPool(address tokenA, address tokenB, uint24 fee, address pool) external {
        _pools[_key(tokenA, tokenB, fee)] = pool;
    }

    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address) {
        return _pools[_key(tokenA, tokenB, fee)];
    }

    function _key(address tokenA, address tokenB, uint24 fee) private pure returns (bytes32) {
        (address first, address second) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        return keccak256(abi.encode(first, second, fee));
    }
}

contract MockDeltaV3Pool {
    address public immutable token0;
    address public immutable token1;
    uint24 public immutable fee;
    int24 public immutable tickSpacing;
    uint160 public sqrtPriceX96 = uint160(1 << 96);
    int24 public tick;

    constructor(address token0_, address token1_, uint24 fee_, int24 tickSpacing_) {
        token0 = token0_;
        token1 = token1_;
        fee = fee_;
        tickSpacing = tickSpacing_;
    }

    function setPrice(uint160 sqrtPriceX96_, int24 tick_) external {
        sqrtPriceX96 = sqrtPriceX96_;
        tick = tick_;
    }

    function slot0() external view returns (uint160, int24, uint16, uint16, uint16, uint8, bool) {
        return (sqrtPriceX96, tick, 0, 0, 0, 0, true);
    }
}

contract MockDeltaV3PositionManager is ERC721, IMockDeltaPositionManager {
    using SafeERC20 for IERC20;

    struct Position {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        uint128 tokensOwed0;
        uint128 tokensOwed1;
    }

    address public immutable factory;
    address public immutable WETH9;
    MockDeltaV3Pool public immutable pool;
    uint256 private _nextTokenId = 1;
    mapping(uint256 tokenId => Position position) private _positions;

    constructor(address factory_, address weth_, address pool_) ERC721("Mock V3 Position", "MV3") {
        factory = factory_;
        WETH9 = weth_;
        pool = MockDeltaV3Pool(pool_);
    }

    function ownerOf(uint256 tokenId)
        public
        view
        override(ERC721, IYieldBankV3PositionManager)
        returns (address)
    {
        return super.ownerOf(tokenId);
    }

    function mint(MintParams calldata params)
        external
        payable
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        // Test deadlines intentionally exercise the production deadline field.
        // forge-lint: disable-next-line(block-timestamp)
        require(params.deadline >= block.timestamp, "expired");
        require(
            params.token0 == pool.token0() && params.token1 == pool.token1()
                && params.fee == pool.fee(),
            "pool"
        );
        uint160 sqrtPriceX96 = pool.sqrtPriceX96();
        liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(params.tickLower),
            TickMath.getSqrtPriceAtTick(params.tickUpper),
            params.amount0Desired,
            params.amount1Desired
        );
        (amount0, amount1) =
            _amountsForLiquidity(sqrtPriceX96, params.tickLower, params.tickUpper, liquidity);
        require(amount0 >= params.amount0Min && amount1 >= params.amount1Min, "minimum");
        if (amount0 != 0) {
            IERC20(params.token0).safeTransferFrom(msg.sender, address(this), amount0);
        }
        if (amount1 != 0) {
            IERC20(params.token1).safeTransferFrom(msg.sender, address(this), amount1);
        }
        tokenId = _nextTokenId++;
        _positions[tokenId] = Position({
            token0: params.token0,
            token1: params.token1,
            fee: params.fee,
            tickLower: params.tickLower,
            tickUpper: params.tickUpper,
            liquidity: liquidity,
            tokensOwed0: 0,
            tokensOwed1: 0
        });
        _safeMint(params.recipient, tokenId);
    }

    function decreaseLiquidity(DecreaseLiquidityParams calldata params)
        external
        payable
        returns (uint256 amount0, uint256 amount1)
    {
        require(ownerOf(params.tokenId) == msg.sender, "owner");
        // Test deadlines intentionally exercise the production deadline field.
        // forge-lint: disable-next-line(block-timestamp)
        require(params.deadline >= block.timestamp, "expired");
        Position storage position = _positions[params.tokenId];
        require(params.liquidity != 0 && params.liquidity <= position.liquidity, "liquidity");
        (amount0, amount1) = _amountsForLiquidity(
            pool.sqrtPriceX96(), position.tickLower, position.tickUpper, params.liquidity
        );
        require(amount0 >= params.amount0Min && amount1 >= params.amount1Min, "minimum");
        position.liquidity -= params.liquidity;
        position.tokensOwed0 += uint128(amount0);
        position.tokensOwed1 += uint128(amount1);
    }

    function collect(CollectParams calldata params)
        external
        payable
        returns (uint256 amount0, uint256 amount1)
    {
        require(ownerOf(params.tokenId) == msg.sender, "owner");
        Position storage position = _positions[params.tokenId];
        amount0 =
            position.tokensOwed0 < params.amount0Max ? position.tokensOwed0 : params.amount0Max;
        amount1 =
            position.tokensOwed1 < params.amount1Max ? position.tokensOwed1 : params.amount1Max;
        position.tokensOwed0 -= uint128(amount0);
        position.tokensOwed1 -= uint128(amount1);
        if (amount0 != 0) IERC20(position.token0).safeTransfer(params.recipient, amount0);
        if (amount1 != 0) IERC20(position.token1).safeTransfer(params.recipient, amount1);
    }

    function burn(uint256 tokenId) external payable {
        require(ownerOf(tokenId) == msg.sender, "owner");
        Position memory position = _positions[tokenId];
        require(
            position.liquidity == 0 && position.tokensOwed0 == 0 && position.tokensOwed1 == 0,
            "not empty"
        );
        delete _positions[tokenId];
        _burn(tokenId);
    }

    function addFees(uint256 tokenId, uint128 amount0, uint128 amount1) external {
        Position storage position = _positions[tokenId];
        require(position.token0 != address(0), "position");
        position.tokensOwed0 += amount0;
        position.tokensOwed1 += amount1;
        if (amount0 != 0) MockYieldBankAsset(position.token0).mint(address(this), amount0);
        if (amount1 != 0) MockYieldBankAsset(position.token1).mint(address(this), amount1);
    }

    function positionAmounts(uint256 tokenId)
        external
        view
        returns (uint256 amount0, uint256 amount1)
    {
        Position memory position = _positions[tokenId];
        (amount0, amount1) = _amountsForLiquidity(
            pool.sqrtPriceX96(), position.tickLower, position.tickUpper, position.liquidity
        );
        amount0 += position.tokensOwed0;
        amount1 += position.tokensOwed1;
    }

    function positions(uint256 tokenId)
        external
        view
        returns (
            uint96,
            address,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256,
            uint256,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        )
    {
        Position memory position = _positions[tokenId];
        return (
            0,
            address(0),
            position.token0,
            position.token1,
            position.fee,
            position.tickLower,
            position.tickUpper,
            position.liquidity,
            0,
            0,
            position.tokensOwed0,
            position.tokensOwed1
        );
    }

    function _amountsForLiquidity(
        uint160 sqrtPriceX96,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) private pure returns (uint256 amount0, uint256 amount1) {
        uint160 sqrtLowerX96 = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 sqrtUpperX96 = TickMath.getSqrtPriceAtTick(tickUpper);
        if (sqrtPriceX96 <= sqrtLowerX96) {
            amount0 = SqrtPriceMath.getAmount0Delta(sqrtLowerX96, sqrtUpperX96, liquidity, false);
        } else if (sqrtPriceX96 < sqrtUpperX96) {
            amount0 = SqrtPriceMath.getAmount0Delta(sqrtPriceX96, sqrtUpperX96, liquidity, false);
            amount1 = SqrtPriceMath.getAmount1Delta(sqrtLowerX96, sqrtPriceX96, liquidity, false);
        } else {
            amount1 = SqrtPriceMath.getAmount1Delta(sqrtLowerX96, sqrtUpperX96, liquidity, false);
        }
    }
}

contract MockDeltaPositionBuilder is IDeltaPositionBuilder {
    using SafeERC20 for IERC20;

    address public immutable uniFactory;
    address public immutable positionManager;
    address public immutable weth;

    constructor(address factory_, address positionManager_, address weth_) {
        uniFactory = factory_;
        positionManager = positionManager_;
        weth = weth_;
    }

    function mintLadder(
        address pool,
        Rung[] calldata rungs,
        int24 minimumCurrentTick,
        int24 maximumCurrentTick,
        uint256 deadline
    ) external payable returns (uint256[] memory tokenIds) {
        MockDeltaV3Pool targetPool = MockDeltaV3Pool(pool);
        (, int24 tick,,,,,) = targetPool.slot0();
        require(tick >= minimumCurrentTick && tick <= maximumCurrentTick, "tick");
        uint256 total0;
        uint256 total1;
        for (uint256 i; i < rungs.length; ++i) {
            total0 += rungs[i].amount0;
            total1 += rungs[i].amount1;
        }
        IERC20 token0 = IERC20(targetPool.token0());
        IERC20 token1 = IERC20(targetPool.token1());
        token0.safeTransferFrom(msg.sender, address(this), total0);
        token1.safeTransferFrom(msg.sender, address(this), total1);
        token0.forceApprove(positionManager, total0);
        token1.forceApprove(positionManager, total1);
        tokenIds = new uint256[](rungs.length);
        for (uint256 i; i < rungs.length; ++i) {
            Rung calldata rung = rungs[i];
            (tokenIds[i],,,) = IMockDeltaPositionManager(positionManager)
                .mint(
                    IMockDeltaPositionManager.MintParams({
                    token0: address(token0),
                    token1: address(token1),
                    fee: targetPool.fee(),
                    tickLower: rung.tickLower,
                    tickUpper: rung.tickUpper,
                    amount0Desired: rung.amount0,
                    amount1Desired: rung.amount1,
                    amount0Min: rung.amount0Min,
                    amount1Min: rung.amount1Min,
                    recipient: msg.sender,
                    deadline: deadline
                })
                );
        }
        token0.forceApprove(positionManager, 0);
        token1.forceApprove(positionManager, 0);
        uint256 refund0 = token0.balanceOf(address(this));
        uint256 refund1 = token1.balanceOf(address(this));
        if (refund0 != 0) token0.safeTransfer(msg.sender, refund0);
        if (refund1 != 0) token1.safeTransfer(msg.sender, refund1);
    }
}
