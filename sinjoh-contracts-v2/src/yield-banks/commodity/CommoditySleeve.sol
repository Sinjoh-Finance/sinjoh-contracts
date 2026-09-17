// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { StockBankReceipt } from "../stock/StockBankReceipt.sol";
import { IStockCompositeAllocator, IStockCompositeLP } from "../stock/StockCompositeSleeve.sol";
import { IYieldBankCollection } from "../interfaces/IYieldBankCollection.sol";
import { IYieldBankAllocationRoute } from "../interfaces/IYieldBankAllocationRoute.sol";
import { IYieldBankV3Pool } from "../interfaces/IYieldBankV3.sol";
import { YieldBankAdapterRedemptionCall } from "../interfaces/IYieldBankManagedSleeve.sol";
import { YieldBankAdapterState, YieldBankRedemptionMode } from "../YieldBankTypes.sol";
import { YieldBankIds } from "../libraries/YieldBankIds.sol";
import { IPriceHub } from "../interfaces/IPriceHub.sol";
import { CollectionPortfolioAllocator } from "../CollectionPortfolioAllocator.sol";

/// @notice Bank-isolated GLD, SLV, USO and cbBTC custody in the existing dynamic allocator slot.
/// @dev Reuses the existing LP adapter to retain the bank's remaining LP allocation. Commodity
/// swaps enforce quoted minimum outputs only. No dividend processing or additional price gates.
contract CommoditySleeve is StockBankReceipt, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Target {
        address owner;
        uint64 nonce;
        uint16 allocationBps;
        uint16 lpBps;
        uint16[4] weights;
    }

    struct Execution {
        uint256 bank;
        uint64 nonce;
        uint256[4] minimumOutputs;
        bytes[4] routeData;
        uint256 minimumLPUnits;
        bytes lpData;
    }

    struct Redemption {
        uint256[4] minimumOutputs;
        bytes[4] routeData;
        uint256 minimumLPWeth;
        bytes lpData;
    }

    struct Asset {
        address token;
        address pool;
        address quoteAsset;
        address entry;
        address exit;
        uint8 decimals;
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
    address public portfolioAdapter;
    bool public configured;
    bool public depositsPaused = true;
    Asset[4] private _assets;
    mapping(address => YieldBankAdapterState) public adapterState;
    mapping(address => uint16) public adapterCapBps;
    mapping(uint256 => Target) private _targets;
    mapping(address => uint256) public bankOf;
    mapping(uint256 => uint256[4]) private _units;
    uint256[4] public totalUnits;
    mapping(uint256 => uint256) public lpUnitsOf;
    uint256 public totalLPUnits;

    error Unauthorized();
    error InvalidConfiguration();
    error InvalidTarget();
    error InexactTransfer();
    error FullRebalanceRequired();
    error PriceUnavailable();
    event CommodityTargetSet(
        uint256 indexed bank,
        address indexed owner,
        uint64 nonce,
        uint16 allocationBps,
        uint16 lpBps,
        uint16[4] weights
    );
    event CommodityDeposited(uint256 indexed bank, uint256 weth, uint256 shares);
    event CommodityRedeemed(uint256 indexed bank, uint256 weth, uint256 shares);

    // Constructor signature is fixed by the deployed DeltaPoolController.
    constructor(
        string memory,
        string memory,
        address weth_,
        address allocator_,
        address controller_,
        address guardian_,
        address hub_,
        address registry_,
        address policy_,
        uint8 strategies_,
        uint16 cap_,
        uint16 loss_
    ) StockBankReceipt("Piggy Banks Commodities", "PB-COMMODITY") {
        if (weth_.code.length == 0 || allocator_.code.length == 0 || strategies_ != 1) {
            revert InvalidConfiguration();
        }
        accountingAsset = weth_;
        allocator = allocator_;
        timelock = controller_;
        guardian = guardian_;
        priceHub = hub_;
        strategyRegistry = registry_;
        eligibilityPolicy = policy_;
        maximumStrategies = strategies_;
        maximumAdapterCapBps = cap_;
        maximumOperatorLossBps = loss_;
        collection = IStockCompositeAllocator(allocator_).collection();
        governance = IStockCompositeAllocator(allocator_).timelock();
    }

    modifier onlyAllocator() {
        if (msg.sender != allocator) revert Unauthorized();
        _;
    }
    modifier onlyController() {
        if (msg.sender != timelock) revert Unauthorized();
        _;
    }

    /// @notice One-time, governance-bound four-asset universe. Orders match GLD/SLV/USO/cbBTC.
    function configureAssets(
        address[4] calldata tokens,
        address[4] calldata pools,
        address[4] calldata entries,
        address[4] calldata exits
    ) external {
        if (msg.sender != governance || configured) revert Unauthorized();
        for (uint256 i; i < 4; ++i) {
            if (
                tokens[i].code.length == 0 || entries[i].code.length == 0
                    || exits[i].code.length == 0
            ) revert InvalidConfiguration();
            for (uint256 j; j < i; ++j) {
                if (tokens[i] == tokens[j]) revert InvalidConfiguration();
            }
            uint8 d = IERC20Metadata(tokens[i]).decimals();
            address t0 = IYieldBankV3Pool(pools[i]).token0();
            address t1 = IYieldBankV3Pool(pools[i]).token1();
            if (
                d > 18 || (tokens[i] != t0 && tokens[i] != t1)
                    || IYieldBankAllocationRoute(entries[i]).inputAsset() != accountingAsset
                    || IYieldBankAllocationRoute(entries[i]).outputAsset() != tokens[i]
                    || IYieldBankAllocationRoute(exits[i]).inputAsset() != tokens[i]
                    || IYieldBankAllocationRoute(exits[i]).outputAsset() != accountingAsset
            ) revert InvalidConfiguration();
            _assets[i] =
                Asset(tokens[i], pools[i], tokens[i] == t0 ? t1 : t0, entries[i], exits[i], d);
        }
        configured = true;
    }

    function assets() external view returns (Asset[4] memory) {
        return _assets;
    }

    function unitsOf(uint256 bank) external view returns (uint256[4] memory) {
        return _units[bank];
    }

    function targetOf(uint256 bank) external view returns (Target memory) {
        return _targets[bank];
    }

    function setTarget(uint256 bank, uint16 allocationBps, uint16 lpBps, uint16[4] calldata weights)
        external
        nonReentrant
    {
        address owner = IERC721(collection.nft()).ownerOf(bank);
        if (msg.sender != owner || collection.accountOf(bank) == address(0)) revert Unauthorized();
        if (!configured || uint256(allocationBps) + lpBps > 10000) revert InvalidTarget();
        uint256 total;
        for (uint256 i; i < 4; ++i) {
            total += weights[i];
        }
        if (
            (allocationBps != 0 && total != 10000)
                || (allocationBps == 0 && total != 0 && total != 10000)
        ) revert InvalidTarget();
        uint64 nonce = _targets[bank].nonce + 1;
        _targets[bank] = Target(owner, nonce, allocationBps, lpBps, weights);
        emit CommodityTargetSet(bank, owner, nonce, allocationBps, lpBps, weights);
    }

    function inventoryAssets() external view returns (address[] memory result) {
        result = new address[](1);
        result[0] = accountingAsset;
    }

    function adapters() external view returns (address[] memory result) {
        result = new address[](portfolioAdapter == address(0) ? 0 : 1);
        if (result.length != 0) result[0] = portfolioAdapter;
    }

    function activeStrategyCount() external view returns (uint256) {
        return portfolioAdapter == address(0) ? 0 : 1;
    }

    function addAdapter(address adapter, uint16 cap) external onlyController {
        if (
            portfolioAdapter != address(0) || IStockCompositeLP(adapter).sleeve() != address(this)
                || cap == 0 || cap > maximumAdapterCapBps
        ) revert InvalidConfiguration();
        portfolioAdapter = adapter;
        adapterState[adapter] = YieldBankAdapterState.ACTIVE;
        adapterCapBps[adapter] = cap;
    }

    function setAdapterCap(address adapter, uint16 cap) external onlyController {
        if (adapter != portfolioAdapter || cap == 0 || cap > maximumAdapterCapBps) {
            revert InvalidConfiguration();
        }
        adapterCapBps[adapter] = cap;
    }

    function retireAdapter(address adapter) external onlyController {
        if (adapter != portfolioAdapter) revert InvalidConfiguration();
        depositsPaused = true;
        adapterState[adapter] = YieldBankAdapterState.EXIT_ONLY;
    }

    function setDepositsPaused(bool paused) external onlyController {
        depositsPaused = paused;
    }

    function deposit(uint256 amount, address receiver, uint256 minimumShares, bytes calldata data)
        external
        onlyAllocator
        nonReentrant
        returns (uint256 shares)
    {
        if (
            !configured || depositsPaused || amount == 0
                || adapterState[portfolioAdapter] != YieldBankAdapterState.ACTIVE
        ) revert InvalidConfiguration();
        Execution memory e = abi.decode(data, (Execution));
        Target memory t = _targets[e.bank];
        uint256 combined = uint256(t.allocationBps) + t.lpBps;
        CollectionPortfolioAllocator.AllocationTarget memory bankTarget =
            CollectionPortfolioAllocator(allocator).allocationTargetOf(e.bank);
        if (
            combined == 0 || collection.accountOf(e.bank) != receiver
                || t.owner != IERC721(collection.nft()).ownerOf(e.bank) || e.nonce != t.nonce
                || bankTarget.marketMakingWeightBps != combined || lpUnitsOf[e.bank] != 0
                || uint256(t.lpBps) * 10000 > uint256(adapterCapBps[portfolioAdapter]) * combined
        ) revert InvalidTarget();
        for (uint256 i; i < 4; ++i) {
            if (_units[e.bank][i] != 0) revert FullRebalanceRequired();
        }
        uint256 beforeWeth = IERC20(accountingAsset).balanceOf(address(this));
        IERC20(accountingAsset).safeTransferFrom(msg.sender, address(this), amount);
        if (IERC20(accountingAsset).balanceOf(address(this)) != beforeWeth + amount) {
            revert InexactTransfer();
        }
        uint256 lpAmount = Math.mulDiv(amount, t.lpBps, combined);
        uint256 commodityAmount = amount - lpAmount;
        uint256 used;
        uint256 last;
        for (uint256 i; i < 4; ++i) {
            if (t.weights[i] != 0) last = i;
        }
        bankOf[receiver] = e.bank;
        for (uint256 i; i < 4; ++i) {
            if (commodityAmount == 0 || t.weights[i] == 0) {
                if (e.minimumOutputs[i] != 0 || e.routeData[i].length != 0) {
                    revert InvalidConfiguration();
                }
                continue;
            }
            uint256 input = i == last
                ? commodityAmount - used
                : Math.mulDiv(commodityAmount, t.weights[i], 10000);
            used += input;
            uint256 units = _convert(
                accountingAsset,
                _assets[i].token,
                _assets[i].entry,
                input,
                e.minimumOutputs[i],
                e.routeData[i]
            );
            _units[e.bank][i] = units;
            totalUnits[i] += units;
        }
        if (lpAmount != 0) {
            IERC20(accountingAsset).forceApprove(portfolioAdapter, lpAmount);
            uint256 beforeLP = IERC20(IStockCompositeLP(portfolioAdapter).lpReceiptToken())
                .balanceOf(address(this));
            uint256 units = IStockCompositeLP(portfolioAdapter)
                .purchaseLP(lpAmount, e.minimumLPUnits, e.lpData);
            IERC20(accountingAsset).forceApprove(portfolioAdapter, 0);
            if (
                units == 0
                    || IERC20(IStockCompositeLP(portfolioAdapter).lpReceiptToken())
                            .balanceOf(address(this)) != beforeLP + units
            ) revert InexactTransfer();
            lpUnitsOf[e.bank] = units;
            totalLPUnits += units;
        } else if (e.minimumLPUnits != 0 || e.lpData.length != 0) {
            revert InvalidConfiguration();
        }
        if (
            IERC20(accountingAsset).balanceOf(address(this)) != beforeWeth
                || t.owner != IERC721(collection.nft()).ownerOf(e.bank)
        ) revert InexactTransfer();
        shares = balanceOf(receiver);
        if (shares == 0 || shares < minimumShares) revert InvalidConfiguration();
        emit Transfer(address(0), receiver, shares);
        emit CommodityDeposited(e.bank, amount, shares);
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
        returns (address[] memory resultAssets, uint256[] memory amounts)
    {
        uint256 bank = bankOf[owner];
        if (bank == 0 || receiver != allocator || shares == 0 || shares != balanceOf(owner)) {
            revert FullRebalanceRequired();
        }
        if (
            minimumOutputs.length != 1 || calls.length != 1 || calls[0].adapter != portfolioAdapter
                || calls[0].maxLossBps > maximumOperatorLossBps
        ) revert InvalidConfiguration();
        _spendAllowance(owner, msg.sender, shares);
        Redemption memory e = abi.decode(calls[0].data, (Redemption));
        uint256 beforeWeth = IERC20(accountingAsset).balanceOf(address(this));
        for (uint256 i; i < 4; ++i) {
            uint256 units = _units[bank][i];
            if (units == 0) {
                if (e.minimumOutputs[i] != 0 || e.routeData[i].length != 0) {
                    revert InvalidConfiguration();
                }
                continue;
            }
            delete _units[bank][i];
            totalUnits[i] -= units;
            _convert(
                _assets[i].token,
                accountingAsset,
                _assets[i].exit,
                units,
                e.minimumOutputs[i],
                e.routeData[i]
            );
        }
        uint256 lp = lpUnitsOf[bank];
        if (lp != 0) {
            delete lpUnitsOf[bank];
            totalLPUnits -= lp;
            IERC20(IStockCompositeLP(portfolioAdapter).lpReceiptToken())
                .forceApprove(portfolioAdapter, lp);
            IStockCompositeLP(portfolioAdapter)
                .redeemLP(lp, e.minimumLPWeth, calls[0].maxLossBps, e.lpData);
            IERC20(IStockCompositeLP(portfolioAdapter).lpReceiptToken())
                .forceApprove(portfolioAdapter, 0);
        } else if (e.minimumLPWeth != 0 || e.lpData.length != 0) {
            revert InvalidConfiguration();
        }
        uint256 returned = IERC20(accountingAsset).balanceOf(address(this)) - beforeWeth;
        if (returned == 0 || returned < minimumOutputs[0]) revert InexactTransfer();
        IERC20(accountingAsset).safeTransfer(receiver, returned);
        resultAssets = new address[](1);
        amounts = new uint256[](1);
        resultAssets[0] = accountingAsset;
        amounts[0] = returned;
        emit Transfer(owner, address(0), shares);
        emit CommodityRedeemed(bank, returned, shares);
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

    /// @notice Current pool mark for accounting; not a second swap-price constraint.
    function assetPriceUsd18(uint256 index) public view returns (uint256 price, uint48 at) {
        Asset memory a = _assets[index];
        (uint160 sqrtPrice,,,,,,) = IYieldBankV3Pool(a.pool).slot0();
        uint256 ratioX128 = Math.mulDiv(sqrtPrice, sqrtPrice, 1 << 64);
        if (ratioX128 == 0) revert PriceUnavailable();
        uint256 quoteUnits = IYieldBankV3Pool(a.pool).token0() == a.token
            ? Math.mulDiv(10 ** a.decimals, ratioX128, 1 << 128)
            : Math.mulDiv(10 ** a.decimals, 1 << 128, ratioX128);
        (uint256 quotePrice, uint48 pricedAt, IPriceHub.FailureReason failure) =
            IPriceHub(priceHub).quoteUsd18(a.quoteAsset);
        if (failure != IPriceHub.FailureReason.NONE || quotePrice == 0) revert PriceUnavailable();
        return (
            Math.mulDiv(quoteUnits, quotePrice, 10 ** IERC20Metadata(a.quoteAsset).decimals()),
            pricedAt
        );
    }

    function bankValues(uint256 bank)
        public
        view
        returns (uint256 commoditiesUsd18, uint256 lpUsd18)
    {
        commoditiesUsd18 = _commodityValue36(_units[bank]) / 1 ether;
        if (lpUnitsOf[bank] != 0) {
            (uint256 price,) = IStockCompositeLP(portfolioAdapter).lpUnitPriceUsd18();
            lpUsd18 = Math.mulDiv(lpUnitsOf[bank], price, 1 ether);
        }
    }

    function totalAssetsUsd18() external view returns (uint256 value, uint48 pricedAt) {
        return (_totalValue36() / 1 ether, uint48(block.timestamp));
    }

    function _accountValue36(address account) internal view override returns (uint256 value) {
        uint256 bank = bankOf[account];
        if (bank == 0) return 0;
        value = _commodityValue36(_units[bank]);
        if (lpUnitsOf[bank] != 0) {
            (uint256 price,) = IStockCompositeLP(portfolioAdapter).lpUnitPriceUsd18();
            value += lpUnitsOf[bank] * price;
        }
    }

    function _totalValue36() internal view override returns (uint256 value) {
        value = _commodityValue36(totalUnits);
        if (totalLPUnits != 0) {
            (uint256 price,) = IStockCompositeLP(portfolioAdapter).lpUnitPriceUsd18();
            value += totalLPUnits * price;
        }
    }

    function _commodityValue36(uint256[4] memory units) private view returns (uint256 value) {
        for (uint256 i; i < 4; ++i) {
            if (units[i] != 0) {
                (uint256 price,) = assetPriceUsd18(i);
                value += units[i] * (10 ** (18 - _assets[i].decimals)) * price;
            }
        }
    }

    function _convert(
        address input,
        address output,
        address route,
        uint256 amount,
        uint256 minimum,
        bytes memory data
    ) private returns (uint256 received) {
        if (amount == 0 || minimum == 0) revert InvalidConfiguration();
        uint256 beforeInput = IERC20(input).balanceOf(address(this));
        uint256 beforeOutput = IERC20(output).balanceOf(address(this));
        IERC20(input).forceApprove(route, amount);
        IYieldBankAllocationRoute(route).convert(amount, minimum, address(this), data);
        IERC20(input).forceApprove(route, 0);
        received = IERC20(output).balanceOf(address(this)) - beforeOutput;
        if (IERC20(input).balanceOf(address(this)) != beforeInput - amount || received < minimum) {
            revert InexactTransfer();
        }
    }
}
