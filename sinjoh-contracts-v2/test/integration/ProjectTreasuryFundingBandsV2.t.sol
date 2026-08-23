// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import {
    FundingBandConfig,
    FundingBandDestination,
    FundingBandState,
    FundingBandsDeploymentConfig,
    FundingBandsMarketConfig,
    FundingBandsProjectConfig
} from "../../src/bands/FundingBandTypes.sol";
import { ProjectFundingBandsV2 } from "../../src/bands/ProjectFundingBandsV2.sol";
import { ProjectTreasuryVaultV2 } from "../../src/treasury/ProjectTreasuryVaultV2.sol";
import { ProjectVotesToken } from "../../src/token/ProjectVotesToken.sol";
import { MockRegistry } from "../mocks/MockRegistry.sol";
import { MockProjectController } from "../mocks/MockTreasuryIntegrations.sol";
import {
    MockFundingBandGuard,
    MockFundingBandPool,
    MockFundingBandPositionAdapter
} from "../mocks/MockFundingBandIntegrations.sol";
import { MockBasketAsset } from "../mocks/MockBasketIntegrations.sol";

contract ProjectTreasuryFundingBandsV2IntegrationTest is Test {
    uint128 private constant LOWER = 1_000_000e8;
    uint128 private constant UPPER = 2_000_000e8;
    uint128 private constant INVENTORY = 100e18;
    address private constant CREATOR = address(0xC0FFEE);

    function testControllerAtomicallyFundsAndCreatesBandFromRealTreasury() public {
        MockRegistry registry = new MockRegistry();
        ProjectVotesToken.TokenAllocation[] memory allocations =
            new ProjectVotesToken.TokenAllocation[](1);
        allocations[0] =
            ProjectVotesToken.TokenAllocation({ recipient: address(this), amount: 1_000_000e18 });
        ProjectVotesToken subject = new ProjectVotesToken(
            "Project Token", "PROJECT", address(registry), CREATOR, allocations, new address[](0)
        );
        MockProjectController controller = new MockProjectController(subject.projectId());
        ProjectTreasuryVaultV2 treasury = new ProjectTreasuryVaultV2(
            address(registry),
            address(subject),
            CREATOR,
            address(controller),
            bytes32(0),
            address(0)
        );
        subject.approve(address(treasury), INVENTORY);
        treasury.deposit(address(subject), INVENTORY, false);

        MockBasketAsset quote = new MockBasketAsset("Quote", "QUOTE");
        MockFundingBandPool pool = new MockFundingBandPool();
        MockFundingBandGuard guard =
            new MockFundingBandGuard(address(subject), address(pool), subject.totalSupply());
        MockFundingBandPositionAdapter adapter =
            new MockFundingBandPositionAdapter(address(subject), address(quote), address(pool));
        address predictedBands = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        guard.bind(predictedBands);
        adapter.bind(predictedBands);
        bytes32 approvalRoot =
            _integrationLeaf(predictedBands, subject, quote, pool, guard, adapter);
        ProjectFundingBandsV2 bands = new ProjectFundingBandsV2(
            abi.encode(
                FundingBandsDeploymentConfig({
                    project: FundingBandsProjectConfig({
                        registry: address(registry),
                        subject: address(subject),
                        creator: CREATOR,
                        controller: address(controller),
                        treasury: address(treasury),
                        router: address(0),
                        airdrop: address(0),
                        raffle: address(0),
                        protocolFeeRecipient: address(0xFEE)
                    }),
                    market: FundingBandsMarketConfig({
                        canonicalPool: address(pool),
                        quoteAsset: address(quote),
                        referenceSupply: subject.totalSupply(),
                        integrationApprovalRoot: approvalRoot,
                        marketCapGuard: address(guard),
                        positionAdapter: address(adapter),
                        v3IntegrationFactory: address(0),
                        twapWindow: 0,
                        quoteUsdOracle: address(0),
                        tickReferenceQuoteUsdE8: 0,
                        confirmationPeriod: 15 minutes,
                        maximumObservationAge: 5 minutes,
                        integrationApprovalProof: new bytes32[](0)
                    })
                })
            )
        );
        assertEq(address(bands), predictedBands);
        guard.setObservation(
            LOWER - 1, uint48(block.timestamp), keccak256("create"), int24(100), int24(200)
        );
        FundingBandConfig memory config = FundingBandConfig({
            lowerMarketCapUsdE8: LOWER,
            upperMarketCapUsdE8: UPPER,
            subjectAmount: INVENTORY,
            destination: FundingBandDestination.CREATOR,
            destinationConfig: bytes("")
        });
        address[] memory targets = new address[](2);
        bytes[] memory calls = new bytes[](2);
        targets[0] = address(treasury);
        targets[1] = address(bands);
        calls[0] = abi.encodeCall(treasury.send, (address(subject), INVENTORY, address(bands)));
        calls[1] = abi.encodeCall(bands.createBand, (config, bytes("")));

        bytes[] memory results = controller.executeBatch(targets, calls);
        assertEq(abi.decode(results[1], (uint256)), 1);
        (ProjectFundingBandsV2.Band memory active,) = bands.bandStatus(1);
        assertEq(uint8(active.state), uint8(FundingBandState.ACTIVE));
        assertEq(active.committedSubject, INVENTORY);
        assertEq(treasury.accountedBalance(address(subject)), 0);
        assertEq(subject.balanceOf(address(treasury)), 0);
        assertEq(subject.balanceOf(address(adapter)), INVENTORY);
    }

    function _integrationLeaf(
        address, /* bands */
        ProjectVotesToken, /* subject */
        MockBasketAsset quote,
        MockFundingBandPool pool,
        MockFundingBandGuard guard,
        MockFundingBandPositionAdapter adapter
    ) private view returns (bytes32) {
        bytes32 inner = keccak256(
            abi.encode(
                keccak256("SINJOH_V2_FUNDING_BAND_INTEGRATION"),
                block.chainid,
                address(pool).codehash,
                address(quote),
                address(guard).codehash,
                address(adapter).codehash,
                address(adapter).codehash
            )
        );
        return keccak256(bytes.concat(inner));
    }
}
