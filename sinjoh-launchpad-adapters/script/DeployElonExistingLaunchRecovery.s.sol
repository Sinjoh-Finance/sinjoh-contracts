// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {
    ExistingLaunchRouterTypes,
    SinjohPonsV2ExistingLaunchCollectorFactory
} from "../src/SinjohPonsV2ExistingLaunchCollectorFactory.sol";
import {
    SinjohPonsV2ExistingLaunchCollector
} from "../src/SinjohPonsV2ExistingLaunchCollector.sol";
import { IPonsV2LaunchFactory } from "../src/interfaces/IPonsV2.sol";

interface VmElonRecovery {
    function startBroadcast() external;
    function stopBroadcast() external;
}

interface IPonsElonRecoveryAdmin {
    function owner() external view returns (address);
    function setCreatorFeeRecipient(address token, address recipient) external;
    function pendingCreatorFeeRecipient(address token)
        external
        view
        returns (address newRecipient, uint64 effectiveAt, uint64 expiresAt);
}

interface IElonRecoveryRouter {
    function subject() external view returns (address);
    function creator() external view returns (address);
    function protocolFeeRecipient() external view returns (address);
    function weth() external view returns (address);
    function launchpadAdapter() external view returns (address);
    function bound() external view returns (bool);
    function configHash() external view returns (bytes32);
}

