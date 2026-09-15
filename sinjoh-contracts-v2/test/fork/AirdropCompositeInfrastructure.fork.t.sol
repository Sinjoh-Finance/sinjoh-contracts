// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { YieldBankCollection } from "../../src/yield-banks/YieldBankCollection.sol";
import {
    CollectionPortfolioAllocator
} from "../../src/yield-banks/CollectionPortfolioAllocator.sol";
import { DeltaPoolController } from "../../src/yield-banks/DeltaPoolController.sol";
import {
    YieldBankSelfServiceExecutionRouter
} from "../../src/yield-banks/YieldBankSelfServiceExecutionRouter.sol";
import { DeltaV3SinglePoolRoute } from "../../src/yield-banks/adapters/DeltaV3SinglePoolRoute.sol";
import { DeltaV3TwapUsdFeed } from "../../src/yield-banks/adapters/DeltaV3TwapUsdFeed.sol";
import {
    AirdropCompositeSleeve as StockCompositeSleeve
} from "../../src/yield-banks/airdrop/AirdropCompositeSleeve.sol";
import { StockCompositeLPAdapter } from "../../src/yield-banks/stock/StockCompositeLPAdapter.sol";
import {
    StockInfrastructureBuilder,
    StockInfrastructurePositionDescriptor
} from "../../src/yield-banks/stock/StockInfrastructureBuilder.sol";
import { IDeltaPositionBuilder } from "../../src/yield-banks/interfaces/IDeltaPositionBuilder.sol";
import { IYieldBankV3Pool } from "../../src/yield-banks/interfaces/IYieldBankV3.sol";

interface IAirdropForkFactory {
    function createPool(address, address, uint24) external returns (address);
    function enableFeeAmount(uint24, int24) external;
    function owner() external view returns (address);
    function setOwner(address) external;
}

interface IAirdropForkPool {
    function initialize(uint160) external;
}

interface IAirdropForkWETH {
    function deposit() external payable;
}

interface IAirdropForkManager {
    function ownerOf(uint256) external view returns (address);
}

