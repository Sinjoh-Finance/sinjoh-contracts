// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { RouterTypes } from "../src/RouterTypes.sol";
import { SinjohFeeRouter } from "../src/SinjohFeeRouter.sol";
import { SinjohFeeRouterFactory } from "../src/SinjohFeeRouterFactory.sol";

interface Vm {
    function addr(uint256 privateKey) external returns (address);
    function envUint(string calldata name) external returns (uint256);
    function startBroadcast(uint256 privateKey) external;
    function stopBroadcast() external;
}

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
}

interface ILiquidityManager {
    function mint(
        address funder,
        address subject,
        uint256 notional,
        uint256 callerMinOut,
        bytes calldata guardData
    ) external returns (uint256 tokenId, uint128 liquidity);
}

/// @notice Repeatable live test of the complete simple WETH-first route.
contract TestnetSimpleFlow {
    struct AirdropConfig {
        uint128 minPayout;
        uint16 maxBatchSize;
        uint16 minConfirmations;
        address[] exclusions;
    }

    struct LiquidityConfig {
        uint8 venue;
        address quoteAsset;
        uint24 poolFee;
        int24 tickSpacing;
        address hooks;
        address swapAdapter;
        address priceGuard;
        bytes swapRouteData;
        uint16 quoteSwapBps;
        uint16 maxMintSlippageBps;
        uint128 minNotionalPerMint;
        uint128 maxNotionalPerMint;
        uint48 minMintInterval;
        uint8 feeMode;
        address feeRecipient;
    }

    uint256 internal constant CHAIN_ID = 46_630;
    address internal constant EXPECTED_DEPLOYER = 0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49;
    address internal constant FACTORY = 0x035f13b39DA594fF97BF53E7aCAc7aC670E12079;
    address internal constant ADAPTER = 0x1D5a12305F8cb32537F3A710806C159F24231aCe;
    address internal constant TESTNET_GUARD = 0x22eccE7132Ed5AC4c496E498ea24aAE77B8A82fD;
    address internal constant REVENUE_COLLECTOR = 0x1e22b9B257c73b309F1fcDA3508A48755896619b;
    address internal constant AIRDROP = 0x55b8b547D811FA9c356E7493b04A275CB2E21e54;
    address internal constant LIQUIDITY = 0xF9A5808200F41a0a61655CA5C764bEaA637D440D;
    address internal constant WETH = 0x37E402B8081eFcE1D82A09a066512278006e4691;
    address internal constant SUBJECT = 0x690caA9c7FF95e01d470Ec60Ed6aD57d794a38F5;
    address internal constant TSLA = 0xC9f9c86933092BbbfFF3CCb4b105A4A94bf3Bd4E;
    address internal constant AMD = 0x71178BAc73cBeb415514eB542a8995b82669778d;
    address internal constant BURN = 0x000000000000000000000000000000000000dEaD;

    uint256 internal constant SUBJECT_INPUT = 2_000 ether;
    uint256 internal constant WETH_INPUT = 100_000_000_000;

    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    error WrongChain(uint256 chainId);
    error WrongDeployer(address deployer);
    error TransferFailed();
    error IncompleteDrain(address asset, uint256 balance, uint256 liability);

    event LiveFlowPassed(
        address indexed router,
        uint256 normalizedSubject,
        uint256 directWeth,
        uint256 liquidityPositionId,
        uint128 liquidity
    );

    function run() external returns (address routerAddress) {
        if (block.chainid != CHAIN_ID) revert WrongChain(block.chainid);
        uint256 key = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(key);
        if (deployer != EXPECTED_DEPLOYER) revert WrongDeployer(deployer);

        RouterTypes.Config memory config = _config(deployer);
        bytes32 salt = keccak256("SINJOH_SIMPLE_WETH_E2E_20260729_1");

        vm.startBroadcast(key);
        routerAddress = SinjohFeeRouterFactory(FACTORY).deploy(deployer, salt, config);
        SinjohFeeRouter router = SinjohFeeRouter(payable(routerAddress));
        if (!router.bound()) router.bind(SUBJECT);

        if (!IERC20(SUBJECT).transfer(routerAddress, SUBJECT_INPUT)) {
            revert TransferFailed();
        }
        if (!IERC20(WETH).transfer(routerAddress, WETH_INPUT)) {
            revert TransferFailed();
        }

        (uint256 normalizedSubject,) = router.sync(SUBJECT);
        router.sync(WETH);

        for (uint8 bucketId; bucketId < 5; ++bucketId) {
            uint256 pending = router.bucketInputOwed(bucketId, WETH);
            router.processBucket(bucketId, WETH, pending, 0, "");
        }

        uint256 protocol = router.protocolOwed(WETH);
        if (protocol != 0) router.sendProtocolFee(WETH, protocol);

        _sendWallet(router, deployer, WETH);
        _sendWallet(router, deployer, address(0));
        _sendWallet(router, deployer, TSLA);
        _sendWallet(router, BURN, SUBJECT);
        _sendWallet(router, BURN, AMD);

        _fundSink(router, 0, 1);
        uint256 lpAmount = _fundSink(router, 0, 2);
        _fundSink(router, 3, 1);

        (uint256 tokenId, uint128 liquidity) =
            ILiquidityManager(LIQUIDITY).mint(routerAddress, SUBJECT, lpAmount, 0, "");

        _assertDrained(router, WETH);
        _assertDrained(router, address(0));
        _assertDrained(router, SUBJECT);
        _assertDrained(router, TSLA);
        _assertDrained(router, AMD);
        vm.stopBroadcast();

        emit LiveFlowPassed(routerAddress, normalizedSubject, WETH_INPUT, tokenId, liquidity);
    }

    function _config(address creator) private pure returns (RouterTypes.Config memory config) {
        config.creator = creator;
        config.protocolFeeRecipient = REVENUE_COLLECTOR;
        config.weth = WETH;
        config.subjectToWeth = _swapRoute(10_000);
        config.buckets = new RouterTypes.Bucket[](5);

        config.buckets[0] = RouterTypes.Bucket({
            output: _fixed(WETH),
            bps: 3_000,
            route: _identityRoute(),
            allocations: _wethAllocations(creator)
        });
        config.buckets[1] = RouterTypes.Bucket({
            output: _native(),
            bps: 1_000,
            route: RouterTypes.Route({ adapter: ADAPTER, routeData: "" }),
            allocations: _singleWallet(creator)
        });
        config.buckets[2] = RouterTypes.Bucket({
            output: _subject(),
            bps: 2_000,
            route: _swapRoute(10_000),
            allocations: _singleWallet(BURN)
        });
        config.buckets[3] = RouterTypes.Bucket({
            output: _fixed(TSLA),
            bps: 2_000,
            route: _swapRoute(3_000),
            allocations: _rwaAllocations(creator)
        });
        config.buckets[4] = RouterTypes.Bucket({
            output: _fixed(AMD),
            bps: 2_000,
            route: _swapRoute(3_000),
            allocations: _singleWallet(BURN)
        });
    }

    function _wethAllocations(address creator)
        private
        pure
        returns (RouterTypes.Allocation[] memory allocations)
    {
        allocations = new RouterTypes.Allocation[](3);
        allocations[0] = _wallet(creator, 2_000);
        allocations[1] = _sink(AIRDROP, 3_000, _airdropConfig());
        allocations[2] = _sink(LIQUIDITY, 5_000, _liquidityConfig());
    }

    function _rwaAllocations(address creator)
        private
        pure
        returns (RouterTypes.Allocation[] memory allocations)
    {
        allocations = new RouterTypes.Allocation[](2);
        allocations[0] = _wallet(creator, 5_000);
        allocations[1] = _sink(AIRDROP, 5_000, _airdropConfig());
    }

    function _singleWallet(address recipient)
        private
        pure
        returns (RouterTypes.Allocation[] memory allocations)
    {
        allocations = new RouterTypes.Allocation[](1);
        allocations[0] = _wallet(recipient, 10_000);
    }

    function _wallet(address recipient, uint16 bps)
        private
        pure
        returns (RouterTypes.Allocation memory)
    {
        return RouterTypes.Allocation({
            destination: recipient,
            bps: bps,
            isSink: false,
            creatorMayRepoint: false,
            sinkConfig: ""
        });
    }

    function _sink(address destination, uint16 bps, bytes memory sinkConfig)
        private
        pure
        returns (RouterTypes.Allocation memory)
    {
        return RouterTypes.Allocation({
            destination: destination,
            bps: bps,
            isSink: true,
            creatorMayRepoint: false,
            sinkConfig: sinkConfig
        });
    }

    function _airdropConfig() private pure returns (bytes memory) {
        address[] memory exclusions = new address[](0);
        return abi.encode(
            AirdropConfig({
                minPayout: 1, maxBatchSize: 16, minConfirmations: 2, exclusions: exclusions
            })
        );
    }

    function _liquidityConfig() private pure returns (bytes memory) {
        return abi.encode(
            LiquidityConfig({
                venue: 0,
                quoteAsset: WETH,
                poolFee: 10_000,
                tickSpacing: 200,
                hooks: address(0),
                swapAdapter: ADAPTER,
                priceGuard: TESTNET_GUARD,
                swapRouteData: abi.encode(uint24(10_000)),
                quoteSwapBps: 5_000,
                maxMintSlippageBps: 500,
                minNotionalPerMint: 1,
                maxNotionalPerMint: 2_000_000_000_000,
                minMintInterval: 0,
                feeMode: 2,
                feeRecipient: address(0)
            })
        );
    }

    function _fixed(address token) private pure returns (RouterTypes.AssetRef memory) {
        return RouterTypes.AssetRef({ kind: RouterTypes.AssetKind.FIXED_ERC20, token: token });
    }

    function _native() private pure returns (RouterTypes.AssetRef memory) {
        return RouterTypes.AssetRef({ kind: RouterTypes.AssetKind.NATIVE, token: address(0) });
    }

    function _subject() private pure returns (RouterTypes.AssetRef memory) {
        return RouterTypes.AssetRef({ kind: RouterTypes.AssetKind.SUBJECT, token: address(0) });
    }

    function _identityRoute() private pure returns (RouterTypes.Route memory) {
        return RouterTypes.Route({ adapter: address(0), routeData: "" });
    }

    function _swapRoute(uint24 fee) private pure returns (RouterTypes.Route memory) {
        return RouterTypes.Route({ adapter: ADAPTER, routeData: abi.encode(fee) });
    }

    function _sendWallet(SinjohFeeRouter router, address recipient, address asset) private {
        uint256 amount = router.walletOwed(recipient, asset);
        if (amount != 0) router.sendWallet(recipient, asset, amount);
    }

    function _fundSink(SinjohFeeRouter router, uint8 bucketId, uint8 allocationId)
        private
        returns (uint256 amount)
    {
        (, address asset,,,) = router.bucketInfo(bucketId);
        amount = router.sinkOwed(router.allocationKey(bucketId, allocationId), asset);
        if (amount != 0) router.fundSink(bucketId, allocationId, amount);
    }

    function _assertDrained(SinjohFeeRouter router, address asset) private view {
        uint256 balance = asset == address(0)
            ? address(router).balance
            : IERC20(asset).balanceOf(address(router));
        uint256 liability = router.totalLiability(asset);
        if (balance != 0 || liability != 0) {
            revert IncompleteDrain(asset, balance, liability);
        }
    }
}
