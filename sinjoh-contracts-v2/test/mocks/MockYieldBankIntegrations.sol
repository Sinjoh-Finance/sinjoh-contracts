// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { YieldBankAccount } from "../../src/yield-banks/YieldBankAccount.sol";
import { YieldBankCollection } from "../../src/yield-banks/YieldBankCollection.sol";
import { YieldBankNFT } from "../../src/yield-banks/YieldBankNFT.sol";
import {
    CollectionPortfolioAllocator
} from "../../src/yield-banks/CollectionPortfolioAllocator.sol";
import { YieldBankDistributor } from "../../src/yield-banks/YieldBankDistributor.sol";
import {
    IYieldBankEligibilityPolicy
} from "../../src/yield-banks/interfaces/IYieldBankEligibilityPolicy.sol";
import { IYieldBankRenderer } from "../../src/yield-banks/interfaces/IYieldBankRenderer.sol";
import {
    IYieldBankAllocationReceiver
} from "../../src/yield-banks/interfaces/IYieldBankAllocationReceiver.sol";
import {
    IYieldBankAllocationRoute
} from "../../src/yield-banks/interfaces/IYieldBankAllocationRoute.sol";
import { IStrategyAdapter } from "../../src/yield-banks/interfaces/IStrategyAdapter.sol";
import { YieldBankCollectionState } from "../../src/yield-banks/YieldBankTypes.sol";

contract MockYieldBankAsset is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) { }

    function mint(address recipient, uint256 amount) external {
        _mint(recipient, amount);
    }
}

contract MockYieldBankWETH is ERC20 {
    constructor() ERC20("Wrapped Ether", "WETH") { }

    receive() external payable {
        _mint(msg.sender, msg.value);
    }

    function deposit() external payable {
        _mint(msg.sender, msg.value);
    }

    function withdraw(uint256 amount) external {
        _burn(msg.sender, amount);
        (bool ok,) = payable(msg.sender).call{ value: amount }("");
        require(ok);
    }
}

contract MockYieldBankSeaDrop {
    function mint(YieldBankNFT nft, address minter, uint256 quantity) external payable {
        nft.mintSeaDrop(minter, quantity);
        (bool ok,) = payable(nft.proceedsVault()).call{ value: msg.value }("");
        require(ok, "payout failed");
    }
}

contract MockYieldBankPrimaryAllocator {
    address[3] public sleeves;
    uint16 public immutable coreWeightBps;
    uint16 public immutable marketMakingWeightBps;
    uint16 public immutable usdgWeightBps;

    constructor(
        address[3] memory sleeves_,
        uint16 coreWeightBps_,
        uint16 marketMakingWeightBps_,
        uint16 usdgWeightBps_
    ) {
        sleeves = sleeves_;
        coreWeightBps = coreWeightBps_;
        marketMakingWeightBps = marketMakingWeightBps_;
        usdgWeightBps = usdgWeightBps_;
    }

    function allocatePrimary(
        address asset,
        uint256 amount,
        address receiver,
        CollectionPortfolioAllocator.AllocationCall[3] calldata
    ) external returns (address[] memory assets, uint256[] memory amounts) {
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        assets = new address[](3);
        amounts = new uint256[](3);
        amounts[0] = amount * coreWeightBps / 10_000;
        uint256 marketCumulative = amount * (coreWeightBps + marketMakingWeightBps) / 10_000;
        amounts[1] = marketCumulative - amounts[0];
        amounts[2] = amount - marketCumulative;
        for (uint256 i; i < 3; ++i) {
            assets[i] = sleeves[i];
            MockYieldBankAsset(sleeves[i]).mint(receiver, amounts[i]);
        }
    }
}

contract MockYieldBankCollectionPointer {
    address public proceedsVault;
    YieldBankCollectionState public state = YieldBankCollectionState.ACTIVE;

    function setProceedsVault(address value) external {
        proceedsVault = value;
    }

    function setState(YieldBankCollectionState value) external {
        state = value;
    }
}

