// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { StdInvariant } from "forge-std/StdInvariant.sol";
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
    MockBasketAsset,
    MockBasketModule,
    MockBasketYieldAdapter
} from "../mocks/MockBasketIntegrations.sol";

contract BasketVaultV2Handler is Test {
    MockBasketAsset public immutable asset;
    MockBasketYieldAdapter public immutable adapter;
    BasketVaultV2 public vault;
    uint256 public totalYieldAdded;

    constructor(MockBasketAsset asset_, MockBasketYieldAdapter adapter_) {
        asset = asset_;
        adapter = adapter_;
    }

    function configure(BasketVaultV2 vault_) external {
        require(address(vault) == address(0), "configured");
        vault = vault_;
        vault.activate();
    }

    function fund(uint128 rawAmount) external {
        uint256 amount = bound(uint256(rawAmount), 1, 1e24);
        asset.mint(address(this), amount);
        asset.approve(address(vault), amount);
        vault.allocateFunding(address(asset), amount);
    }

    function addYield(uint128 rawAmount) external {
        uint256 amount = bound(uint256(rawAmount), 1, 1e24);
        asset.mint(address(this), amount);
        asset.approve(address(adapter), amount);
        adapter.addYield(address(asset), amount);
        totalYieldAdded += amount;
    }

    function advanceAndHarvest(uint32 rawDelay) external {
        uint256 delay = bound(uint256(rawDelay), 1 days, 30 days);
        vm.warp(block.timestamp + delay);
        vault.harvest();
    }
}

contract BasketVaultV2InvariantTest is StdInvariant, Test {
    bytes32 private constant PROJECT_ID = keccak256("basket-invariant-project");

    MockBasketAsset private asset;
    MockBasketYieldAdapter private adapter;
    MockBasketModule private airdrop;
    BasketVaultV2 private vault;
    BasketVaultV2Handler private handler;

    function setUp() public {
        asset = new MockBasketAsset("Invariant Asset", "INV");
        address[] memory outputs = new address[](1);
        outputs[0] = address(asset);
        adapter = new MockBasketYieldAdapter(address(asset), outputs);
        airdrop = new MockBasketModule(address(1), address(2), PROJECT_ID, 0, address(2));
        handler = new BasketVaultV2Handler(asset, adapter);

        BasketVaultV2 implementation = new BasketVaultV2();
        bytes32 salt = keccak256("basket-invariant-vault");
        address predicted = Clones.predictDeterministicAddress(address(implementation), salt);
        adapter.bind(predicted);
        vault = BasketVaultV2(payable(Clones.cloneDeterministic(address(implementation), salt)));
        bytes32 root = _yieldLeaf();
        BasketAllocationConfig memory allocation;
        allocation.inputAssets = new address[](1);
        allocation.inputAssets[0] = address(asset);
        allocation.targets = new BasketTarget[](1);
        allocation.targets[0] = BasketTarget({
            depositAsset: address(asset),
            yieldAdapter: address(adapter),
            targetWeightBps: 10_000,
            rewardAssets: new address[](0),
            yieldApprovalProof: new bytes32[](0)
        });
        allocation.swapLegs = new BasketSwapLeg[](0);
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
            address(handler),
            address(1),
            address(2),
            PROJECT_ID,
            1,
            address(3),
            address(4),
            address(0),
            address(airdrop),
            root,
            config
        );
        vault.validateConfiguration();
        handler.configure(vault);
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = handler.fund.selector;
        selectors[1] = handler.addYield.selector;
        selectors[2] = handler.advanceAndHarvest.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({ addr: address(handler), selectors: selectors }));
    }

    function invariantPrincipalAlwaysEqualsCumulativeFunding() public view {
        (,,, uint256 principal,,,,,) = vault.targetStatus(0);
        assertEq(principal, vault.totalFunded(address(asset)));
    }

    function invariantPositionNeverFallsBelowLockedPrincipal() public view {
        (,,, uint256 principal, uint256 position,,,,) = vault.targetStatus(0);
        assertGe(position, principal);
    }

    function invariantOnlyRealizedYieldCanReachAirdrop() public view {
        assertLe(airdrop.funded(address(asset)), handler.totalYieldAdded());
    }

    function invariantAllAddedYieldIsExactlyReconciled() public view {
        (,,, uint256 principal, uint256 position,,,,) = vault.targetStatus(0);
        uint256 unharvested = position - principal;
        assertEq(
            handler.totalYieldAdded(),
            unharvested + vault.pendingDividend(address(asset)) + airdrop.funded(address(asset))
        );
    }

    function _yieldLeaf() private view returns (bytes32) {
        bytes32 inner = keccak256(
            abi.encode(
                keccak256("SINJOH_V2_BASKET_YIELD_APPROVAL"),
                block.chainid,
                address(adapter).codehash,
                address(asset),
                address(adapter)
            )
        );
        return keccak256(bytes.concat(inner));
    }
}
