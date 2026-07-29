// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { SinjohUniswapV3SwapAdapter } from "../src/SinjohUniswapV3SwapAdapter.sol";
import { SinjohV3TwapPriceGuard } from "../src/SinjohV3TwapPriceGuard.sol";

interface VmSjtestReverseExecution {
    function addr(uint256 privateKey) external returns (address);
    function envUint(string calldata name) external returns (uint256);
    function startBroadcast(uint256 privateKey) external;
    function stopBroadcast() external;
}

contract DeploySjtestReverseExecution {
    uint256 internal constant ROBINHOOD_TESTNET_CHAIN_ID = 46_630;
    address internal constant EXPECTED_DEPLOYER = 0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49;
    address internal constant SJTEST = 0x690caA9c7FF95e01d470Ec60Ed6aD57d794a38F5;
    address internal constant PONS_WETH = 0x37E402B8081eFcE1D82A09a066512278006e4691;
    address internal constant PONS_V3_POOL = 0xa0594e9a288939864C6A918e5dee7f65194f5730;
    address internal constant PONS_V3_ROUTER = 0x1b32F47434a7EF83E97d0675C823E547F9266725;
    address internal constant PONS_V3_FACTORY = 0xFECCB63CD759d768538458Ea56F47eA8004323c1;

    VmSjtestReverseExecution internal constant vm =
        VmSjtestReverseExecution(address(uint160(uint256(keccak256("hevm cheat code")))));

    error WrongEnvironment();
    error DeploymentFailed();

    function run()
        external
        returns (SinjohUniswapV3SwapAdapter reverseAdapter, SinjohV3TwapPriceGuard guard)
    {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        if (
            block.chainid != ROBINHOOD_TESTNET_CHAIN_ID || vm.addr(deployerKey) != EXPECTED_DEPLOYER
        ) revert WrongEnvironment();

        bytes memory routeData = abi.encode(uint160(0));
        vm.startBroadcast(deployerKey);
        reverseAdapter = new SinjohUniswapV3SwapAdapter(
            PONS_V3_ROUTER, PONS_V3_FACTORY, PONS_V3_POOL, SJTEST, PONS_WETH, 10_000
        );
        guard = new SinjohV3TwapPriceGuard(
            PONS_V3_POOL,
            SJTEST,
            PONS_WETH,
            keccak256(routeData),
            60,
            500,
            500,
            60,
            type(uint128).max,
            1_000_000_000
        );
        vm.stopBroadcast();

        if (address(reverseAdapter).code.length == 0 || address(guard).code.length == 0) {
            revert DeploymentFailed();
        }
    }
}
