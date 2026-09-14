// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { MarketMakingSleeve } from "../sleeves/MarketMakingSleeve.sol";
import { DeltaV3LPAdapter } from "../adapters/DeltaV3LPAdapter.sol";
import { IPriceHub } from "../interfaces/IPriceHub.sol";
import { IYieldBankAllocationRoute } from "../interfaces/IYieldBankAllocationRoute.sol";
import { YieldBankAdapterRedemptionCall } from "../interfaces/IYieldBankManagedSleeve.sol";
import { IntegrationBinding } from "../libraries/IntegrationBinding.sol";
import {
    IYieldBankV3Pool,
    IYieldBankV3Factory,
    IYieldBankV3PositionManager
} from "../interfaces/IYieldBankV3.sol";
import { IDeltaPositionBuilder } from "../interfaces/IDeltaPositionBuilder.sol";
import { IStockCompositeAllocator } from "./StockCompositeSleeve.sol";

interface ICompositeSleeveIdentity {
    function allocator() external view returns (address);
    function accountingAsset() external view returns (address);
}

/// @notice LP leg of a bank-isolated composite portfolio, using the existing Delta LP code.
/// @dev `pool` is the infrastructure registration/settlement pool. `lpPool()` is the actual
/// invested LP pool; the release and UI must expose this distinction. This separation allows
/// an independently approved infrastructure generation without disabling older foundations.
/// A real, source-verified settlement pool is mandatory; fabricated pool identities are not valid.
contract StockCompositeLPAdapter is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ABI layout deliberately matches DeltaPoolController.AdapterDeploymentConfig.
    struct Config {
        address sleeve;
        address weth;
        address pairedAsset;
        address priceHub;
        address pool;
        address positionManager;
        address positionBuilder;
        address entryRoute;
        address exitRoute;
        bytes32 poolCodeHash;
        bytes32 factoryCodeHash;
        bytes32 positionManagerCodeHash;
        bytes32 positionBuilderCodeHash;
        bytes32 entryRouteCodeHash;
        bytes32 exitRouteCodeHash;
        uint8 maximumPositions;
    }

    struct LPDeposit {
        uint256 assetsToDeploy;
        uint256 minimumPositionUnits;
        bytes adapterData;
    }

    struct LPRedemption {
        uint256[] minimumOutputs;
        YieldBankAdapterRedemptionCall[] adapterCalls;
        uint256 minimumConvertedWeth;
        bytes routeData;
    }

    address public immutable sleeve;
    address public immutable weth;
    address public immutable accountingAsset;
    address public immutable pairedAsset;
    address public immutable priceHub;
    address public immutable pool;
    address public immutable factory;
    address public immutable positionManager;
    address public immutable positionBuilder;
    address public immutable governance;
    MarketMakingSleeve public lpVault;
    address public lpAdapter;
    address public lpExitRoute;
    address public lpPairedAsset;
    bytes32 public lpVaultCodeHash;
    bytes32 public lpExitCodeHash;

    error Unauthorized();
    error InvalidConfiguration();
    error InexactTransfer();
    error OracleUnavailable();
    error UnsupportedOperation();

    event LPVaultConfigured(
        address indexed vault,
        address indexed adapter,
        address indexed investedPool,
        address exitRoute
    );

    constructor(Config memory c) {
        if (
            c.sleeve.code.length == 0 || c.weth.code.length == 0 || c.pairedAsset.code.length == 0
                || c.priceHub.code.length == 0 || c.maximumPositions == 0
        ) revert InvalidConfiguration();
        IntegrationBinding.requireBound(c.pool, c.poolCodeHash);
        IntegrationBinding.requireBound(c.positionManager, c.positionManagerCodeHash);
        IntegrationBinding.requireBound(c.positionBuilder, c.positionBuilderCodeHash);
        IntegrationBinding.requireBound(c.entryRoute, c.entryRouteCodeHash);
        IntegrationBinding.requireBound(c.exitRoute, c.exitRouteCodeHash);
        address factory_ = IYieldBankV3Pool(c.pool).factory();
        IntegrationBinding.requireBound(factory_, c.factoryCodeHash);
        address token0 = IYieldBankV3Pool(c.pool).token0();
        address token1 = IYieldBankV3Pool(c.pool).token1();
        if (
            !((token0 == c.weth && token1 == c.pairedAsset)
                    || (token1 == c.weth && token0 == c.pairedAsset))
                || IYieldBankV3Factory(factory_)
                        .getPool(token0, token1, IYieldBankV3Pool(c.pool).fee()) != c.pool
                || IYieldBankV3PositionManager(c.positionManager).factory() != factory_
                || IYieldBankV3PositionManager(c.positionManager).WETH9() != c.weth
                || IDeltaPositionBuilder(c.positionBuilder).uniFactory() != factory_
                || IDeltaPositionBuilder(c.positionBuilder).positionManager() != c.positionManager
                || IDeltaPositionBuilder(c.positionBuilder).weth() != c.weth
                || ICompositeSleeveIdentity(c.sleeve).accountingAsset() != c.weth
        ) revert InvalidConfiguration();
        sleeve = c.sleeve;
        weth = c.weth;
        accountingAsset = c.weth;
        pairedAsset = c.pairedAsset;
        priceHub = c.priceHub;
        pool = c.pool;
        factory = factory_;
        positionManager = c.positionManager;
        positionBuilder = c.positionBuilder;
        governance =
            IStockCompositeAllocator(ICompositeSleeveIdentity(c.sleeve).allocator()).timelock();
    }
    modifier onlySleeve() {
        if (msg.sender != sleeve) revert Unauthorized();
        _;
    }

    function configureLP(address vault, address adapter, address exitRoute) external {
        if (msg.sender != governance) revert Unauthorized();
        if (
            address(lpVault) != address(0) || vault.code.length == 0 || adapter.code.length == 0
                || exitRoute.code.length == 0
        ) revert InvalidConfiguration();
        MarketMakingSleeve candidate = MarketMakingSleeve(vault);
        DeltaV3LPAdapter strategy = DeltaV3LPAdapter(adapter);
        address paired = address(strategy.pairedAsset());
        if (
            candidate.allocator() != address(this) || candidate.accountingAsset() != weth
                || address(candidate.priceHub()) != priceHub || candidate.timelock() != governance
                || candidate.decimals() != 18 || strategy.sleeve() != vault
                || strategy.accountingAsset() != weth || address(strategy.priceHub()) != priceHub
                || candidate.adapters().length != 1 || candidate.adapters()[0] != adapter
                || IYieldBankAllocationRoute(exitRoute).inputAsset() != paired
                || IYieldBankAllocationRoute(exitRoute).outputAsset() != weth
                || IERC20Metadata(paired).decimals() > 18
        ) revert InvalidConfiguration();
        lpVault = candidate;
        lpAdapter = adapter;
        lpExitRoute = exitRoute;
        lpPairedAsset = paired;
        lpVaultCodeHash = vault.codehash;
        lpExitCodeHash = exitRoute.codehash;
        emit LPVaultConfigured(vault, adapter, address(strategy.pool()), exitRoute);
    }

    function lpReceiptToken() external view returns (address) {
        return address(lpVault);
    }

    function lpPool() external view returns (address) {
        return address(DeltaV3LPAdapter(lpAdapter).pool());
    }

    function lpUnitPriceUsd18() public view returns (uint256 price, uint48 at) {
        IntegrationBinding.requireBound(address(lpVault), lpVaultCodeHash);
        uint256 supply = lpVault.totalSupply();
        if (supply == 0) return (1 ether, uint48(block.timestamp));
        (uint256 nav, uint48 pricedAt) = lpVault.totalAssetsUsd18();
        return (Math.mulDiv(nav, 1 ether, supply), pricedAt);
    }

    function positionAssets() external view returns (address[] memory assets) {
        if (address(lpVault) == address(0)) {
            assets = new address[](1);
            assets[0] = weth;
        } else {
            assets = lpVault.inventoryAssets();
        }
    }

    function totalPositionUnits() external view returns (uint256) {
        return address(lpVault) == address(0) ? 0 : lpVault.balanceOf(sleeve);
    }

    function totalManagedAssets() external view returns (uint256) {
        if (address(lpVault) == address(0) || lpVault.totalSupply() == 0) return 0;
        (uint256 price,) = lpUnitPriceUsd18();
        (uint256 wethPrice,, IPriceHub.FailureReason failure) = IPriceHub(priceHub).quoteUsd18(weth);
        if (wethPrice == 0 || failure != IPriceHub.FailureReason.NONE) revert OracleUnavailable();
        return Math.mulDiv(lpVault.balanceOf(sleeve), price, wethPrice);
    }

    function purchaseLP(uint256 assets, uint256 minimumShares, bytes calldata data)
        external
        onlySleeve
        nonReentrant
        returns (uint256 shares)
    {
        IntegrationBinding.requireBound(address(lpVault), lpVaultCodeHash);
        if (assets == 0 || minimumShares == 0) revert InvalidConfiguration();
        uint256 beforeWeth = IERC20(weth).balanceOf(address(this));
        IERC20(weth).safeTransferFrom(sleeve, address(this), assets);
        if (IERC20(weth).balanceOf(address(this)) != beforeWeth + assets) revert InexactTransfer();
        IERC20(weth).forceApprove(address(lpVault), assets);
        shares = lpVault.deposit(assets, sleeve, minimumShares, "");
        IERC20(weth).forceApprove(address(lpVault), 0);
        if (data.length != 0) {
            LPDeposit memory deployment = abi.decode(data, (LPDeposit));
            if (
                deployment.assetsToDeploy == 0 || deployment.assetsToDeploy > assets
                    || deployment.minimumPositionUnits == 0
            ) revert InvalidConfiguration();
            lpVault.depositToAdapter(
                lpAdapter,
                deployment.assetsToDeploy,
                deployment.minimumPositionUnits,
                deployment.adapterData
            );
        }
        if (IERC20(weth).balanceOf(address(this)) != beforeWeth) revert InexactTransfer();
    }

    function redeemLP(uint256 shares, uint256 minimumWeth, uint16 maxLossBps, bytes calldata data)
        external
        onlySleeve
        nonReentrant
        returns (uint256 wethOut)
    {
        IntegrationBinding.requireBound(address(lpVault), lpVaultCodeHash);
        if (shares == 0 || minimumWeth == 0 || maxLossBps > lpVault.maximumOperatorLossBps()) {
            revert InvalidConfiguration();
        }
        LPRedemption memory redemption = abi.decode(data, (LPRedemption));
        for (uint256 i; i < redemption.adapterCalls.length; ++i) {
            if (
                redemption.adapterCalls[i].adapter != lpAdapter
                    || redemption.adapterCalls[i].maxLossBps > maxLossBps
            ) revert InvalidConfiguration();
        }
        (uint256 price,) = lpUnitPriceUsd18();
        (uint256 wethPrice,, IPriceHub.FailureReason failure) = IPriceHub(priceHub).quoteUsd18(weth);
        if (wethPrice == 0 || failure != IPriceHub.FailureReason.NONE) revert OracleUnavailable();
        uint256 expectedWeth = Math.mulDiv(shares, price, wethPrice);
        minimumWeth = Math.max(
            minimumWeth, Math.mulDiv(expectedWeth, 10000 - maxLossBps, 10000, Math.Rounding.Ceil)
        );
        uint256 beforeWeth = IERC20(weth).balanceOf(address(this));
        uint256 beforePaired = IERC20(lpPairedAsset).balanceOf(address(this));
        lpVault.redeemManaged(
            shares, address(this), sleeve, redemption.minimumOutputs, redemption.adapterCalls
        );
        uint256 pairedReturned = IERC20(lpPairedAsset).balanceOf(address(this)) - beforePaired;
        if (pairedReturned != 0) {
            IntegrationBinding.requireBound(lpExitRoute, lpExitCodeHash);
            (uint256 pairedPrice,, IPriceHub.FailureReason pairedFailure) =
                IPriceHub(priceHub).quoteUsd18(lpPairedAsset);
            if (pairedPrice == 0 || pairedFailure != IPriceHub.FailureReason.NONE) {
                revert OracleUnavailable();
            }
            uint256 value = Math.mulDiv(
                pairedReturned, pairedPrice, 10 ** IERC20Metadata(lpPairedAsset).decimals()
            );
            uint256 quote = Math.mulDiv(value, 1 ether, wethPrice);
            // Actual in-kind output includes fees accrued after the owner's quote. Apply
            // the oracle floor to that exact output; a caller can only strengthen it.
            // Only the paired half needs a swap. Its route may use twice the LP loss
            // budget, while minimumWeth still enforces the original limit on the full LP.
            uint256 conversionMinimum = Math.max(
                redemption.minimumConvertedWeth,
                Math.max(
                    1,
                    Math.mulDiv(
                        quote,
                        10000 - Math.min(uint256(maxLossBps) * 2, 500),
                        10000,
                        Math.Rounding.Ceil
                    )
                )
            );
            IERC20(lpPairedAsset).forceApprove(lpExitRoute, pairedReturned);
            IYieldBankAllocationRoute(lpExitRoute)
                .convert(pairedReturned, conversionMinimum, address(this), redemption.routeData);
            IERC20(lpPairedAsset).forceApprove(lpExitRoute, 0);
        } else if (redemption.minimumConvertedWeth != 0 || redemption.routeData.length != 0) {
            revert InvalidConfiguration();
        }
        if (IERC20(lpPairedAsset).balanceOf(address(this)) != beforePaired) {
            revert InexactTransfer();
        }
        wethOut = IERC20(weth).balanceOf(address(this)) - beforeWeth;
        if (wethOut < minimumWeth) revert InexactTransfer();
        IERC20(weth).safeTransfer(sleeve, wethOut);
        if (IERC20(weth).balanceOf(address(this)) != beforeWeth) revert InexactTransfer();
    }

    /// @notice Governance can consolidate LP positions or invest accumulated idle WETH.
    /// All assets remain in the existing LP vault; bank receipt balances cannot be changed here.
    function rebalanceLP(
        uint256 withdrawAssets,
        uint16 maxLossBps,
        bytes calldata withdrawalData,
        uint256 depositAssets,
        uint256 minimumPositionUnits,
        bytes calldata depositData
    ) external nonReentrant {
        if (msg.sender != governance) revert Unauthorized();
        IntegrationBinding.requireBound(address(lpVault), lpVaultCodeHash);
        if (
            maxLossBps > lpVault.maximumOperatorLossBps()
                || (withdrawAssets == 0 && depositAssets == 0)
        ) revert InvalidConfiguration();
        (uint256 beforeValue,) = lpVault.totalAssetsUsd18();
        uint256 beforeShares = lpVault.totalSupply();
        if (withdrawAssets != 0) {
            lpVault.withdrawFromAdapter(lpAdapter, withdrawAssets, maxLossBps, withdrawalData);
        } else if (withdrawalData.length != 0) {
            revert InvalidConfiguration();
        }
        if (depositAssets != 0) {
            lpVault.depositToAdapter(lpAdapter, depositAssets, minimumPositionUnits, depositData);
        } else if (minimumPositionUnits != 0 || depositData.length != 0) {
            revert InvalidConfiguration();
        }
        (uint256 afterValue,) = lpVault.totalAssetsUsd18();
        if (
            lpVault.totalSupply() != beforeShares
                || afterValue
                    < Math.mulDiv(beforeValue, 10000 - maxLossBps, 10000, Math.Rounding.Ceil)
        ) revert InexactTransfer();
    }

    /// @notice Permissionless fee collection can only credit the LP vault.
    function collectLP(bytes calldata data) external nonReentrant {
        IntegrationBinding.requireBound(address(lpVault), lpVaultCodeHash);
        lpVault.collectAdapter(lpAdapter, data);
    }

    // Generic pooled strategy calls cannot select a bank or debit its LP receipt units.
    // The composite uses the explicitly bank-accounted purchaseLP/redeemLP interface above.
    function deposit(uint256, uint256, bytes calldata) external pure returns (uint256) {
        revert UnsupportedOperation();
    }

    function withdraw(uint256, address, uint16, bytes calldata) external pure returns (uint256) {
        revert UnsupportedOperation();
    }

    function collect(address, bytes calldata)
        external
        pure
        returns (address[] memory, uint256[] memory)
    {
        revert UnsupportedOperation();
    }

    function exitAll(address, uint16, bytes calldata)
        external
        pure
        returns (address[] memory, uint256[] memory)
    {
        revert UnsupportedOperation();
    }
}
