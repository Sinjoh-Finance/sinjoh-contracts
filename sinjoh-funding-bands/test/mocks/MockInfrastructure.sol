// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { PoolId } from "@uniswap/v4-core/src/types/PoolId.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";

import { IV4StateView } from "../../src/SinjohFundingBands.sol";
import { IChainlinkAggregatorV3 } from "../../src/interfaces/IChainlinkAggregatorV3.sol";
import {
    ISinjohFundingBandPriceGuard
} from "../../src/interfaces/ISinjohFundingBandPriceGuard.sol";
import { ISinjohLaunchVerifier } from "../../src/interfaces/ISinjohLaunchVerifier.sol";
import { IUniswapV3PositionManager } from "../../src/interfaces/IUniswapV3PositionManager.sol";
import { IPonsV1LaunchFactory } from "../../src/profiles/SinjohPonsV1LaunchVerifier.sol";
import { IPonsV2LaunchFactory } from "../../src/profiles/SinjohPonsV2LaunchVerifier.sol";

interface IERC721ReceiverLike {
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        returns (bytes4);
}

contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public immutable decimals;
    uint256 public totalSupply;
    uint16 public transferFeeBps;
    mapping(address => bool) public blockedRecipient;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) {
        name = name_;
        symbol = symbol_;
        decimals = decimals_;
    }

    function mint(address to, uint256 amount) public {
        totalSupply += amount;
        balanceOf[to] += amount;
    }

    function setTransferFeeBps(uint16 value) external {
        transferFeeBps = value;
    }

    function setBlockedRecipient(address recipient, bool blocked) external {
        blockedRecipient[recipient] = blocked;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        require(allowed >= amount, "ALLOWANCE");
        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) private {
        require(balanceOf[from] >= amount, "BALANCE");
        require(!blockedRecipient[to], "BLOCKED_RECIPIENT");
        balanceOf[from] -= amount;
        uint256 fee = amount * transferFeeBps / 10_000;
        balanceOf[to] += amount - fee;
        totalSupply -= fee;
    }
}

contract MockWETH is MockERC20 {
    constructor() MockERC20("Wrapped Ether", "WETH", 18) { }

    function deposit() external payable {
        mint(msg.sender, msg.value);
    }
}

contract MockOracle is IChainlinkAggregatorV3 {
    uint8 public immutable decimals;
    uint80 public roundId = 1;
    int256 public answer = 2_000e8;
    uint256 public updatedAt;
    uint80 public answeredInRound = 1;

    constructor(uint8 decimals_) {
        decimals = decimals_;
        updatedAt = block.timestamp;
    }

    function setRound(uint80 roundId_, int256 answer_, uint256 updatedAt_, uint80 answeredInRound_)
        external
    {
        roundId = roundId_;
        answer = answer_;
        updatedAt = updatedAt_;
        answeredInRound = answeredInRound_;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (roundId, answer, updatedAt, updatedAt, answeredInRound);
    }
}

contract MockLaunchVerifier is ISinjohLaunchVerifier {
    VerifiedLaunch private _launch;

    function setLaunch(VerifiedLaunch calldata launch_) external {
        _launch = launch_;
    }

    function verify(address subject, bytes calldata launchData)
        external
        view
        returns (VerifiedLaunch memory)
    {
        require(launchData.length == 0, "LAUNCH_DATA");
        require(subject == _launch.subject, "SUBJECT");
        return _launch;
    }
}

contract MockBandPriceGuard is ISinjohFundingBandPriceGuard {
    int24 public spotTick;
    int24 public referenceTick;
    bool public stale;
    bool public enforceGuardData;
    bytes32 public expectedGuardDataHash;

    function setTicks(int24 spotTick_, int24 referenceTick_) external {
        spotTick = spotTick_;
        referenceTick = referenceTick_;
    }

    function setStale(bool value) external {
        stale = value;
    }

    function setExpectedGuardData(bytes calldata guardData) external {
        expectedGuardDataHash = keccak256(guardData);
        enforceGuardData = true;
    }

    function validateBelow(
        ISinjohLaunchVerifier.VerifiedLaunch calldata,
        int24 boundaryTick,
        bool subjectIsToken0,
        bytes calldata guardData
    ) external view {
        require(!stale, "STALE");
        if (enforceGuardData) require(keccak256(guardData) == expectedGuardDataHash, "GUARD_DATA");
        if (subjectIsToken0) {
            require(spotTick < boundaryTick && referenceTick < boundaryTick, "NOT_BELOW");
        } else {
            require(spotTick > boundaryTick && referenceTick > boundaryTick, "NOT_BELOW");
        }
    }

    function validateAbove(
        ISinjohLaunchVerifier.VerifiedLaunch calldata,
        int24 boundaryTick,
        bool subjectIsToken0,
        bytes calldata guardData
    ) external view {
        require(!stale, "STALE");
        if (enforceGuardData) require(keccak256(guardData) == expectedGuardDataHash, "GUARD_DATA");
        if (subjectIsToken0) {
            require(spotTick >= boundaryTick && referenceTick >= boundaryTick, "NOT_ABOVE");
        } else {
            require(spotTick <= boundaryTick && referenceTick <= boundaryTick, "NOT_ABOVE");
        }
    }
}

