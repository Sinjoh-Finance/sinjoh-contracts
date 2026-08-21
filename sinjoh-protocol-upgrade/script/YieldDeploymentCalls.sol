// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IYieldAdapter } from "../src/interfaces/IYieldAdapter.sol";
import { YieldBasket } from "../src/YieldBasket.sol";
import { YieldDeploymentTypes } from "./YieldDeploymentTypes.sol";

library YieldDeploymentCalls {
    function build(YieldBasket basket, YieldDeploymentTypes.Parameters memory parameters)
        external
        pure
        returns (address[] memory targets, bytes[] memory calldatas)
    {
        uint256 routeBearingAdapters;
        for (uint256 i; i < parameters.adapters.length; ++i) {
            for (uint256 j; j < parameters.rewardRoutes.length; ++j) {
                if (parameters.rewardRoutes[j].adapter == parameters.adapters[i].adapter) {
                    ++routeBearingAdapters;
                    break;
                }
            }
        }
        targets = new address[](parameters.adapters.length + routeBearingAdapters);
        calldatas = new bytes[](targets.length);
        uint256 callIndex;
        for (uint256 i; i < parameters.adapters.length; ++i) {
            YieldDeploymentTypes.AdapterPlan memory adapter = parameters.adapters[i];
            targets[callIndex] = address(basket);
            calldatas[callIndex] = abi.encodeCall(
                basket.configureAdapter,
                (
                    IYieldAdapter(adapter.adapter),
                    adapter.allocationLimitBps,
                    adapter.distributionInterval
                )
            );
            ++callIndex;

            uint256 routeCount;
            for (uint256 j; j < parameters.rewardRoutes.length; ++j) {
                if (parameters.rewardRoutes[j].adapter == adapter.adapter) ++routeCount;
            }
            if (routeCount == 0) continue;
            YieldBasket.RewardRouteInput[] memory routes =
                new YieldBasket.RewardRouteInput[](routeCount);
            uint256 routeIndex;
            for (uint256 j; j < parameters.rewardRoutes.length; ++j) {
                YieldDeploymentTypes.RewardRoutePlan memory route = parameters.rewardRoutes[j];
                if (route.adapter != adapter.adapter) continue;
                routes[routeIndex++] = YieldBasket.RewardRouteInput({
                    rewardToken: route.rewardToken,
                    distributor: route.distributor,
                    distributionConfig: route.distributionConfig
                });
            }
            targets[callIndex] = address(basket);
            calldatas[callIndex] = abi.encodeCall(
                basket.setAdapterRewardRoutes, (IYieldAdapter(adapter.adapter), routes)
            );
            ++callIndex;
        }
    }
}
