// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import {
    BasketAllocationConfig,
    BasketBurnTaxDestination,
    BasketConfig,
    BasketEligibilityMode,
    BasketHarvestCadence,
    BasketSwapLeg,
    BasketTarget
} from "../../src/basket/BasketTypes.sol";
import { BasketVaultV2 } from "../../src/basket/BasketVaultV2.sol";
import {
    MockProjectPriceGuard,
    MockProjectSwapAdapter
} from "../mocks/MockTreasuryIntegrations.sol";
import { MockBasketAsset, MockBasketYieldAdapter } from "../mocks/MockBasketIntegrations.sol";

contract BasketVaultV2FuzzTest is Test {
    bytes32 private constant PROJECT_ID = keccak256("basket-fuzz-project");
    bytes private constant ROUTE = hex"beef";

    MockBasketAsset private assetA;
    MockBasketAsset private assetB;
    MockBasketYieldAdapter private adapterA;
    MockBasketYieldAdapter private adapterB;
    MockProjectSwapAdapter private swapAdapter;
    MockProjectPriceGuard private guard;
    BasketVaultV2 private vault;

    function setUp() public {
        assetA = new MockBasketAsset("Asset A", "A");
        assetB = new MockBasketAsset("Asset B", "B");
        address[] memory outputA = new address[](1);
        outputA[0] = address(assetA);
        address[] memory outputB = new address[](1);
        outputB[0] = address(assetB);
        adapterA = new MockBasketYieldAdapter(address(assetA), outputA);
        adapterB = new MockBasketYieldAdapter(address(assetB), outputB);
        swapAdapter = new MockProjectSwapAdapter();
        guard = new MockProjectPriceGuard();

        BasketVaultV2 implementation = new BasketVaultV2();
        bytes32 salt = keccak256("basket-fuzz-vault");
        address predicted = Clones.predictDeterministicAddress(address(implementation), salt);
        adapterA.bind(predicted);
        adapterB.bind(predicted);
        vault = BasketVaultV2(payable(Clones.cloneDeterministic(address(implementation), salt)));

        bytes32 leafA = _yieldLeaf(address(adapterA), address(assetA));
        bytes32 leafB = _yieldLeaf(address(adapterB), address(assetB));
        bytes32 swapLeaf = _swapLeaf();
        bytes32 pair = _hashPair(leafA, leafB);
        bytes32 root = _hashPair(pair, swapLeaf);

        BasketAllocationConfig memory allocation;
        allocation.inputAssets = new address[](1);
        allocation.inputAssets[0] = address(assetA);
        allocation.targets = new BasketTarget[](2);
        bytes32[] memory proofA = new bytes32[](2);
        proofA[0] = leafB;
        proofA[1] = swapLeaf;
        allocation.targets[0] = BasketTarget({
            depositAsset: address(assetA),
            yieldAdapter: address(adapterA),
            targetWeightBps: 3_000,
            rewardAssets: new address[](0),
            yieldApprovalProof: proofA
        });
        bytes32[] memory proofB = new bytes32[](2);
        proofB[0] = leafA;
        proofB[1] = swapLeaf;
        allocation.targets[1] = BasketTarget({
            depositAsset: address(assetB),
            yieldAdapter: address(adapterB),
            targetWeightBps: 7_000,
            rewardAssets: new address[](0),
            yieldApprovalProof: proofB
        });
        allocation.swapLegs = new BasketSwapLeg[](1);
        bytes32[] memory swapProof = new bytes32[](1);
        swapProof[0] = pair;
        allocation.swapLegs[0] = BasketSwapLeg({
            inputAsset: address(assetA),
            targetIndex: 1,
            swapAdapter: address(swapAdapter),
            priceGuard: address(guard),
            maxSlippageBps: 100,
            routeData: ROUTE,
            approvalProof: swapProof
        });
        BasketConfig memory config = BasketConfig({
            cadence: BasketHarvestCadence.ONE_DAY,
            eligibilityMode: BasketEligibilityMode.HOLDERS,
            governanceUpdatesEnabled: false,
            burnTaxBps: 0,
            burnTaxDestination: BasketBurnTaxDestination.CREATOR,
            burnPriceSubject: 0,
            airdropAccountConfig: hex"01",
            allocation: allocation
        });
        vault.initialize(
            address(this),
            address(1),
            address(2),
            PROJECT_ID,
            1,
            address(3),
            address(4),
            address(0),
            address(5),
            root,
            config
        );
        vault.validateConfiguration();
        vault.activate();
    }

    function testFuzzAllocationPreservesExactCumulativeWeights(uint128 rawAmount) public {
        uint256 amount = bound(uint256(rawAmount), 4, 1e28);
        _fund(amount);
        uint256 expectedA = amount * 3_000 / 10_000;
        uint256 expectedB = amount - expectedA;
        _assertPositions(expectedA, expectedB);
    }

    function testFuzzSplitFundingEqualsSingleCumulativeAllocation(uint96 rawA, uint96 rawB) public {
        uint256 amountA = bound(uint256(rawA), 4, 1e24);
        uint256 amountB = bound(uint256(rawB), 4, 1e24);
        _fund(amountA);
        _fund(amountB);
        uint256 total = amountA + amountB;
        uint256 expectedA = total * 3_000 / 10_000;
        uint256 expectedB = total - expectedA;
        _assertPositions(expectedA, expectedB);
    }

    function testFuzzRealizedLossIsReportedAndNeverConvertedToYield(
        uint128 rawAmount,
        uint128 rawLoss
    ) public {
        uint256 amount = bound(uint256(rawAmount), 4, 1e28);
        _fund(amount);
        (,,, uint256 principal,,,,,) = vault.targetStatus(0);
        uint256 loss = bound(uint256(rawLoss), 1, principal);
        adapterA.realizeLoss(loss);

        (,,,, uint256 positionValue, uint256 gain, uint256 unrealizedLoss,,) = vault.targetStatus(0);
        assertEq(positionValue, principal - loss);
        assertEq(gain, 0);
        assertEq(unrealizedLoss, loss);
    }

    function testFuzzPriceGuardMinimumCannotBeWeakened(uint128 rawAmount) public {
        uint256 amount = bound(uint256(rawAmount), 4, 1e28);
        uint256 desiredB = amount - amount * 3_000 / 10_000;
        assetB.mint(address(swapAdapter), desiredB);
        swapAdapter.configure(desiredB - 1, type(uint256).max, false);
        guard.setQuote(desiredB, uint48(block.timestamp + 1 days));
        assetA.mint(address(this), amount);
        assetA.approve(address(vault), amount);

        vm.expectRevert(
            abi.encodeWithSelector(
                BasketVaultV2.InsufficientSwapOutput.selector, desiredB, desiredB - 1
            )
        );
        vault.allocateFunding(address(assetA), amount);
        assertEq(vault.totalFunded(address(assetA)), 0);
    }

    function testFuzzBurnReturnsAllRemainingPrincipalToOwner(uint128 rawAmount) public {
        uint256 amount = bound(uint256(rawAmount), 4, 1e28);
        address owner = address(0xA11CE);
        _fund(amount);

        vault.beginBurn();
        vault.processBurnTarget(0);
        vault.processBurnTarget(1);
        vault.finalizeRedemption(owner);

        assertEq(assetA.balanceOf(owner) + assetB.balanceOf(owner), amount);
        assertEq(assetA.balanceOf(address(vault)) + assetB.balanceOf(address(vault)), 0);
    }

    function _fund(uint256 amount) private {
        uint256 cumulativeAfter = vault.totalFunded(address(assetA)) + amount;
        uint256 desiredB = cumulativeAfter - cumulativeAfter * 3_000 / 10_000;
        (,,, uint256 existingB,,,,,) = vault.targetStatus(1);
        uint256 swapAmount = desiredB - existingB;
        assetB.mint(address(swapAdapter), swapAmount);
        swapAdapter.configure(swapAmount, type(uint256).max, false);
        guard.setQuote(swapAmount, uint48(block.timestamp + 1 days));
        assetA.mint(address(this), amount);
        assetA.approve(address(vault), amount);
        assertEq(vault.allocateFunding(address(assetA), amount), amount);
    }

    function _assertPositions(uint256 expectedA, uint256 expectedB) private view {
        (,,, uint256 principalA, uint256 positionA,,,,) = vault.targetStatus(0);
        (,,, uint256 principalB, uint256 positionB,,,,) = vault.targetStatus(1);
        assertEq(principalA, expectedA);
        assertEq(positionA, expectedA);
        assertEq(principalB, expectedB);
        assertEq(positionB, expectedB);
        assertEq(assetA.balanceOf(address(vault)), 0);
        assertEq(assetB.balanceOf(address(vault)), 0);
    }

    function _yieldLeaf(address adapter, address depositAsset) private view returns (bytes32) {
        bytes32 inner = keccak256(
            abi.encode(
                keccak256("SINJOH_V2_BASKET_YIELD_APPROVAL"),
                block.chainid,
                adapter.codehash,
                depositAsset,
                adapter
            )
        );
        return keccak256(bytes.concat(inner));
    }

    function _swapLeaf() private view returns (bytes32) {
        bytes32 inner = keccak256(
            abi.encode(
                keccak256("SINJOH_V2_BASKET_SWAP_APPROVAL"),
                block.chainid,
                address(assetA),
                address(assetB),
                address(swapAdapter).codehash,
                address(guard),
                uint16(100),
                keccak256(ROUTE)
            )
        );
        return keccak256(bytes.concat(inner));
    }

    function _hashPair(bytes32 a, bytes32 b) private pure returns (bytes32) {
        return a < b ? keccak256(bytes.concat(a, b)) : keccak256(bytes.concat(b, a));
    }
}
