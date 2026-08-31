// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import {
    CollectionPortfolioAllocator
} from "../../src/yield-banks/CollectionPortfolioAllocator.sol";
import { YieldBankAccount } from "../../src/yield-banks/YieldBankAccount.sol";
import {
    YieldBankAdapterRedemptionCall
} from "../../src/yield-banks/interfaces/IYieldBankManagedSleeve.sol";
import {
    YieldBankAdapterState,
    YieldBankCollectionState
} from "../../src/yield-banks/YieldBankTypes.sol";
import { YieldBankIds } from "../../src/yield-banks/libraries/YieldBankIds.sol";
import { IPriceHub } from "../../src/yield-banks/interfaces/IPriceHub.sol";
import {
    MockYieldBankAllocationRoute,
    MockYieldBankAsset
} from "../mocks/MockYieldBankIntegrations.sol";

contract MockOwnerAllocationNFT {
    mapping(uint256 tokenId => address owner) public ownerOf;

    function mint(address owner, uint256 tokenId) external {
        ownerOf[tokenId] = owner;
    }

    function transfer(uint256 tokenId, address owner) external {
        ownerOf[tokenId] = owner;
    }
}

contract MockOwnerAllocationVault {
    uint8 public constant PRIMARY_PENDING = 1;
    uint8 public constant PRIMARY_ALLOCATED = 2;
    address public allocationOperator;
    mapping(uint256 tokenId => uint8 state) public primaryStateOf;

    constructor(address operator_) {
        allocationOperator = operator_;
    }

    function setPrimaryState(uint256 tokenId, uint8 state) external {
        primaryStateOf[tokenId] = state;
    }
}

contract MockOwnerAllocationCollection {
    YieldBankCollectionState public state = YieldBankCollectionState.ACTIVE;
    address public nft;
    address public portfolioAllocator;
    address public weth;
    address public proceedsVault;
    uint16 public constant coreWeightBps = 4_000;
    uint16 public constant marketMakingWeightBps = 3_750;
    uint16 public constant usdgWeightBps = 2_250;
    mapping(uint256 tokenId => address account) public accountOf;
    mapping(address sleeve => bool registered) public isSleeveAsset;

    constructor(address nft_, address weth_, address proceedsVault_) {
        nft = nft_;
        weth = weth_;
        proceedsVault = proceedsVault_;
    }

    function configure(address allocator_, uint256 tokenId, address account) external {
        portfolioAllocator = allocator_;
        accountOf[tokenId] = account;
    }

    function setState(YieldBankCollectionState value) external {
        state = value;
    }

    function track(address account, address asset) external {
        YieldBankAccount(account).trackAsset(asset);
    }

    function registerSleeve(address sleeve) external {
        isSleeveAsset[sleeve] = true;
    }

    function claimPrimary(uint256) external { }
    function settle(uint256) external { }
}

contract MockOwnerAllocationSleeve is ERC20 {
    address public immutable accountingAsset;

    constructor(address accountingAsset_, string memory symbol_) ERC20(symbol_, symbol_) {
        accountingAsset = accountingAsset_;
    }

    function inventoryAssets() external view returns (address[] memory assets) {
        assets = new address[](1);
        assets[0] = accountingAsset;
    }

    function totalAssetsUsd18() external view returns (uint256 value, uint48 pricedAt) {
        return (IERC20(accountingAsset).balanceOf(address(this)), uint48(block.timestamp));
    }

    function priceHub() external view returns (address) {
        return address(this);
    }

    function quoteUsd18(address) external view returns (uint256, uint48, IPriceHub.FailureReason) {
        return (1e18, uint48(block.timestamp), IPriceHub.FailureReason.NONE);
    }

    function deposit(uint256 assets, address receiver, uint256 minimumShares, bytes calldata)
        external
        returns (uint256 shares)
    {
        IERC20(accountingAsset).transferFrom(msg.sender, address(this), assets);
        shares = assets;
        require(shares >= minimumShares);
        _mint(receiver, shares);
    }

    function redeemManaged(
        uint256 shares,
        address receiver,
        address owner,
        uint256[] calldata minimumOutputs,
        YieldBankAdapterRedemptionCall[] calldata adapterCalls
    ) external returns (address[] memory assets, uint256[] memory amounts) {
        require(minimumOutputs.length == 1 && adapterCalls.length == 0);
        _spendAllowance(owner, msg.sender, shares);
        _burn(owner, shares);
        require(shares >= minimumOutputs[0]);
        IERC20(accountingAsset).transfer(receiver, shares);
        assets = new address[](1);
        amounts = new uint256[](1);
        assets[0] = accountingAsset;
        amounts[0] = shares;
    }
}

