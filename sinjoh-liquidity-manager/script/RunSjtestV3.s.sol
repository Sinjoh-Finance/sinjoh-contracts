// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { SinjohLiquidityManager } from "../src/SinjohLiquidityManager.sol";

interface VmRunSjtestV3 {
    function addr(uint256 privateKey) external returns (address);
    function envAddress(string calldata name) external returns (address);
    function envUint(string calldata name) external returns (uint256);
    function startBroadcast(uint256 privateKey) external;
    function stopBroadcast() external;
}

interface IERC20RunSjtestV3 {
    function approve(address spender, uint256 amount) external returns (bool);
}

contract RunSjtestV3 {
    address internal constant EXPECTED_DEPLOYER = 0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49;
    address internal constant SJTEST = 0x690caA9c7FF95e01d470Ec60Ed6aD57d794a38F5;
    address internal constant PONS_WETH = 0x37E402B8081eFcE1D82A09a066512278006e4691;
    uint256 internal constant NOTIONAL = 1_000_000_000_000;

    VmRunSjtestV3 internal constant vm =
        VmRunSjtestV3(address(uint160(uint256(keccak256("hevm cheat code")))));

    error WrongEnvironment();

    function run() external returns (uint256 tokenId, uint128 liquidity) {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address v3Adapter = vm.envAddress("V3_ADAPTER");
        address guard = vm.envAddress("PRICE_GUARD");
        address v3Manager = vm.envAddress("V3_MANAGER");
        if (block.chainid != 46_630 || vm.addr(deployerKey) != EXPECTED_DEPLOYER) {
            revert WrongEnvironment();
        }
        if (v3Adapter.code.length == 0 || guard.code.length == 0 || v3Manager.code.length == 0) {
            revert WrongEnvironment();
        }
        bytes memory routeData = abi.encode(uint160(0));
        SinjohLiquidityManager.Config memory config = SinjohLiquidityManager.Config({
            venue: SinjohLiquidityManager.Venue.UNISWAP_V3,
            quoteAsset: PONS_WETH,
            poolFee: 10_000,
            tickSpacing: 200,
            hooks: address(0),
            swapAdapter: v3Adapter,
            priceGuard: guard,
            swapRouteData: routeData,
            quoteSwapBps: 5_000,
            maxMintSlippageBps: 500,
            minNotionalPerMint: 1_000_000_000,
            maxNotionalPerMint: 2_000_000_000_000,
            minMintInterval: 0,
            feeMode: SinjohLiquidityManager.FeeMode.RECYCLE,
            feeRecipient: address(0)
        });

        vm.startBroadcast(deployerKey);
        IERC20RunSjtestV3(PONS_WETH).approve(v3Manager, NOTIONAL);
        SinjohLiquidityManager(payable(v3Manager))
            .fund(SJTEST, PONS_WETH, NOTIONAL, abi.encode(config));
        (tokenId, liquidity) = SinjohLiquidityManager(payable(v3Manager))
            .mint(EXPECTED_DEPLOYER, SJTEST, NOTIONAL, 1, "");
        vm.stopBroadcast();
    }
}
