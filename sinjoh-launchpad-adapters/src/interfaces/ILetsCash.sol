// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @dev ABI transcription of the live letscash.fun (CashCatFactoryVNext)
/// surface used by Sinjoh. Upstream Currency and PoolId are address/bytes32
/// user-defined value types, so their ABI representations are used directly.
interface ILetsCashFactory {
    struct Socials {
        string telegram;
        string twitter;
        string discord;
        string website;
        string extra;
    }

    struct TokenParams {
        string name;
        string symbol;
        string logo;
        string description;
        string metadataURI;
        Socials socials;
        address creator;
        uint256 supply;
    }

    struct LaunchConfig {
        uint256 moduleSetId;
        address quote;
        uint256 supply;
        int24 tickSpacing;
        int24 startTick;
        uint16 creatorFeeBps;
        uint24 feeRate;
        bool enabled;
        bool selfBurn;
        bool exists;
    }

    struct ModuleSet {
        address hook;
        address tokenMaster;
        address selfBurner;
        address splitterMaster;
        bool exists;
    }

    function launchWithFeeSplit(
        TokenParams calldata params,
        uint256 configId,
        uint256 firstBuyIn,
        uint256 firstBuyMinOut,
        bytes32 salt,
        address[] calldata recipients,
        uint16[] calldata shares
    ) external payable returns (address token, bytes32 poolId);

    function mineSalt(
        TokenParams calldata params,
        uint256 configId,
        address sender,
        uint256 start,
        uint256 rounds
    ) external view returns (bytes32 salt, address token);

    function getLaunchConfig(uint256 configId) external view returns (LaunchConfig memory);
    function getModuleSet(uint256 id) external view returns (ModuleSet memory);
    function launchEnabled() external view returns (bool);
    function launchFee() external view returns (uint256);
    function poolManager() external view returns (address);
}

interface ILetsCashHook {
    function factory() external view returns (address);
    function poolManager() external view returns (address);
    function claim(bytes32 poolId) external returns (uint256 amount);
    function poolConfigs(bytes32 poolId)
        external
        view
        returns (address creator, uint16 creatorFeeBps, uint24 feeRate, bool exists, address quote);
}

interface ILetsCashToken {
    function deployer() external view returns (address);
    function factory() external view returns (address);
    function hook() external view returns (address);
    function poolId() external view returns (bytes32);
}

interface ILetsCashWeth {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}
