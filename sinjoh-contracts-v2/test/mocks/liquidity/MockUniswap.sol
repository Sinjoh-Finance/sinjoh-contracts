// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Currency, CurrencyLibrary } from "@uniswap/v4-core/src/types/Currency.sol";
import { PoolId } from "@uniswap/v4-core/src/types/PoolId.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import {
    INonfungiblePositionManager,
    IV4StateView
} from "../../../src/liquidity/ProjectLiquidityManagerV2.sol";

interface IERC20Uni {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IERC721ReceiverLike {
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        returns (bytes4);
}

contract MockV3Pool {
    uint160 public sqrtPriceX96 = 79_228_162_514_264_337_593_543_950_336;
    int24 public tickSpacing = 60;

    function setSqrtPrice(uint160 value) external {
        sqrtPriceX96 = value;
    }

    function slot0() external view returns (uint160, int24, uint16, uint16, uint16, uint8, bool) {
        return (sqrtPriceX96, 0, 0, 0, 0, 0, true);
    }
}

contract MockV3Factory {
    address public pool;

    function setPool(address value) external {
        pool = value;
    }

    function getPool(address, address, uint24) external view returns (address) {
        return pool;
    }
}

contract MockV3PositionManager {
    uint256 public nextTokenId = 1;
    uint16 public useBps = 10_000;
    bool public useSafeMintCallback = true;
    uint256 public mintCalls;
    uint256 public increaseCalls;
    mapping(uint256 => address) public token0;
    mapping(uint256 => address) public token1;
    mapping(uint256 => address) public ownerOf;
    mapping(uint256 => uint128) public liquidity;
    mapping(uint256 => uint256) public fee0;
    mapping(uint256 => uint256) public fee1;

    function setUseBps(uint16 value) external {
        useBps = value;
    }

    function setUseSafeMintCallback(bool value) external {
        useSafeMintCallback = value;
    }

    function setFees(uint256 tokenId, uint256 amount0, uint256 amount1) external {
        fee0[tokenId] = amount0;
        fee1[tokenId] = amount1;
    }

    function mint(INonfungiblePositionManager.MintParams calldata params)
        external
        payable
        returns (uint256 tokenId, uint128 liquidityAdded, uint256 amount0, uint256 amount1)
    {
        amount0 =
            params.amount0Desired * useBps / 10_000;
        amount1 = params.amount1Desired * useBps / 10_000;
        require(amount0 >= params.amount0Min && amount1 >= params.amount1Min, "SLIPPAGE");
        _pull(params.token0, amount0);
        _pull(params.token1, amount1);
        tokenId = nextTokenId++;
        token0[tokenId] = params.token0;
        token1[tokenId] = params.token1;
        ownerOf[tokenId] = params.recipient;
        liquidityAdded = uint128(amount0 < amount1 ? amount0 : amount1);
        liquidity[tokenId] = liquidityAdded;
        mintCalls++;
        if (useSafeMintCallback) {
            bytes4 result = IERC721ReceiverLike(params.recipient)
                .onERC721Received(msg.sender, address(0), tokenId, "");
            require(result == IERC721ReceiverLike.onERC721Received.selector);
        }
    }

    function increaseLiquidity(INonfungiblePositionManager.IncreaseLiquidityParams calldata params)
        external
        payable
        returns (uint128 liquidityAdded, uint256 amount0, uint256 amount1)
    {
        amount0 = params.amount0Desired * useBps / 10_000;
        amount1 = params.amount1Desired * useBps / 10_000;
        require(amount0 >= params.amount0Min && amount1 >= params.amount1Min, "SLIPPAGE");
        _pull(token0[params.tokenId], amount0);
        _pull(token1[params.tokenId], amount1);
        liquidityAdded = uint128(amount0 < amount1 ? amount0 : amount1);
        liquidity[params.tokenId] += liquidityAdded;
        increaseCalls++;
    }

    function collect(INonfungiblePositionManager.CollectParams calldata params)
        external
        payable
        returns (uint256 amount0, uint256 amount1)
    {
        amount0 = fee0[params.tokenId];
        amount1 = fee1[params.tokenId];
        fee0[params.tokenId] = 0;
        fee1[params.tokenId] = 0;
        require(IERC20Uni(token0[params.tokenId]).transfer(params.recipient, amount0));
        require(IERC20Uni(token1[params.tokenId]).transfer(params.recipient, amount1));
    }

    function _pull(address token, uint256 amount) private {
        if (amount != 0) require(IERC20Uni(token).transferFrom(msg.sender, address(this), amount));
    }
}

contract MockV4StateView is IV4StateView {
    uint160 public sqrtPriceX96 = 79_228_162_514_264_337_593_543_950_336;

    function setSqrtPrice(uint160 value) external {
        sqrtPriceX96 = value;
    }

    function getSlot0(PoolId) external view returns (uint160, int24, uint24, uint24) {
        return (sqrtPriceX96, 0, 0, 3_000);
    }
}

contract MockPermit2 {
    mapping(
        address owner => mapping(address token => mapping(address spender => uint160 amount))
    ) public allowance;

    function approve(address token, address spender, uint160 amount, uint48) external {
        allowance[msg.sender][token][spender] = amount;
    }

    function transferFrom(address from, address to, uint160 amount, address token) external {
        uint160 allowed = allowance[from][token][msg.sender];
        require(allowed >= amount, "PERMIT2_ALLOWANCE");
        allowance[from][token][msg.sender] = allowed - amount;
        require(IERC20Uni(token).transferFrom(from, to, amount));
    }
}

contract MockV4PositionManager {
    using CurrencyLibrary for Currency;

    MockPermit2 public immutable permit2;
    uint256 public nextTokenId = 1;
    uint16 public useBps = 10_000;
    bool public rejectHook;
    uint256 public mintCalls;
    uint256 public increaseCalls;
    uint128 public lastAmount0Max;
    uint128 public lastAmount1Max;
    mapping(uint256 => PoolKey) internal _keys;
    mapping(uint256 => uint128) public positionLiquidity;
    mapping(uint256 => uint256) public fee0;
    mapping(uint256 => uint256) public fee1;

    constructor(MockPermit2 permit2_) {
        permit2 = permit2_;
    }

    function setUseBps(uint16 value) external {
        useBps = value;
    }

    function setRejectHook(bool value) external {
        rejectHook = value;
    }

    function setFees(uint256 tokenId, uint256 amount0, uint256 amount1) external {
        fee0[tokenId] = amount0;
        fee1[tokenId] = amount1;
    }

    function modifyLiquidities(bytes calldata unlockData, uint256) external payable {
        if (rejectHook) revert("HOOK_REJECTED");
        (bytes memory actions, bytes[] memory params) = abi.decode(unlockData, (bytes, bytes[]));
        uint8 first = uint8(actions[0]);
        if (first == 0x02) {
            (PoolKey memory key,,, uint256 liquidity, uint128 amount0Max, uint128 amount1Max,,) = abi.decode(
                params[0], (PoolKey, int24, int24, uint256, uint128, uint128, address, bytes)
            );
            uint256 tokenId = nextTokenId++;
            _keys[tokenId] = key;
            // The production manager supplies uint128 liquidity.
            // forge-lint: disable-next-line(unsafe-typecast)
            positionLiquidity[tokenId] = uint128(liquidity);
            lastAmount0Max = amount0Max;
            lastAmount1Max = amount1Max;
            _takePair(key, amount0Max, amount1Max);
            mintCalls++;
        } else if (first == 0x00) {
            (uint256 tokenId, uint256 liquidity, uint128 amount0Max, uint128 amount1Max,) =
                abi.decode(params[0], (uint256, uint256, uint128, uint128, bytes));
            // The production manager supplies uint128 liquidity.
            // forge-lint: disable-next-line(unsafe-typecast)
            positionLiquidity[tokenId] += uint128(liquidity);
            lastAmount0Max = amount0Max;
            lastAmount1Max = amount1Max;
            _takePair(_keys[tokenId], amount0Max, amount1Max);
            increaseCalls++;
        } else if (first == 0x01) {
            (uint256 tokenId,,,,) =
                abi.decode(params[0], (uint256, uint256, uint128, uint128, bytes));
            (,, address recipient) = abi.decode(params[1], (Currency, Currency, address));
            PoolKey memory key = _keys[tokenId];
            _send(Currency.unwrap(key.currency0), recipient, fee0[tokenId]);
            _send(Currency.unwrap(key.currency1), recipient, fee1[tokenId]);
            fee0[tokenId] = 0;
            fee1[tokenId] = 0;
        }
        if (address(this).balance != 0) {
            (bool success,) = msg.sender.call{ value: address(this).balance }("");
            require(success);
        }
    }

    function getPositionLiquidity(uint256 tokenId) external view returns (uint128) {
        return positionLiquidity[tokenId];
    }

    function _takePair(PoolKey memory key, uint128 max0, uint128 max1) private {
        uint256 amount0 = uint256(max0) * useBps / 10_000;
        uint256 amount1 = uint256(max1) * useBps / 10_000;
        _take(Currency.unwrap(key.currency0), amount0);
        _take(Currency.unwrap(key.currency1), amount1);
    }

    function _take(address token, uint256 amount) private {
        if (amount == 0) return;
        if (token == address(0)) {
            require(msg.value >= amount);
            (bool success,) = payable(address(0xdEaD)).call{ value: amount }("");
            require(success);
        } else {
            // `amount` is derived from a uint128 maximum and a uint16 multiplier.
            // forge-lint: disable-next-line(unsafe-typecast)
            permit2.transferFrom(msg.sender, address(this), uint160(amount), token);
        }
    }

    function _send(address token, address recipient, uint256 amount) private {
        if (amount == 0) return;
        if (token == address(0)) {
            (bool success,) = recipient.call{ value: amount }("");
            require(success);
        } else {
            require(IERC20Uni(token).transfer(recipient, amount));
        }
    }

    receive() external payable { }
}
