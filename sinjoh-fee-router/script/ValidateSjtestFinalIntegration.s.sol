// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { RouterTypes } from "../src/RouterTypes.sol";
import { SinjohFeeRouter } from "../src/SinjohFeeRouter.sol";

interface VmSjtestFinalValidation {
    function envAddress(string calldata name) external returns (address);
}

interface IAdapterValidation {
    function assetIn() external view returns (address);
    function assetOut() external view returns (address);
    function pool() external view returns (address);
}

interface IGuardValidation {
    function oraclePool() external view returns (address);
    function quoteAsset() external view returns (address);
    function subject() external view returns (address);
}

interface IRevenueCollectorValidation {
    function owner() external view returns (address);
    function processor() external view returns (address);
}

interface IAirdropValidation {
    function attestor() external view returns (address);
    function protocolFeeRecipient() external view returns (address);
}

interface ILiquidityManagerValidation {
    function v3Factory() external view returns (address);
    function v3PositionManager() external view returns (address);
    function v4PositionManager() external view returns (address);
    function v4StateView() external view returns (address);
    function permit2() external view returns (address);
    function protocolFeeRecipient() external view returns (address);
}

interface IFactoryValidation {
    function implementation() external view returns (address);
}

interface IPonsAdapterFactoryValidation {
    function implementation() external view returns (address);
    function ponsLocker() external view returns (address);
    function weth() external view returns (address);
    function deploymentChainId() external view returns (uint256);
}

interface IPonsAdapterValidation {
    function ponsLocker() external view returns (address);
    function weth() external view returns (address);
    function deploymentChainId() external view returns (uint256);
    function subject() external view returns (address);
    function router() external view returns (address);
    function initialized() external view returns (bool);
}