contract MockFeeRouter {
    address public creator;
    address public subject;
    mapping(address => bool) public isIntakeAsset;

    constructor(address creator_, address subject_, address weth_) {
        creator = creator_;
        subject = subject_;
        isIntakeAsset[weth_] = true;
        isIntakeAsset[subject_] = true;
    }
}

contract MockCounterfeitFeeRouter {
    address public creator;
    address public subject;
    mapping(address => bool) public isIntakeAsset;

    constructor(address creator_, address subject_, address weth_) {
        creator = creator_;
        subject = subject_;
        isIntakeAsset[weth_] = true;
        isIntakeAsset[subject_] = true;
    }

    function arbitraryCall(address target, bytes calldata data) external returns (bytes memory) {
        (bool success, bytes memory result) = target.call(data);
        require(success, "CALL");
        return result;
    }
}

contract MockV3Pool {
    uint160 public sqrtPriceX96 = 1 << 96;
    int24 public tickSpacing = 60;
    int24 public spotTick;
    int24 public twapTick;

    function setTicks(int24 spotTick_, int24 twapTick_) external {
        spotTick = spotTick_;
        twapTick = twapTick_;
    }

    function slot0() external view returns (uint160, int24, uint16, uint16, uint16, uint8, bool) {
        return (sqrtPriceX96, spotTick, 0, 2, 2, 0, true);
    }

    function observe(uint32[] calldata secondsAgos)
        external
        view
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidity)
    {
        require(secondsAgos.length == 2, "SECONDS");
        tickCumulatives = new int56[](2);
        secondsPerLiquidity = new uint160[](2);
        tickCumulatives[1] = int56(twapTick) * int56(uint56(secondsAgos[0]));
    }
}

contract MockV3Factory {
    address public pool;

    function setPool(address pool_) external {
        pool = pool_;
    }

    function getPool(address, address, uint24) external view returns (address) {
        return pool;
    }
}

contract MockPonsV1Factory is IPonsV1LaunchFactory {
    mapping(address => LaunchedToken) private _records;

    function setLaunch(address token, LaunchedToken calldata record) external {
        _records[token] = record;
    }

    function getLaunchedToken(address token) external view returns (LaunchedToken memory) {
        return _records[token];
    }
}

contract MockPonsV2Factory is IPonsV2LaunchFactory {
    mapping(address => LaunchedToken) private _records;

    function setLaunch(address token, LaunchedToken calldata record) external {
        _records[token] = record;
    }

    function getLaunchedToken(address token) external view returns (LaunchedToken memory) {
        return _records[token];
    }
}

contract MockPonsV2Token is MockERC20 {
    address public immutable deployer;
    address public immutable launchFactory;
    address public immutable curve;

    constructor(address deployer_, address launchFactory_, address curve_)
        MockERC20("Pons V2 Subject", "PV2", 18)
    {
        deployer = deployer_;
        launchFactory = launchFactory_;
        curve = curve_;
    }
}

contract MockSinjohPonsV2Adapter {
    address public immutable creator;
    address public immutable launchFactory;
    address public immutable curve;
    address public subject;

    constructor(address creator_, address launchFactory_, address curve_) {
        creator = creator_;
        launchFactory = launchFactory_;
        curve = curve_;
    }

    function setSubject(address subject_) external {
        require(subject == address(0), "SET");
        subject = subject_;
    }
}

/// @dev Pons v2's production hook enables beforeInitialize and afterSwap only.
/// Liquidity actions therefore require no hook callback and use empty hook data.
contract MockPonsV2MemeHook { }

