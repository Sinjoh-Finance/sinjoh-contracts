// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { TestBase } from "./TestBase.sol";
import {
    ExistingLaunchRouterTypes,
    SinjohPonsV2ExistingLaunchCollectorFactory
} from "../src/SinjohPonsV2ExistingLaunchCollectorFactory.sol";
import {
    SinjohPonsV2ExistingLaunchCollector
} from "../src/SinjohPonsV2ExistingLaunchCollector.sol";
import { IPonsV2BondingCurve, IPonsV2LaunchFactory } from "../src/interfaces/IPonsV2.sol";

interface ISinjohPriceGuardRecovery {
    function minimumOutput(
        address subject,
        address assetIn,
        address assetOut,
        uint256 amountIn,
        bytes32 routeHash,
        bytes calldata guardData
    ) external view returns (uint256 minOut, uint48 validUntil);
}

interface IERC20Recovery {
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

interface VmRecoveryMock {
    function mockCall(address callee, bytes calldata data, bytes calldata returnData) external;
}

interface IPonsRecoveryAdmin {
    function setCreatorFeeRecipient(address token, address recipient) external;
    function pendingCreatorFeeRecipient(address token)
        external
        view
        returns (address newRecipient, uint64 effectiveAt, uint64 expiresAt);
}

interface IRecoveryRouter {
    function subject() external view returns (address);
    function bound() external view returns (bool);
    function launchpadAdapter() external view returns (address);
    function sync(address asset, uint256 minimum) external returns (uint256 gross, uint256 fee);
    function bucketInputOwed(uint8 bucket, address asset) external view returns (uint256);
    function processBucket(
        uint8 bucket,
        address input,
        uint256 amount,
        uint256 minimum,
        bytes calldata data
    ) external returns (uint256);
    function walletOwed(address recipient, address asset) external view returns (uint256);
    function sinkOwed(uint16 key, address asset) external view returns (uint256);
    function sendWallet(address recipient, address asset, uint256 amount) external;
    function fundSink(uint8 bucket, uint8 allocation, uint256 amount) external;
    function totalLiability(address asset) external view returns (uint256);
}

contract ExistingLaunchRecoveryMainnetForkTest is TestBase {
    struct AirdropConfig {
        uint128 minPayout;
        uint16 maxBatchSize;
        uint16 minConfirmations;
        address[] exclusions;
    }
    VmRecoveryMock constant recoveryMock =
        VmRecoveryMock(address(uint160(uint256(keccak256("hevm cheat code")))));
    address constant ELON = 0x8672065D4442cBa3688fd9325C1BA4A207509c0E;
    address constant CURVE = 0x9892Af394930D9C7398464e35c20D377B608AAb9;
    address constant TSLA = 0x322F0929c4625eD5bAd873c95208D54E1c003b2d;
    address constant TSLA_POOL = 0xA953CA88ff430e9487c60cA34d757414f4efdA07;
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
    uint256 constant CHAIN_ID = 4663;
    bytes32 constant USER_SALT = keccak256("ELON_CURRENT_FACTORY_RECOVERY_20260825");
    bytes32 constant ROUTER_CLONE_CODEHASH =
        0x9b92fd035acdf23a2c5d6ea1f89e4e21455d426c6d820cf4c6cca96bd0e6d6af;

    SinjohPonsV2ExistingLaunchCollectorFactory recoveryFactory;
    SinjohPonsV2ExistingLaunchCollector collector;
    IRecoveryRouter router;

    function setUp() public {
        string memory rpcUrl = vm.envOr("SINJOH_RPC_PRIMARY", string(""));
        require(bytes(rpcUrl).length != 0, "SINJOH_RPC_PRIMARY is required");
        vm.createSelectFork(rpcUrl);

        recoveryFactory = new SinjohPonsV2ExistingLaunchCollectorFactory(ROUTER_IMPLEMENTATION);
        address predictedRouter = recoveryFactory.predictRouter(CREATOR, USER_SALT);
        address predicted = recoveryFactory.predictCollector(
            PONS_FACTORY, ELON, OLD_ADAPTER, predictedRouter, WETH, CHAIN_ID, USER_SALT
        );
        ExistingLaunchRouterTypes.Config memory config = _config(predicted, predictedRouter);
        (address deployedCollector, address deployedRouter) = recoveryFactory.deployRecovery(
            PONS_FACTORY, ELON, OLD_ADAPTER, WETH, CHAIN_ID, USER_SALT, config
        );
        assertEq(deployedCollector, predicted);
        collector = SinjohPonsV2ExistingLaunchCollector(payable(deployedCollector));
        router = IRecoveryRouter(deployedRouter);
    }

    function test_exactElonRecoveryCutoverAndAllBuckets() public {
        assertEq(collector.subject(), ELON);
        assertEq(collector.curve(), CURVE);
        assertEq(collector.pairToken(), TSLA);
        assertEq(collector.previousRecipient(), OLD_ADAPTER);
        assertEq(collector.router(), address(router));
        assertTrue(router.bound());
        assertEq(router.subject(), ELON);
        assertEq(router.launchpadAdapter(), address(collector));
        assertEq(uint256(address(router).codehash), uint256(ROUTER_CLONE_CODEHASH));

        vm.prank(address(0xBAD));
        vm.expectRevert();
        collector.initializeRouter(address(router));

        vm.prank(address(0xBAD));
        vm.expectRevert();
        recoveryFactory.deployRecovery(
            PONS_FACTORY,
            ELON,
            OLD_ADAPTER,
            WETH,
            CHAIN_ID,
            USER_SALT,
            _config(address(collector), address(router))
        );

        vm.expectRevert();
        collector.activate();
        assertTrue(!collector.activated());
        IPonsV2LaunchFactory.LaunchedToken memory preLaunch =
            IPonsV2LaunchFactory(PONS_FACTORY).getLaunchedToken(ELON);
        assertEq(preLaunch.creatorFeeRecipient, OLD_ADAPTER);

        vm.prank(PONS_OWNER);
        IPonsRecoveryAdmin(PONS_FACTORY).setCreatorFeeRecipient(ELON, address(collector));
        (address proposed, uint64 effectiveAt,) =
            IPonsRecoveryAdmin(PONS_FACTORY).pendingCreatorFeeRecipient(ELON);
        assertEq(proposed, address(collector));

        address buyer = address(0xB0B);
        vm.prank(TSLA_POOL);
        IERC20Recovery(TSLA).transfer(buyer, 1 ether);
        vm.startPrank(buyer);
        IERC20Recovery(TSLA).approve(CURVE, type(uint256).max);
        IPonsV2BondingCurve(CURVE).buy(0.1 ether, 1, buyer);
        vm.stopPrank();
        uint256 directOld = 0.001 ether;
        vm.prank(buyer);
        IERC20Recovery(TSLA).transfer(OLD_ADAPTER, directOld);
        uint256 oldRouterBefore = IERC20Recovery(TSLA).balanceOf(OLD_ROUTER);

        vm.warp(effectiveAt);
        uint256 drained = collector.activate();
        assertTrue(drained > directOld);
        assertEq(IERC20Recovery(TSLA).balanceOf(OLD_ADAPTER), 0);
        assertEq(IERC20Recovery(TSLA).balanceOf(OLD_ROUTER) - oldRouterBefore, drained);
        IPonsV2LaunchFactory.LaunchedToken memory launch =
            IPonsV2LaunchFactory(PONS_FACTORY).getLaunchedToken(ELON);
        assertEq(launch.creatorFeeRecipient, address(collector));
        assertEq(_curveDeployer(), address(collector));
        assertTrue(collector.activated());

        vm.startPrank(buyer);
        IPonsV2BondingCurve(CURVE).buy(0.1 ether, 1, buyer);
        vm.stopPrank();
        uint256[] memory collected = collector.collect();
        assertTrue(collected[0] > 0);
        uint256 successorBefore = IERC20Recovery(TSLA).balanceOf(address(router));
        assertEq(collector.forward(TSLA), collected[0]);
        assertEq(IERC20Recovery(TSLA).balanceOf(address(router)) - successorBefore, collected[0]);

        bytes memory guardReturn = abi.encode(uint256(1), uint48(block.timestamp + 1 days));
        recoveryMock.mockCall(
            PAIR_GUARD,
            abi.encodeWithSelector(ISinjohPriceGuardRecovery.minimumOutput.selector),
            guardReturn
        );
        recoveryMock.mockCall(
            BUYBACK_GUARD,
            abi.encodeWithSelector(ISinjohPriceGuardRecovery.minimumOutput.selector),
            guardReturn
        );
        (, uint256 protocolFee) = router.sync(TSLA, 1);
        assertTrue(protocolFee > 0);

        for (uint8 i; i < 3; ++i) {
            uint256 owed = router.bucketInputOwed(i, WETH);
            assertTrue(owed > 0);
            router.processBucket(i, WETH, owed, 1, "");
        }
        uint256 airdropWeth = router.sinkOwed(0, WETH);
        uint256 burned = router.walletOwed(BURN, ELON);
        uint256 airdropTsla = router.sinkOwed(uint16(2) << 8, TSLA);
        assertTrue(airdropWeth > 0);
        assertTrue(burned > 0);
        assertTrue(airdropTsla > 0);

        uint256 supplyBefore = IERC20Recovery(ELON).totalSupply();
        router.fundSink(0, 0, airdropWeth);
        router.sendWallet(BURN, ELON, burned);
        router.fundSink(2, 0, airdropTsla);
        assertEq(IERC20Recovery(ELON).totalSupply(), supplyBefore);
        assertEq(IERC20Recovery(ELON).balanceOf(BURN), burned);
        assertEq(router.totalLiability(ELON), 0);
    }

    function _curveDeployer() private view returns (address value) {
        (bool ok, bytes memory result) = CURVE.staticcall(abi.encodeWithSignature("deployer()"));
        require(ok, "deployer read failed");
        value = abi.decode(result, (address));
    }

    function _config(address predictedCollector, address predictedRouter)
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
            _airdropConfig(predictedCollector, predictedRouter)
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
            _airdropConfig(predictedCollector, predictedRouter)
        );
        config = ExistingLaunchRouterTypes.Config({
            creator: CREATOR,
            protocolFeeRecipient: PROTOCOL,
            weth: WETH,
            launchpadAdapter: predictedCollector,
            normalizations: normalizations,
            buckets: buckets
        });
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
        allocations[0] = ExistingLaunchRouterTypes.Allocation({
            destination: destination,
            bps: 10_000,
            isSink: sink,
            creatorMayRepoint: false,
            sinkConfig: sinkConfig
        });
        bucket = ExistingLaunchRouterTypes.Bucket({
            output: ExistingLaunchRouterTypes.AssetRef(kind, token),
            bps: bps,
            route: ExistingLaunchRouterTypes.Route(
                adapter, adapter == address(0) ? bytes("") : abi.encode(uint24(3000))
            ),
            priceGuard: guard,
            maxAmountInPerCall: cap,
            allocations: allocations
        });
    }

    function _airdropConfig(address predictedCollector, address predictedRouter)
        private
        pure
        returns (bytes memory)
    {
        address[] memory exclusions = new address[](8);
        exclusions[0] = predictedCollector;
        exclusions[1] = predictedRouter;
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
        return abi.encode(
            AirdropConfig({
                minPayout: 1, maxBatchSize: 16, minConfirmations: 2, exclusions: exclusions
            })
        );
    }
}