contract DeployElonExistingLaunchRecovery {
    struct AirdropConfig {
        uint128 minPayout;
        uint16 maxBatchSize;
        uint16 minConfirmations;
        address[] exclusions;
    }

    uint256 constant CHAIN_ID = 4663;
    address constant ELON = 0x8672065D4442cBa3688fd9325C1BA4A207509c0E;
    address constant CURVE = 0x9892Af394930D9C7398464e35c20D377B608AAb9;
    address constant TSLA = 0x322F0929c4625eD5bAd873c95208D54E1c003b2d;
    address constant PONS_FACTORY = 0x7DCeEaB0A53684b001A4900768a52eAcDb27294e;
    address constant PONS_OWNER = 0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49;
    address constant OLD_ADAPTER = 0x56Df79BE02a103f4E54d9D4387dA0795D583780a;
    address constant OLD_ROUTER = 0xCeb2681417e0D234494885904c7219F3bfa6d309;
    address constant ROUTER_IMPLEMENTATION = 0x06274b69d4Cd4D98Ed7Cf4f45Fd50137e8A184a6;
    address constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;
    address constant CREATOR = 0xff7Fe63267A76a992571eaE7e10DA53B002C8073;
    address constant PROTOCOL = 0x5Bb7582557F5be30b62c335Ad3ccf4bA79E138c5;
    address constant AIRDROP = 0xA1d65242D367501D9A261389a69005e584F4786a;
    address constant BURN = 0x000000000000000000000000000000000000dEaD;
    address constant PAIR_ADAPTER = 0xc9F600ebaf9EE1F4a24568D2e4Af9E8df1e07D7B;
    address constant PAIR_GUARD = 0xd01273Fa749BF16e333cFB85D27fD11A82D1515D;
    address constant BUYBACK_ADAPTER = 0x1BE0E8F04221329FDfea34f41a1832a80c2c147c;
    address constant BUYBACK_GUARD = 0x902A6Fa8Ca273aAB186633FF27879Cd3703F6AED;
    bytes32 constant USER_SALT = keccak256("ELON_CURRENT_FACTORY_RECOVERY_20260825");
    bytes32 constant ROUTER_CLONE_CODEHASH =
        0x9b92fd035acdf23a2c5d6ea1f89e4e21455d426c6d820cf4c6cca96bd0e6d6af;

    VmElonRecovery constant vm =
        VmElonRecovery(address(uint160(uint256(keccak256("hevm cheat code")))));

    error WrongChain(uint256 actual);
    error InvalidLiveState();
    error VerificationFailed();

    function run()
        external
        returns (
            SinjohPonsV2ExistingLaunchCollectorFactory recoveryFactory,
            address collector,
            address router,
            uint64 effectiveAt,
            uint64 expiresAt
        )
    {
        if (block.chainid != CHAIN_ID) revert WrongChain(block.chainid);
        _assertPreProposalState();

        vm.startBroadcast();
        recoveryFactory = new SinjohPonsV2ExistingLaunchCollectorFactory(ROUTER_IMPLEMENTATION);
        router = recoveryFactory.predictRouter(CREATOR, USER_SALT);
        collector = recoveryFactory.predictCollector(
            PONS_FACTORY, ELON, OLD_ADAPTER, router, WETH, CHAIN_ID, USER_SALT
        );
        ExistingLaunchRouterTypes.Config memory config = _config(collector, router);
        (address deployedCollector, address deployedRouter) = recoveryFactory.deployRecovery(
            PONS_FACTORY, ELON, OLD_ADAPTER, WETH, CHAIN_ID, USER_SALT, config
        );
        vm.stopBroadcast();
        if (deployedCollector != collector || deployedRouter != router) {
            revert VerificationFailed();
        }
        _assertRecovery(recoveryFactory, collector, router, config);

        vm.startBroadcast();
        IPonsElonRecoveryAdmin(PONS_FACTORY).setCreatorFeeRecipient(ELON, collector);
        vm.stopBroadcast();

        (address pendingRecipient, uint64 pendingEffectiveAt, uint64 pendingExpiresAt) =
            IPonsElonRecoveryAdmin(PONS_FACTORY).pendingCreatorFeeRecipient(ELON);
        if (
            pendingRecipient != collector || pendingEffectiveAt <= block.timestamp
                || pendingExpiresAt != pendingEffectiveAt + 3 days
        ) revert VerificationFailed();
        effectiveAt = pendingEffectiveAt;
        expiresAt = pendingExpiresAt;
    }

    function _assertPreProposalState() private view {
        IPonsV2LaunchFactory.LaunchedToken memory launch =
            IPonsV2LaunchFactory(PONS_FACTORY).getLaunchedToken(ELON);
        (address pending,,) = IPonsElonRecoveryAdmin(PONS_FACTORY).pendingCreatorFeeRecipient(ELON);
        if (
            IPonsElonRecoveryAdmin(PONS_FACTORY).owner() != PONS_OWNER || !launch.exists
                || launch.curve != CURVE || launch.pairToken != TSLA
                || launch.creatorFeeRecipient != OLD_ADAPTER || launch.deployer != OLD_ADAPTER
                || pending != address(0)
        ) revert InvalidLiveState();
    }

    function _assertRecovery(
        SinjohPonsV2ExistingLaunchCollectorFactory recoveryFactory,
        address collector,
        address router,
        ExistingLaunchRouterTypes.Config memory config
    ) private view {
        SinjohPonsV2ExistingLaunchCollector deployed =
            SinjohPonsV2ExistingLaunchCollector(payable(collector));
        IElonRecoveryRouter deployedRouter = IElonRecoveryRouter(router);
        if (
            recoveryFactory.operator() != PONS_OWNER
                || recoveryFactory.routerImplementation() != ROUTER_IMPLEMENTATION
                || deployed.launchFactory() != PONS_FACTORY || deployed.subject() != ELON
                || deployed.curve() != CURVE || deployed.pairToken() != TSLA
                || deployed.previousRecipient() != OLD_ADAPTER || deployed.router() != router
                || deployedRouter.creator() != CREATOR
                || deployedRouter.protocolFeeRecipient() != PROTOCOL
                || deployedRouter.weth() != WETH || deployedRouter.launchpadAdapter() != collector
                || !deployedRouter.bound() || deployedRouter.subject() != ELON
                || deployedRouter.configHash() != keccak256(abi.encode(config))
                || router.codehash != ROUTER_CLONE_CODEHASH
        ) revert VerificationFailed();
    }

    function _config(address collector, address router)
        private
        pure
        returns (ExistingLaunchRouterTypes.Config memory config)
    {
        ExistingLaunchRouterTypes.Normalization[] memory normalizations =
            new ExistingLaunchRouterTypes.Normalization[](1);
        normalizations[0] = ExistingLaunchRouterTypes.Normalization({
            asset: ExistingLaunchRouterTypes.AssetRef(
                ExistingLaunchRouterTypes.AssetKind.FIXED_ERC20, TSLA
            ),
            route: ExistingLaunchRouterTypes.Route(PAIR_ADAPTER, abi.encode(uint24(3000))),
            priceGuard: PAIR_GUARD,
            maxAmountInPerCall: 70_302_249_240_160_682
        });
        ExistingLaunchRouterTypes.Bucket[] memory buckets =
            new ExistingLaunchRouterTypes.Bucket[](3);
        buckets[0] = _bucket(
            ExistingLaunchRouterTypes.AssetKind.FIXED_ERC20,
            WETH,
            2500,
            address(0),
            address(0),
            type(uint128).max,
            AIRDROP,
            true,
            _airdropConfig(collector, router)
        );
        buckets[1] = _bucket(
            ExistingLaunchRouterTypes.AssetKind.SUBJECT,
            address(0),
            5000,
            BUYBACK_ADAPTER,
            BUYBACK_GUARD,
            10 ether,
            BURN,
            false,
            ""
        );
        buckets[2] = _bucket(
            ExistingLaunchRouterTypes.AssetKind.FIXED_ERC20,
            TSLA,
            2500,
            PAIR_ADAPTER,
            PAIR_GUARD,
            0.01 ether,
            AIRDROP,
            true,
            _airdropConfig(collector, router)
        );
        config = ExistingLaunchRouterTypes.Config(
            CREATOR, PROTOCOL, WETH, collector, normalizations, buckets
        );
    }

    function _bucket(
        ExistingLaunchRouterTypes.AssetKind kind,
        address token,
        uint16 bps,
        address adapter,
        address guard,
        uint128 cap,
        address destination,
        bool sink,
        bytes memory sinkConfig
    ) private pure returns (ExistingLaunchRouterTypes.Bucket memory bucket) {
        ExistingLaunchRouterTypes.Allocation[] memory allocations =
            new ExistingLaunchRouterTypes.Allocation[](1);
        allocations[0] =
            ExistingLaunchRouterTypes.Allocation(destination, 10_000, sink, false, sinkConfig);
        bucket = ExistingLaunchRouterTypes.Bucket(
            ExistingLaunchRouterTypes.AssetRef(kind, token),
            bps,
            ExistingLaunchRouterTypes.Route(
                adapter, adapter == address(0) ? bytes("") : abi.encode(uint24(3000))
            ),
            guard,
            cap,
            allocations
        );
    }

    function _airdropConfig(address collector, address router) private pure returns (bytes memory) {
        address[] memory exclusions = new address[](8);
        exclusions[0] = collector;
        exclusions[1] = router;
        exclusions[2] = OLD_ADAPTER;
        exclusions[3] = OLD_ROUTER;
        exclusions[4] = PROTOCOL;
        exclusions[5] = CURVE;
        exclusions[6] = AIRDROP;
        exclusions[7] = CREATOR;
        for (uint256 i = 1; i < exclusions.length; ++i) {
            address value = exclusions[i];
            uint256 j = i;
            while (j > 0 && exclusions[j - 1] > value) {
                exclusions[j] = exclusions[j - 1];
                --j;
            }
            exclusions[j] = value;
        }
        return abi.encode(AirdropConfig(1, 16, 2, exclusions));
    }
}
