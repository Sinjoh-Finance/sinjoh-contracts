// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { StockBankReceipt } from "./StockBankReceipt.sol";
import { StockStrategyMath } from "./StockStrategyMath.sol";
import { StockDividendVault } from "./StockDividendVault.sol";
import { IPriceHub } from "../interfaces/IPriceHub.sol";
import { IYieldBankCollection } from "../interfaces/IYieldBankCollection.sol";
import { IYieldBankAllocationRoute } from "../interfaces/IYieldBankAllocationRoute.sol";
import { YieldBankAdapterRedemptionCall } from "../interfaces/IYieldBankManagedSleeve.sol";
import { YieldBankAdapterState, YieldBankRedemptionMode } from "../YieldBankTypes.sol";
import { YieldBankIds } from "../libraries/YieldBankIds.sol";
import { IntegrationBinding } from "../libraries/IntegrationBinding.sol";
import { CollectionPortfolioAllocator } from "../CollectionPortfolioAllocator.sol";

interface IStockCompositeAllocator {
    function collection() external view returns (IYieldBankCollection);
    function timelock() external view returns (address);
}

interface IStockCompositeLP {
    function sleeve() external view returns (address);
    function lpReceiptToken() external view returns (address);
    function lpUnitPriceUsd18() external view returns (uint256, uint48);
    function purchaseLP(uint256 assets, uint256 minimumShares, bytes calldata data)
        external
        returns (uint256);
    function redeemLP(uint256 shares, uint256 minimumWeth, uint16 maxLossBps, bytes calldata data)
        external
        returns (uint256);
}

