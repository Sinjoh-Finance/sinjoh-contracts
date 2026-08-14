// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import { ISinjohLaunchVerifier } from "../interfaces/ISinjohLaunchVerifier.sol";

interface IPonsV1LaunchFactory {
    struct LaunchedToken {
        address token;
        address deployer;
        address pairedToken;
        address positionManager;
        uint256 positionId;
        uint256 dexId;
        uint256 launchConfigId;
        uint256 restrictionsEndBlock;
        uint256 supply;
        bool isToken0;
        uint24 poolFee;
        bool exists;
        uint256 initialBuyAmount;
    }

    function getLaunchedToken(address token) external view returns (LaunchedToken memory);
}

contract SinjohPonsV1LaunchVerifier is ISinjohLaunchVerifier {
    error InvalidAddress();
    error InvalidLaunch();

    IPonsV1LaunchFactory public immutable ponsFactory;
    IUniswapV3Factory public immutable v3Factory;
    address public immutable v3PositionManager;
    address public immutable weth;

    constructor(
        address ponsFactory_,
        address v3Factory_,
        address v3PositionManager_,
        address weth_
    ) {
        if (
            ponsFactory_.code.length == 0 || v3Factory_.code.length == 0
                || v3PositionManager_.code.length == 0 || weth_.code.length == 0
        ) revert InvalidAddress();
        ponsFactory = IPonsV1LaunchFactory(ponsFactory_);
        v3Factory = IUniswapV3Factory(v3Factory_);
        v3PositionManager = v3PositionManager_;
        weth = weth_;
    }

    function verify(address subject, bytes calldata launchData)
        external
        view
        returns (VerifiedLaunch memory launch)
    {
        if (launchData.length != 0) revert InvalidLaunch();
        IPonsV1LaunchFactory.LaunchedToken memory record = ponsFactory.getLaunchedToken(subject);
        if (
            !record.exists || record.token != subject || record.deployer == address(0)
                || record.pairedToken != weth || record.positionManager != v3PositionManager
                || record.supply == 0
        ) revert InvalidLaunch();
        address pool = v3Factory.getPool(subject, weth, record.poolFee);
        if (pool.code.length == 0) revert InvalidLaunch();
        int24 tickSpacing = IUniswapV3Pool(pool).tickSpacing();
        if (tickSpacing <= 0) revert InvalidLaunch();

        launch = VerifiedLaunch({
            creatorAtLaunch: record.deployer,
            subject: subject,
            venue: Venue.UNISWAP_V3,
            quoteAsset: weth,
            pool: pool,
            poolFee: record.poolFee,
            tickSpacing: tickSpacing,
            hooks: address(0),
            poolId: bytes32(0),
            launchSupply: record.supply
        });
    }
}