contract MockYieldBankSleeve is ERC20 {
    address public immutable accountingAsset;
    address public lastAdapter;
    uint256 public lastAdapterAssets;

    constructor(address accountingAsset_, string memory symbol_) ERC20(symbol_, symbol_) {
        accountingAsset = accountingAsset_;
    }

    function deposit(uint256 assets, address receiver, uint256 minShares, bytes calldata)
        external
        returns (uint256 shares)
    {
        IERC20(accountingAsset).transferFrom(msg.sender, address(this), assets);
        shares = assets;
        require(shares >= minShares, "minimum shares");
        _mint(receiver, shares);
    }

    function depositToAdapter(
        address adapter,
        uint256 assets,
        uint256 minPositionUnits,
        bytes calldata
    ) external returns (uint256 positionUnits) {
        lastAdapter = adapter;
        lastAdapterAssets = assets;
        positionUnits = assets;
        require(positionUnits >= minPositionUnits);
    }

    function withdrawFromAdapter(address adapter, uint256 assets, uint16, bytes calldata)
        external
        returns (uint256 assetsReturned)
    {
        lastAdapter = adapter;
        lastAdapterAssets = assets;
        return assets;
    }

    function collectAdapter(address adapter, bytes calldata)
        external
        returns (address[] memory assets, uint256[] memory amounts)
    {
        lastAdapter = adapter;
        assets = new address[](0);
        amounts = new uint256[](0);
    }

    function exitAdapter(address adapter, uint16, bytes calldata)
        external
        returns (address[] memory assets, uint256[] memory amounts)
    {
        lastAdapter = adapter;
        assets = new address[](0);
        amounts = new uint256[](0);
    }
}

contract MockYieldBankEligibilityPolicy is IYieldBankEligibilityPolicy {
    mapping(address account => bool blocked) public blocked;

    function setBlocked(address account, bool blocked_) external {
        blocked[account] = blocked_;
    }

    function canMint(address account, bytes calldata) external view returns (bool) {
        return !blocked[account];
    }

    function canReceiveNFT(address account, bytes calldata) external view returns (bool) {
        return !blocked[account];
    }

    function canReceiveRestrictedShares(address account, bytes calldata)
        external
        view
        returns (bool)
    {
        return !blocked[account];
    }

    function canRedeem(address account, bytes calldata) external view returns (bool) {
        return !blocked[account];
    }
}

contract MockYieldBankRenderer is IYieldBankRenderer {
    function tokenURI(address, uint256, address, uint8) external pure returns (string memory) {
        return "ipfs://yield-bank";
    }
}

contract MockYieldBankAllocator {
    function allocateSeed(address, uint256, bytes calldata) external { }

    function fundSeed(YieldBankCollection, address, uint256) external pure {
        revert("removed");
    }
}

contract MockYieldBankRevenueRouter {
    uint16 public immutable primaryBackingBps;
    uint16 public immutable primaryCreatorBps;
    uint16 public immutable primarySinjohBps;
    uint16 public immutable primaryOperationsBps;

    constructor(
        uint16 primaryBackingBps_,
        uint16 primaryCreatorBps_,
        uint16 primarySinjohBps_,
        uint16 primaryOperationsBps_
    ) {
        primaryBackingBps = primaryBackingBps_;
        primaryCreatorBps = primaryCreatorBps_;
        primarySinjohBps = primarySinjohBps_;
        primaryOperationsBps = primaryOperationsBps_;
    }

    function accrue(YieldBankCollection collection, address asset, uint256 amount) external {
        IERC20(asset).approve(address(collection.distributor()), amount);
        collection.accrueDistribution(asset, amount);
    }
}

contract MockYieldBankTimelock { }

contract MockYieldBankFundableReceiver {
    uint256 public received;

    function fund(bytes32, address asset, uint256 amount, bytes32, bytes calldata)
        external
        returns (uint256)
    {
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        received += amount;
        return amount;
    }
}

