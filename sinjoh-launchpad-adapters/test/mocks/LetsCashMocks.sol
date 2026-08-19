// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { ILetsCashFactory } from "../../src/interfaces/ILetsCash.sol";
import { MockERC20 } from "./PonsV2Mocks.sol";

contract MockLetsCashToken is MockERC20 {
    address public deployer;
    address public factory;
    address public hook;
    bytes32 public poolId;

    constructor(address deployer_, address factory_, address hook_)
        MockERC20("LetsCash Test", "LCASH", 18)
    {
        deployer = deployer_;
        factory = factory_;
        hook = hook_;
    }

    function setPoolId(bytes32 poolId_) external {
        require(msg.sender == factory && poolId == bytes32(0), "pool set");
        poolId = poolId_;
    }
}

interface IMockLetsCashUnlockCallback {
    function unlockCallback(bytes calldata data) external returns (bytes memory);
}

contract MockLetsCashPoolManager {
    struct PoolKey {
        address currency0;
        address currency1;
        uint24 fee;
        int24 tickSpacing;
        address hooks;
    }

    struct SwapParams {
        bool zeroForOne;
        int256 amountSpecified;
        uint160 sqrtPriceLimitX96;
    }

    mapping(bytes32 => bytes32) private _slots;
    uint256 public rate = 1_000;
    bool private _unlocked;
    bool private _settled;

    function markPool(bytes32 poolId) external {
        bytes32 stateSlot = keccak256(abi.encodePacked(poolId, bytes32(uint256(6))));
        _slots[stateSlot] = bytes32(uint256(uint160(1 << 96)));
    }

    function extsload(bytes32 slot) external view returns (bytes32) {
        return _slots[slot];
    }

    function unlock(bytes calldata data) external returns (bytes memory result) {
        _unlocked = true;
        result = IMockLetsCashUnlockCallback(msg.sender).unlockCallback(data);
        require(_settled, "not settled");
        _unlocked = false;
        _settled = false;
    }

    function swap(PoolKey calldata, SwapParams calldata params, bytes calldata)
        external
        view
        returns (int256 delta)
    {
        require(_unlocked && params.zeroForOne, "bad swap");
        uint256 spent = uint256(-params.amountSpecified);
        uint256 output = spent * rate;
        delta = (-int256(spent) << 128) | int256(output);
    }

    function settle() external payable returns (uint256) {
        require(_unlocked, "locked");
        _settled = true;
        return msg.value;
    }

    function take(address currency, address to, uint256 amount) external {
        require(_unlocked, "locked");
        MockERC20(currency).mint(to, amount);
    }
}

contract MockLetsCashHook {
    struct PoolConfig {
        address creator;
        uint16 creatorFeeBps;
        uint24 feeRate;
        bool exists;
        address quote;
    }

    address public immutable factory;
    address public immutable poolManager;
    mapping(bytes32 => PoolConfig) public poolConfigs;
    mapping(bytes32 => uint256) public pending;

    constructor(address factory_, address poolManager_) {
        factory = factory_;
        poolManager = poolManager_;
    }

    function register(
        bytes32 poolId,
        address creator,
        address quote,
        uint16 creatorFeeBps,
        uint24 feeRate
    ) external {
        require(msg.sender == factory, "not factory");
        poolConfigs[poolId] = PoolConfig(creator, creatorFeeBps, feeRate, true, quote);
    }

    function credit(bytes32 poolId) external payable {
        pending[poolId] += msg.value;
    }

    function claim(bytes32 poolId) external returns (uint256 amount) {
        require(msg.sender == poolConfigs[poolId].creator, "not creator");
        amount = pending[poolId];
        pending[poolId] = 0;
        if (amount != 0) {
            (bool sent,) = payable(msg.sender).call{ value: amount }("");
            require(sent, "pay failed");
        }
    }
}

contract MockLetsCashFactory {
    address public immutable poolManager;
    address public hook;
    bool public launchEnabled = true;
    uint256 public launchFee = 0.0005 ether;

    mapping(uint256 => ILetsCashFactory.LaunchConfig) private _configs;
    mapping(uint256 => ILetsCashFactory.ModuleSet) private _modules;

    constructor(address poolManager_) {
        poolManager = poolManager_;
    }

    function setHook(address hook_) external {
        require(hook == address(0), "hook set");
        hook = hook_;
        _modules[0] = ILetsCashFactory.ModuleSet(hook_, address(1), address(2), address(3), true);
    }

    function setModuleHook(address hook_) external {
        _modules[0].hook = hook_;
    }

    function setLaunchEnabled(bool enabled) external {
        launchEnabled = enabled;
    }

    function setConfig(uint256 id, address quote, bool enabled, bool selfBurn) external {
        _configs[id] = ILetsCashFactory.LaunchConfig({
            moduleSetId: 0,
            quote: quote,
            supply: 1_000_000_000 ether,
            tickSpacing: 200,
            startTick: 204_200,
            creatorFeeBps: 7_000,
            feeRate: 10_000,
            enabled: enabled,
            selfBurn: selfBurn,
            exists: true
        });
    }

    function setCreatorFeeBps(uint256 id, uint16 creatorFeeBps) external {
        _configs[id].creatorFeeBps = creatorFeeBps;
    }

    function getLaunchConfig(uint256 id)
        external
        view
        returns (ILetsCashFactory.LaunchConfig memory)
    {
        return _configs[id];
    }

    function getModuleSet(uint256 id) external view returns (ILetsCashFactory.ModuleSet memory) {
        return _modules[id];
    }

    function launchWithFeeSplit(
        ILetsCashFactory.TokenParams calldata params,
        uint256 configId,
        uint256 firstBuyIn,
        uint256,
        bytes32,
        address[] calldata recipients,
        uint16[] calldata shares
    ) external payable returns (address token, bytes32 poolId) {
        require(launchEnabled, "paused");
        ILetsCashFactory.LaunchConfig memory config = _configs[configId];
        require(config.exists && config.enabled && !config.selfBurn, "bad config");
        require(config.quote == address(0), "not native");
        require(params.creator == msg.sender, "not creator");
        require(msg.value == launchFee + firstBuyIn, "value");
        require(recipients.length == 1 && shares.length == 1 && shares[0] == 10_000, "route");

        token = address(new MockLetsCashToken(msg.sender, address(this), hook));
        poolId = keccak256(abi.encode(address(0), token, uint24(0), config.tickSpacing, hook));
        MockLetsCashToken(token).setPoolId(poolId);
        MockLetsCashPoolManager(poolManager).markPool(poolId);
        MockLetsCashHook(hook)
            .register(poolId, recipients[0], config.quote, config.creatorFeeBps, config.feeRate);
        if (firstBuyIn != 0) MockLetsCashToken(token).mint(msg.sender, firstBuyIn * 1_000);
    }
}
