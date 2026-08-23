// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { FundingBandConfig, FundingBandDestination } from "../src/bands/FundingBandTypes.sol";
import { ProjectFundingBandsV2 } from "../src/bands/ProjectFundingBandsV2.sol";
import { MockRegistry } from "./mocks/MockRegistry.sol";
import { MockProjectToken } from "./mocks/MockProjectToken.sol";
import { MockProjectController } from "./mocks/MockTreasuryIntegrations.sol";
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
        guard = new MockFundingBandGuard(address(subject), address(pool), referenceSupply);
        positionAdapter =
            new MockFundingBandPositionAdapter(address(subject), address(quote), address(pool));

        address predictedBands = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        guard.bind(predictedBands);
        positionAdapter.bind(predictedBands);
        bytes32 root = _integrationLeaf(predictedBands);
        bands = new ProjectFundingBandsV2(
            address(registry),
            address(subject),
            CREATOR,
            address(projectController),
            address(treasury),
            address(router),
            address(airdrop),
            address(raffle),
            FEE_RECIPIENT,
            address(pool),
            address(quote),
            referenceSupply,
            root,
            address(guard),
            address(positionAdapter),
            15 minutes,
            5 minutes,
            new bytes32[](0)
        );
        assertEq(address(bands), predictedBands);
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
                keccak256("SINJOH_V2_FUNDING_BAND_INTEGRATION"),
                block.chainid,
                address(pool).codehash,
                address(quote),
                referenceSupply,
                address(guard).codehash,
                address(positionAdapter).codehash,
                address(positionAdapter).codehash
            )
        );
        return keccak256(bytes.concat(inner));
    }
}