/// @dev Stores constructor wiring in storage so every instance shares one predictable runtime hash.
contract MockYieldBankPlannedComponent {
    address public collection;
    address public dependency;
    uint16 public primaryBackingBps;
    uint16 public primaryCreatorBps;
    uint16 public primarySinjohBps;
    uint16 public primaryOperationsBps;
    uint16 public coreWeightBps;
    uint16 public marketMakingWeightBps;
    uint16 public usdgWeightBps;

    constructor(address collection_, address dependency_, uint16[7] memory economics_) {
        require(collection_ != address(0) && dependency_ != address(0));
        collection = collection_;
        dependency = dependency_;
        primaryBackingBps = economics_[0];
        primaryCreatorBps = economics_[1];
        primarySinjohBps = economics_[2];
        primaryOperationsBps = economics_[3];
        coreWeightBps = economics_[4];
        marketMakingWeightBps = economics_[5];
        usdgWeightBps = economics_[6];
    }
}

contract MockSynchronousYieldBankAdapter is IStrategyAdapter {
    address public immutable sleeve;
    address public immutable accountingAsset;
    address public immutable rewardAsset;
    uint256 public managed;
    uint256 public claimableRewards;
    bool public omitCollectReport;

    constructor(address sleeve_, address accountingAsset_, address rewardAsset_) {
        sleeve = sleeve_;
        accountingAsset = accountingAsset_;
        rewardAsset = rewardAsset_;
    }

    modifier onlySleeve() {
        require(msg.sender == sleeve);
        _;
    }

    function positionAssets() external view returns (address[] memory assets) {
        assets = new address[](rewardAsset == accountingAsset ? 1 : 2);
        assets[0] = accountingAsset;
        if (assets.length == 2) assets[1] = rewardAsset;
    }

    function totalManagedAssets() external view returns (uint256) {
        return managed;
    }

    function addRewards(uint256 amount) external {
        IERC20(rewardAsset).transferFrom(msg.sender, address(this), amount);
        claimableRewards += amount;
    }

    function setOmitCollectReport(bool value) external {
        omitCollectReport = value;
    }

    function deposit(uint256 assets, uint256 minPositionUnits, bytes calldata)
        external
        onlySleeve
        returns (uint256 positionUnits)
    {
        IERC20(accountingAsset).transferFrom(sleeve, address(this), assets);
        managed += assets;
        positionUnits = assets;
        require(positionUnits >= minPositionUnits);
    }

    function withdraw(uint256 assets, address receiver, uint16, bytes calldata)
        external
        onlySleeve
        returns (uint256 assetsReturned)
    {
        require(receiver == sleeve && assets != 0 && assets <= managed);
        managed -= assets;
        assetsReturned = assets;
        IERC20(accountingAsset).transfer(receiver, assetsReturned);
    }

    function collect(address receiver, bytes calldata)
        external
        onlySleeve
        returns (address[] memory assets, uint256[] memory amounts)
    {
        require(receiver == sleeve);
        uint256 rewards = claimableRewards;
        claimableRewards = 0;
        if (omitCollectReport) {
            assets = new address[](0);
            amounts = new uint256[](0);
            if (rewards != 0) IERC20(rewardAsset).transfer(receiver, rewards);
            return (assets, amounts);
        }
        assets = new address[](1);
        amounts = new uint256[](1);
        assets[0] = rewardAsset;
        amounts[0] = rewards;
        if (rewards != 0) IERC20(rewardAsset).transfer(receiver, rewards);
    }

    function exitAll(address receiver, uint16, bytes calldata)
        external
        onlySleeve
        returns (address[] memory assets, uint256[] memory amounts)
    {
        require(receiver == sleeve);
        uint256 returned = managed;
        managed = 0;
        IERC20(accountingAsset).transfer(receiver, returned);
        assets = new address[](1);
        amounts = new uint256[](1);
        assets[0] = accountingAsset;
        amounts[0] = returned;
    }
}

