// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;
import { DeltaPoolController } from "../DeltaPoolController.sol";
import { StockCompositeSleeve } from "./StockCompositeSleeve.sol";
import { StockCompositeLPAdapter } from "./StockCompositeLPAdapter.sol";
import { StockDividendVault } from "./StockDividendVault.sol";

/// @notice Final assertion in the timelock's atomic Stock activation batch.
/// @dev Counterfactual CREATE addresses are committed in the governance operation. If another
/// materialization changes the controller nonce, this check reverts the entire activation,
/// including materialization. Empty-code calls to obsolete predicted addresses cannot pass.
contract StockReleaseVerifier {
    struct Activation {
        address controller;
        address registrationPool;
        address sleeve;
        address adapter;
        address vault;
        address lpVault;
        address lpAdapter;
        address originalFactory;
        address originalPool;
        bytes32 originalInfrastructureHash;
        bytes32 manifestHash;
        address[] stocks;
    }
    error ActivationMismatch();

    function verify(Activation calldata a) external view {
        if (
            a.sleeve.code.length == 0 || a.adapter.code.length == 0 || a.vault.code.length == 0
                || a.lpVault.code.length == 0 || a.lpAdapter.code.length == 0
                || a.stocks.length == 0 || a.stocks.length > 64 || a.manifestHash == bytes32(0)
        ) revert ActivationMismatch();
        DeltaPoolController controller = DeltaPoolController(a.controller);
        (address sleeve, address adapter,,,) = controller.foundationOf(a.registrationPool);
        if (
            sleeve != a.sleeve || adapter != a.adapter
                || !controller.isAllocationPool(a.registrationPool)
                || !controller.isAllocationPool(a.originalPool)
        ) revert ActivationMismatch();
        (bool ok, bytes memory original) = a.controller
            .staticcall(
                abi.encodeWithSignature("infrastructureOfFactory(address)", a.originalFactory)
            );
        if (!ok || keccak256(original) != a.originalInfrastructureHash) {
            revert ActivationMismatch();
        }
        StockCompositeSleeve composite = StockCompositeSleeve(a.sleeve);
        StockCompositeLPAdapter facade = StockCompositeLPAdapter(a.adapter);
        StockDividendVault vault = StockDividendVault(a.vault);
        if (
            composite.depositsPaused() || address(composite.stockVault()) != a.vault
                || composite.portfolioAdapter() != a.adapter || facade.sleeve() != a.sleeve
                || address(facade.lpVault()) != a.lpVault || facade.lpAdapter() != a.lpAdapter
                || facade.lpPool() != a.originalPool || vault.controller() != a.sleeve
                || vault.owner() != composite.governance()
                || vault.registry().owner() != composite.governance()
        ) revert ActivationMismatch();
        for (uint256 i; i < a.stocks.length; ++i) {
            address stock = a.stocks[i];
            vault.registry().requireCurrent(stock, true);
            (,,,, bytes32 manifest) = vault.registry().assets(stock);
            (address entry,) = composite.stockEntryRoute(stock);
            (address exit,) = composite.stockExitRoute(stock);
            (address dividend,) = vault.dividendRoutes(stock);
            if (
                manifest != a.manifestHash || entry.code.length == 0 || exit.code.length == 0
                    || dividend.code.length == 0
            ) revert ActivationMismatch();
        }
    }
}
