// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";

import { SinjohUniswapV3SwapAdapterClone } from "./SinjohUniswapV3SwapAdapterClone.sol";
import { SinjohV3TwapPriceGuard } from "./SinjohV3TwapPriceGuard.sol";

/// @notice Deterministically deploys immutable V3 execution dependencies before
/// a predicted subject and pool contain code.
contract SinjohV3ExecutionFactory {
    error InvalidCreator();
    error ActivationFailed(address dependency, bytes reason);

    address public immutable swapAdapterImplementation;

    struct V3RouteConfig {
        address router;
        address factory;
        address pool;
        address subject;
        address quoteAsset;
        uint24 poolFee;
        bytes32 routeHash;
        uint32 twapWindow;
        uint16 maxSpotDeviationBps;
        uint16 maxOutputSlippageBps;
        uint48 validityPeriod;
        uint128 maxAmountIn;
        uint128 comparisonAmount;
    }

    event SwapAdapterDeployed(
        address indexed adapter,
        address indexed creator,
        bytes32 indexed userSalt,
        bytes32 derivedSalt,
        bool created
    );
    event PriceGuardDeployed(
        address indexed guard,
        address indexed creator,
        bytes32 indexed userSalt,
        bytes32 derivedSalt,
        bool created
    );

    constructor() {
        swapAdapterImplementation = address(new SinjohUniswapV3SwapAdapterClone());
    }

    /// @notice Activates a set of immutable execution dependencies in one transaction.
    /// @dev Already-active dependencies are skipped so the operation is resumable.
    function activate(address[] calldata dependencies) external {
        for (uint256 i; i < dependencies.length; ++i) {
            address dependency = dependencies[i];
            (bool readOk, bytes memory result) =
                dependency.staticcall(abi.encodeWithSignature("active()"));
            if (!readOk || result.length != 32) {
                revert ActivationFailed(dependency, result);
            }
            if (abi.decode(result, (bool))) continue;
            (bool activateOk, bytes memory reason) =
                dependency.call(abi.encodeWithSignature("activate()"));
            if (!activateOk) revert ActivationFailed(dependency, reason);
        }
    }

    /// @notice Deploys both swap directions and their shared price guard atomically.
    /// @dev Every child deployment remains idempotent, so interrupted launches can resume.
    function deployRoute(address creator, bytes32 userSalt, V3RouteConfig calldata route)
        external
        returns (address forwardAdapter, address reverseAdapter, address guard)
    {
        forwardAdapter = deploySwapAdapter(
            creator,
            userSalt,
            route.router,
            route.factory,
            route.pool,
            route.quoteAsset,
            route.subject,
            route.poolFee
        );
        reverseAdapter = deploySwapAdapter(
            creator,
            userSalt,
            route.router,
            route.factory,
            route.pool,
            route.subject,
            route.quoteAsset,
            route.poolFee
        );
        guard = deployPriceGuard(
            creator,
            userSalt,
            route.pool,
            route.factory,
            route.subject,
            route.quoteAsset,
            route.poolFee,
            route.routeHash,
            route.twapWindow,
            route.maxSpotDeviationBps,
            route.maxOutputSlippageBps,
            route.validityPeriod,
            route.maxAmountIn,
            route.comparisonAmount
        );
    }

    function deploySwapAdapter(
        address creator,
        bytes32 userSalt,
        address router,
        address factory,
        address pool,
        address assetIn,
        address assetOut,
        uint24 poolFee
    ) public returns (address adapter) {
        if (creator == address(0)) revert InvalidCreator();
        bytes32 salt =
            _swapSalt(creator, userSalt, router, factory, pool, assetIn, assetOut, poolFee);
        adapter = predictSwapAdapter(
            creator, userSalt, router, factory, pool, assetIn, assetOut, poolFee
        );
        bool created;
        if (adapter.code.length == 0) {
            adapter = Clones.cloneDeterministicWithImmutableArgs(
                swapAdapterImplementation,
                _swapAdapterArgs(router, factory, pool, assetIn, assetOut, poolFee),
                salt
            );
            created = true;
        }
        emit SwapAdapterDeployed(adapter, creator, userSalt, salt, created);
    }

    function predictSwapAdapter(
        address creator,
        bytes32 userSalt,
        address router,
        address factory,
        address pool,
        address assetIn,
        address assetOut,
        uint24 poolFee
    ) public view returns (address) {
        if (creator == address(0)) revert InvalidCreator();
        bytes32 salt =
            _swapSalt(creator, userSalt, router, factory, pool, assetIn, assetOut, poolFee);
        return Clones.predictDeterministicAddressWithImmutableArgs(
            swapAdapterImplementation,
            _swapAdapterArgs(router, factory, pool, assetIn, assetOut, poolFee),
            salt,
            address(this)
        );
    }

    function deployPriceGuard(
        address creator,
        bytes32 userSalt,
        address oraclePool,
        address factory,
        address subject,
        address quoteAsset,
        uint24 poolFee,
        bytes32 routeHash,
        uint32 twapWindow,
        uint16 maxSpotDeviationBps,
        uint16 maxOutputSlippageBps,
        uint48 validityPeriod,
        uint128 maxAmountIn,
        uint128 comparisonAmount
    ) public returns (address guard) {
        if (creator == address(0)) revert InvalidCreator();
        bytes32 salt = _guardSalt(
            creator,
            userSalt,
            oraclePool,
            factory,
            subject,
            quoteAsset,
            poolFee,
            routeHash,
            twapWindow,
            maxSpotDeviationBps,
            maxOutputSlippageBps,
            validityPeriod,
            maxAmountIn,
            comparisonAmount
        );
        guard = predictPriceGuard(
            creator,
            userSalt,
            oraclePool,
            factory,
            subject,
            quoteAsset,
            poolFee,
            routeHash,
            twapWindow,
            maxSpotDeviationBps,
            maxOutputSlippageBps,
            validityPeriod,
            maxAmountIn,
            comparisonAmount
        );
        bool created;
        if (guard.code.length == 0) {
            guard = address(
                new SinjohV3TwapPriceGuard{ salt: salt }(
                    oraclePool,
                    factory,
                    subject,
                    quoteAsset,
                    poolFee,
                    routeHash,
                    twapWindow,
                    maxSpotDeviationBps,
                    maxOutputSlippageBps,
                    validityPeriod,
                    maxAmountIn,
                    comparisonAmount
                )
            );
            created = true;
        }
        emit PriceGuardDeployed(guard, creator, userSalt, salt, created);
    }

    function predictPriceGuard(
        address creator,
        bytes32 userSalt,
        address oraclePool,
        address factory,
        address subject,
        address quoteAsset,
        uint24 poolFee,
        bytes32 routeHash,
        uint32 twapWindow,
        uint16 maxSpotDeviationBps,
        uint16 maxOutputSlippageBps,
        uint48 validityPeriod,
        uint128 maxAmountIn,
        uint128 comparisonAmount
    ) public view returns (address) {
        if (creator == address(0)) revert InvalidCreator();
        bytes32 salt = _guardSalt(
            creator,
            userSalt,
            oraclePool,
            factory,
            subject,
            quoteAsset,
            poolFee,
            routeHash,
            twapWindow,
            maxSpotDeviationBps,
            maxOutputSlippageBps,
            validityPeriod,
            maxAmountIn,
            comparisonAmount
        );
        bytes32 initCodeHash = keccak256(
            abi.encodePacked(
                type(SinjohV3TwapPriceGuard).creationCode,
                abi.encode(
                    oraclePool,
                    factory,
                    subject,
                    quoteAsset,
                    poolFee,
                    routeHash,
                    twapWindow,
                    maxSpotDeviationBps,
                    maxOutputSlippageBps,
                    validityPeriod,
                    maxAmountIn,
                    comparisonAmount
                )
            )
        );
        return _create2Address(salt, initCodeHash);
    }

    function _swapSalt(
        address creator,
        bytes32 userSalt,
        address router,
        address factory,
        address pool,
        address assetIn,
        address assetOut,
        uint24 poolFee
    ) private view returns (bytes32) {
        return keccak256(
            abi.encode(
                block.chainid, creator, userSalt, router, factory, pool, assetIn, assetOut, poolFee
            )
        );
    }

    function _swapAdapterArgs(
        address router,
        address factory,
        address pool,
        address assetIn,
        address assetOut,
        uint24 poolFee
    ) private pure returns (bytes memory) {
        return abi.encode(router, factory, pool, assetIn, assetOut, poolFee);
    }

    function _guardSalt(
        address creator,
        bytes32 userSalt,
        address oraclePool,
        address factory,
        address subject,
        address quoteAsset,
        uint24 poolFee,
        bytes32 routeHash,
        uint32 twapWindow,
        uint16 maxSpotDeviationBps,
        uint16 maxOutputSlippageBps,
        uint48 validityPeriod,
        uint128 maxAmountIn,
        uint128 comparisonAmount
    ) private view returns (bytes32) {
        return keccak256(
            abi.encode(
                block.chainid,
                creator,
                userSalt,
                oraclePool,
                factory,
                subject,
                quoteAsset,
                poolFee,
                routeHash,
                twapWindow,
                maxSpotDeviationBps,
                maxOutputSlippageBps,
                validityPeriod,
                maxAmountIn,
                comparisonAmount
            )
        );
    }

    function _create2Address(bytes32 salt, bytes32 initCodeHash) private view returns (address) {
        return Create2.computeAddress(salt, initCodeHash);
    }
}
