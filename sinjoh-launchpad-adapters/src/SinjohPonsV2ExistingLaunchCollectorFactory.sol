// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { SinjohPonsV2ExistingLaunchCollector } from "./SinjohPonsV2ExistingLaunchCollector.sol";

library ExistingLaunchRouterTypes {
    enum AssetKind {
        NATIVE,
        FIXED_ERC20,
        SUBJECT
    }

    struct AssetRef {
        AssetKind kind;
        address token;
    }

    struct Route {
        address adapter;
        bytes routeData;
    }

    struct Normalization {
        AssetRef asset;
        Route route;
        address priceGuard;
        uint128 maxAmountInPerCall;
    }

    struct Allocation {
        address destination;
        uint16 bps;
        bool isSink;
        bool creatorMayRepoint;
        bytes sinkConfig;
    }

    struct Bucket {
        AssetRef output;
        uint16 bps;
        Route route;
        address priceGuard;
        uint128 maxAmountInPerCall;
        Allocation[] allocations;
    }

    struct Config {
        address creator;
        address protocolFeeRecipient;
        address weth;
        address launchpadAdapter;
        Normalization[] normalizations;
        Bucket[] buckets;
    }
}

interface IRecoveryRouterInitializer {
    function initialize(ExistingLaunchRouterTypes.Config calldata config) external;
}

/// @notice Deterministically deploys and atomically binds one existing-launch recovery pair.
contract SinjohPonsV2ExistingLaunchCollectorFactory {
    error DeploymentMismatch(address expected, address actual);
    error InvalidConfiguration();
    error InvalidImplementation();
    error Unauthorized(address caller);

    event RecoveryDeployed(
        address indexed collector, address indexed router, address indexed subject, bytes32 userSalt
    );

    bytes32 public constant ROUTER_IMPLEMENTATION_CODEHASH =
        0x00eecc775b2dff40c52bdd038cdccc19b5812a527aa811b359a55249c6987276;

    address public immutable operator;
    address public immutable routerImplementation;

    constructor(address routerImplementation_) {
        if (
            routerImplementation_.code.length == 0
                || routerImplementation_.codehash != ROUTER_IMPLEMENTATION_CODEHASH
        ) revert InvalidImplementation();
        operator = msg.sender;
        routerImplementation = routerImplementation_;
    }

    function deployRecovery(
        address launchFactory,
        address subject,
        address previousRecipient,
        address weth,
        uint256 chainId,
        bytes32 userSalt,
        ExistingLaunchRouterTypes.Config calldata config
    ) external returns (address collector, address router) {
        if (msg.sender != operator) revert Unauthorized(msg.sender);
        router = predictRouter(config.creator, userSalt);
        collector = predictCollector(
            launchFactory, subject, previousRecipient, router, weth, chainId, userSalt
        );
        if (
            config.launchpadAdapter != collector || config.weth != weth
                || config.creator == address(0)
        ) revert InvalidConfiguration();

        if (collector.code.length == 0) {
            bytes32 collectorSalt = derivedCollectorSalt(subject, previousRecipient, userSalt);
            address deployedCollector = address(
                new SinjohPonsV2ExistingLaunchCollector{ salt: collectorSalt }(
                    launchFactory, subject, previousRecipient, router, weth, chainId
                )
            );
            if (deployedCollector != collector) {
                revert DeploymentMismatch(collector, deployedCollector);
            }
        }

        if (router.code.length != 0) revert InvalidConfiguration();
        bytes32 routerSalt = derivedRouterSalt(config.creator, userSalt);
        router = _cloneDeterministic(routerImplementation, routerSalt);
        if (router != predictRouter(config.creator, userSalt)) {
            revert DeploymentMismatch(predictRouter(config.creator, userSalt), router);
        }
        IRecoveryRouterInitializer(router).initialize(config);
        SinjohPonsV2ExistingLaunchCollector(payable(collector)).initializeRouter(router);
        emit RecoveryDeployed(collector, router, subject, userSalt);
    }

    function predictCollector(
        address launchFactory,
        address subject,
        address previousRecipient,
        address router,
        address weth,
        uint256 chainId,
        bytes32 userSalt
    ) public view returns (address collector) {
        bytes32 salt = derivedCollectorSalt(subject, previousRecipient, userSalt);
        bytes32 initCodeHash = keccak256(
            abi.encodePacked(
                type(SinjohPonsV2ExistingLaunchCollector).creationCode,
                abi.encode(launchFactory, subject, previousRecipient, router, weth, chainId)
            )
        );
        collector = address(
            uint160(
                uint256(
                    keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, initCodeHash))
                )
            )
        );
    }

    function predictRouter(address creator, bytes32 userSalt)
        public
        view
        returns (address predicted)
    {
        bytes32 salt = derivedRouterSalt(creator, userSalt);
        bytes32 initCodeHash = keccak256(
            abi.encodePacked(
                hex"3d602d80600a3d3981f3",
                hex"363d3d373d3d3d363d73",
                routerImplementation,
                hex"5af43d82803e903d91602b57fd5bf3"
            )
        );
        predicted = address(
            uint160(
                uint256(
                    keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, initCodeHash))
                )
            )
        );
    }

    function derivedCollectorSalt(address subject, address previousRecipient, bytes32 userSalt)
        public
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                "SINJOH_PONS_V2_EXISTING_LAUNCH_COLLECTOR",
                address(this),
                block.chainid,
                subject,
                previousRecipient,
                userSalt
            )
        );
    }

    function derivedRouterSalt(address creator, bytes32 userSalt) public view returns (bytes32) {
        return keccak256(
            abi.encode(
                "SINJOH_PONS_V2_EXISTING_LAUNCH_ROUTER",
                address(this),
                block.chainid,
                creator,
                userSalt
            )
        );
    }

    function _cloneDeterministic(address implementation, bytes32 salt)
        private
        returns (address instance)
    {
        bytes memory code = abi.encodePacked(
            hex"3d602d80600a3d3981f3",
            hex"363d3d373d3d3d363d73",
            implementation,
            hex"5af43d82803e903d91602b57fd5bf3"
        );
        assembly ("memory-safe") {
            instance := create2(0, add(code, 0x20), mload(code), salt)
        }
        if (instance == address(0)) revert InvalidConfiguration();
    }
}