/// @notice Bank-isolated Stock and LP allocation within the allocator's dynamic destination.
/// @dev Uses the controller's existing constructor/registration and allocator's deposit/redeem
/// interfaces. Requires a separately reviewed, configured LP adapter and Stock custody vault.
/// This source is not a claim that its infrastructure generation is enabled on mainnet.
contract StockCompositeSleeve is StockBankReceipt, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Target {
        address owner;
        uint64 nonce;
        uint48 validUntil;
        uint16 lpWeightBps;
        uint16 stockWeightBps;
        address[] assets;
        uint16[] weights;
    }

    struct DepositExecution {
        uint256 bank;
        uint64 targetNonce;
        uint256[] minimumStockUnits;
        bytes[] stockRouteData;
        uint256 minimumLPUnits;
        bytes lpData;
    }

    struct RedemptionExecution {
        uint256[] minimumStockWeth;
        bytes[] stockRouteData;
        uint256 minimumLPWeth;
        bytes lpData;
    }

    struct Route {
        address route;
        bytes32 codeHash;
    }

    bytes32 public constant category = YieldBankIds.MARKET_MAKING;
    address public immutable accountingAsset;
    address public immutable allocator;
    address public immutable timelock;
    address public immutable guardian;
    address public immutable priceHub;
    address public immutable strategyRegistry;
    address public immutable eligibilityPolicy;
    uint8 public immutable maximumStrategies;
    uint16 public immutable maximumAdapterCapBps;
    uint16 public immutable maximumOperatorLossBps;
    IYieldBankCollection public immutable collection;
    address public immutable governance;
    StockDividendVault public stockVault;
    address public portfolioAdapter;
    bool public depositsPaused = true;
    mapping(address => YieldBankAdapterState) public adapterState;
    mapping(address => uint16) public adapterCapBps;
    mapping(uint256 => Target) private _targets;
    mapping(uint256 => address[]) private _bankAssets;
    mapping(address => uint256) public bankOf;
    mapping(uint256 => uint256) public lpUnitsOf;
    uint256 public totalLPUnits;
    address[] private _stocks;
    mapping(address => bool) private _listed;
    mapping(address => Route) public stockEntryRoute;
    mapping(address => Route) public stockExitRoute;

    error Unauthorized();
    error InvalidConfiguration();
    error InvalidTarget();
    error DepositsUnavailable();
    error InexactTransfer();
    error OracleUnavailable();
    error FullRebalanceRequired();
    error UnsupportedOperation();

    event StockTargetSet(
        uint256 indexed bank,
        address indexed owner,
        uint64 nonce,
        uint16 lpWeightBps,
        uint16 stockWeightBps,
        address[] assets,
        uint16[] weights,
        uint48 validUntil
    );
    event CompositeDeposited(uint256 indexed bank, uint256 weth, uint256 receiptUnits);
    event CompositeRedeemed(uint256 indexed bank, uint256 weth, uint256 receiptUnits);
    event StockRoutesBound(address indexed asset, address entry, address exit);

    constructor(
        string memory name_,
        string memory symbol_,
        address accountingAsset_,
        address allocator_,
        address timelock_,
        address guardian_,
        address priceHub_,
        address strategyRegistry_,
        address eligibilityPolicy_,
        uint8 maximumStrategies_,
        uint16 maximumAdapterCapBps_,
        uint16 maximumOperatorLossBps_
    ) StockBankReceipt(name_, symbol_) {
        if (
            accountingAsset_.code.length == 0 || allocator_.code.length == 0
                || timelock_ == address(0) || guardian_ == address(0) || priceHub_.code.length == 0
                || strategyRegistry_.code.length == 0 || eligibilityPolicy_.code.length == 0
                || maximumStrategies_ != 1 || maximumAdapterCapBps_ == 0
                || maximumAdapterCapBps_ > 10000 || maximumOperatorLossBps_ > 500
                || IERC20Metadata(accountingAsset_).decimals() != 18
        ) revert InvalidConfiguration();
        accountingAsset = accountingAsset_;
        allocator = allocator_;
        timelock = timelock_;
        guardian = guardian_;
        priceHub = priceHub_;
        strategyRegistry = strategyRegistry_;
        eligibilityPolicy = eligibilityPolicy_;
        maximumStrategies = maximumStrategies_;
        maximumAdapterCapBps = maximumAdapterCapBps_;
        maximumOperatorLossBps = maximumOperatorLossBps_;
        collection = IStockCompositeAllocator(allocator_).collection();
        governance = IStockCompositeAllocator(allocator_).timelock();
    }

    modifier onlyAllocator() {
        if (msg.sender != allocator) revert Unauthorized();
        _;
    }
    modifier onlyGovernance() {
        if (msg.sender != governance) revert Unauthorized();
        _;
    }
    modifier onlyController() {
        if (msg.sender != timelock) revert Unauthorized();
        _;
    }

    function configureVault(address vault) external onlyGovernance {
        if (address(stockVault) != address(0) || vault.code.length == 0) {
            revert InvalidConfiguration();
        }
        StockDividendVault candidate = StockDividendVault(vault);
        if (
            candidate.controller() != address(this)
                || address(candidate.collection()) != address(collection)
                || address(candidate.priceHub()) != priceHub || candidate.owner() != governance
        ) revert InvalidConfiguration();
        stockVault = candidate;
    }

    function bindStockRoutes(address asset, address entry, address exit) external onlyGovernance {
        if (
            address(stockVault) == address(0) || asset == accountingAsset
                || IERC20Metadata(asset).decimals() != 18
        ) revert InvalidConfiguration();
        stockVault.registry().requireCurrent(asset, true);
        if (
            entry.code.length == 0 || exit.code.length == 0
                || IYieldBankAllocationRoute(entry).inputAsset() != accountingAsset
                || IYieldBankAllocationRoute(entry).outputAsset() != asset
                || IYieldBankAllocationRoute(exit).inputAsset() != asset
                || IYieldBankAllocationRoute(exit).outputAsset() != accountingAsset
        ) revert InvalidConfiguration();
        if (!_listed[asset]) {
            if (_stocks.length >= 64) revert InvalidConfiguration();
            _listed[asset] = true;
            _stocks.push(asset);
        }
        stockEntryRoute[asset] = Route(entry, entry.codehash);
        stockExitRoute[asset] = Route(exit, exit.codehash);
        emit StockRoutesBound(asset, entry, exit);
    }

    function setTarget(
        uint256 bank,
        uint16 lpWeightBps,
        uint16 stockWeightBps,
        bool basket,
        address[] calldata assets,
        uint16[] calldata weights,
        uint48 validUntil
    ) external nonReentrant {
        address owner = IERC721(collection.nft()).ownerOf(bank);
        if (msg.sender != owner || collection.accountOf(bank) == address(0)) revert Unauthorized();
        if (
            stockWeightBps == 0 || uint256(lpWeightBps) + stockWeightBps > 10000
                || validUntil <= block.timestamp || validUntil > block.timestamp + 1 days
        ) revert InvalidTarget();
        StockStrategyMath.validate(basket, assets, weights);
        for (uint256 i; i < assets.length; ++i) {
            if (!_listed[assets[i]]) revert InvalidTarget();
            stockVault.registry().requireCurrent(assets[i], true);
        }
        Target storage target = _targets[bank];
        target.owner = owner;
        ++target.nonce;
        target.validUntil = validUntil;
        target.lpWeightBps = lpWeightBps;
        target.stockWeightBps = stockWeightBps;
        target.assets = assets;
        target.weights = weights;
        emit StockTargetSet(
            bank, owner, target.nonce, lpWeightBps, stockWeightBps, assets, weights, validUntil
        );
    }

    function targetOf(uint256 bank) external view returns (Target memory) {
        return _targets[bank];
    }

    function bankAssets(uint256 bank) external view returns (address[] memory) {
        return _bankAssets[bank];
    }

    function inventoryAssets() external view returns (address[] memory assets) {
        assets = new address[](1);
        assets[0] = accountingAsset;
    }

    function adapters() external view returns (address[] memory result) {
        result = new address[](portfolioAdapter == address(0) ? 0 : 1);
        if (result.length != 0) result[0] = portfolioAdapter;
    }

    function activeStrategyCount() external view returns (uint256) {
        return portfolioAdapter == address(0) ? 0 : 1;
    }

    function addAdapter(address adapter, uint16 capBps) external onlyController {
        if (
            portfolioAdapter != address(0) || adapter.code.length == 0
                || IStockCompositeLP(adapter).sleeve() != address(this) || capBps == 0
                || capBps > maximumAdapterCapBps
        ) revert InvalidConfiguration();
        portfolioAdapter = adapter;
        adapterState[adapter] = YieldBankAdapterState.ACTIVE;
        adapterCapBps[adapter] = capBps;
    }

    function setAdapterCap(address adapter, uint16 capBps) external onlyController {
        if (adapter != portfolioAdapter || capBps == 0 || capBps > maximumAdapterCapBps) {
            revert InvalidConfiguration();
        }
        adapterCapBps[adapter] = capBps;
    }

    function retireAdapter(address adapter) external onlyController {
        if (adapter != portfolioAdapter) revert InvalidConfiguration();
        depositsPaused = true;
        adapterState[adapter] = YieldBankAdapterState.EXIT_ONLY;
    }

    function setDepositsPaused(bool paused) external onlyController {
        depositsPaused = paused;
    }

    function pauseDeposits() external {
        if (msg.sender != guardian) revert Unauthorized();
        depositsPaused = true;
    }

    function deposit(uint256 assets, address receiver, uint256 minimumShares, bytes calldata data)
        external
        onlyAllocator
        nonReentrant
        returns (uint256 shares)
    {
        if (
            depositsPaused || address(stockVault) == address(0) || portfolioAdapter == address(0)
                || adapterState[portfolioAdapter] != YieldBankAdapterState.ACTIVE || assets == 0
        ) revert DepositsUnavailable();
        DepositExecution memory execution = abi.decode(data, (DepositExecution));
        Target storage target = _targets[execution.bank];
        uint256 combinedWeight = uint256(target.lpWeightBps) + target.stockWeightBps;
        CollectionPortfolioAllocator.AllocationTarget memory bankTarget =
            CollectionPortfolioAllocator(allocator).allocationTargetOf(execution.bank);
        if (
            collection.accountOf(execution.bank) != receiver
                || target.owner != IERC721(collection.nft()).ownerOf(execution.bank)
                || target.nonce != execution.targetNonce || target.validUntil < block.timestamp
                || target.assets.length == 0 || _bankAssets[execution.bank].length != 0
                || lpUnitsOf[execution.bank] != 0
                || uint256(target.lpWeightBps) * 10000
                    > uint256(adapterCapBps[portfolioAdapter]) * combinedWeight
                || bankTarget.coreWeightBps != 0
                || bankTarget.marketMakingWeightBps != combinedWeight
                || uint256(bankTarget.usdgWeightBps) + combinedWeight != 10000
        ) revert InvalidTarget();
        if (
            execution.minimumStockUnits.length != target.assets.length
                || execution.stockRouteData.length != target.assets.length
        ) revert InvalidConfiguration();
        uint256 beforeWeth = IERC20(accountingAsset).balanceOf(address(this));
        IERC20(accountingAsset).safeTransferFrom(msg.sender, address(this), assets);
        if (IERC20(accountingAsset).balanceOf(address(this)) != beforeWeth + assets) {
            revert InexactTransfer();
        }
        uint256 lpAmount = Math.mulDiv(assets, target.lpWeightBps, combinedWeight);
        uint256 stockAmount = assets - lpAmount;
        uint256[] memory amounts = StockStrategyMath.allocate(
            stockAmount, target.assets.length > 1, target.assets, target.weights
        );
        bankOf[receiver] = execution.bank;
        _bankAssets[execution.bank] = target.assets;
        for (uint256 i; i < target.assets.length; ++i) {
            address asset = target.assets[i];
            stockVault.registry().requireCurrent(asset, true);
            uint256 units = _convert(
                accountingAsset,
                asset,
                amounts[i],
                execution.minimumStockUnits[i],
                stockEntryRoute[asset],
                execution.stockRouteData[i],
                maximumOperatorLossBps
            );
            IERC20(asset).forceApprove(address(stockVault), units);
            stockVault.deposit(execution.bank, asset, units);
            IERC20(asset).forceApprove(address(stockVault), 0);
        }
        if (lpAmount != 0) {
            IERC20(accountingAsset).forceApprove(portfolioAdapter, lpAmount);
            uint256 beforeLP = IERC20(IStockCompositeLP(portfolioAdapter).lpReceiptToken())
                .balanceOf(address(this));
            uint256 lpUnits = IStockCompositeLP(portfolioAdapter)
                .purchaseLP(lpAmount, execution.minimumLPUnits, execution.lpData);
            IERC20(accountingAsset).forceApprove(portfolioAdapter, 0);
            if (
                lpUnits == 0
                    || IERC20(IStockCompositeLP(portfolioAdapter).lpReceiptToken())
                            .balanceOf(address(this)) != beforeLP + lpUnits
            ) revert InexactTransfer();
            lpUnitsOf[execution.bank] = lpUnits;
            totalLPUnits += lpUnits;
        } else if (execution.minimumLPUnits != 0 || execution.lpData.length != 0) {
            revert InvalidConfiguration();
        }
        if (IERC20(accountingAsset).balanceOf(address(this)) != beforeWeth) {
            revert InexactTransfer();
        }
        if (target.owner != IERC721(collection.nft()).ownerOf(execution.bank)) {
            revert InvalidTarget();
        }
        shares = balanceOf(receiver);
        if (shares == 0 || shares < minimumShares) revert InvalidConfiguration();
        emit Transfer(address(0), receiver, shares);
        emit CompositeDeposited(execution.bank, assets, shares);
    }

    function redeemManaged(
        uint256 shares,
        address receiver,
        address owner,
        uint256[] calldata minimumOutputs,
        YieldBankAdapterRedemptionCall[] calldata calls
    )
        external
        onlyAllocator
        nonReentrant
        returns (address[] memory assets, uint256[] memory amounts)
    {
        uint256 bank = bankOf[owner];
        address nftOwner = IERC721(collection.nft()).ownerOf(bank);
        if (bank == 0 || receiver != allocator || shares == 0 || shares != balanceOf(owner)) {
            revert FullRebalanceRequired();
        }
        if (
            minimumOutputs.length != 1 || minimumOutputs[0] == 0 || calls.length != 1
                || calls[0].adapter != portfolioAdapter
                || calls[0].maxLossBps > maximumOperatorLossBps
        ) revert InvalidConfiguration();
        _spendAllowance(owner, msg.sender, shares);
        RedemptionExecution memory execution = abi.decode(calls[0].data, (RedemptionExecution));
        address[] memory stocks = _bankAssets[bank];
        if (
            execution.minimumStockWeth.length != stocks.length
                || execution.stockRouteData.length != stocks.length
        ) revert InvalidConfiguration();
        uint256 beforeWeth = IERC20(accountingAsset).balanceOf(address(this));
        for (uint256 i; i < stocks.length; ++i) {
            stockVault.checkpoint(bank, stocks[i], 32);
            (uint256 principal, uint256 reserved,,) = stockVault.positions(bank, stocks[i]);
            if (reserved != 0) {
                stockVault.retainDividendDust(bank, stocks[i]);
                (principal,,,) = stockVault.positions(bank, stocks[i]);
            }
            if (principal == 0) revert InvalidConfiguration();
            stockVault.withdrawPrincipal(bank, stocks[i], principal);
            _convert(
                stocks[i],
                accountingAsset,
                principal,
                execution.minimumStockWeth[i],
                stockExitRoute[stocks[i]],
                execution.stockRouteData[i],
                calls[0].maxLossBps
            );
        }
        uint256 lpUnits = lpUnitsOf[bank];
        if (lpUnits != 0) {
            IERC20 lpToken = IERC20(IStockCompositeLP(portfolioAdapter).lpReceiptToken());
            uint256 beforeLP = lpToken.balanceOf(address(this));
            uint256 beforeLPWeth = IERC20(accountingAsset).balanceOf(address(this));
            lpToken.forceApprove(portfolioAdapter, lpUnits);
            IStockCompositeLP(portfolioAdapter)
                .redeemLP(lpUnits, execution.minimumLPWeth, calls[0].maxLossBps, execution.lpData);
            lpToken.forceApprove(portfolioAdapter, 0);
            if (
                lpToken.balanceOf(address(this)) != beforeLP - lpUnits
                    || IERC20(accountingAsset).balanceOf(address(this))
                        < beforeLPWeth + execution.minimumLPWeth
            ) revert InexactTransfer();
            totalLPUnits -= lpUnits;
            delete lpUnitsOf[bank];
        } else if (execution.minimumLPWeth != 0 || execution.lpData.length != 0) {
            revert InvalidConfiguration();
        }
        if (IERC721(collection.nft()).ownerOf(bank) != nftOwner) revert InvalidTarget();
        delete _bankAssets[bank];
        uint256 returned = IERC20(accountingAsset).balanceOf(address(this)) - beforeWeth;
        if (returned < minimumOutputs[0]) revert InvalidConfiguration();
        IERC20(accountingAsset).safeTransfer(receiver, returned);
        if (IERC20(accountingAsset).balanceOf(address(this)) != beforeWeth) {
            revert InexactTransfer();
        }
        assets = new address[](1);
        amounts = new uint256[](1);
        assets[0] = accountingAsset;
        amounts[0] = returned;
        emit Transfer(owner, address(0), shares);
        emit CompositeRedeemed(bank, returned, shares);
    }

    function redeem(
        uint256,
        address,
        address,
        YieldBankRedemptionMode,
        uint256[] calldata,
        bytes calldata
    ) external pure returns (address[] memory, uint256[] memory) {
        revert FullRebalanceRequired();
    }

    function totalAssetsUsd18() external view returns (uint256 value, uint48 pricedAt) {
        (uint256 numerator, uint48 oldest) = _totalValue();
        return (numerator / 1 ether, oldest);
    }

    function _accountValue36(address account) internal view override returns (uint256 value) {
        uint256 bank = bankOf[account];
        if (bank == 0) return 0;
        address[] storage stocks = _bankAssets[bank];
        for (uint256 i; i < stocks.length; ++i) {
            (uint256 principal, uint256 reserved,,) = stockVault.positions(bank, stocks[i]);
            uint256 units = principal + reserved;
            if (units != 0) {
                (uint256 price,) = _stockPrice(stocks[i]);
                value += units * price;
            }
        }
        if (lpUnitsOf[bank] != 0) {
            (uint256 price,) = IStockCompositeLP(portfolioAdapter).lpUnitPriceUsd18();
            if (price == 0) revert OracleUnavailable();
            value += lpUnitsOf[bank] * price;
        }
    }

    function _totalValue36() internal view override returns (uint256 value) {
        (value,) = _totalValue();
    }

    function _totalValue() private view returns (uint256 value, uint48 oldest) {
        oldest = uint48(block.timestamp);
        for (uint256 i; i < _stocks.length; ++i) {
            uint256 units = stockVault.accountedUnits(_stocks[i]);
            if (units == 0) continue;
            (uint256 price, uint48 at) = _stockPrice(_stocks[i]);
            value += units * price;
            if (at < oldest) oldest = at;
        }
        if (totalLPUnits != 0) {
            (uint256 price, uint48 at) = IStockCompositeLP(portfolioAdapter).lpUnitPriceUsd18();
            if (price == 0) revert OracleUnavailable();
            value += totalLPUnits * price;
            if (at < oldest) oldest = at;
        }
    }

    function _stockPrice(address asset) private view returns (uint256 price, uint48 at) {
        stockVault.registry().requireCurrent(asset, false);
        return _price(asset);
    }

    function _price(address asset) private view returns (uint256 price, uint48 at) {
        IPriceHub.FailureReason failure;
        (price, at, failure) = IPriceHub(priceHub).quoteUsd18(asset);
        if (failure != IPriceHub.FailureReason.NONE || price == 0) revert OracleUnavailable();
    }

    function _convert(
        address input,
        address output,
        uint256 amount,
        uint256 minimum,
        Route memory route,
        bytes memory data,
        uint16 lossBps
    ) private returns (uint256 received) {
        IntegrationBinding.requireBound(route.route, route.codeHash);
        (uint256 inputPrice,) = _price(input);
        (uint256 outputPrice,) = _price(output);
        uint256 quote = Math.mulDiv(amount, inputPrice, outputPrice);
        uint256 floor = Math.mulDiv(quote, 10000 - lossBps, 10000, Math.Rounding.Ceil);
        if (minimum == 0) revert InvalidConfiguration();
        minimum = Math.max(minimum, floor);
        uint256 beforeInput = IERC20(input).balanceOf(address(this));
        uint256 beforeOutput = IERC20(output).balanceOf(address(this));
        IERC20(input).forceApprove(route.route, amount);
        IYieldBankAllocationRoute(route.route).convert(amount, minimum, address(this), data);
        IERC20(input).forceApprove(route.route, 0);
        if (IERC20(input).balanceOf(address(this)) != beforeInput - amount) {
            revert InexactTransfer();
        }
        received = IERC20(output).balanceOf(address(this)) - beforeOutput;
        if (received < minimum) revert InexactTransfer();
    }
}
