// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import {
    FundingBandConfig,
    FundingBandDeliveryConfig,
    FundingBandDestination,
    FundingBandState,
    FundingBandSwapConfig,
    FundingBandsDeploymentConfig,
    FundingBandsMarketConfig,
    FundingBandsProjectConfig
} from "../src/bands/FundingBandTypes.sol";
import { ProjectFundingBandsV2 } from "../src/bands/ProjectFundingBandsV2.sol";
import { MockRegistry } from "./mocks/MockRegistry.sol";
import { MockProjectToken } from "./mocks/MockProjectToken.sol";
import {
    MockProjectController,
    MockProjectPriceGuard,
    MockProjectSwapAdapter
} from "./mocks/MockTreasuryIntegrations.sol";
import { MockBasketAsset, MockBasketModule } from "./mocks/MockBasketIntegrations.sol";
import {
    MockFundingBandGuard,
    MockFundingBandPool,
    MockFundingBandPositionAdapter
} from "./mocks/MockFundingBandIntegrations.sol";

abstract contract FundingBandsTestBase is Test {
    uint128 internal constant LOWER = 1_000_000e8;
    uint128 internal constant UPPER = 2_000_000e8;
    address internal constant CREATOR = address(0xC0FFEE);
    address internal constant FEE_RECIPIENT = address(0xFEE);

    MockRegistry internal registry;
    MockProjectToken internal subject;
    MockProjectController internal projectController;
    MockBasketAsset internal quote;
    MockFundingBandPool internal pool;
    MockFundingBandGuard internal guard;
    MockFundingBandPositionAdapter internal positionAdapter;
    MockProjectSwapAdapter internal swapAdapter;
    MockProjectPriceGuard internal priceGuard;
    MockBasketModule internal treasury;
    MockBasketModule internal router;
    MockBasketModule internal airdrop;
    MockBasketModule internal raffle;
    ProjectFundingBandsV2 internal bands;
    uint256 internal referenceSupply;

    function _setUpFundingBands() internal {
        vm.warp(1_000_000);
        registry = new MockRegistry();
        subject = new MockProjectToken(address(registry), address(this), 1_000_000e18);
        referenceSupply = subject.totalSupply();
        projectController = new MockProjectController(subject.projectId());
        quote = new MockBasketAsset("Quote", "QUOTE");
        pool = new MockFundingBandPool();
        treasury = _module();
        router = _module();
        airdrop = _module();
        raffle = _module();
        guard = new MockFundingBandGuard(
            address(subject), address(quote), address(pool), referenceSupply
        );
        positionAdapter =
            new MockFundingBandPositionAdapter(address(subject), address(quote), address(pool));
        swapAdapter = new MockProjectSwapAdapter();
        priceGuard = new MockProjectPriceGuard();

        address predictedBands = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        guard.bind(predictedBands);
        positionAdapter.bind(predictedBands);
        bytes32 integrationLeaf = _integrationLeaf(predictedBands);
        bytes32 swapLeaf = _swapLeaf();
        bytes32 root = _hashPair(integrationLeaf, swapLeaf);
        bytes32[] memory integrationProof = new bytes32[](1);
        integrationProof[0] = swapLeaf;
        FundingBandsDeploymentConfig memory config = FundingBandsDeploymentConfig({
            project: _projectDeploymentConfig(),
            market: _marketDeploymentConfig(root, integrationProof)
        });
        bands = new ProjectFundingBandsV2(abi.encode(config));
        assertEq(address(bands), predictedBands);
    }

    function _projectDeploymentConfig()
        private
        view
        returns (FundingBandsProjectConfig memory config)
    {
        config.registry = address(registry);
        config.subject = address(subject);
        config.creator = CREATOR;
        config.controller = address(projectController);
        config.treasury = address(treasury);
        config.router = address(router);
        config.airdrop = address(airdrop);
        config.raffle = address(raffle);
        config.protocolFeeRecipient = FEE_RECIPIENT;
    }

    function _marketDeploymentConfig(bytes32 root, bytes32[] memory integrationProof)
        private
        view
        returns (FundingBandsMarketConfig memory config)
    {
        config.canonicalPool = address(pool);
        config.quoteAsset = address(quote);
        config.referenceSupply = referenceSupply;
        config.integrationApprovalRoot = root;
        config.marketCapGuard = address(guard);
        config.positionAdapter = address(positionAdapter);
        config.confirmationPeriod = 15 minutes;
        config.maximumObservationAge = 5 minutes;
        config.integrationApprovalProof = integrationProof;
    }

    function _config(uint128 amount, FundingBandDestination destination)
        internal
        pure
        returns (FundingBandConfig memory)
    {
        return FundingBandConfig({
            lowerMarketCapUsdE8: LOWER,
            upperMarketCapUsdE8: UPPER,
            subjectAmount: amount,
            destination: destination,
            destinationConfig: bytes("")
        });
    }

    function _setObservation(uint256 marketCap, bytes32 observationId) internal {
        guard.setObservation(
            marketCap, uint48(vm.getBlockTimestamp()), observationId, int24(100), int24(200)
        );
    }

    function _createBand(uint128 amount, FundingBandDestination destination)
        internal
        returns (uint256 bandId)
    {
        assertTrue(subject.transfer(address(bands), amount));
        _setObservation(LOWER - 1, keccak256(abi.encode("create", bands.nextBandId())));
        bytes memory result = projectController.execute(
            address(bands),
            abi.encodeCall(bands.createBand, (_config(amount, destination), bytes("")))
        );
        return abi.decode(result, (uint256));
    }

    function _destinationConfig(FundingBandDestination destination, bytes memory configData)
        internal
        pure
        returns (FundingBandConfig memory)
    {
        return FundingBandConfig({
            lowerMarketCapUsdE8: LOWER,
            upperMarketCapUsdE8: UPPER,
            subjectAmount: 100e18,
            destination: destination,
            destinationConfig: configData
        });
    }

    function _buybackConfig(FundingBandDestination destination, bytes memory fundConfig)
        internal
        view
        returns (FundingBandConfig memory)
    {
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = _integrationLeaf(address(bands));
        FundingBandSwapConfig memory conversion = FundingBandSwapConfig({
            swapAdapter: address(swapAdapter),
            priceGuard: address(priceGuard),
            routeData: hex"babe",
            guardData: bytes(""),
            approvalProof: proof
        });
        return _destinationConfig(
            destination,
            abi.encode(
                FundingBandDeliveryConfig({ fundConfig: fundConfig, conversion: conversion })
            )
        );
    }

    function _createAndSettle(FundingBandConfig memory config) internal returns (uint256 bandId) {
        assertTrue(subject.transfer(address(bands), config.subjectAmount));
        _setObservation(LOWER - 1, keccak256(abi.encode("create", bands.nextBandId())));
        bandId = abi.decode(
            projectController.execute(
                address(bands), abi.encodeCall(bands.createBand, (config, bytes("")))
            ),
            (uint256)
        );
        _setObservation(UPPER, keccak256(abi.encode("arm", bandId)));
        bands.armSettlement(bandId, "");
        vm.warp(block.timestamp + 15 minutes);
        _setObservation(UPPER + 1, keccak256(abi.encode("confirm", bandId)));
        positionAdapter.configureSettlement(10e18, 1_000e18);
        quote.mint(address(positionAdapter), 1_000e18);
        bands.settle(bandId, "");
        (ProjectFundingBandsV2.Band memory status,) = bands.bandStatus(bandId);
        assertEq(uint8(status.state), uint8(FundingBandState.DELIVERED));
    }

    function _module() private returns (MockBasketModule) {
        return new MockBasketModule(
            address(registry), address(subject), subject.projectId(), 0, address(subject)
        );
    }

    function _integrationLeaf(
        address /* predictedBands */
    )
        private
        view
        returns (bytes32)
    {
        bytes32 inner = keccak256(
            abi.encode(
                keccak256("SINJOH_V2_FUNDING_BAND_PAIR_INTEGRATION"),
                block.chainid,
                address(guard),
                address(guard).codehash,
                address(positionAdapter),
                address(positionAdapter).codehash
            )
        );
        return keccak256(bytes.concat(inner));
    }

    function _swapLeaf() private view returns (bytes32) {
        bytes32 inner = keccak256(
            abi.encode(
                keccak256("SINJOH_V2_SWAP_INTEGRATION_APPROVAL"),
                block.chainid,
                address(swapAdapter),
                address(swapAdapter).codehash,
                address(priceGuard),
                address(priceGuard).codehash
            )
        );
        return keccak256(bytes.concat(inner));
    }

    function _hashPair(bytes32 a, bytes32 b) private pure returns (bytes32) {
        return a < b ? keccak256(bytes.concat(a, b)) : keccak256(bytes.concat(b, a));
    }
}