contract MockOwnerPoolSleeve is MockOwnerAllocationSleeve {
    bytes32 public constant category = YieldBankIds.MARKET_MAKING;
    uint8 public constant maximumStrategies = 1;
    address public immutable allocator;
    mapping(address adapter => YieldBankAdapterState state) public adapterState;
    address private _adapter;

    constructor(address accountingAsset_, address allocator_)
        MockOwnerAllocationSleeve(accountingAsset_, "POOL")
    {
        allocator = allocator_;
    }

    function activate(address adapter) external {
        _adapter = adapter;
        adapterState[adapter] = YieldBankAdapterState.ACTIVE;
    }

    function adapters() external view returns (address[] memory values) {
        values = new address[](1);
        values[0] = _adapter;
    }
}

contract MockOwnerDeltaPoolAdapter {
    address public immutable sleeve;
    address public immutable pool;

    constructor(address sleeve_, address pool_) {
        sleeve = sleeve_;
        pool = pool_;
    }
}

contract MockOwnerDeltaPoolController {
    struct Foundation {
        address sleeve;
        address adapter;
        bytes32 poolRuntimeCodeHash;
        bytes32 sleeveRuntimeCodeHash;
        bytes32 adapterRuntimeCodeHash;
    }

    mapping(address pool => Foundation foundation) public foundationOf;
    mapping(address sleeve => address pool) public poolOfSleeve;
    mapping(address pool => bool selectable) public isSelectablePool;

    function materialize(address pool, address sleeve, address adapter) external {
        foundationOf[pool] = Foundation({
            sleeve: sleeve,
            adapter: adapter,
            poolRuntimeCodeHash: pool.codehash,
            sleeveRuntimeCodeHash: sleeve.codehash,
            adapterRuntimeCodeHash: adapter.codehash
        });
        poolOfSleeve[sleeve] = pool;
        isSelectablePool[pool] = true;
    }

    function setSelectable(address pool, bool selectable) external {
        isSelectablePool[pool] = selectable;
    }

    function isAllocationPool(address pool) external view returns (bool) {
        return isSelectablePool[pool];
    }
}