contract MockV3PositionManager is IUniswapV3PositionManager {
    uint16 public fillBps = 10_000;
    uint256 public nextTokenId = 1;
    uint256 public mintCalls;
    uint256 public increaseCalls;
    mapping(uint256 => address) public ownerOf;
    mapping(uint256 => address) public token0;
    mapping(uint256 => address) public token1;
    mapping(uint256 => uint128) public liquidity;
    mapping(uint256 => uint256) public settle0;
    mapping(uint256 => uint256) public settle1;

    function setFillBps(uint16 fillBps_) external {
        require(fillBps_ <= 10_000, "FILL_BPS");
        fillBps = fillBps_;
    }

    function setSettlement(uint256 tokenId, uint256 amount0, uint256 amount1) external {
        settle0[tokenId] = amount0;
        settle1[tokenId] = amount1;
    }

    function mint(MintParams calldata params)
        external
        payable
        returns (uint256 tokenId, uint128 liquidityAdded, uint256 amount0, uint256 amount1)
    {
        amount0 =
            params.amount0Desired * fillBps / 10_000;
        amount1 = params.amount1Desired * fillBps / 10_000;
        _pull(params.token0, amount0);
        _pull(params.token1, amount1);
        tokenId = nextTokenId++;
        ownerOf[tokenId] = params.recipient;
        token0[tokenId] = params.token0;
        token1[tokenId] = params.token1;
        require(amount0 + amount1 <= type(uint128).max, "LIQUIDITY_OVERFLOW");
        // The preceding bound makes this mock cast exact.
        // forge-lint: disable-next-line(unsafe-typecast)
        liquidityAdded = uint128(amount0 + amount1);
        liquidity[tokenId] = liquidityAdded;
        mintCalls++;
        bytes4 result = IERC721ReceiverLike(params.recipient)
            .onERC721Received(msg.sender, address(0), tokenId, "");
        require(result == IERC721ReceiverLike.onERC721Received.selector, "UNSAFE");
    }

    function increaseLiquidity(IncreaseLiquidityParams calldata params)
        external
        payable
        returns (uint128 liquidityAdded, uint256 amount0, uint256 amount1)
    {
        amount0 = params.amount0Desired * fillBps / 10_000;
        amount1 = params.amount1Desired * fillBps / 10_000;
        _pull(token0[params.tokenId], amount0);
        _pull(token1[params.tokenId], amount1);
        require(amount0 + amount1 <= type(uint128).max, "LIQUIDITY_OVERFLOW");
        // The preceding bound makes this mock cast exact.
        // forge-lint: disable-next-line(unsafe-typecast)
        liquidityAdded = uint128(amount0 + amount1);
        liquidity[params.tokenId] += liquidityAdded;
        increaseCalls++;
    }

    function decreaseLiquidity(DecreaseLiquidityParams calldata params)
        external
        payable
        returns (uint256 amount0, uint256 amount1)
    {
        require(ownerOf[params.tokenId] == msg.sender, "OWNER");
        require(liquidity[params.tokenId] == params.liquidity, "LIQUIDITY");
        liquidity[params.tokenId] = 0;
        return (settle0[params.tokenId], settle1[params.tokenId]);
    }

    function collect(CollectParams calldata params)
        external
        payable
        returns (uint256 amount0, uint256 amount1)
    {
        amount0 = settle0[params.tokenId];
        amount1 = settle1[params.tokenId];
        settle0[params.tokenId] = 0;
        settle1[params.tokenId] = 0;
        _send(token0[params.tokenId], params.recipient, amount0);
        _send(token1[params.tokenId], params.recipient, amount1);
    }

    function burn(uint256 tokenId_) external payable {
        require(ownerOf[tokenId_] == msg.sender && liquidity[tokenId_] == 0, "BURN");
        delete ownerOf[tokenId_];
    }

    function _pull(address token, uint256 amount) private {
        if (amount != 0) require(MockERC20(token).transferFrom(msg.sender, address(this), amount));
    }

    function _send(address token, address recipient, uint256 amount) private {
        if (amount != 0) require(MockERC20(token).transfer(recipient, amount));
    }
}

contract MockV4PoolManager {
    function sendNative(address recipient, uint256 amount) external {
        (bool success,) = recipient.call{ value: amount }("");
        require(success, "ETH");
    }

    receive() external payable { }
}

contract MockV4StateView is IV4StateView {
    address public immutable poolManager;
    uint160 public sqrtPriceX96 = 1 << 96;
    int24 public spotTick;

    constructor(address poolManager_) {
        poolManager = poolManager_;
    }

    function setTick(int24 tick_) external {
        spotTick = tick_;
    }

    function setSqrtPriceX96(uint160 sqrtPriceX96_) external {
        sqrtPriceX96 = sqrtPriceX96_;
    }

    function getSlot0(PoolId) external view returns (uint160, int24, uint24, uint24) {
        return (sqrtPriceX96, spotTick, 0, 3_000);
    }
}

contract MockPermit2 {
    mapping(address => mapping(address => mapping(address => uint160))) public allowance;

    function approve(address token, address spender, uint160 amount, uint48) external {
        allowance[msg.sender][token][spender] = amount;
    }

    function transferFrom(address from, address to, uint160 amount, address token) external {
        uint160 allowed = allowance[from][token][msg.sender];
        require(allowed >= amount, "PERMIT2");
        allowance[from][token][msg.sender] = allowed - amount;
        require(MockERC20(token).transferFrom(from, to, amount));
    }
}

