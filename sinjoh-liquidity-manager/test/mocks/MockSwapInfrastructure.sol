// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IUnlockCallback } from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import { BalanceDelta, toBalanceDelta } from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { SwapParams } from "@uniswap/v4-core/src/types/PoolOperation.sol";
import { ISwapRouter } from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

interface IERC20SwapInfrastructure {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

contract MockV3ExecutionPool {
    address public immutable factory;
    address public immutable token0;
    address public immutable token1;
    uint24 public immutable fee;
    int24 public immutable tickSpacing;
    uint16 public cardinalityNext = 1;

    constructor(address factory_, address token0_, address token1_, uint24 fee_, int24 spacing_) {
        factory = factory_;
        token0 = token0_;
        token1 = token1_;
        fee = fee_;
        tickSpacing = spacing_;
    }

    function increaseObservationCardinalityNext(uint16 value) external {
        if (value > cardinalityNext) cardinalityNext = value;
    }
}

contract MockV3ExecutionFactory {
    address public pool;
    mapping(uint24 => int24) public feeAmountTickSpacing;

    constructor() {
        feeAmountTickSpacing[500] = 10;
        feeAmountTickSpacing[3_000] = 60;
        feeAmountTickSpacing[10_000] = 200;
    }

    function setPool(address pool_) external {
        pool = pool_;
    }

    function getPool(address, address, uint24) external view returns (address) {
        return pool;
    }
}

contract MockV3ExecutionRouter {
    uint16 public useBps = 10_000;

    function setUseBps(uint16 useBps_) external {
        useBps = useBps_;
    }

    function exactInputSingle(ISwapRouter.ExactInputSingleParams calldata params)
        external
        payable
        returns (uint256 amountOut)
    {
        uint256 amountTaken = params.amountIn * useBps / 10_000;
        require(
            IERC20SwapInfrastructure(params.tokenIn)
                .transferFrom(msg.sender, address(this), amountTaken)
        );
        amountOut = amountTaken;
        require(amountOut >= params.amountOutMinimum);
        require(IERC20SwapInfrastructure(params.tokenOut).transfer(params.recipient, amountOut));
    }
}

contract MockV3OraclePool {
    address public immutable factory;
    address public immutable token0;
    address public immutable token1;
    uint24 public immutable fee;
    int24 public spotTick;
    int24 public twapTick;
    uint160 public sqrtPriceX96 = 79_228_162_514_264_337_593_543_950_336;
    uint16 public cardinality = 2;
    uint16 public cardinalityNext = 2;
    bool public unlocked = true;
    bool public observeReverts;

    constructor(address factory_, address token0_, address token1_, uint24 fee_) {
        factory = factory_;
        token0 = token0_;
        token1 = token1_;
        fee = fee_;
    }

    function setTicks(int24 spotTick_, int24 twapTick_) external {
        spotTick = spotTick_;
        twapTick = twapTick_;
    }

    function setSqrtPrice(uint160 value) external {
        sqrtPriceX96 = value;
    }

    function setCardinality(uint16 value) external {
        cardinality = value;
        cardinalityNext = value;
    }

    function increaseObservationCardinalityNext(uint16 value) external {
        if (value > cardinalityNext) cardinalityNext = value;
    }

    function setObserveReverts(bool value) external {
        observeReverts = value;
    }

    function slot0() external view returns (uint160, int24, uint16, uint16, uint16, uint8, bool) {
        return (sqrtPriceX96, spotTick, 0, cardinality, cardinalityNext, 0, unlocked);
    }

    function observe(uint32[] calldata secondsAgos)
        external
        view
        returns (int56[] memory tickCumulatives, uint160[] memory liquidityCumulatives)
    {
        require(!observeReverts && secondsAgos.length == 2);
        tickCumulatives = new int56[](2);
        liquidityCumulatives = new uint160[](2);
        tickCumulatives[1] = int56(twapTick) * int56(uint56(secondsAgos[0]));
    }
}

contract MockV4ExecutionPoolManager {
    address public immutable token0;
    address public immutable token1;
    uint256 private _inputBalanceBefore;
    address private _input;
    uint256 private _amountIn;
    uint256 private _amountOut;
    uint16 public useBps = 10_000;

    constructor(address token0_, address token1_) {
        token0 = token0_;
        token1 = token1_;
    }

    function setUseBps(uint16 useBps_) external {
        require(useBps_ <= 10_000);
        useBps = useBps_;
    }

    function unlock(bytes calldata data) external returns (bytes memory result) {
        result = IUnlockCallback(msg.sender).unlockCallback(data);
    }

    function swap(PoolKey memory key, SwapParams memory params, bytes calldata)
        external
        returns (BalanceDelta)
    {
        require(
            Currency.unwrap(key.currency0) == token0 && Currency.unwrap(key.currency1) == token1
        );
        require(params.amountSpecified < 0);
        _amountIn = uint256(-params.amountSpecified) * useBps / 10_000;
        _amountOut = _amountIn;
        _input = params.zeroForOne ? token0 : token1;
        return params.zeroForOne
            ? toBalanceDelta(-int128(int256(_amountIn)), int128(int256(_amountOut)))
            : toBalanceDelta(int128(int256(_amountOut)), -int128(int256(_amountIn)));
    }

    function sync(Currency currency) external {
        _input = Currency.unwrap(currency);
        _inputBalanceBefore = IERC20SwapInfrastructure(_input).balanceOf(address(this));
    }

    function settle() external returns (uint256 paid) {
        paid = IERC20SwapInfrastructure(_input).balanceOf(address(this)) - _inputBalanceBefore;
        require(paid == _amountIn);
    }

    function take(Currency currency, address to, uint256 amount) external {
        require(amount == _amountOut);
        require(IERC20SwapInfrastructure(Currency.unwrap(currency)).transfer(to, amount));
    }
}

/// @notice A v3 factory whose `getPool` answers per pair and fee, which a
/// two-hop route needs in order to canonicalise both of its pools.
contract MockV3MultiPoolFactory {
    mapping(bytes32 key => address pool) private _pools;

    function setPool(address tokenA, address tokenB, uint24 fee, address pool) external {
        _pools[_key(tokenA, tokenB, fee)] = pool;
    }

    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address) {
        return _pools[_key(tokenA, tokenB, fee)];
    }