/// @notice Genuine canonical V3 deployment on an isolated mainnet fork. Infrastructure seed
/// ETH belongs only to this test deployer; no Piggy Bank balance, storage or bytecode is changed.
contract AirdropCompositeInfrastructureForkTest is Test {
    YieldBankCollection internal constant COLLECTION =
        YieldBankCollection(0xc275fa302Cd53DFa42D41b1C5b770661d923ba43);
    CollectionPortfolioAllocator internal constant ALLOCATOR =
        CollectionPortfolioAllocator(0x42e14eA9f926ad7b530ce49d433CB6f748f8D0a1);
    address internal constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;
    address internal constant USDG = 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168;
    address internal constant OLD_FACTORY = 0x1f7d7550B1b028f7571E69A784071F0205FD2EfA;
    address internal constant USDG_POOL = 0x52e65B17fB6E5BA00Ed806f37Afcd2DaA50271Ca;
    address internal constant INJOH_POOL = 0xB09fa4f04032b9d9e690ac4a1d29523b5f9A72DC;
    address internal factory;
    address internal manager;
    address internal registrationPool;
    StockInfrastructureBuilder internal builder;
    StockCompositeSleeve internal composite;
    StockCompositeLPAdapter internal facade;

    function testNewCompositeRegistrationPreservesExistingLPInfrastructure() public {
        _fork();
        DeltaPoolController controller =
            DeltaPoolController(address(ALLOCATOR.deltaPoolController()));
        bytes32 beforeInfrastructure = _infrastructureHash(address(controller), OLD_FACTORY);
        assertTrue(controller.isAllocationPool(INJOH_POOL));
        address bank = COLLECTION.accountOf(334);
        uint256 backingBefore = IERC20(ALLOCATOR.sleeves(2)).balanceOf(bank);
        _deployInfrastructure();
        _registerComposite(controller);
        assertEq(_infrastructureHash(address(controller), OLD_FACTORY), beforeInfrastructure);
        assertTrue(controller.isAllocationPool(INJOH_POOL));
        assertTrue(controller.isAllocationPool(registrationPool));
        assertTrue(COLLECTION.isSleeveAsset(address(composite)));
        assertTrue(ALLOCATOR.isDeltaPoolSleeve(address(composite)));
        assertEq(controller.poolOfSleeve(address(composite)), registrationPool);
        assertEq(composite.decimals(), 36);
        assertLe(address(composite).code.length, 24576, "EIP-170");
        assertEq(composite.portfolioAdapter(), address(facade));
        assertTrue(composite.depositsPaused());
        assertEq(IERC20(ALLOCATOR.sleeves(2)).balanceOf(bank), backingBefore);
    }

    function _fork() internal {
        string memory rpc = vm.envOr("ROBINHOOD_MAINNET_RPC_URL", string(""));
        if (bytes(rpc).length == 0) vm.skip(true);
        vm.createSelectFork(rpc, _forkBlockNumber());
        assertEq(block.chainid, 4663);
    }
    function _forkBlockNumber() internal view virtual returns(uint256){return vm.envOr("STOCK_FORK_BLOCK", uint256(62_601_489));}

    function _deployInfrastructure() internal {
        factory = _artifact("UniswapV3Factory", "");
        address descriptor = address(new StockInfrastructurePositionDescriptor());
        manager = _artifact("NonfungiblePositionManager", abi.encode(factory, WETH, descriptor));
        builder = new StockInfrastructureBuilder(factory, manager, WETH);
        IAirdropForkFactory(factory).enableFeeAmount(100, 1);
        registrationPool = IAirdropForkFactory(factory).createPool(WETH, USDG, 100);
        (uint160 sqrtPrice, int24 tick,,,,,) = IYieldBankV3Pool(USDG_POOL).slot0();
        IAirdropForkPool(registrationPool).initialize(sqrtPrice);
        // Explicit fork-only infrastructure bootstrap; funds never enter an NFT treasury.
        vm.deal(address(this), 0.01 ether);
        IAirdropForkWETH(WETH).deposit{ value: 0.01 ether }();
        DeltaV3SinglePoolRoute buyUSDG = new DeltaV3SinglePoolRoute(
            USDG_POOL, OLD_FACTORY, WETH, USDG, USDG_POOL.codehash, OLD_FACTORY.codehash
        );
        IERC20(WETH).approve(address(buyUSDG), 0.005 ether);
        uint256 usdg = buyUSDG.convert(0.005 ether, 1, address(this), "");
        IERC20(WETH).approve(address(builder), 0.005 ether);
        IERC20(USDG).approve(address(builder), usdg);
        IDeltaPositionBuilder.Rung[] memory rungs = new IDeltaPositionBuilder.Rung[](1);
        rungs[0] = IDeltaPositionBuilder.Rung(tick - 1000, tick + 1000, 0.005 ether, usdg, 1, 1);
        uint256[] memory ids = builder.mintLadder(
            registrationPool, rungs, tick - 1, tick + 1, block.timestamp + 15 minutes
        );
        assertEq(ids.length, 1);
        assertEq(IAirdropForkManager(manager).ownerOf(ids[0]), address(this));
        assertGt(IYieldBankV3Pool(registrationPool).liquidity(), 0);
        assertEq(IERC20(WETH).allowance(address(builder), manager), 0);
        assertEq(IERC20(USDG).allowance(address(builder), manager), 0);
        assertEq(IERC20(WETH).balanceOf(address(builder)), 0);
        assertEq(IERC20(USDG).balanceOf(address(builder)), 0);
        IAirdropForkFactory(factory).setOwner(COLLECTION.collectionTimelock());
    }

    function _registerComposite(DeltaPoolController controller) internal {
        vm.prank(COLLECTION.collectionTimelock());
        controller.configureInfrastructure(
            factory,
            DeltaPoolController.InfrastructureConfig({
                positionManager: manager,
                positionBuilder: address(builder),
                factoryRuntimeCodeHash: factory.codehash,
                positionManagerRuntimeCodeHash: manager.codehash,
                positionBuilderRuntimeCodeHash: address(builder).codehash,
                routeCreationCodeHash: keccak256(type(DeltaV3SinglePoolRoute).creationCode),
                sleeveCreationCodeHash: keccak256(type(StockCompositeSleeve).creationCode),
                adapterCreationCodeHash: keccak256(type(StockCompositeLPAdapter).creationCode),
                feedCreationCodeHash: keccak256(type(DeltaV3TwapUsdFeed).creationCode)
            })
        );
        bytes memory callData = abi.encodeCall(
            DeltaPoolController.materializePool,
            (
                registrationPool,
                DeltaPoolController.MaterializationConfig(
                    1, controller.maximumAdapterCapBps(), _maximumCompositeLoss()
                ),
                type(DeltaV3SinglePoolRoute).creationCode,
                type(StockCompositeSleeve).creationCode,
                type(StockCompositeLPAdapter).creationCode
            )
        );
        YieldBankSelfServiceExecutionRouter router =
            YieldBankSelfServiceExecutionRouter(ALLOCATOR.allocationOperator());
        vm.prank(COLLECTION.collectionTimelock());
        bytes memory result = router.executeGovernanceCall(address(controller), callData);
        (address sleeve, address adapter) = abi.decode(result, (address, address));
        composite = StockCompositeSleeve(sleeve);
        facade = StockCompositeLPAdapter(adapter);
    }

    function _maximumCompositeLoss() internal view virtual returns(uint16){return 200;}

    function _artifact(string memory name, bytes memory args) private returns (address deployed) {
        string memory json =
            vm.readFile(string.concat("deployments/stock-infrastructure/", name, ".json"));
        bytes memory creation = abi.encodePacked(vm.parseJsonBytes(json, ".bytecode"), args);
        assembly ("memory-safe") { deployed := create(0, add(creation, 32), mload(creation)) }
        require(deployed.code.length != 0, "canonical artifact deployment failed");
    }

    function _infrastructureHash(address controller, address venue) internal view returns (bytes32) {
        (bool ok, bytes memory result) = controller.staticcall(
            abi.encodeWithSignature("infrastructureOfFactory(address)", venue)
        );
        require(ok);
        return keccak256(result);
    }
}
