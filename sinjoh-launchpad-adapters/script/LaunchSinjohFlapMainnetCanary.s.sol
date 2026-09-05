// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { SinjohFlapAdapter } from "../src/SinjohFlapAdapter.sol";
import { SinjohFlapAdapterFactory } from "../src/SinjohFlapAdapterFactory.sol";
import { IFlapPortalTypes } from "../src/interfaces/IFlap.sol";
import { Clones } from "../src/libraries/Clones.sol";
import { RouterTypes } from "sinjoh-fee-router/src/RouterTypes.sol";
import { SinjohFeeRouter } from "sinjoh-fee-router/src/SinjohFeeRouter.sol";
import { SinjohFeeRouterFactory } from "sinjoh-fee-router/src/SinjohFeeRouterFactory.sol";

interface VmSinjohFlapMainnetCanary {
    function envAddress(string calldata name) external view returns (address);
    function envBytes32(string calldata name) external view returns (bytes32);
    function startBroadcast(address signer) external;
    function stopBroadcast() external;
}

/// @notice Prepared Phase-1 canary script. Running it is a later, irreversible
/// phase: it creates a real mainnet token. Never broadcast without the explicit
/// canary-launch approval and freshly mined FLAP_TOKEN_SALT.
contract LaunchSinjohFlapMainnetCanary {
    error WrongChain(uint256 actual);
    error WrongDeployer(address actual);
    error DependencyMismatch(address dependency, bytes32 expected, bytes32 actual);
    error AddressMismatch(address expected, address actual);
    error PortalConfigurationMismatch(bytes32 expected, bytes32 actual);
    error InvalidVanitySalt(bytes32 salt, address predicted);
    error PredictedTokenAlreadyExists(address token);
    error DeploymentIncomplete();

    event SinjohFlapMainnetCanaryLaunched(
        address indexed subject,
        address indexed adapter,
        address indexed router,
        address taxProcessor,
        bytes32 userSalt,
        bytes32 tokenSalt,
        bytes32 portalConfigHash
    );

    uint256 private constant CHAIN_ID = 4_663;
    address private constant EXPECTED_DEPLOYER = 0x1A0925c9651836281FFe3EBD1D99d5D9739967EA;

    address private constant PORTAL = 0x26605f322f7fF986f381bB9A6e3f5DAb0bEaEb09;
    address private constant TAX_TOKEN_V3 = 0x7777C8743C88B3aff3cf262135beF2c8b2e83333;
    address private constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;
    address private constant REVENUE_COLLECTOR = 0x5Bb7582557F5be30b62c335Ad3ccf4bA79E138c5;

    bytes32 private constant PORTAL_CODEHASH =
        0xcecb292d9c022858199c9348abf0d5836f9ea4dab5cf03710e1dcf41fd9a4c35;
    bytes32 private constant TAX_TOKEN_V3_CODEHASH =
        0xa73abf611d52de6364ec684feed2ef3e9aec9706a02b808523e75a6d8438b164;
    bytes32 private constant WETH_CODEHASH =
        0x5706be52f64875fee65a2cec0d80e47a23d8793cbe85d214b48445e2d05f5353;
    bytes32 private constant REVENUE_COLLECTOR_CODEHASH =
        0x2a2605aed6c20353f19ea155b13605c9730f53b8b0fc9f2c1aea78433654789b;
    bytes32 private constant ROUTER_IMPLEMENTATION_CODEHASH =
        0x00eecc775b2dff40c52bdd038cdccc19b5812a527aa811b359a55249c6987276;
    bytes32 private constant REVIEWED_PORTAL_CONFIG_HASH =
        0xd11206f76d4086d0aab6f96707b25806347b07d7ef45197bf15699765ef975d3;
    uint16 private constant FLAP_FEE_RATE = 300;
    bytes4 private constant VERSION_SELECTOR = bytes4(keccak256("version()"));
    bytes4 private constant QUOTE_CONFIG_SELECTOR =
        bytes4(keccak256("getQuoteTokenConfiguration(address)"));

    VmSinjohFlapMainnetCanary private constant vm =
        VmSinjohFlapMainnetCanary(address(uint160(uint256(keccak256("hevm cheat code")))));

    struct Deployment {
        address adapter;
        address router;
        address subject;
        address taxProcessor;
        bytes32 userSalt;
        bytes32 tokenSalt;
    }

    function run() external returns (Deployment memory deployed) {
        if (block.chainid != CHAIN_ID) revert WrongChain(block.chainid);
        address deployer = vm.envAddress("DEPLOYER_ADDRESS");
        if (deployer != EXPECTED_DEPLOYER) revert WrongDeployer(deployer);

        SinjohFeeRouterFactory routerFactory =
            SinjohFeeRouterFactory(vm.envAddress("SINJOH_AGNOSTIC_ROUTER_FACTORY"));
        SinjohFlapAdapterFactory adapterFactory =
            SinjohFlapAdapterFactory(vm.envAddress("SINJOH_FLAP_ADAPTER_FACTORY"));
        _assertDependencies(routerFactory, adapterFactory);

        bytes32 currentPortalConfig = _portalConfigHash();
        if (currentPortalConfig != REVIEWED_PORTAL_CONFIG_HASH) {
            revert PortalConfigurationMismatch(REVIEWED_PORTAL_CONFIG_HASH, currentPortalConfig);
        }

        deployed.tokenSalt = vm.envBytes32("FLAP_TOKEN_SALT");
        deployed.subject =
            Clones.predictDeterministicAddress(TAX_TOKEN_V3, deployed.tokenSalt, PORTAL);
        if (uint16(uint160(deployed.subject)) != 0x7777) {
            revert InvalidVanitySalt(deployed.tokenSalt, deployed.subject);
        }
        if (deployed.subject.code.length != 0) {
            revert PredictedTokenAlreadyExists(deployed.subject);
        }

        deployed.userSalt =
            keccak256(abi.encode("SINJOH_FLAP_MAINNET_CANARY_V1", deployed.tokenSalt));
        deployed.adapter = adapterFactory.predictAddress(deployer, deployed.userSalt);
        deployed.router = routerFactory.predictLaunchpadAddress(deployer, deployed.userSalt);
        RouterTypes.Config memory config = _routerConfig(deployer, deployed.adapter);

        vm.startBroadcast(deployer);
        address actualRouter = routerFactory.deployForLaunchpad(deployer, deployed.userSalt, config);
        if (actualRouter != deployed.router) revert AddressMismatch(deployed.router, actualRouter);
        address actualAdapter = adapterFactory.deploy(deployer, deployed.router, deployed.userSalt);
        if (actualAdapter != deployed.adapter) {
            revert AddressMismatch(deployed.adapter, actualAdapter);
        }
        SinjohFlapAdapter adapter = SinjohFlapAdapter(payable(deployed.adapter));
        deployed.subject = adapter.launch(
            _launchParams(deployed.adapter, deployed.tokenSalt),
            REVIEWED_PORTAL_CONFIG_HASH,
            FLAP_FEE_RATE,
            0
        );
        deployed.taxProcessor = adapter.taxProcessor();
        vm.stopBroadcast();

        _assertDeployment(deployed, deployer);
        emit SinjohFlapMainnetCanaryLaunched(
            deployed.subject,
            deployed.adapter,
            deployed.router,
            deployed.taxProcessor,
            deployed.userSalt,
            deployed.tokenSalt,
            REVIEWED_PORTAL_CONFIG_HASH
        );
    }

    function _assertDependencies(
        SinjohFeeRouterFactory routerFactory,
        SinjohFlapAdapterFactory adapterFactory
    ) private view {
        _assertCodehash(PORTAL, PORTAL_CODEHASH);
        _assertCodehash(TAX_TOKEN_V3, TAX_TOKEN_V3_CODEHASH);
        _assertCodehash(WETH, WETH_CODEHASH);
        _assertCodehash(REVENUE_COLLECTOR, REVENUE_COLLECTOR_CODEHASH);
        _assertCodehash(
            address(routerFactory), vm.envBytes32("SINJOH_AGNOSTIC_ROUTER_FACTORY_CODEHASH")
        );
        _assertCodehash(
            address(adapterFactory), vm.envBytes32("SINJOH_FLAP_ADAPTER_FACTORY_CODEHASH")
        );

        address routerImplementation = routerFactory.implementation();
        _assertCodehash(routerImplementation, ROUTER_IMPLEMENTATION_CODEHASH);
        address adapterImplementation = adapterFactory.implementation();
        _assertCodehash(
            adapterImplementation, vm.envBytes32("SINJOH_FLAP_ADAPTER_IMPLEMENTATION_CODEHASH")
        );
        if (
            adapterFactory.portal() != PORTAL
                || adapterFactory.taxTokenImplementation() != TAX_TOKEN_V3
                || adapterFactory.flapWrappedNative() != WETH || adapterFactory.weth() != WETH
                || adapterFactory.deploymentChainId() != CHAIN_ID
        ) revert DeploymentIncomplete();
    }

    function _launchParams(address adapter, bytes32 tokenSalt)
        private
        pure
        returns (IFlapPortalTypes.NewTokenV6Params memory params)
    {
        params.name = "Sinjoh Flap Mainnet Canary";
        params.symbol = "SFLAPC";
        params.meta = "Sinjoh Flap adapter mainnet canary";
        params.dexThresh = IFlapPortalTypes.DexThreshType.FOUR_FIFTHS;
        params.salt = tokenSalt;
        params.migratorType = IFlapPortalTypes.MigratorType.V2_MIGRATOR;
        params.quoteToken = address(0);
        params.quoteAmt = 0;
        params.beneficiary = adapter;
        params.dexId = IFlapPortalTypes.DEXId.DEX0;
        params.lpFeeProfile = IFlapPortalTypes.V3LPFeeProfile.LP_FEE_PROFILE_STANDARD;
        params.buyTaxRate = 300;
        params.sellTaxRate = 1_000;
        params.taxDuration = 365 days;
        params.antiFarmerDuration = 1 days;
        params.mktBps = 10_000;
        params.dividendToken = address(0);
        params.commissionReceiver = adapter;
        params.tokenVersion = IFlapPortalTypes.TokenVersion.TOKEN_TAXED_V3;
    }

    function _routerConfig(address deployer, address adapter)
        private
        pure
        returns (RouterTypes.Config memory config)
    {
        RouterTypes.Allocation[] memory allocations = new RouterTypes.Allocation[](1);
        allocations[0] = RouterTypes.Allocation({
            destination: deployer,
            bps: 10_000,
            isSink: false,
            creatorMayRepoint: true,
            sinkConfig: ""
        });
        RouterTypes.Bucket[] memory buckets = new RouterTypes.Bucket[](1);
        buckets[0] = RouterTypes.Bucket({
            output: RouterTypes.AssetRef(RouterTypes.AssetKind.FIXED_ERC20, WETH),
            bps: 10_000,
            route: RouterTypes.Route(address(0), ""),
            priceGuard: address(0),
            maxAmountInPerCall: 10 ether,
            allocations: allocations
        });
        config = RouterTypes.Config({
            creator: deployer,
            protocolFeeRecipient: REVENUE_COLLECTOR,
            weth: WETH,
            launchpadAdapter: adapter,
            normalizations: new RouterTypes.Normalization[](0),
            buckets: buckets
        });
    }

    function _assertDeployment(Deployment memory deployed, address deployer) private view {
        SinjohFlapAdapter adapter = SinjohFlapAdapter(payable(deployed.adapter));
        SinjohFeeRouter router = SinjohFeeRouter(payable(deployed.router));
        if (
            deployed.subject.code.length == 0 || deployed.taxProcessor.code.length == 0
                || adapter.creator() != deployer || adapter.router() != deployed.router
                || adapter.subject() != deployed.subject
                || adapter.taxProcessor() != deployed.taxProcessor || !adapter.launched()
                || !adapter.feeRoutingIntact() || adapter.flapFeeRate() != FLAP_FEE_RATE
        ) revert DeploymentIncomplete();
        if (
            router.creator() != deployer || router.protocolFeeRecipient() != REVENUE_COLLECTOR
                || router.weth() != WETH || router.launchpadAdapter() != deployed.adapter
                || router.subject() != deployed.subject || !router.bound()
                || router.configHash() != adapter.routerConfigHash()
        ) revert DeploymentIncomplete();
    }

    function _portalConfigHash() private view returns (bytes32) {
        (bool versionSuccess, bytes memory versionData) =
            PORTAL.staticcall(abi.encodeWithSelector(VERSION_SELECTOR));
        (bool configSuccess, bytes memory configData) =
            PORTAL.staticcall(abi.encodeWithSelector(QUOTE_CONFIG_SELECTOR, address(0)));
        if (!versionSuccess || !configSuccess || versionData.length == 0 || configData.length == 0)
        {
            revert DeploymentIncomplete();
        }
        return keccak256(abi.encode(PORTAL.codehash, keccak256(versionData), keccak256(configData)));
    }

    function _assertCodehash(address target, bytes32 expected) private view {
        bytes32 actual = target.codehash;
        if (actual != expected) revert DependencyMismatch(target, expected, actual);
    }
}
