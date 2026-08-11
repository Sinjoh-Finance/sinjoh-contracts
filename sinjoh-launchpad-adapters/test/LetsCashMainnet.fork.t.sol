// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { TestBase, Vm } from "./TestBase.sol";
import { SinjohLetsCashAdapter } from "../src/SinjohLetsCashAdapter.sol";
import { SinjohLetsCashAdapterFactory } from "../src/SinjohLetsCashAdapterFactory.sol";
import {
    SinjohLetsCashBuybackAdapter,
    SinjohLetsCashBuybackPriceGuard
} from "../src/SinjohLetsCashBuybackAdapter.sol";
import { ILetsCashFactory } from "../src/interfaces/ILetsCash.sol";
import { RouterTypes } from "sinjoh-fee-router/src/RouterTypes.sol";
import { SinjohFeeRouter } from "sinjoh-fee-router/src/SinjohFeeRouter.sol";
import { SinjohFeeRouterFactory } from "sinjoh-fee-router/src/SinjohFeeRouterFactory.sol";

interface ILetsCashBalance {
    function balanceOf(address account) external view returns (uint256);
}

/// @notice Exercises the current letscash.fun proxy and immutable v2 hook on a
/// local mainnet fork. No state change reaches Robinhood mainnet.
contract LetsCashMainnetForkTest is TestBase {
    uint256 private constant CHAIN_ID = 4_663;
    address private constant FACTORY = 0x5bd1Fbe78a78fe8236fa00CF48fbEBA74ae34661;
    address private constant POOL_MANAGER = 0x8366a39CC670B4001A1121B8F6A443A643e40951;
    address private constant HOOK = 0x75A54357D9C78a2Db19004a5FDc76c50F9242AEC;
    address private constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;
    uint256 private constant CONFIG_ID = 1_000;
    uint256 private constant SIGNER_KEY = uint256(keccak256("sinjoh-letscash-fork-signer"));
    address private constant CREATOR = address(0x1E75CA5);
    address private constant PROTOCOL_RECIPIENT = address(0x1001);
    address private constant TREASURY = address(0x2002);
    address private constant BURN = 0x000000000000000000000000000000000000dEaD;
    bytes32 private constant USER_SALT = keccak256("sinjoh-letscash-mainnet-fork");
    bytes32 private constant TOKEN_LAUNCHED_TOPIC = keccak256(
        "TokenLaunched(address,address,bytes32,uint256,uint256,uint256,address,address)"
    );
    string private constant DEFAULT_RPC = "https://rpc.mainnet.chain.robinhood.com";

    function setUp() public {
        vm.createSelectFork(vm.envOr("ROBINHOOD_MAINNET_RPC_URL", DEFAULT_RPC));
        vm.deal(CREATOR, 10 ether);
        vm.deal(address(this), 10 ether);
    }

    function _params() private pure returns (ILetsCashFactory.TokenParams memory params) {
        params = ILetsCashFactory.TokenParams({
            name: "Sinjoh LetsCash Fork",
            symbol: "SJLCF",
            logo: "ipfs://sinjoh-letscash-logo",
            description: "Sinjoh letscash.fun adapter fork proof",
            metadataURI: "ipfs://sinjoh-letscash-metadata",
            socials: ILetsCashFactory.Socials({
                telegram: "",
                twitter: "sinjoh",
                discord: "",
                website: "https://sinjoh.example",
                extra: ""
            }),
            creator: CREATOR
        });
    }

    function _routerConfig(
        address predictedAdapter,
        SinjohLetsCashBuybackAdapter buyback,
        SinjohLetsCashBuybackPriceGuard guard
    ) private pure returns (RouterTypes.Config memory config) {
        RouterTypes.Allocation[] memory buybackAllocations = new RouterTypes.Allocation[](1);
        buybackAllocations[0] = RouterTypes.Allocation({
            destination: BURN, bps: 10_000, isSink: false, creatorMayRepoint: false, sinkConfig: ""
        });
        RouterTypes.Allocation[] memory treasuryAllocations = new RouterTypes.Allocation[](1);
        treasuryAllocations[0] = RouterTypes.Allocation({
            destination: TREASURY,
            bps: 10_000,
            isSink: false,
            creatorMayRepoint: false,
            sinkConfig: ""
        });
        RouterTypes.Bucket[] memory buckets = new RouterTypes.Bucket[](2);
        buckets[0] = RouterTypes.Bucket({
            output: RouterTypes.AssetRef(RouterTypes.AssetKind.SUBJECT, address(0)),
            bps: 5_000,
            route: RouterTypes.Route(address(buyback), abi.encode(CONFIG_ID)),
            priceGuard: address(guard),
            maxAmountInPerCall: type(uint128).max,
            allocations: buybackAllocations
        });
        buckets[1] = RouterTypes.Bucket({
            output: RouterTypes.AssetRef(RouterTypes.AssetKind.FIXED_ERC20, WETH),
            bps: 5_000,
            route: RouterTypes.Route(address(0), ""),
            priceGuard: address(0),
            maxAmountInPerCall: type(uint128).max,
            allocations: treasuryAllocations
        });
        config = RouterTypes.Config({
            creator: CREATOR,
            protocolFeeRecipient: PROTOCOL_RECIPIENT,
            weth: WETH,
            launchpadAdapter: predictedAdapter,
            normalizations: new RouterTypes.Normalization[](0),
            buckets: buckets
        });
    }

    function _guardData(
        SinjohLetsCashBuybackPriceGuard guard,
        address router,
        address subject,
        uint256 amountIn,
        uint256 minimum
    ) private returns (bytes memory) {
        uint48 validAfter = uint48(block.timestamp - 1);
        uint48 validUntil = uint48(block.timestamp + 100);
        bytes32 digest = guard.floorDigest(
            router,
            subject,
            WETH,
            subject,
            amountIn,
            keccak256(abi.encode(CONFIG_ID)),
            minimum,
            validAfter,
            validUntil
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            SIGNER_KEY, keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", digest))
        );
        return abi.encode(minimum, validAfter, validUntil, abi.encodePacked(r, s, v));
    }

    function test_liveLaunchRunsFullRouterBuybackBurnAndTreasuryPath() public {
        assertEq(block.chainid, CHAIN_ID);
        SinjohLetsCashBuybackAdapter buyback = new SinjohLetsCashBuybackAdapter(
            FACTORY,
            POOL_MANAGER,
            HOOK,
            WETH,
            FACTORY.codehash,
            POOL_MANAGER.codehash,
            HOOK.codehash,
            WETH.codehash
        );
        SinjohLetsCashBuybackPriceGuard guard =
            new SinjohLetsCashBuybackPriceGuard(WETH, WETH.codehash, vm.addr(SIGNER_KEY));
        SinjohLetsCashAdapterFactory adapterFactory =
            new SinjohLetsCashAdapterFactory(FACTORY, POOL_MANAGER, HOOK, WETH, CHAIN_ID);
        address predictedAdapter = adapterFactory.predictAddress(CREATOR, USER_SALT);
        SinjohFeeRouter implementation = new SinjohFeeRouter();
        SinjohFeeRouterFactory routerFactory = new SinjohFeeRouterFactory(address(implementation));
        address predictedRouter = routerFactory.predictLaunchpadAddress(CREATOR, USER_SALT);
        vm.prank(CREATOR);
        SinjohFeeRouter router = SinjohFeeRouter(
            payable(routerFactory.deployForLaunchpad(
                    CREATOR, USER_SALT, _routerConfig(predictedAdapter, buyback, guard)
                ))
        );
        assertEq(address(router), predictedRouter);
        vm.prank(CREATOR);
        SinjohLetsCashAdapter adapter = SinjohLetsCashAdapter(
            payable(adapterFactory.deploy(CREATOR, address(router), USER_SALT))
        );

        ILetsCashFactory.TokenParams memory params = _params();
        (bytes32 salt,) = ILetsCashFactory(FACTORY).mineSalt(params, CONFIG_ID, CREATOR, 1, 200_000);
        address[] memory recipients = new address[](1);
        uint16[] memory shares = new uint16[](1);
        recipients[0] = address(adapter);
        shares[0] = 10_000;
        uint256 launchFee = ILetsCashFactory(FACTORY).launchFee();
        uint256 firstBuyIn = 0.001 ether;
        vm.recordLogs();
        vm.prank(CREATOR);
        (address token, bytes32 poolId) = ILetsCashFactory(FACTORY)
        .launchWithFeeSplit{ value: launchFee + firstBuyIn }(
            params, CONFIG_ID, firstBuyIn, 1, salt, recipients, shares
        );
        Vm.Log[] memory launchLogs = vm.getRecordedLogs();
        bool foundLaunchEvent;
        for (uint256 i; i < launchLogs.length; ++i) {
            Vm.Log memory entry = launchLogs[i];
            if (
                entry.emitter != FACTORY || entry.topics.length != 4
                    || entry.topics[0] != TOKEN_LAUNCHED_TOPIC
            ) continue;
            (
                uint256 eventConfigId,
                uint256 eventFirstBuyIn,
                uint256 eventFirstBuyOut,
                address eventHook,
                address eventFeeRecipient
            ) = abi.decode(entry.data, (uint256, uint256, uint256, address, address));
            assertEq(address(uint160(uint256(entry.topics[1]))), token);
            assertEq(address(uint160(uint256(entry.topics[2]))), CREATOR);
            assertTrue(entry.topics[3] == poolId);
            assertEq(eventConfigId, CONFIG_ID);
            assertEq(eventFirstBuyIn, firstBuyIn);
            assertTrue(eventFirstBuyOut > 0);
            assertEq(eventHook, HOOK);
            assertEq(eventFeeRecipient, address(adapter));
            foundLaunchEvent = true;
            break;
        }
        assertTrue(foundLaunchEvent);
        assertTrue(ILetsCashBalance(token).balanceOf(CREATOR) > 0);

        vm.prank(CREATOR);
        adapter.activate(token, poolId, CONFIG_ID);
        assertEq(adapter.subject(), token);
        assertEq(router.subject(), token);
        assertTrue(adapter.feeRoutingIntact());

        (, bytes32 resolvedPoolId,) = buyback.resolvePoolKey(token, CONFIG_ID);
        assertTrue(resolvedPoolId == poolId);
        assertTrue(buyback.spotQuote(token, CONFIG_ID, 0.001 ether) > 0);

        uint256[] memory collected = adapter.collect();
        assertTrue(collected[0] > 0);
        assertEq(ILetsCashBalance(WETH).balanceOf(address(adapter)), collected[0]);
        assertEq(adapter.forward(WETH), collected[0]);
        assertEq(ILetsCashBalance(WETH).balanceOf(address(router)), collected[0]);

        (uint256 gross, uint256 protocolFee) = router.sync(WETH, 0);
        assertEq(gross, collected[0]);
        assertEq(protocolFee, collected[0] / 100);
        uint256 buybackInput = router.bucketInputOwed(0, WETH);
        uint256 treasuryInput = router.bucketInputOwed(1, WETH);
        assertTrue(buybackInput > 0 && treasuryInput > 0);

        uint256 spot = buyback.spotQuote(token, CONFIG_ID, buybackInput);
        router.processBucket(
            0,
            WETH,
            buybackInput,
            0,
            _guardData(guard, address(router), token, buybackInput, spot * 8_000 / 10_000)
        );
        uint256 burned = router.walletOwed(BURN, token);
        assertTrue(burned > 0);
        router.sendWallet(BURN, token, burned);

        router.processBucket(1, WETH, treasuryInput, 0, "");
        router.sendWallet(TREASURY, WETH, treasuryInput);
        router.sendProtocolFee(WETH, protocolFee);

        assertEq(ILetsCashBalance(token).balanceOf(BURN), burned);
        assertEq(ILetsCashBalance(WETH).balanceOf(TREASURY), treasuryInput);
        assertEq(ILetsCashBalance(WETH).balanceOf(PROTOCOL_RECIPIENT), protocolFee);
        assertEq(ILetsCashBalance(WETH).balanceOf(address(router)), 0);
        assertEq(ILetsCashBalance(token).balanceOf(address(router)), 0);
        assertEq(router.totalLiability(WETH), 0);
        assertEq(router.totalLiability(token), 0);
    }
}