contract YieldBankOwnerAllocationTest is Test {
    address private constant ALICE = address(0xA11CE);
    uint256 private constant TOKEN_ID = 1;

    MockYieldBankAsset private weth;
    MockYieldBankAsset private stock;
    MockOwnerAllocationNFT private nft;
    MockOwnerAllocationVault private vault;
    MockOwnerAllocationCollection private collection;
    MockOwnerAllocationSleeve private core;
    MockOwnerAllocationSleeve private market;
    MockOwnerAllocationSleeve private usdg;
    CollectionPortfolioAllocator private allocator;
    MockOwnerDeltaPoolController private deltaPoolController;
    MockYieldBankAllocationRoute private stockEntryRoute;
    MockYieldBankAllocationRoute private stockExitRoute;
    YieldBankAccount private account;

    function setUp() external {
        weth = new MockYieldBankAsset("Wrapped Ether", "WETH");
        stock = new MockYieldBankAsset("Stock Token", "STOCK");
        nft = new MockOwnerAllocationNFT();
        vault = new MockOwnerAllocationVault(address(this));
        collection = new MockOwnerAllocationCollection(address(nft), address(weth), address(vault));
        core = new MockOwnerAllocationSleeve(address(stock), "CORE");
        market = new MockOwnerAllocationSleeve(address(weth), "MARKET");
        usdg = new MockOwnerAllocationSleeve(address(weth), "USDG");
        deltaPoolController = new MockOwnerDeltaPoolController();
        allocator = new CollectionPortfolioAllocator(
            address(collection),
            address(this),
            address(this),
            address(this),
            address(deltaPoolController),
            address(core),
            address(market),
            address(usdg),
            4_000,
            3_750,
            2_250
        );
        YieldBankAccount implementation = new YieldBankAccount();
        account = YieldBankAccount(Clones.clone(address(implementation)));
        account.initialize(address(collection), address(nft), TOKEN_ID, address(this));
        collection.configure(address(allocator), TOKEN_ID, address(account));
        nft.mint(ALICE, TOKEN_ID);

        stockEntryRoute = new MockYieldBankAllocationRoute(address(weth), address(stock));
        allocator.bindRoute(
            address(weth),
            address(core),
            address(stockEntryRoute),
            address(stockEntryRoute).codehash
        );
        stockExitRoute = new MockYieldBankAllocationRoute(address(stock), address(weth));
        allocator.bindRebalanceRoute(
            address(stock), address(stockExitRoute), address(stockExitRoute).codehash
        );
        stock.mint(address(this), 400 ether);
        weth.mint(address(this), 600 ether);
        stock.approve(address(core), 400 ether);
        weth.approve(address(market), 375 ether);
        weth.approve(address(usdg), 225 ether);
        core.deposit(400 ether, address(account), 400 ether, "");
        market.deposit(375 ether, address(account), 375 ether, "");
        usdg.deposit(225 ether, address(account), 225 ether, "");
        collection.track(address(account), address(core));
        collection.track(address(account), address(market));
        collection.track(address(account), address(usdg));
    }

    function testOwnerCanRequestAndOperatorCanFullyRebalanceExistingBacking() external {
        weth.mint(address(account), 10 ether);
        uint16[3] memory weights = [uint16(0), uint16(0), uint16(10_000)];
        uint64 revision = _requestTarget(weights);

        CollectionPortfolioAllocator.RebalanceExecution memory execution;
        uint256[3] memory existing = [uint256(400 ether), 375 ether, 225 ether];
        for (uint256 i; i < 3; ++i) {
            execution.redemptions[i].minimumOutputs = new uint256[](1);
            execution.redemptions[i].minimumOutputs[0] = existing[i];
        }
        execution.allocations[2].minimumOutput = 1_010 ether;
        execution.allocations[2].minimumShares = 1_010 ether;
        execution.conversions = new CollectionPortfolioAllocator.ConversionCall[](1);
        execution.conversions[0] = CollectionPortfolioAllocator.ConversionCall({
            asset: address(stock), minimumWethOut: 400 ether, routeData: ""
        });
        execution.minimumWethRecovered = 1_010 ether;
        execution.deadline = block.timestamp + 1 hours;

        (uint256 recovered, uint256[3] memory shares) =
            allocator.executeTargetAllocation(TOKEN_ID, revision, execution);
        assertEq(recovered, 1_010 ether);
        assertEq(shares[0], 0);
        assertEq(shares[1], 0);
        assertEq(shares[2], 1_010 ether);
        assertEq(core.balanceOf(address(account)), 0);
        assertEq(market.balanceOf(address(account)), 0);
        assertEq(usdg.balanceOf(address(account)), 1_010 ether);
        CollectionPortfolioAllocator.AllocationTarget memory target =
            allocator.allocationTargetOf(TOKEN_ID);
        assertEq(target.revision, revision);
        assertEq(target.executedRevision, revision);
        assertEq(target.usdgWeightBps, 10_000);

        vm.expectRevert(
            abi.encodeWithSelector(
                CollectionPortfolioAllocator.TargetAlreadyExecuted.selector, TOKEN_ID, revision
            )
        );
        allocator.executeTargetAllocation(TOKEN_ID, revision, execution);
    }

    function testOwnerLossLimitCoversConversionsAndFinalAllocationValue() external {
        stockExitRoute.setOutputBps(9_000);
        uint16[3] memory weights = [uint16(0), uint16(0), uint16(10_000)];
        uint64 revision = _requestTarget(weights);

        CollectionPortfolioAllocator.RebalanceExecution memory execution;
        uint256[3] memory existing = [uint256(400 ether), 375 ether, 225 ether];
        for (uint256 i; i < 3; ++i) {
            execution.redemptions[i].minimumOutputs = new uint256[](1);
            execution.redemptions[i].minimumOutputs[0] = existing[i];
        }
        execution.conversions = new CollectionPortfolioAllocator.ConversionCall[](1);
        execution.conversions[0] = CollectionPortfolioAllocator.ConversionCall({
            asset: address(stock), minimumWethOut: 360 ether, routeData: ""
        });
        execution.allocations[2].minimumOutput = 960 ether;
        execution.allocations[2].minimumShares = 960 ether;
        execution.minimumWethRecovered = 960 ether;
        execution.deadline = block.timestamp + 1 hours;

        vm.expectPartialRevert(CollectionPortfolioAllocator.OwnerTotalLossLimitExceeded.selector);
        allocator.executeTargetAllocation(TOKEN_ID, revision, execution);
    }

    function testOnlyCurrentNftOwnerCanSetTargetAndExecutionIsRevisionBound() external {
        uint16[3] memory weights = [uint16(10_000), uint16(0), uint16(0)];
        vm.expectRevert(
            abi.encodeWithSelector(
                CollectionPortfolioAllocator.OnlyTokenOwner.selector, TOKEN_ID, address(this)
            )
        );
        allocator.setTargetAllocation(
            TOKEN_ID, weights, address(0), 100, uint48(block.timestamp + 2 hours)
        );

        uint64 revision = _requestTarget(weights);
        CollectionPortfolioAllocator.RebalanceExecution memory execution;
        execution.deadline = block.timestamp + 1 hours;
        vm.expectRevert(
            abi.encodeWithSelector(
                CollectionPortfolioAllocator.InvalidTargetRevision.selector,
                TOKEN_ID,
                revision + 1,
                revision
            )
        );
        allocator.executeTargetAllocation(TOKEN_ID, revision + 1, execution);
    }

    function testUnexecutedRequestCannotFollowNftToANewOwner() external {
        uint16[3] memory weights = [uint16(0), uint16(10_000), uint16(0)];
        uint64 revision = _requestTarget(weights);
        address bob = address(0xB0B);
        nft.transfer(TOKEN_ID, bob);

        CollectionPortfolioAllocator.RebalanceExecution memory execution;
        execution.deadline = block.timestamp + 1 hours;
        vm.expectRevert(
            abi.encodeWithSelector(
                CollectionPortfolioAllocator.TargetOwnerChanged.selector, TOKEN_ID, ALICE, bob
            )
        );
        allocator.executeTargetAllocation(TOKEN_ID, revision, execution);
    }

    function testExecutionRejectsExpiredInstructionsAndPendingPrimaryBacking() external {
        uint16[3] memory weights = [uint16(0), uint16(10_000), uint16(0)];
        uint64 revision = _requestTarget(weights);
        CollectionPortfolioAllocator.RebalanceExecution memory execution;
        execution.deadline = block.timestamp - 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                CollectionPortfolioAllocator.RebalanceExpired.selector, execution.deadline
            )
        );
        allocator.executeTargetAllocation(TOKEN_ID, revision, execution);

        vault.setPrimaryState(TOKEN_ID, vault.PRIMARY_PENDING());
        execution.deadline = block.timestamp + 1 hours;
        vm.expectRevert(
            abi.encodeWithSelector(
                CollectionPortfolioAllocator.PrimaryAllocationPending.selector, TOKEN_ID
            )
        );
        allocator.executeTargetAllocation(TOKEN_ID, revision, execution);
    }

    function testOwnerAdapterLossAndExpiryLimitsCannotBeExceeded() external {
        uint16[3] memory weights = [uint16(0), uint16(10_000), uint16(0)];
        uint64 revision = _requestTarget(weights);
        CollectionPortfolioAllocator.RebalanceExecution memory execution;
        execution.deadline = block.timestamp + 1 hours;
        execution.redemptions[0].adapterCalls = new YieldBankAdapterRedemptionCall[](1);
        execution.redemptions[0].adapterCalls[0] = YieldBankAdapterRedemptionCall({
            adapter: address(0xA11CE), maxLossBps: 101, data: ""
        });
        vm.expectRevert(
            abi.encodeWithSelector(
                CollectionPortfolioAllocator.OwnerAdapterLossLimitExceeded.selector, 100, 101
            )
        );
        allocator.executeTargetAllocation(TOKEN_ID, revision, execution);

        uint256 targetExpiry = block.timestamp + 2 hours;
        vm.warp(targetExpiry + 1);
        execution.deadline = block.timestamp;
        execution.redemptions[0].adapterCalls[0].maxLossBps = 100;
        vm.expectRevert(
            abi.encodeWithSelector(
                CollectionPortfolioAllocator.RebalanceExpired.selector, targetExpiry
            )
        );
        allocator.executeTargetAllocation(TOKEN_ID, revision, execution);
    }

    function testFuzzOwnerSelectedWeightsConserveAllBacking(uint16 rawCore, uint16 rawMarket)
        external
    {
        uint16 coreWeight = rawCore % 10_001;
        uint16 remaining = 10_000 - coreWeight;
        uint16 marketWeight = rawMarket % (remaining + 1);
        uint16 usdgWeight = remaining - marketWeight;
        uint16[3] memory weights = [coreWeight, marketWeight, usdgWeight];
        uint64 revision = _requestTarget(weights);

        CollectionPortfolioAllocator.RebalanceExecution memory execution;
        uint256[3] memory existing = [uint256(400 ether), 375 ether, 225 ether];
        for (uint256 i; i < 3; ++i) {
            execution.redemptions[i].minimumOutputs = new uint256[](1);
            execution.redemptions[i].minimumOutputs[0] = existing[i];
        }
        execution.conversions = new CollectionPortfolioAllocator.ConversionCall[](1);
        execution.conversions[0] = CollectionPortfolioAllocator.ConversionCall({
            asset: address(stock), minimumWethOut: 400 ether, routeData: ""
        });
        uint256[3] memory expected;
        expected[0] = 1_000 ether * uint256(coreWeight) / 10_000;
        uint256 marketCumulative = 1_000 ether * (uint256(coreWeight) + marketWeight) / 10_000;
        expected[1] = marketCumulative - expected[0];
        expected[2] = 1_000 ether - marketCumulative;
        for (uint256 i; i < 3; ++i) {
            if (expected[i] == 0) continue;
            execution.allocations[i].minimumOutput = expected[i];
            execution.allocations[i].minimumShares = expected[i];
        }
        execution.minimumWethRecovered = 1_000 ether;
        execution.deadline = block.timestamp + 1 hours;

        (uint256 recovered, uint256[3] memory shares) =
            allocator.executeTargetAllocation(TOKEN_ID, revision, execution);
        assertEq(recovered, 1_000 ether);
        assertEq(shares[0], expected[0]);
        assertEq(shares[1], expected[1]);
        assertEq(shares[2], expected[2]);
        assertEq(core.balanceOf(address(account)), expected[0]);
        assertEq(market.balanceOf(address(account)), expected[1]);
        assertEq(usdg.balanceOf(address(account)), expected[2]);
        assertEq(shares[0] + shares[1] + shares[2], 1_000 ether);
    }

    function testOwnerCanSelectAndLaterLeaveAnIsolatedRegisteredDeltaPool() external {
        MockYieldBankAsset pool = new MockYieldBankAsset("Delta Pool Identity", "POOL-ID");
        MockOwnerPoolSleeve poolSleeve = new MockOwnerPoolSleeve(address(weth), address(allocator));
        MockOwnerDeltaPoolAdapter adapter =
            new MockOwnerDeltaPoolAdapter(address(poolSleeve), address(pool));
        poolSleeve.activate(address(adapter));
        deltaPoolController.materialize(address(pool), address(poolSleeve), address(adapter));

        uint16[3] memory poolWeights = [uint16(0), uint16(10_000), uint16(0)];
        vm.prank(ALICE);
        uint64 poolRevision = allocator.setTargetAllocation(
            TOKEN_ID, poolWeights, address(pool), 100, uint48(block.timestamp + 2 hours)
        );
        CollectionPortfolioAllocator.RebalanceExecution memory enter;
        uint256[3] memory existing = [uint256(400 ether), 375 ether, 225 ether];
        for (uint256 i; i < 3; ++i) {
            enter.redemptions[i].minimumOutputs = new uint256[](1);
            enter.redemptions[i].minimumOutputs[0] = existing[i];
        }
        enter.conversions = new CollectionPortfolioAllocator.ConversionCall[](1);
        enter.conversions[0] = CollectionPortfolioAllocator.ConversionCall({
            asset: address(stock), minimumWethOut: 400 ether, routeData: ""
        });
        enter.allocations[1].minimumOutput = 1_000 ether;
        enter.allocations[1].minimumShares = 1_000 ether;
        enter.minimumWethRecovered = 1_000 ether;
        enter.deadline = block.timestamp + 1 hours;
        allocator.executeTargetAllocation(TOKEN_ID, poolRevision, enter);

        assertEq(allocator.activeDeltaPoolOf(TOKEN_ID), address(pool));
        assertEq(poolSleeve.balanceOf(address(account)), 1_000 ether);
        assertEq(market.balanceOf(address(account)), 0);

        uint16[3] memory usdgWeights = [uint16(0), uint16(0), uint16(10_000)];
        uint64 leaveRevision = _requestTarget(usdgWeights);
        CollectionPortfolioAllocator.RebalanceExecution memory leave;
        leave.deltaPoolRedemption.minimumOutputs = new uint256[](1);
        leave.deltaPoolRedemption.minimumOutputs[0] = 1_000 ether;
        leave.allocations[2].minimumOutput = 1_000 ether;
        leave.allocations[2].minimumShares = 1_000 ether;
        leave.minimumWethRecovered = 1_000 ether;
        leave.deadline = block.timestamp + 1 hours;
        allocator.executeTargetAllocation(TOKEN_ID, leaveRevision, leave);

        assertEq(allocator.activeDeltaPoolOf(TOKEN_ID), address(0));
        assertEq(poolSleeve.balanceOf(address(account)), 0);
        assertEq(usdg.balanceOf(address(account)), 1_000 ether);
        assertFalse(account.isTrackedAsset(address(poolSleeve)));
    }

    function testInfrastructureDeactivationBlocksNewDynamicPoolDeposits() external {
        MockYieldBankAsset pool = new MockYieldBankAsset("Delta Pool Identity", "POOL-ID");
        MockOwnerPoolSleeve poolSleeve = new MockOwnerPoolSleeve(address(weth), address(allocator));
        MockOwnerDeltaPoolAdapter adapter =
            new MockOwnerDeltaPoolAdapter(address(poolSleeve), address(pool));
        poolSleeve.activate(address(adapter));
        deltaPoolController.materialize(address(pool), address(poolSleeve), address(adapter));
        deltaPoolController.setSelectable(address(pool), false);

        vm.expectRevert(
            abi.encodeWithSelector(
                CollectionPortfolioAllocator.DeltaPoolUnavailable.selector, address(pool)
            )
        );
        allocator.depositToAdapter(address(poolSleeve), address(adapter), 1, 1, "");
    }

    function testTargetCanBeChangedWhilePausedButExecutionCannotRun() external {
        collection.setState(YieldBankCollectionState.INVESTMENT_PAUSED);
        uint16[3] memory weights = [uint16(0), uint16(10_000), uint16(0)];
        uint64 revision = _requestTarget(weights);
        CollectionPortfolioAllocator.RebalanceExecution memory execution;
        vm.expectRevert(
            abi.encodeWithSelector(
                CollectionPortfolioAllocator.InvestmentUnavailable.selector,
                YieldBankCollectionState.INVESTMENT_PAUSED
            )
        );
        allocator.executeTargetAllocation(TOKEN_ID, revision, execution);
    }

    function _requestTarget(uint16[3] memory weights) private returns (uint64 revision) {
        vm.prank(ALICE);
        return allocator.setTargetAllocation(
            TOKEN_ID, weights, address(0), 100, uint48(block.timestamp + 2 hours)
        );
    }
}
