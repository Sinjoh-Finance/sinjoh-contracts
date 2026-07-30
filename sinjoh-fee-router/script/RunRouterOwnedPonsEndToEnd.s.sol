// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { RouterTypes } from "../src/RouterTypes.sol";
import { SinjohFeeRouter } from "../src/SinjohFeeRouter.sol";
import { SinjohFeeRouterFactory } from "../src/SinjohFeeRouterFactory.sol";
import { IPonsV1LaunchFactory } from "../src/interfaces/IPonsV1.sol";

interface VmRouterOwnedEndToEnd {
    function addr(uint256 privateKey) external returns (address);
    function envUint(string calldata name) external returns (uint256);
    function startBroadcast(uint256 privateKey) external;
    function stopBroadcast() external;
}

interface IERC20RouterOwnedEndToEnd {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
}

interface IPonsFeeRouterEndToEnd {
    function launchFee() external view returns (uint256);
}

contract RunRouterOwnedPonsEndToEnd {
    uint256 internal constant ROBINHOOD_TESTNET_CHAIN_ID = 46_630;
    address internal constant EXPECTED_DEPLOYER = 0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49;
    address internal constant FACTORY = 0xd19cCBfE7a5159e43E30719e8f1d88bD6324cd16;
    address internal constant PONS_FACTORY = 0x1160351B42ac027b9dFd3BFC497ee8985912c9dc;
    address internal constant WETH = 0x37E402B8081eFcE1D82A09a066512278006e4691;
    address internal constant SWAP_ADAPTER = 0x1D5a12305F8cb32537F3A710806C159F24231aCe;
    address internal constant REVENUE_COLLECTOR = 0x1e22b9B257c73b309F1fcDA3508A48755896619b;
    uint256 internal constant DEVELOPER_BUY = 0.00005 ether;

    VmRouterOwnedEndToEnd internal constant vm =
        VmRouterOwnedEndToEnd(address(uint160(uint256(keccak256("hevm cheat code")))));

    error WrongChain(uint256 actual);
    error WrongDeployer(address actual);
    error EndToEndFailed();

    function run() external returns (address routerAddress, address subject) {
        if (block.chainid != ROBINHOOD_TESTNET_CHAIN_ID) revert WrongChain(block.chainid);
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        if (deployer != EXPECTED_DEPLOYER) revert WrongDeployer(deployer);

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
            allocations: allocations
        });
        RouterTypes.Config memory config = RouterTypes.Config({
            creator: deployer,
            protocolFeeRecipient: REVENUE_COLLECTOR,
            weth: WETH,
            subjectToWeth: RouterTypes.Route(SWAP_ADAPTER, abi.encode(uint24(10_000))),
            buckets: buckets
        });
        bytes32 routerSalt = keccak256("router-owned-live-e2e-2026-07-29-2");
        bytes32 launchSalt = keccak256("router-owned-live-token-2026-07-29-2");

        vm.startBroadcast(deployerKey);
        routerAddress = SinjohFeeRouterFactory(FACTORY).deployPons(deployer, routerSalt, config);
        SinjohFeeRouter router = SinjohFeeRouter(payable(routerAddress));
        IPonsV1LaunchFactory.LaunchParams memory params = IPonsV1LaunchFactory.LaunchParams({
            name: "Sinjoh Router Owned Test",
            symbol: "SROT",
            logo: "",
            description: "Sinjoh router-owned Pons launch end-to-end test",
            socials: IPonsV1LaunchFactory.Socials({
                twitter: "", telegram: "", discord: "", website: "", farcaster: ""
            }),
            feeWallet: routerAddress
        });
        uint256 launchValue = IPonsFeeRouterEndToEnd(PONS_FACTORY).launchFee() + DEVELOPER_BUY;
        subject =
            router.launchPonsToken{ value: launchValue }(PONS_FACTORY, params, 0, 0, launchSalt);

        IERC20RouterOwnedEndToEnd subjectToken = IERC20RouterOwnedEndToEnd(subject);
        uint256 developerTokens = subjectToken.balanceOf(deployer);
        if (developerTokens == 0) revert EndToEndFailed();
        if (!subjectToken.transfer(routerAddress, developerTokens / 2)) {
            revert EndToEndFailed();
        }

        router.collectPonsFees();
        router.sync(subject);
        router.sync(WETH);
        uint256 bucketAmount = router.bucketInputOwed(0, WETH);
        if (bucketAmount == 0) revert EndToEndFailed();
        router.processBucket(0, WETH, bucketAmount, 0, "");
        uint256 walletAmount = router.walletOwed(deployer, WETH);
        router.sendWallet(deployer, WETH, walletAmount);
        uint256 protocolAmount = router.protocolOwed(WETH);
        router.sendProtocolFee(WETH, protocolAmount);
        vm.stopBroadcast();

        if (
            !router.bound() || router.subject() != subject
                || router.ponsLaunchFactory() != PONS_FACTORY || router.totalLiability(WETH) != 0
                || subjectToken.balanceOf(routerAddress) != 0
                || IERC20RouterOwnedEndToEnd(WETH).balanceOf(routerAddress) != 0
        ) {
            revert EndToEndFailed();
        }
    }
}