    function _key(address tokenA, address tokenB, uint24 fee) private pure returns (bytes32) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        return keccak256(abi.encode(token0, token1, fee));
    }
}

/// @notice Executes `exactInput` by reading only the path's first and last
/// token, so a test can assert the adapter submitted the exact bytes it froze.
contract MockV3MultiHopRouter {
    uint16 public useBps = 10_000;
    uint16 public strandMidBps;
    address public strandedMidAsset;
    bytes public lastPath;

    function setUseBps(uint16 useBps_) external {
        useBps = useBps_;
    }

    /// @notice Simulates a router that leaves intermediate dust with the caller.
    function setStrandedMid(address asset, uint16 bps) external {
        strandedMidAsset = asset;
        strandMidBps = bps;
    }

    function exactInput(ISwapRouter.ExactInputParams calldata params)
        external
        payable
        returns (uint256 amountOut)
    {
        lastPath = params.path;
        require(params.path.length == 66);
        address tokenIn = _toAddress(params.path, 0);
        address tokenOut = _toAddress(params.path, 46);

        uint256 amountTaken = params.amountIn * useBps / 10_000;
        require(
            IERC20SwapInfrastructure(tokenIn).transferFrom(msg.sender, address(this), amountTaken)
        );
        amountOut = amountTaken;
        require(amountOut >= params.amountOutMinimum);
        require(IERC20SwapInfrastructure(tokenOut).transfer(params.recipient, amountOut));

        if (strandMidBps != 0) {
            require(
                IERC20SwapInfrastructure(strandedMidAsset)
                    .transfer(msg.sender, params.amountIn * strandMidBps / 10_000)
            );
        }
    }

    /// @dev An asset bucket deploys a two-hop and a direct adapter against the
    /// same router, so this mock answers both entry points.
    function exactInputSingle(ISwapRouter.ExactInputSingleParams calldata params)
        external
        payable
        returns (uint256 amountOut)
    {
        uint256 amountTaken = params.amountIn * useBps / 10_000;
        require(
            IERC20SwapInfrastructure(params.tokenIn)
                .transferFrom(msg.sender, address(this), amountTaken)
        );
        amountOut = amountTaken;
        require(amountOut >= params.amountOutMinimum);
        require(IERC20SwapInfrastructure(params.tokenOut).transfer(params.recipient, amountOut));
    }

    function _toAddress(bytes calldata data, uint256 offset) private pure returns (address value) {
        bytes calldata word = data[offset:offset + 20];
        assembly ("memory-safe") {
            calldatacopy(0x00, word.offset, 20)
            value := shr(96, mload(0x00))
        }
    }
}