contract MockYieldBankAggregator {
    uint8 public immutable decimals;
    int256 public answer;
    uint256 public updatedAt;

    constructor(uint8 decimals_, int256 answer_) {
        decimals = decimals_;
        answer = answer_;
        // Test feed initialization intentionally mirrors the current test timestamp.
        // forge-lint: disable-next-line(block-timestamp)
        updatedAt = block.timestamp;
    }

    function setAnswer(int256 answer_, uint256 updatedAt_) external {
        answer = answer_;
        updatedAt = updatedAt_;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (1, answer, updatedAt, updatedAt, 1);
    }
}

contract MockYieldBankReferencePrice {
    uint256 public price;
    uint48 public pricedAt;

    function setPrice(uint256 price_, uint48 pricedAt_) external {
        price = price_;
        pricedAt = pricedAt_;
    }

    function priceUsd18(address) external view returns (uint256, uint48) {
        return (price, pricedAt);
    }
}

contract MockYieldBankAllocationRoute is IYieldBankAllocationRoute {
    address public immutable inputAsset;
    address public immutable outputAsset;

    constructor(address inputAsset_, address outputAsset_) {
        inputAsset = inputAsset_;
        outputAsset = outputAsset_;
    }

    function convert(uint256 amountIn, uint256 minimumOutput, address receiver, bytes calldata)
        external
        returns (uint256 amountOut)
    {
        IERC20(inputAsset).transferFrom(msg.sender, address(this), amountIn);
        amountOut = amountIn;
        require(amountOut >= minimumOutput);
        MockYieldBankAsset(outputAsset).mint(receiver, amountOut);
    }
}

contract MockYieldBankAllocationReceiver is IYieldBankAllocationReceiver {
    bool public shouldFail;
    address[3] public outputs;

    constructor(address[3] memory outputs_) {
        outputs = outputs_;
    }

    function setShouldFail(bool value) external {
        shouldFail = value;
    }

    function allocate(address asset, uint256 amount, bytes calldata)
        external
        returns (address[] memory distributionAssets, uint256[] memory distributionAmounts)
    {
        if (shouldFail) {
            revert("allocation failed");
        }
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        distributionAssets = new address[](3);
        distributionAmounts = new uint256[](3);
        for (uint256 i; i < 3; ++i) {
            distributionAssets[i] = outputs[i];
            distributionAmounts[i] = amount / 3;
            MockYieldBankAsset(outputs[i]).mint(msg.sender, distributionAmounts[i]);
        }
    }
}

contract MockYieldBankCollectionReceiver {
    bytes32 public immutable collectionId;
    address public immutable distributor = address(this);
    uint256 public liveSupply = 7;
    mapping(address asset => uint256 amount) public received;

    constructor(bytes32 collectionId_) {
        collectionId = collectionId_;
    }

    function accountOf(uint256) external pure returns (address) {
        return address(0);
    }

    function fundSeedAsset(address, uint256) external pure { }

    function accrueDistribution(address asset, uint256 amount) external {
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        received[asset] += amount;
    }
}

contract MockYieldBankDistributorHarness {
    YieldBankDistributor public immutable distributor;
    address public immutable accountImplementation;

    constructor() {
        distributor = new YieldBankDistributor(address(this));
        accountImplementation = address(new YieldBankAccount());
    }

    function registerAsset(address asset) external {
        distributor.registerAsset(asset);
    }

    function createAccount(uint256 tokenId) external returns (address account) {
        account = Clones.clone(accountImplementation);
        YieldBankAccount(account)
            .initialize(address(this), address(1), tokenId, address(distributor));
        distributor.initializeTokenDebt(tokenId);
    }

    function accrue(address asset, uint256 amount, uint256 liveSupply) external {
        IERC20(asset).approve(address(distributor), amount);
        distributor.accrueFrom(asset, address(this), amount, liveSupply);
    }

    function settle(uint256 tokenId, address account, bool terminal) external {
        distributor.settle(tokenId, account, terminal);
    }

    function retire(uint256 tokenId) external {
        distributor.retireToken(tokenId);
    }
}