contract ValidateSjtestFinalIntegration {
    uint256 internal constant ROBINHOOD_TESTNET_CHAIN_ID = 46_630;
    address internal constant DESIGNATED = 0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49;
    address internal constant GOVERNANCE = 0x39E2f5eFdFd808F26B98979a06BA11ea82E1C85f;
    address internal constant SUBJECT = 0x690caA9c7FF95e01d470Ec60Ed6aD57d794a38F5;
    address internal constant PONS_WETH = 0x37E402B8081eFcE1D82A09a066512278006e4691;
    address internal constant PONS_LOCKER = 0x9E18AFba6eADDC1A00Edd35FB7AB6C5CD1E1dEE0;
    address internal constant PONS_POOL = 0xa0594e9a288939864C6A918e5dee7f65194f5730;
    address internal constant PONS_POSITION_MANAGER = 0xBc82a9aA33ff24FCd56D36a0fB0a2105B193A327;
    address internal constant PONS_V3_FACTORY = 0xFECCB63CD759d768538458Ea56F47eA8004323c1;
    address internal constant V4_POSITION_MANAGER = 0x58daec3116aae6D93017bAAea7749052E8a04fA7;
    address internal constant V4_STATE_VIEW = 0xF3334192D15450CdD385c8B70e03f9A6bD9E673b;
    address internal constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address internal constant ADAPTER_FACTORY = 0x3a92f7C900aD154a46e8630f60176c805B561C98;

    VmSjtestFinalValidation internal constant vm =
        VmSjtestFinalValidation(address(uint160(uint256(keccak256("hevm cheat code")))));

    error ValidationFailed();

    function run() external {
        address routerImplementation = vm.envAddress("ROUTER_IMPLEMENTATION");
        address routerFactory = vm.envAddress("ROUTER_FACTORY");
        address routerAddress = vm.envAddress("FEE_ROUTER");
        address ponsAdapter = vm.envAddress("PONS_ADAPTER");
        address reverseAdapter = vm.envAddress("REVERSE_ADAPTER");
        address bidirectionalGuard = vm.envAddress("BIDIRECTIONAL_GUARD");
        address revenueCollector = vm.envAddress("REVENUE_COLLECTOR");
        address airdropDistributor = vm.envAddress("AIRDROP_DISTRIBUTOR");
        address liquidityManager = vm.envAddress("LIQUIDITY_MANAGER");
        address v4LiquidityManager = vm.envAddress("V4_LIQUIDITY_MANAGER");
        address forwardAdapter = vm.envAddress("FORWARD_ADAPTER");
        address forwardGuard = vm.envAddress("FORWARD_GUARD");

        if (
            block.chainid != ROBINHOOD_TESTNET_CHAIN_ID || routerImplementation.code.length == 0
                || IFactoryValidation(routerFactory).implementation() != routerImplementation
                || IAdapterValidation(reverseAdapter).assetIn() != SUBJECT
                || IAdapterValidation(reverseAdapter).assetOut() != PONS_WETH
                || IAdapterValidation(reverseAdapter).pool() != PONS_POOL
                || IAdapterValidation(forwardAdapter).assetIn() != PONS_WETH
                || IAdapterValidation(forwardAdapter).assetOut() != SUBJECT
                || IAdapterValidation(forwardAdapter).pool() != PONS_POOL
                || !_validGuard(bidirectionalGuard) || !_validGuard(forwardGuard)
                || IRevenueCollectorValidation(revenueCollector).owner() != GOVERNANCE
                || IRevenueCollectorValidation(revenueCollector).processor() != GOVERNANCE
                || IAirdropValidation(airdropDistributor).attestor() != DESIGNATED
                || IAirdropValidation(airdropDistributor).protocolFeeRecipient() != revenueCollector
                || liquidityManager == v4LiquidityManager
                || !_validLiquidityManager(liquidityManager, revenueCollector)
                || !_validLiquidityManager(v4LiquidityManager, revenueCollector)
                || liquidityManager.codehash != v4LiquidityManager.codehash || !_validPonsFactory()
                || !_validPonsAdapter(ponsAdapter, routerAddress)
                || !_validRouter(
                    SinjohFeeRouter(payable(routerAddress)),
                    revenueCollector,
                    airdropDistributor,
                    liquidityManager,
                    reverseAdapter,
                    bidirectionalGuard
                )
        ) revert ValidationFailed();
    }

    function _validGuard(address guard) private view returns (bool) {
        return guard.code.length != 0 && IGuardValidation(guard).oraclePool() == PONS_POOL
            && IGuardValidation(guard).subject() == SUBJECT
            && IGuardValidation(guard).quoteAsset() == PONS_WETH;
    }

    function _validLiquidityManager(address manager, address revenueCollector)
        private
        view
        returns (bool)
    {
        return manager.code.length != 0
            && ILiquidityManagerValidation(manager).v3Factory() == PONS_V3_FACTORY
            && ILiquidityManagerValidation(manager).v3PositionManager() == PONS_POSITION_MANAGER
            && ILiquidityManagerValidation(manager).v4PositionManager() == V4_POSITION_MANAGER
            && ILiquidityManagerValidation(manager).v4StateView() == V4_STATE_VIEW
            && ILiquidityManagerValidation(manager).permit2() == PERMIT2
            && ILiquidityManagerValidation(manager).protocolFeeRecipient() == revenueCollector;
    }

    function _validPonsFactory() private view returns (bool) {
        return ADAPTER_FACTORY.code.length != 0
            && IPonsAdapterFactoryValidation(ADAPTER_FACTORY).implementation().code.length != 0
            && IPonsAdapterFactoryValidation(ADAPTER_FACTORY).ponsLocker() == PONS_LOCKER
            && IPonsAdapterFactoryValidation(ADAPTER_FACTORY).weth() == PONS_WETH
            && IPonsAdapterFactoryValidation(ADAPTER_FACTORY).deploymentChainId()
                == ROBINHOOD_TESTNET_CHAIN_ID;
    }

    function _validPonsAdapter(address adapter, address router) private view returns (bool) {
        return adapter.code.length != 0 && IPonsAdapterValidation(adapter).initialized()
            && IPonsAdapterValidation(adapter).ponsLocker() == PONS_LOCKER
            && IPonsAdapterValidation(adapter).weth() == PONS_WETH
            && IPonsAdapterValidation(adapter).deploymentChainId() == ROBINHOOD_TESTNET_CHAIN_ID
            && IPonsAdapterValidation(adapter).subject() == SUBJECT
            && IPonsAdapterValidation(adapter).router() == router;
    }

    function _validRouter(
        SinjohFeeRouter router,
        address revenueCollector,
        address airdropDistributor,
        address liquidityManager,
        address reverseAdapter,
        address bidirectionalGuard
    ) private view returns (bool) {
        if (
            address(router).code.length == 0 || !router.bound() || router.creator() != DESIGNATED
                || router.subject() != SUBJECT || router.weth() != PONS_WETH
                || router.protocolFeeRecipient() != revenueCollector
                || router.intakeAssetCount() != 2 || router.bucketCount() != 1
                || router.resolvedBucketOutput(0) != PONS_WETH
        ) return false;

        (RouterTypes.AssetRef memory subjectRef, address resolvedSubject) = router.intakeAsset(0);
        (RouterTypes.AssetRef memory wethRef, address resolvedWeth) = router.intakeAsset(1);
        if (
            subjectRef.kind != RouterTypes.AssetKind.SUBJECT || subjectRef.token != address(0)
                || resolvedSubject != SUBJECT || wethRef.kind != RouterTypes.AssetKind.FIXED_ERC20
                || wethRef.token != PONS_WETH || resolvedWeth != PONS_WETH
        ) return false;

        (,, uint16 bucketBps, uint256 conversionCount, uint256 allocationCount) =
            router.bucketInfo(0);
        if (bucketBps != 10_000 || conversionCount != 2 || allocationCount != 3) return false;

        (,, address subjectAdapter, address subjectGuard,,,) = router.conversionInfo(0, 0);
        (,, address wethAdapter, address wethGuard, bytes memory wethRoute,,) =
            router.conversionInfo(0, 1);
        if (
            subjectAdapter != reverseAdapter || subjectGuard != bidirectionalGuard
                || wethAdapter != address(0) || wethGuard != address(0) || wethRoute.length != 0
        ) return false;

        (address treasury, uint16 treasuryBps, bool treasurySink, bool treasuryRepoint,) =
            router.allocationInfo(0, 0);
        (address airdrop, uint16 airdropBps, bool airdropSink,, bytes memory airdropConfig) =
            router.allocationInfo(0, 1);
        (
            address liquidity,
            uint16 liquidityBps,
            bool liquiditySink,,
            bytes memory liquidityConfig
        ) = router.allocationInfo(0, 2);
        return treasury == DESIGNATED && treasuryBps == 4_000 && !treasurySink && !treasuryRepoint
            && airdrop == airdropDistributor && airdropBps == 3_000 && airdropSink
            && airdropConfig.length != 0 && liquidity == liquidityManager && liquidityBps == 3_000
            && liquiditySink && liquidityConfig.length != 0;
    }
}