contract MockV4PositionManager {
    MockPermit2 public immutable permit2;
    MockV4PoolManager public immutable poolManager;
    uint256 public nextTokenId = 1;
    uint256 public mintCalls;
    uint256 public increaseCalls;
    bytes32 public expectedHookDataHash;
    bool public enforceHookData;
    address public expectedHook;
    bool public enforceHook;
    mapping(uint256 => address) public ownerOf;
    mapping(uint256 => PoolKey) private _keys;
    mapping(uint256 => uint128) public positionLiquidity;
    mapping(uint256 => uint256) public settle0;
    mapping(uint256 => uint256) public settle1;

    constructor(MockPermit2 permit2_, MockV4PoolManager poolManager_) {
        permit2 = permit2_;
        poolManager = poolManager_;
    }

    function setSettlement(uint256 tokenId, uint256 amount0, uint256 amount1) external {
        settle0[tokenId] = amount0;
        settle1[tokenId] = amount1;
    }

    function setExpectedHookData(bytes calldata hookData) external {
        expectedHookDataHash = keccak256(hookData);
        enforceHookData = true;
    }

    function setExpectedHook(address hook) external {
        expectedHook = hook;
        enforceHook = true;
    }

    function modifyLiquidities(bytes calldata unlockData, uint256) external payable {
        (bytes memory actions, bytes[] memory params) = abi.decode(unlockData, (bytes, bytes[]));
        uint8 action = uint8(actions[0]);
        if (action == 0x02) {
            (
                PoolKey memory key,,,
                uint256 liquidity,
                uint128 amount0Max,
                uint128 amount1Max,
                address recipient,
                bytes memory hookData
            ) = abi.decode(
                params[0], (PoolKey, int24, int24, uint256, uint128, uint128, address, bytes)
            );
            _checkHookData(hookData);
            if (enforceHook) require(address(key.hooks) == expectedHook, "HOOK");
            uint256 tokenId = nextTokenId++;
            ownerOf[tokenId] = recipient;
            _keys[tokenId] = key;
            require(liquidity <= type(uint128).max, "LIQUIDITY_OVERFLOW");
            // The preceding bound makes this mock cast exact.
            // forge-lint: disable-next-line(unsafe-typecast)
            positionLiquidity[tokenId] = uint128(liquidity);
            _pullPair(key, amount0Max, amount1Max);
            mintCalls++;
        } else if (action == 0x00) {
            (
                uint256 tokenId,
                uint256 liquidity,
                uint128 amount0Max,
                uint128 amount1Max,
                bytes memory hookData
            ) = abi.decode(params[0], (uint256, uint256, uint128, uint128, bytes));
            _checkHookData(hookData);
            require(ownerOf[tokenId] == msg.sender, "OWNER");
            require(liquidity <= type(uint128).max, "LIQUIDITY_OVERFLOW");
            // The preceding bound makes this mock cast exact.
            // forge-lint: disable-next-line(unsafe-typecast)
            positionLiquidity[tokenId] += uint128(liquidity);
            _pullPair(_keys[tokenId], amount0Max, amount1Max);
            increaseCalls++;
        } else if (action == 0x03) {
            (uint256 tokenId,,, bytes memory hookData) =
                abi.decode(params[0], (uint256, uint128, uint128, bytes));
            _checkHookData(hookData);
            (,, address recipient) = abi.decode(params[1], (Currency, Currency, address));
            require(ownerOf[tokenId] == msg.sender, "OWNER");
            PoolKey memory key = _keys[tokenId];
            positionLiquidity[tokenId] = 0;
            delete ownerOf[tokenId];
            _send(Currency.unwrap(key.currency0), recipient, settle0[tokenId]);
            _send(Currency.unwrap(key.currency1), recipient, settle1[tokenId]);
            settle0[tokenId] = 0;
            settle1[tokenId] = 0;
        } else {
            revert("ACTION");
        }
    }

    function getPositionLiquidity(uint256 tokenId) external view returns (uint128) {
        return positionLiquidity[tokenId];
    }

    function _pullPair(PoolKey memory key, uint128 amount0, uint128 amount1) private {
        _pull(Currency.unwrap(key.currency0), amount0);
        _pull(Currency.unwrap(key.currency1), amount1);
    }

    function _pull(address token, uint128 amount) private {
        if (amount != 0) permit2.transferFrom(msg.sender, address(this), uint160(amount), token);
    }

    function _send(address token, address recipient, uint256 amount) private {
        if (amount == 0) return;
        if (token == address(0)) {
            poolManager.sendNative(recipient, amount);
        } else {
            require(MockERC20(token).transfer(recipient, amount));
        }
    }

    function _checkHookData(bytes memory hookData) private view {
        if (enforceHookData) require(keccak256(hookData) == expectedHookDataHash, "HOOK_DATA");
    }

    receive() external payable { }
}
