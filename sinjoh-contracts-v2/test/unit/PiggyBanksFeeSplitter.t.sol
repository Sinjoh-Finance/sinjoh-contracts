// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { PiggyBanksFeeSplitter } from "../../src/yield-banks/PiggyBanksFeeSplitter.sol";
import { IPriceHub } from "../../src/yield-banks/interfaces/IPriceHub.sol";

contract SplitterWeth is ERC20 {
    constructor() ERC20("Wrapped Ether", "WETH") { }

    function mint(address recipient, uint256 amount) external {
        _mint(recipient, amount);
    }
}

contract SplitterSourceRouterMock {
    address public immutable creator;
    address public immutable subject;
    address public immutable weth;

    constructor(address creator_, address subject_, address weth_) {
        creator = creator_;
        subject = subject_;
        weth = weth_;
    }

    function allocationInfo(uint8 bucketId, uint8 allocationId)
        external
        view
        returns (address, uint16, bool, bool, bytes memory)
    {
        require(bucketId == 0 && allocationId == 0);
        return (creator, 8_000, false, true, "");
    }
}

contract SplitterAllocatorMock {
    address[3] public sleeves;

    constructor(address usdgSleeve_) {
        sleeves[2] = usdgSleeve_;
    }
}

contract SplitterPriceHubMock {
    mapping(address asset => uint256 price) public prices;

    function setPrice(address asset, uint256 price) external {
        prices[asset] = price;
    }

    function quoteUsd18(address asset)
        external
        view
        returns (uint256 priceUsd18, uint48 pricedAt, IPriceHub.FailureReason failure)
    {
        priceUsd18 = prices[asset];
        pricedAt = uint48(block.timestamp);
        failure = priceUsd18 == 0
            ? IPriceHub.FailureReason.UNSUPPORTED_ASSET
            : IPriceHub.FailureReason.NONE;
    }
}

contract SplitterUsdg is ERC20 {
    address public immutable priceHub;

    constructor(address priceHub_) ERC20("USDG Sleeve", "sUSDG") {
        priceHub = priceHub_;
        _mint(address(this), 1_000_000 ether);
    }

    function accountingAsset() external view returns (address) {
        return address(this);
    }

    function totalAssetsUsd18() external pure returns (uint256 value, uint48 pricedAt) {
        return (1_000_000 ether, 1);
    }
}

contract SplitterCollectionMock {
    bytes32 public immutable collectionId;
    address public immutable weth;
    address public revenueRouter;

    constructor(bytes32 collectionId_, address weth_) {
        collectionId = collectionId_;
        weth = weth_;
    }

    function setRevenueRouter(address revenueRouter_) external {
        require(revenueRouter == address(0));
        revenueRouter = revenueRouter_;
    }
}

contract SplitterRevenueRouterMock {
    using SafeERC20 for IERC20;

    address public immutable collection;
    address public immutable allocator;
    uint16 public constant royaltyBackingBps = 10_000;
    uint16 public constant royaltyCreatorBps = 0;
    uint16 public constant royaltySinjohBps = 0;

    mapping(address asset => mapping(bytes32 routeHash => uint256 amount)) public
        failedNftAllocation;
    bool public failAllocation;
    uint256 public totalFunded;
    bytes32 public lastSourceType;

    constructor(address collection_, address allocator_) {
        collection = collection_;
        allocator = allocator_;
    }

    function setFailAllocation(bool value) external {
        failAllocation = value;
    }

    function fund(
        bytes32,
        address sourceAsset,
        uint256 amount,
        bytes32 sourceType,
        bytes calldata sourceData
    ) external returns (uint256 received) {
        IERC20(sourceAsset).safeTransferFrom(msg.sender, address(this), amount);
        if (failAllocation) failedNftAllocation[sourceAsset][keccak256(sourceData)] += amount;
        totalFunded += amount;
        lastSourceType = sourceType;
        return amount;
    }
}

