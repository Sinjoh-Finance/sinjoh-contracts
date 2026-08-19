// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { SinjohFlapAdapter } from "../src/SinjohFlapAdapter.sol";
import { SinjohFlapAdapterFactory } from "../src/SinjohFlapAdapterFactory.sol";
import { IFlapPortalTypes } from "../src/interfaces/IFlap.sol";
import { RouterTypes } from "sinjoh-fee-router/src/RouterTypes.sol";
import { SinjohFeeRouter } from "sinjoh-fee-router/src/SinjohFeeRouter.sol";
import { SinjohFeeRouterFactory } from "sinjoh-fee-router/src/SinjohFeeRouterFactory.sol";

interface VmSinjohFlapTestnet {
    function envUint(string calldata name) external view returns (uint256);
    function envOr(string calldata name, uint256 defaultValue) external view returns (uint256);
    function addr(uint256 privateKey) external pure returns (address);
    function startBroadcast(uint256 privateKey) external;
    function stopBroadcast() external;
}

/// @notice Deploys a fresh Flap adapter factory, mutually configured router
/// and adapter clones, and a real Tax Token V3 through the live testnet Portal.
contract DeploySinjohFlapTestnet {
    error WrongChain(uint256 actual);
    error WrongDeployer(address actual);
    error DependencyMismatch(address dependency, bytes32 expected, bytes32 actual);
    error AddressMismatch(address expected, address actual);
    error UnexpectedExistingCode(address target);
    error DeploymentIncomplete();

    event SinjohFlapTestnetDeployed(
        address indexed adapterFactory,
        address indexed adapter,
        address indexed router,
        address subject,
        address taxProcessor,
        bytes32 userSalt,
        bytes32 tokenSalt,
        bytes32 portalConfigHash
    );

    uint256 private constant CHAIN_ID = 46_630;
    address private constant EXPECTED_DEPLOYER = 0x1A0925c9651836281FFe3EBD1D99d5D9739967EA;

    address private constant PORTAL = 0x26605f322f7fF986f381bB9A6e3f5DAb0bEaEb09;
    address private constant TAX_TOKEN_V3 = 0x7777C8743C88B3aff3cf262135beF2c8b2e83333;
    address private constant FLAP_WRAPPED_NATIVE = 0x7943e237c7F95DA44E0301572D358911207852Fa;
    address private constant ROUTER_WETH = 0x37E402B8081eFcE1D82A09a066512278006e4691;
    address private constant ROUTER_IMPLEMENTATION = 0x06274b69d4Cd4D98Ed7Cf4f45Fd50137e8A184a6;
    address private constant ROUTER_FACTORY = 0xA1F721a697Dd03a45f264F53bCBFd121212318eD;

    bytes32 private constant PORTAL_CODEHASH =
        0xcecb292d9c022858199c9348abf0d5836f9ea4dab5cf03710e1dcf41fd9a4c35;
    bytes32 private constant TAX_TOKEN_V3_CODEHASH =
        0xa73abf611d52de6364ec684feed2ef3e9aec9706a02b808523e75a6d8438b164;
    bytes32 private constant FLAP_WRAPPED_NATIVE_CODEHASH =
        0x5706be52f64875fee65a2cec0d80e47a23d8793cbe85d214b48445e2d05f5353;
    bytes32 private constant ROUTER_WETH_CODEHASH =
        0xa7f01c02394c333cc82f3236a0212384759ac2b0a4b982db822e3ff691e6567d;
    bytes32 private constant ROUTER_IMPLEMENTATION_CODEHASH =
        0x00eecc775b2dff40c52bdd038cdccc19b5812a527aa811b359a55249c6987276;
    bytes32 private constant ROUTER_FACTORY_CODEHASH =
        0x9c409cacd26cd9e6acdf403ce14afa94c263a666886b2fec1a9e2af2063b4ca9;

    bytes32 private constant USER_SALT = keccak256("SINJOH_FLAP_TESTNET_2026-08-01");
    bytes32 private constant TOKEN_SALT =
        0x3b26f5b3439bcb21fcc5112fc947d6d66a9d4bff284314d6d39e99b121f22ab5;
    address private constant PREDICTED_TOKEN = 0xB16B82bF5F5AA6E6cABC57402DA37E9308997777;
    uint16 private constant FLAP_FEE_RATE = 300;

    VmSinjohFlapTestnet private constant vm =
        VmSinjohFlapTestnet(address(uint160(uint256(keccak256("hevm cheat code")))));

    struct Deployment {
        address adapterFactory;
        address adapterImplementation;
        address adapter;
        address router;
        address subject;
        address taxProcessor;
        bytes32 portalConfigHash;
    }

    function run() external returns (Deployment memory deployed) {
        if (block.chainid != CHAIN_ID) revert WrongChain(block.chainid);
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        if (deployer != EXPECTED_DEPLOYER) revert WrongDeployer(deployer);
        _assertDependencies();
        if (PREDICTED_TOKEN.code.length != 0) revert UnexpectedExistingCode(PREDICTED_TOKEN);

        uint256 developerBuy = vm.envOr("FLAP_DEVELOPER_BUY_WEI", uint256(0));
        uint256 minDeveloperBuyOut = vm.envOr("FLAP_MIN_DEVELOPER_BUY_OUT", uint256(0));
        if (developerBuy != 0 && minDeveloperBuyOut == 0) revert DeploymentIncomplete();

        vm.startBroadcast(deployerKey);

        SinjohFlapAdapterFactory adapterFactory = new SinjohFlapAdapterFactory(
            PORTAL, TAX_TOKEN_V3, FLAP_WRAPPED_NATIVE, ROUTER_WETH, CHAIN_ID
        );
        deployed.adapterFactory = address(adapterFactory);
        deployed.adapterImplementation = adapterFactory.implementation();
        deployed.adapter = adapterFactory.predictAddress(deployer, USER_SALT);

        SinjohFeeRouterFactory routerFactory = SinjohFeeRouterFactory(ROUTER_FACTORY);
        deployed.router = routerFactory.predictLaunchpadAddress(deployer, USER_SALT);
        RouterTypes.Config memory config = _routerConfig(deployer, deployed.adapter);
        address actualRouter = routerFactory.deployForLaunchpad(deployer, USER_SALT, config);
        if (actualRouter != deployed.router) revert AddressMismatch(deployed.router, actualRouter);
        address actualAdapter = adapterFactory.deploy(deployer, deployed.router, USER_SALT);
        if (actualAdapter != deployed.adapter) {
            revert AddressMismatch(deployed.adapter, actualAdapter);
        }

        SinjohFlapAdapter adapter = SinjohFlapAdapter(payable(deployed.adapter));
        if (adapter.predictSubject(TOKEN_SALT) != PREDICTED_TOKEN) {
            revert AddressMismatch(PREDICTED_TOKEN, adapter.predictSubject(TOKEN_SALT));
        }
        deployed.portalConfigHash = adapter.portalConfigHash();
        deployed.subject = adapter.launch{ value: developerBuy }(
            _launchParams(deployed.adapter, developerBuy),
            deployed.portalConfigHash,
            FLAP_FEE_RATE,
            minDeveloperBuyOut
        );
        deployed.taxProcessor = adapter.taxProcessor();

        vm.stopBroadcast();

        _assertDeployment(deployed, deployer);
        emit SinjohFlapTestnetDeployed(
            deployed.adapterFactory,
            deployed.adapter,
            deployed.router,
            deployed.subject,
            deployed.taxProcessor,
            USER_SALT,
            TOKEN_SALT,
            deployed.portalConfigHash
        );
    }

    function _launchParams(address adapter, uint256 developerBuy)
        private
        pure
        returns (IFlapPortalTypes.NewTokenV6Params memory params)
    {
        params.name = "Sinjoh Flap Testnet";
        params.symbol = "SFLAP";
        params.meta = "Sinjoh Flap adapter live testnet launch";
        params.dexThresh = IFlapPortalTypes.DexThreshType.FOUR_FIFTHS;
        params.salt = TOKEN_SALT;
        params.migratorType = IFlapPortalTypes.MigratorType.V2_MIGRATOR;
        params.quoteToken = address(0);
        params.quoteAmt = developerBuy;
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
            output: RouterTypes.AssetRef(RouterTypes.AssetKind.FIXED_ERC20, ROUTER_WETH),
            bps: 10_000,
            route: RouterTypes.Route(address(0), ""),
            priceGuard: address(0),
            maxAmountInPerCall: 10 ether,
            allocations: allocations
        });
        config = RouterTypes.Config({
            creator: deployer,
            protocolFeeRecipient: deployer,
            weth: ROUTER_WETH,
            launchpadAdapter: adapter,
            normalizations: new RouterTypes.Normalization[](0),
            buckets: buckets
        });
    }

    function _assertDependencies() private view {
        _assertCodehash(PORTAL, PORTAL_CODEHASH);
        _assertCodehash(TAX_TOKEN_V3, TAX_TOKEN_V3_CODEHASH);
        _assertCodehash(FLAP_WRAPPED_NATIVE, FLAP_WRAPPED_NATIVE_CODEHASH);
        _assertCodehash(ROUTER_WETH, ROUTER_WETH_CODEHASH);
        _assertCodehash(ROUTER_IMPLEMENTATION, ROUTER_IMPLEMENTATION_CODEHASH);
        _assertCodehash(ROUTER_FACTORY, ROUTER_FACTORY_CODEHASH);
        if (SinjohFeeRouterFactory(ROUTER_FACTORY).implementation() != ROUTER_IMPLEMENTATION) {
            revert AddressMismatch(
                ROUTER_IMPLEMENTATION, SinjohFeeRouterFactory(ROUTER_FACTORY).implementation()
            );
        }
    }

    function _assertDeployment(Deployment memory deployed, address deployer) private view {
        SinjohFlapAdapter adapter = SinjohFlapAdapter(payable(deployed.adapter));
        SinjohFeeRouter router = SinjohFeeRouter(payable(deployed.router));
        if (deployed.subject != PREDICTED_TOKEN || deployed.subject.code.length == 0) {
            revert AddressMismatch(PREDICTED_TOKEN, deployed.subject);
        }
        if (
            adapter.router() != deployed.router || adapter.creator() != deployer
                || adapter.subject() != deployed.subject || !adapter.launched()
                || adapter.taxProcessor() != deployed.taxProcessor
                || deployed.taxProcessor.code.length == 0 || !adapter.feeRoutingIntact()
        ) revert DeploymentIncomplete();
        if (
            router.launchpadAdapter() != deployed.adapter || router.creator() != deployer
                || router.weth() != ROUTER_WETH || !router.bound()
                || router.subject() != deployed.subject
                || adapter.routerConfigHash() != router.configHash()
        ) revert DeploymentIncomplete();
    }

    function _assertCodehash(address target, bytes32 expected) private view {
        bytes32 actual = target.codehash;
        if (actual != expected) revert DependencyMismatch(target, expected, actual);
    }
}
