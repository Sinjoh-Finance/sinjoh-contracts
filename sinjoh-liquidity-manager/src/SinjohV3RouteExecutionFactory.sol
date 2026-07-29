// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { SinjohUniswapV3MultiHopSwapAdapter } from "./SinjohUniswapV3MultiHopSwapAdapter.sol";
import { SinjohUniswapV3SwapAdapter } from "./SinjohUniswapV3SwapAdapter.sol";
import { SinjohV3RouteGuardDeployer } from "./SinjohV3RouteGuardDeployer.sol";
import { SinjohV3RouteTwapPriceGuard } from "./SinjohV3RouteTwapPriceGuard.sol";

/// @notice Deterministically deploys the immutable execution dependencies a fee
/// bucket needs when its output asset has no direct pool with the subject.
/// @dev Companion to {SinjohV3ExecutionFactory}, which covers the quote-asset
/// and buyback routes. This one covers a bucket paying out an arbitrary token:
/// subject fees normalise through the quote asset in one atomic two-hop swap,
/// and quote-asset fees take the direct pool. Every child predeploys inactive,
/// so all four addresses are known before the subject and pool exist.
contract SinjohV3RouteExecutionFactory {
    error InvalidCreator();
    error InvalidRoute();
    error InvalidGuardDeployer();
    error ActivationFailed(address dependency, bytes reason);

    /// @notice Deploys this factory's price guards.
    /// @dev A factory embeds its children's creation code in its own runtime.
    /// Carrying the adapters and the guard together exceeded EIP-170, so guards
    /// come from a companion deployer fixed at construction.
    SinjohV3RouteGuardDeployer public immutable guardDeployer;

    constructor(address guardDeployer_) {
        if (guardDeployer_ == address(0) || guardDeployer_.code.length == 0) {
            revert InvalidGuardDeployer();
        }
        guardDeployer = SinjohV3RouteGuardDeployer(guardDeployer_);
    }

    /// @param subjectPool The subject/quote pool created by the launchpad.
    /// @param assetPool The quote/asset pool the payout token already trades in.
    struct AssetRoute {
        address router;
        address factory;
        address subject;
        address quoteAsset;
        address asset;
        address subjectPool;
        address assetPool;
        uint24 subjectPoolFee;
        uint24 assetPoolFee;
        uint32 twapWindow;
        uint16 maxSpotDeviationBps;
        uint16 maxOutputSlippageBps;
        uint48 validityPeriod;
        uint128 maxAmountIn;
        uint128 comparisonAmount;
    }

    /// @notice Every dependency one asset bucket needs, in configuration order.
    struct AssetRouteDependencies {
        address subjectAdapter;
        address subjectGuard;
        address quoteAdapter;
        address quoteGuard;
    }

    event MultiHopAdapterDeployed(
        address indexed adapter,
        address indexed creator,
        bytes32 indexed userSalt,
        bytes32 derivedSalt,
        bool created
    );
    event SwapAdapterDeployed(
        address indexed adapter,
        address indexed creator,
        bytes32 indexed userSalt,
        bytes32 derivedSalt,
        bool created
    );
    /// @notice The canonical `routeData` for a direct single-hop conversion.
    /// @dev One zero sqrt-price limit, meaning the router's full valid range.
    function directRouteData() public pure returns (bytes memory) {
        return abi.encode(uint160(0));
    }

    /// @notice The canonical `routeData` for the subject's two-hop conversion.
    function multiHopRouteData(AssetRoute calldata route) public pure returns (bytes memory) {
        return abi.encodePacked(
            route.subject, route.subjectPoolFee, route.quoteAsset, route.assetPoolFee, route.asset
        );
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

    /// @notice Deploys both conversions of one asset bucket and their guards.
    /// @dev Every child deployment stays idempotent, so an interrupted launch
    /// can resume by re-sending the identical call.
    function deployAssetRoute(address creator, bytes32 userSalt, AssetRoute calldata route)
        external
        returns (AssetRouteDependencies memory dependencies)
    {
        _validateRoute(route);

        dependencies.subjectAdapter = deployMultiHopAdapter(creator, userSalt, route);
        dependencies.subjectGuard =
            deployRouteGuard(creator, userSalt, _subjectGuardConfig(route));
        dependencies.quoteAdapter = deploySwapAdapter(
            creator,
            userSalt,
            route.router,
            route.factory,
            route.assetPool,
            route.quoteAsset,
            route.asset,
            route.assetPoolFee
        );
        dependencies.quoteGuard = deployRouteGuard(creator, userSalt, _quoteGuardConfig(route));
    }

    /// @notice The addresses {deployAssetRoute} will produce, before it runs.
    function predictAssetRoute(address creator, bytes32 userSalt, AssetRoute calldata route)
        external
        view
        returns (AssetRouteDependencies memory dependencies)
    {
        _validateRoute(route);

        dependencies.subjectAdapter = predictMultiHopAdapter(creator, userSalt, route);
        dependencies.subjectGuard =
            predictRouteGuard(creator, userSalt, _subjectGuardConfig(route));
        dependencies.quoteAdapter = predictSwapAdapter(
            creator,
            userSalt,
            route.router,
            route.factory,
            route.assetPool,
            route.quoteAsset,
            route.asset,
            route.assetPoolFee
        );
        dependencies.quoteGuard = predictRouteGuard(creator, userSalt, _quoteGuardConfig(route));
    }

    function deployMultiHopAdapter(address creator, bytes32 userSalt, AssetRoute calldata route)
        public
        returns (address adapter)
    {
        if (creator == address(0)) revert InvalidCreator();
        bytes32 salt = _multiHopSalt(creator, userSalt, route);
        adapter = predictMultiHopAdapter(creator, userSalt, route);
        bool created;
        if (adapter.code.length == 0) {
            adapter = address(
                new SinjohUniswapV3MultiHopSwapAdapter{ salt: salt }(
                    route.router,
                    route.factory,
                    route.subjectPool,
                    route.assetPool,
                    route.subject,
                    route.quoteAsset,
                    route.asset,
                    route.subjectPoolFee,
                    route.assetPoolFee
                )
            );
            created = true;
        }
        emit MultiHopAdapterDeployed(adapter, creator, userSalt, salt, created);
    }

    function predictMultiHopAdapter(
        address creator,
        bytes32 userSalt,
        AssetRoute calldata route
    ) public view returns (address) {
        if (creator == address(0)) revert InvalidCreator();
        bytes32 initCodeHash = keccak256(
            abi.encodePacked(
                type(SinjohUniswapV3MultiHopSwapAdapter).creationCode,
                abi.encode(
                    route.router,
                    route.factory,
                    route.subjectPool,
                    route.assetPool,
                    route.subject,
                    route.quoteAsset,
                    route.asset,
                    route.subjectPoolFee,
                    route.assetPoolFee
                )
            )
        );
        return _create2Address(_multiHopSalt(creator, userSalt, route), initCodeHash);
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
            adapter = address(
                new SinjohUniswapV3SwapAdapter{ salt: salt }(
                    router, factory, pool, assetIn, assetOut, poolFee
                )
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
        bytes32 initCodeHash = keccak256(
            abi.encodePacked(
                type(SinjohUniswapV3SwapAdapter).creationCode,
                abi.encode(router, factory, pool, assetIn, assetOut, poolFee)
            )
        );
        return _create2Address(
            _swapSalt(creator, userSalt, router, factory, pool, assetIn, assetOut, poolFee),
            initCodeHash
        );
    }

    function deployRouteGuard(
        address creator,
        bytes32 userSalt,
        SinjohV3RouteTwapPriceGuard.RouteGuard memory config
    ) public returns (address guard) {
        return guardDeployer.deployGuard(creator, userSalt, config);
    }

    function predictRouteGuard(
        address creator,
        bytes32 userSalt,
        SinjohV3RouteTwapPriceGuard.RouteGuard memory config
    ) public view returns (address) {
        return guardDeployer.predictGuard(creator, userSalt, config);
    }

    function _subjectGuardConfig(AssetRoute calldata route)
        private
        pure
        returns (SinjohV3RouteTwapPriceGuard.RouteGuard memory)
    {
        return SinjohV3RouteTwapPriceGuard.RouteGuard({
            factory: route.factory,
            subject: route.subject,
            assetIn: route.subject,
            midAsset: route.quoteAsset,
            assetOut: route.asset,
            firstPool: route.subjectPool,
            secondPool: route.assetPool,
            firstPoolFee: route.subjectPoolFee,
            secondPoolFee: route.assetPoolFee,
            routeHash: keccak256(multiHopRouteData(route)),
            twapWindow: route.twapWindow,
            maxSpotDeviationBps: route.maxSpotDeviationBps,
            maxOutputSlippageBps: route.maxOutputSlippageBps,
            validityPeriod: route.validityPeriod,
            maxAmountIn: route.maxAmountIn,
            comparisonAmount: route.comparisonAmount
        });
    }

    function _quoteGuardConfig(AssetRoute calldata route)
        private
        pure
        returns (SinjohV3RouteTwapPriceGuard.RouteGuard memory)
    {
        return SinjohV3RouteTwapPriceGuard.RouteGuard({
            factory: route.factory,
            subject: route.subject,
            assetIn: route.quoteAsset,
            midAsset: address(0),
            assetOut: route.asset,
            firstPool: route.assetPool,
            secondPool: address(0),
            firstPoolFee: route.assetPoolFee,
            secondPoolFee: 0,
            routeHash: keccak256(directRouteData()),
            twapWindow: route.twapWindow,
            maxSpotDeviationBps: route.maxSpotDeviationBps,
            maxOutputSlippageBps: route.maxOutputSlippageBps,
            validityPeriod: route.validityPeriod,
            maxAmountIn: route.maxAmountIn,
            comparisonAmount: route.comparisonAmount
        });
    }

    /// @dev Rejects shapes the children would reject anyway, so a caller
    /// predicting an address never gets one that cannot be deployed.
    function _validateRoute(AssetRoute calldata route) private pure {
        if (
            route.subject == address(0) || route.quoteAsset == address(0)
                || route.asset == address(0) || route.subject == route.quoteAsset
                || route.subject == route.asset || route.quoteAsset == route.asset
                || route.subjectPool == address(0) || route.assetPool == address(0)
                || route.subjectPool == route.assetPool
        ) revert InvalidRoute();
    }

    function _multiHopSalt(address creator, bytes32 userSalt, AssetRoute calldata route)
        private
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                block.chainid,
                creator,
                userSalt,
                route.router,
                route.factory,
                route.subjectPool,
                route.assetPool,
                route.subject,
                route.quoteAsset,
                route.asset,
                route.subjectPoolFee,
                route.assetPoolFee
            )
        );
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

    function _create2Address(bytes32 salt, bytes32 initCodeHash) private view returns (address) {
        return address(
            uint160(
                uint256(keccak256(abi.encodePacked(hex"ff", address(this), salt, initCodeHash)))
            )
        );
    }
}
