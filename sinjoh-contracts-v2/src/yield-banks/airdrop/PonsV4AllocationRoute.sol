// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { IPonsV2LaunchFactory } from "sinjoh-launchpad-adapters/src/interfaces/IPonsV2.sol";
import { V4SinglePoolAllocationRoute } from "./V4SinglePoolAllocationRoute.sol";

/// @notice Derives the immutable V4 route from Pons' canonical graduated launch record.
contract PonsV4AllocationRoute is V4SinglePoolAllocationRoute {
    address public immutable launchFactory;
    bytes32 public immutable factoryCodeHash;

    constructor(address factory_, address weth_, address subject_, bool buying_)
        V4SinglePoolAllocationRoute(
            IPonsV2LaunchFactory(factory_).poolManager(),
            weth_,
            subject_,
            buying_,
            _key(factory_, subject_)
        )
    {
        launchFactory = factory_;
        factoryCodeHash = factory_.codehash;
    }

    function _key(address factory_, address subject_) private view returns (PoolKey memory) {
        IPonsV2LaunchFactory factory = IPonsV2LaunchFactory(factory_);
        IPonsV2LaunchFactory.LaunchedToken memory launch = factory.getLaunchedToken(subject_);
        if (!launch.exists || launch.token != subject_ || launch.phase != 2) revert InvalidConfiguration();
        address pair = launch.pairToken;
        address hook_ = factory.memeHook();
        if (hook_.code.length == 0) revert InvalidConfiguration();
        return PoolKey(
            Currency.wrap(subject_ < pair ? subject_ : pair),
            Currency.wrap(subject_ < pair ? pair : subject_),
            launch.poolFee,
            launch.tickSpacing,
            IHooks(hook_)
        );
    }
}
