// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {
    IPonsV2LaunchFactory,
    IPonsV2BondingCurve
} from "sinjoh-launchpad-adapters/src/interfaces/IPonsV2.sol";
import { V4SinglePoolAllocationRoute } from "./V4SinglePoolAllocationRoute.sol";
import { IntegrationBinding } from "../libraries/IntegrationBinding.sol";

interface IPonsCurveSell {
    function sell(uint256, uint256, address) external returns (uint256);
}

interface IPonsGraduation {
    function graduate(address) external;
    function createGraduatedPool(address) external returns (uint256);
}

/// @notice Fixed canonical subject/quote route across bonding, graduation and V4 trading.
/// @dev Permissionless graduation is completed before trading a ready curve. A provider-side
/// rescue or failed graduation fails atomically. Partial curve fills also fail atomically.
contract PonsLifecycleAllocationRoute is V4SinglePoolAllocationRoute {
    using SafeERC20 for IERC20;
    address public immutable launchFactory;
    address public immutable curve;
    bytes32 public immutable factoryCodeHash;
    bytes32 public immutable curveCodeHash;

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
        curve = IPonsV2LaunchFactory(factory_).getLaunchedToken(subject_).curve;
        curveCodeHash = curve.codehash;
        if (curve.code.length == 0) revert InvalidConfiguration();
    }

    function _key(address factory_, address subject_) private view returns (PoolKey memory) {
        IPonsV2LaunchFactory factory = IPonsV2LaunchFactory(factory_);
        IPonsV2LaunchFactory.LaunchedToken memory launch = factory.getLaunchedToken(subject_);
        if (!launch.exists || launch.token != subject_ || launch.phase > 2) revert InvalidConfiguration();
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

    function _nativeSenderAllowed(address sender) internal view override returns (bool) {
        return sender == curve || super._nativeSenderAllowed(sender);
    }

    function _execute(uint256 amountIn, uint256 minimumOutput) internal override {
        IntegrationBinding.requireBound(launchFactory, factoryCodeHash);
        IntegrationBinding.requireBound(curve, curveCodeHash);
        IPonsV2LaunchFactory.LaunchedToken memory launch =
            IPonsV2LaunchFactory(launchFactory).getLaunchedToken(subject);
        if (launch.phase == 0 && IPonsV2BondingCurve(curve).readyToGraduate()) {
            IPonsGraduation(launchFactory).graduate(subject);
            launch.phase = 1;
        }
        if (launch.phase == 1) {
            IPonsGraduation(launchFactory).createGraduatedPool(subject);
            launch.phase = 2;
        }
        if (launch.phase == 2) {
            super._execute(amountIn, minimumOutput);
            return;
        }
        if (launch.phase != 0) revert InvalidConfiguration();
        if (buying && pairToken == address(0)) {
            IPonsV2BondingCurve(curve).buy{ value: amountIn }(
                amountIn, minimumOutput, address(this)
            );
        } else {
            IERC20(inputAsset).forceApprove(curve, amountIn);
            if (buying) IPonsV2BondingCurve(curve).buy(amountIn, minimumOutput, address(this));
            else IPonsCurveSell(curve).sell(amountIn, minimumOutput, address(this));
            IERC20(inputAsset).forceApprove(curve, 0);
        }
    }
}
