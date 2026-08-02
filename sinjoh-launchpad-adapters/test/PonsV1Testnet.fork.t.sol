// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { TestBase } from "./TestBase.sol";
import { SinjohPonsV1LaunchAdapter } from "../src/SinjohPonsV1LaunchAdapter.sol";
import { SinjohPonsV1LaunchAdapterFactory } from "../src/SinjohPonsV1LaunchAdapterFactory.sol";
import { IPonsV1LaunchFactory } from "../src/interfaces/IPonsV1.sol";
import { RouterTypes } from "sinjoh-fee-router/src/RouterTypes.sol";
import { SinjohFeeRouter } from "sinjoh-fee-router/src/SinjohFeeRouter.sol";
import { SinjohFeeRouterFactory } from "sinjoh-fee-router/src/SinjohFeeRouterFactory.sol";

contract TestnetRouteStub { }

/// @notice No-launch integration against the live Robinhood testnet Pons v1
/// dependencies. It proves steps 3-5 can be executed against current chain
/// state without spending testnet funds or creating a token.
contract PonsV1TestnetForkTest is TestBase {
    address constant PONS_FACTORY = 0x1160351B42ac027b9dFd3BFC497ee8985912c9dc;
    address constant PONS_LOCKER = 0x9E18AFba6eADDC1A00Edd35FB7AB6C5CD1E1dEE0;
    address constant WETH = 0x37E402B8081eFcE1D82A09a066512278006e4691;
    uint256 constant CHAIN_ID = 46_630;
    bytes32 constant FACTORY_CODEHASH =
        0xefffb34795f8459fc6e959cd387bd3062f1b4e7ca026b41f0e798a11f99d1a62;
    bytes32 constant LOCKER_CODEHASH =
        0xc98810d63174049c9debaab082a05f52ff16b6df65781dda07cc95d85a34730c;
    bytes32 constant WETH_CODEHASH =
        0xa7f01c02394c333cc82f3236a0212384759ac2b0a4b982db822e3ff691e6567d;

    string constant DEFAULT_RPC = "https://rpc.testnet.chain.robinhood.com";
    address constant CREATOR = address(0xC0FFEE);
    bytes32 constant USER_SALT = keccak256("pons-v1-testnet-router-2026-08-01");
    bytes32 constant TOKEN_SALT = keccak256("pons-v1-testnet-token-2026-08-01");

    function setUp() public {
        vm.createSelectFork(vm.envOr("ROBINHOOD_TESTNET_RPC_URL", DEFAULT_RPC));
    }

    function test_liveDependenciesAreExactlyPinned() public view {
        assertEq(block.chainid, CHAIN_ID);
        assertEq(IPonsV1LaunchFactory(PONS_FACTORY).locker(), PONS_LOCKER);
        assertTrue(IPonsV1LaunchFactory(PONS_FACTORY).launchEnabled());
        assertTrue(IPonsV1LaunchFactory(PONS_FACTORY).launchFee() > 0);
        assertEq(uint256(_codehash(PONS_FACTORY)), uint256(FACTORY_CODEHASH));
        assertEq(uint256(_codehash(PONS_LOCKER)), uint256(LOCKER_CODEHASH));
        assertEq(uint256(_codehash(WETH)), uint256(WETH_CODEHASH));

        (bool ok, bytes memory config) =
            PONS_FACTORY.staticcall(abi.encodeWithSignature("getLaunchConfig(uint256)", 0));
        assertTrue(ok && config.length >= 32);
        address pairToken = abi.decode(config, (address));
        assertEq(pairToken, WETH);
    }

    function test_predictDeployAndConfigureCurrentRouterWithoutLaunchingToken() public {
        SinjohFeeRouter implementation = new SinjohFeeRouter();
        SinjohFeeRouterFactory routerFactory = new SinjohFeeRouterFactory(address(implementation));
        SinjohPonsV1LaunchAdapterFactory adapterFactory =
            new SinjohPonsV1LaunchAdapterFactory(PONS_FACTORY, PONS_LOCKER, WETH, CHAIN_ID);

        address predictedAdapter = adapterFactory.predictAddress(CREATOR, USER_SALT);
        address predictedRouter = routerFactory.predictLaunchpadAddress(CREATOR, USER_SALT);
        TestnetRouteStub swapAdapter = new TestnetRouteStub();
        TestnetRouteStub priceGuard = new TestnetRouteStub();
        RouterTypes.Config memory config =
            _config(predictedAdapter, address(swapAdapter), address(priceGuard));

        vm.prank(CREATOR);
        address router = routerFactory.deployForLaunchpad(CREATOR, USER_SALT, config);
        assertEq(router, predictedRouter);
        vm.prank(CREATOR);
        address deployedAdapter = adapterFactory.deploy(CREATOR, router, USER_SALT);
        assertEq(deployedAdapter, predictedAdapter);

        SinjohPonsV1LaunchAdapter adapter = SinjohPonsV1LaunchAdapter(payable(deployedAdapter));
        assertEq(adapter.router(), router);
        assertEq(adapter.creator(), CREATOR);
        assertTrue(adapter.initialized());
        assertTrue(!adapter.launched());
        assertEq(adapter.subject(), address(0));

        SinjohFeeRouter configuredRouter = SinjohFeeRouter(payable(router));
        assertEq(configuredRouter.launchpadAdapter(), predictedAdapter);
        assertEq(configuredRouter.creator(), CREATOR);
        assertEq(configuredRouter.weth(), WETH);
        assertTrue(!configuredRouter.bound());
        assertTrue(configuredRouter.configHash() != bytes32(0));
        assertEq(uint256(adapter.routerConfigHash()), uint256(configuredRouter.configHash()));

        IPonsV1LaunchFactory.LaunchParams memory params;
        params.name = "Sinjoh Pons v1 Testnet";
        params.symbol = "SJPV1";
        params.description = "prediction only; no token launched";
        params.feeWallet = predictedAdapter;
        address predictedToken = IPonsV1LaunchFactory(PONS_FACTORY)
            .predictTokenAddress(params, 0, 0, TOKEN_SALT, predictedAdapter);
        assertTrue(predictedToken != address(0));
        assertEq(predictedToken.code.length, 0);
    }

    function _config(address adapter, address swapAdapter, address priceGuard)
        private
        pure
        returns (RouterTypes.Config memory config)
    {
        RouterTypes.Allocation[] memory allocations = new RouterTypes.Allocation[](1);
        allocations[0] = RouterTypes.Allocation({
            destination: CREATOR,
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
            maxAmountInPerCall: 1 ether,
            allocations: allocations
        });
        RouterTypes.Normalization[] memory normalizations = new RouterTypes.Normalization[](1);
        normalizations[0] = RouterTypes.Normalization({
            asset: RouterTypes.AssetRef(RouterTypes.AssetKind.SUBJECT, address(0)),
            route: RouterTypes.Route(swapAdapter, abi.encode(uint160(0))),
            priceGuard: priceGuard,
            maxAmountInPerCall: 1 ether
        });
        config = RouterTypes.Config({
            creator: CREATOR,
            protocolFeeRecipient: CREATOR,
            weth: WETH,
            launchpadAdapter: adapter,
            normalizations: normalizations,
            buckets: buckets
        });
    }

    function _codehash(address target) private view returns (bytes32 hash) {
        assembly {
            hash := extcodehash(target)
        }
    }
}