contract PiggyBanksFeeSplitterTest is Test {
    address private constant CREATOR = address(0xC0FFEE);
    bytes32 private constant COLLECTION_ID = keccak256("PIGGY_BANKS");

    SplitterWeth private weth;
    SplitterAllocatorMock private allocator;
    SplitterPriceHubMock private priceHub;
    SplitterUsdg private usdgSleeve;
    SplitterCollectionMock private collection;
    SplitterRevenueRouterMock private revenueRouter;
    SplitterSourceRouterMock private sourceRouter;
    PiggyBanksFeeSplitter private splitter;

    function setUp() external {
        weth = new SplitterWeth();
        priceHub = new SplitterPriceHubMock();
        usdgSleeve = new SplitterUsdg(address(priceHub));
        priceHub.setPrice(address(weth), 2_500 ether);
        priceHub.setPrice(address(usdgSleeve), 1 ether);
        allocator = new SplitterAllocatorMock(address(usdgSleeve));
        collection = new SplitterCollectionMock(COLLECTION_ID, address(weth));
        revenueRouter = new SplitterRevenueRouterMock(address(collection), address(allocator));
        collection.setRevenueRouter(address(revenueRouter));
        SplitterWeth sourceToken = new SplitterWeth();
        sourceRouter = new SplitterSourceRouterMock(CREATOR, address(sourceToken), address(weth));
        splitter = new PiggyBanksFeeSplitter(
            address(weth),
            CREATOR,
            address(sourceRouter),
            address(sourceToken),
            address(collection),
            COLLECTION_ID,
            address(revenueRouter)
        );
    }

    function testSettleSplitsExactlyAndFundsTheNftOnlyPath() external {
        weth.mint(address(splitter), 10 ether);

        (uint256 creatorAmount, uint256 piggyAmount) = splitter.settle();

        assertEq(creatorAmount, 5 ether);
        assertEq(piggyAmount, 5 ether);
        assertEq(weth.balanceOf(CREATOR), 5 ether);
        assertEq(revenueRouter.totalFunded(), 5 ether);
        assertEq(revenueRouter.lastSourceType(), keccak256("YIELD_BANK_ROYALTY_REVENUE"));
        assertEq(splitter.totalCreatorReleased(), splitter.totalPiggyBanksFunded());
        assertEq(weth.balanceOf(address(splitter)), 0);
    }

    function testOddWeiWaitsForNextReceiptWithoutBias() external {
        weth.mint(address(splitter), 1);
        assertEq(splitter.pendingCreator(), 0);
        assertEq(splitter.pendingPiggyBanks(), 0);
        assertEq(weth.balanceOf(address(splitter)), 1);

        weth.mint(address(splitter), 1);
        splitter.settle();

        assertEq(weth.balanceOf(CREATOR), 1);
        assertEq(revenueRouter.totalFunded(), 1);
        assertEq(weth.balanceOf(address(splitter)), 0);
    }

    function testSettleCompletesTheRemainingHalfAfterAnIndependentCreatorRelease() external {
        weth.mint(address(splitter), 8 ether);
        splitter.releaseCreator();

        (uint256 creatorAmount, uint256 piggyAmount) = splitter.settle();

        assertEq(creatorAmount, 0);
        assertEq(piggyAmount, 4 ether);
        assertEq(weth.balanceOf(CREATOR), 4 ether);
        assertEq(revenueRouter.totalFunded(), 4 ether);
        assertEq(weth.balanceOf(address(splitter)), 0);
    }

    function test_RevertWhen_PiggyAllocationWouldBeEscrowed() external {
        weth.mint(address(splitter), 10 ether);
        revenueRouter.setFailAllocation(true);

        (bytes memory sourceData,,) = splitter.previewFundingData(5 ether);
        bytes32 routeHash = keccak256(sourceData);
        vm.expectRevert(
            abi.encodeWithSelector(
                PiggyBanksFeeSplitter.PiggyBanksAllocationEscrowed.selector, routeHash, 0, 5 ether
            )
        );
        splitter.fundPiggyBanks();

        assertEq(weth.balanceOf(address(splitter)), 10 ether);
        assertEq(weth.balanceOf(address(revenueRouter)), 0);
        assertEq(splitter.totalPiggyBanksFunded(), 0);
    }

    function testAnyoneMayFundPiggyBanksWithInternallyGuardedMinimums() external {
        weth.mint(address(splitter), 2 ether);
        vm.prank(address(0xB0B));
        assertEq(splitter.fundPiggyBanks(), 1 ether);
    }

    function testPreviewBuildsTheExactThreeLegPayloadWithTwoPercentProtection() external view {
        (bytes memory sourceData, uint256 minimumOutput, uint256 minimumShares) =
            splitter.previewFundingData(1 ether);
        PiggyBanksFeeSplitter.AllocationCall[3] memory calls =
            abi.decode(sourceData, (PiggyBanksFeeSplitter.AllocationCall[3]));

        assertEq(minimumOutput, 2_450 ether);
        assertEq(minimumShares, 2_450 ether);
        assertEq(calls[0].minimumOutput, 0);
        assertEq(calls[0].minimumShares, 0);
        assertEq(calls[1].minimumOutput, 0);
        assertEq(calls[1].minimumShares, 0);
        assertEq(calls[2].minimumOutput, minimumOutput);
        assertEq(calls[2].minimumShares, minimumShares);
        assertEq(calls[2].routeData, "");
        assertEq(calls[2].sleeveData, "");
    }

    function testPreviewRejectsUnavailableWethPrice() external {
        priceHub.setPrice(address(weth), 0);
        vm.expectRevert(
            abi.encodeWithSelector(
                PiggyBanksFeeSplitter.PriceUnavailable.selector,
                address(weth),
                IPriceHub.FailureReason.UNSUPPORTED_ASSET
            )
        );
        splitter.previewFundingData(1 ether);
    }

    function testCreatorReleaseIsPermissionlessAndIndependent() external {
        weth.mint(address(splitter), 8 ether);

        assertEq(splitter.releaseCreator(), 4 ether);
        assertEq(weth.balanceOf(CREATOR), 4 ether);
        assertEq(splitter.pendingPiggyBanks(), 4 ether);
        assertEq(splitter.totalPiggyBanksFunded(), 0);
    }
}
