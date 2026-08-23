// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";
import { UniswapV3FundingBandMarketCapGuard } from "./UniswapV3FundingBandMarketCapGuard.sol";
import {
    IV3BandPositionManager,
    UniswapV3FundingBandPositionAdapter
} from "./UniswapV3FundingBandPositionAdapter.sol";

struct FundingBandV3IntegrationConfig {
    address bandsContract;
    address subject;
    address quoteAsset;
    address canonicalPool;
    uint256 referenceSupply;
    uint32 twapWindow;
    address quoteUsdOracle;
    uint256 tickReferenceQuoteUsdE8;
    uint48 maximumOracleAge;
}

/// @notice Deterministically materializes the two project-bound V3 Funding Bands integrations.
/// @dev Deployment is permissionless and idempotent; bindings have no post-construction mutator.
contract FundingBandV3IntegrationFactory {
    address public immutable v3Factory;
    address public immutable v3PositionManager;

    error InvalidInfrastructure(address candidate);
    error DeploymentMismatch(address expected, address actual);

    event FundingBandIntegrationsDeployed(
        address indexed bandsContract,
        address indexed marketCapGuard,
        address indexed positionAdapter
    );

    constructor(address v3Factory_, address v3PositionManager_) {
        if (v3Factory_.code.length == 0) revert InvalidInfrastructure(v3Factory_);
        if (
            v3PositionManager_.code.length == 0
                || IV3BandPositionManager(v3PositionManager_).factory() != v3Factory_
        ) revert InvalidInfrastructure(v3PositionManager_);
        v3Factory = v3Factory_;
        v3PositionManager = v3PositionManager_;
    }

    function deploy(FundingBandV3IntegrationConfig calldata config)
        external
        returns (address marketCapGuard, address positionAdapter)
    {
        (marketCapGuard, positionAdapter) = predict(config);
        if (marketCapGuard.code.length == 0) {
            address deployed = address(
                new UniswapV3FundingBandMarketCapGuard{ salt: _guardSalt(config.bandsContract) }(
                    config.bandsContract,
                    config.subject,
                    config.quoteAsset,
                    config.canonicalPool,
                    v3Factory,
                    config.referenceSupply,
                    config.twapWindow,
                    config.quoteUsdOracle,
                    config.tickReferenceQuoteUsdE8,
                    config.maximumOracleAge
                )
            );
            if (deployed != marketCapGuard) revert DeploymentMismatch(marketCapGuard, deployed);
        }
        _verifyGuard(marketCapGuard, config);
        if (positionAdapter.code.length == 0) {
            address deployed = address(
                new UniswapV3FundingBandPositionAdapter{ salt: _adapterSalt(config.bandsContract) }(
                    config.bandsContract,
                    config.subject,
                    config.quoteAsset,
                    config.canonicalPool,
                    v3Factory,
                    v3PositionManager
                )
            );
            if (deployed != positionAdapter) revert DeploymentMismatch(positionAdapter, deployed);
        }
        _verifyAdapter(positionAdapter, config);
        emit FundingBandIntegrationsDeployed(config.bandsContract, marketCapGuard, positionAdapter);
    }

    function predict(FundingBandV3IntegrationConfig calldata config)
        public
        view
        returns (address marketCapGuard, address positionAdapter)
    {
        bytes32 guardCodeHash = keccak256(
            bytes.concat(
                type(UniswapV3FundingBandMarketCapGuard).creationCode,
                abi.encode(
                    config.bandsContract,
                    config.subject,
                    config.quoteAsset,
                    config.canonicalPool,
                    v3Factory,
                    config.referenceSupply,
                    config.twapWindow,
                    config.quoteUsdOracle,
                    config.tickReferenceQuoteUsdE8,
                    config.maximumOracleAge
                )
            )
        );
        bytes32 adapterCodeHash = keccak256(
            bytes.concat(
                type(UniswapV3FundingBandPositionAdapter).creationCode,
                abi.encode(
                    config.bandsContract,
                    config.subject,
                    config.quoteAsset,
                    config.canonicalPool,
                    v3Factory,
                    v3PositionManager
                )
            )
        );
        marketCapGuard =
            Create2.computeAddress(_guardSalt(config.bandsContract), guardCodeHash, address(this));
        positionAdapter = Create2.computeAddress(
            _adapterSalt(config.bandsContract), adapterCodeHash, address(this)
        );
    }

    function _guardSalt(address bandsContract) private pure returns (bytes32) {
        return keccak256(abi.encode("SINJOH_V2_FUNDING_BAND_GUARD", bandsContract));
    }

    function _adapterSalt(address bandsContract) private pure returns (bytes32) {
        return keccak256(abi.encode("SINJOH_V2_FUNDING_BAND_ADAPTER", bandsContract));
    }

    function _verifyGuard(address guard, FundingBandV3IntegrationConfig calldata config)
        private
        view
    {
        UniswapV3FundingBandMarketCapGuard candidate = UniswapV3FundingBandMarketCapGuard(guard);
        if (
            candidate.bandsContract() != config.bandsContract
                || candidate.subject() != config.subject
                || candidate.quoteAsset() != config.quoteAsset
                || candidate.canonicalPool() != config.canonicalPool
                || candidate.referenceSupply() != config.referenceSupply
                || candidate.minimumTwapWindow() != config.twapWindow
                || candidate.quoteUsdOracle() != config.quoteUsdOracle
                || candidate.tickReferenceQuoteUsdE8() != config.tickReferenceQuoteUsdE8
                || candidate.maximumOracleAge() != config.maximumOracleAge
        ) revert DeploymentMismatch(guard, address(0));
    }

    function _verifyAdapter(address adapter, FundingBandV3IntegrationConfig calldata config)
        private
        view
    {
        UniswapV3FundingBandPositionAdapter candidate = UniswapV3FundingBandPositionAdapter(adapter);
        if (
            candidate.bandsContract() != config.bandsContract
                || candidate.subject() != config.subject
                || candidate.quoteAsset() != config.quoteAsset
                || candidate.canonicalPool() != config.canonicalPool
                || candidate.factory() != v3Factory
                || candidate.positionManager() != v3PositionManager
        ) revert DeploymentMismatch(adapter, address(0));
    }
}
