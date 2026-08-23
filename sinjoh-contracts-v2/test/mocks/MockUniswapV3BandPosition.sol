// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IV3BandPositionManager } from "../../src/bands/UniswapV3FundingBandPositionAdapter.sol";
import { IFundingBandQuoteUsdOracle } from "../../src/interfaces/IFundingBandQuoteUsdOracle.sol";

contract MockFundingBandQuoteUsdOracle is IFundingBandQuoteUsdOracle {
    address public immutable override quoteAsset;
    uint256 public priceUsdE8;
    uint48 public observedAt;
    bytes32 public observationId;

    constructor(address quoteAsset_) {
        quoteAsset = quoteAsset_;
    }

    function setObservation(uint256 price, uint48 time, bytes32 id) external {
        priceUsdE8 = price;
        observedAt = time;
        observationId = id;
    }

    function latestPriceUsdE8() external view returns (uint256, uint48, bytes32) {
        return (priceUsdE8, observedAt, observationId);
    }
}

    contract MockV3BandFactory {
        mapping(bytes32 key => address pool) private _pool;

        function setPool(address tokenA, address tokenB, uint24 fee, address pool) external {
            (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
            _pool[keccak256(abi.encode(token0, token1, fee))] = pool;
        }

        function getPool(address tokenA, address tokenB, uint24 fee)
            external
            view
            returns (address)
        {
            (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
            return _pool[keccak256(abi.encode(token0, token1, fee))];
        }
    }

    contract MockV3BandPool {
        address public immutable factory;
        address public immutable token0;
        address public immutable token1;
        uint24 public immutable fee;
        int24 public immutable tickSpacing;
        int24 public currentTick;
        bool public unlocked = true;
        uint16 public observationCardinality = 2;
        uint16 public observationCardinalityNext = 2;

        constructor(
            address factory_,
            address token0_,
            address token1_,
            uint24 fee_,
            int24 tickSpacing_
        ) {
            factory = factory_;
            token0 = token0_;
            token1 = token1_;
            fee = fee_;
            tickSpacing = tickSpacing_;
        }

        function setCurrentTick(int24 tick) external {
            currentTick = tick;
        }

        function setUnlocked(bool value) external {
            unlocked = value;
        }

        function setObservationCardinality(uint16 value) external {
            observationCardinality = value;
        }

        function increaseObservationCardinalityNext(uint16 value) external {
            if (value > observationCardinalityNext) observationCardinalityNext = value;
        }

        function observe(uint32[] calldata secondsAgos)
            external
            view
            returns (
                int56[] memory tickCumulatives,
                uint160[] memory secondsPerLiquidityCumulativeX128s
            )
        {
            require(observationCardinality >= 2 && secondsAgos.length == 2, "oracle");
            tickCumulatives = new int56[](2);
            secondsPerLiquidityCumulativeX128s = new uint160[](2);
            tickCumulatives[0] = -int56(currentTick) * int56(uint56(secondsAgos[0]));
            tickCumulatives[1] = 0;
        }

        function slot0()
            external
            view
            returns (
                uint160 sqrtPriceX96,
                int24 tick,
                uint16 observationIndex,
                uint16 cardinality,
                uint16 cardinalityNext,
                uint8 feeProtocol,
                bool isUnlocked
            )
        {
            return (
                uint160(1 << 96),
                currentTick,
                0,
                observationCardinality,
                observationCardinalityNext,
                0,
                unlocked
            );
        }
    }

    contract MockV3BandPositionManager is ERC721 {
        using SafeERC20 for IERC20;
        using SafeCast for uint256;

        struct Position {
            address token0;
            address token1;
            uint24 fee;
            int24 lower;
            int24 upper;
            uint128 liquidity;
            uint128 owed0;
            uint128 owed1;
        }

        address public immutable factory;
        uint16 public spendBps = 9_000;
        uint256 public nextTokenId = 1;
        uint128 public settlement0;
        uint128 public settlement1;
        mapping(uint256 tokenId => Position position) private _positions;

        constructor(address factory_) ERC721("Mock V3 Position", "MV3P") {
            factory = factory_;
        }

        function setSpendBps(uint16 value) external {
            spendBps = value;
        }

        function setSettlement(uint128 amount0, uint128 amount1) external {
            settlement0 = amount0;
            settlement1 = amount1;
        }

        function mint(IV3BandPositionManager.MintParams calldata params)
            external
            returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
        {
            amount0 =
                params.amount0Desired * spendBps / 10_000;
            amount1 = params.amount1Desired * spendBps / 10_000;
            if (amount0 != 0) {
                IERC20(params.token0).safeTransferFrom(msg.sender, address(this), amount0);
            }
            if (amount1 != 0) {
                IERC20(params.token1).safeTransferFrom(msg.sender, address(this), amount1);
            }
            liquidity = (amount0 + amount1).toUint128();
            tokenId = nextTokenId++;
            _positions[tokenId] = Position({
                token0: params.token0,
                token1: params.token1,
                fee: params.fee,
                lower: params.tickLower,
                upper: params.tickUpper,
                liquidity: liquidity,
                owed0: 0,
                owed1: 0
            });
            _safeMint(params.recipient, tokenId);
        }

        function increaseLiquidity(IV3BandPositionManager.IncreaseLiquidityParams calldata params)
            external
            returns (uint128 liquidity, uint256 amount0, uint256 amount1)
        {
            Position storage position = _positions[params.tokenId];
            amount0 = params.amount0Desired * spendBps / 10_000;
            amount1 = params.amount1Desired * spendBps / 10_000;
            if (amount0 != 0) {
                IERC20(position.token0).safeTransferFrom(msg.sender, address(this), amount0);
            }
            if (amount1 != 0) {
                IERC20(position.token1).safeTransferFrom(msg.sender, address(this), amount1);
            }
            liquidity = (amount0 + amount1).toUint128();
            position.liquidity += liquidity;
        }

        function decreaseLiquidity(IV3BandPositionManager.DecreaseLiquidityParams calldata params)
            external
            returns (uint256 amount0, uint256 amount1)
        {
            require(_isAuthorized(ownerOf(params.tokenId), msg.sender, params.tokenId), "approved");
            Position storage position = _positions[params.tokenId];
            require(position.liquidity == params.liquidity, "liquidity");
            position.liquidity = 0;
            position.owed0 = settlement0;
            position.owed1 = settlement1;
            return (settlement0, settlement1);
        }

        function collect(IV3BandPositionManager.CollectParams calldata params)
            external
            returns (uint256 amount0, uint256 amount1)
        {
            require(_isAuthorized(ownerOf(params.tokenId), msg.sender, params.tokenId), "approved");
            Position storage position = _positions[params.tokenId];
            amount0 = position.owed0;
            amount1 = position.owed1;
            position.owed0 = 0;
            position.owed1 = 0;
            if (amount0 != 0) IERC20(position.token0).safeTransfer(params.recipient, amount0);
            if (amount1 != 0) IERC20(position.token1).safeTransfer(params.recipient, amount1);
        }

        function burn(uint256 tokenId) external {
            require(_isAuthorized(ownerOf(tokenId), msg.sender, tokenId), "approved");
            Position storage position = _positions[tokenId];
            require(position.liquidity == 0 && position.owed0 == 0 && position.owed1 == 0, "open");
            delete _positions[tokenId];
            _burn(tokenId);
        }

        function positions(uint256 tokenId)
            external
            view
            returns (
                uint96 nonce,
                address operator,
                address token0,
                address token1,
                uint24 fee,
                int24 tickLower,
                int24 tickUpper,
                uint128 liquidity,
                uint256 feeGrowthInside0LastX128,
                uint256 feeGrowthInside1LastX128,
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
                position.lower,
                position.upper,
                position.liquidity,
                0,
                0,
                position.owed0,
                position.owed1
            );
        }
    }
