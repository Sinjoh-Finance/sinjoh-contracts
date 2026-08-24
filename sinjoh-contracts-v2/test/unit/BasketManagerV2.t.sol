// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {
    AirdropAccountConfig,
    AirdropCadence,
    AirdropDustDestination
} from "../../src/airdrop/AirdropTypes.sol";
import {
    BasketAllocationConfig,
    BasketBurnTaxDestination,
    BasketConfig,
    BasketEligibilityMode,
    BasketHarvestCadence,
    BasketSwapLeg,
    BasketTarget
} from "../../src/basket/BasketTypes.sol";
import { BasketManagerV2 } from "../../src/basket/BasketManagerV2.sol";
import { BasketVaultV2 } from "../../src/basket/BasketVaultV2.sol";
import { ProjectTreasuryVaultV2 } from "../../src/treasury/ProjectTreasuryVaultV2.sol";
import { MockRegistry } from "../mocks/MockRegistry.sol";
import { MockProjectToken } from "../mocks/MockProjectToken.sol";
import {
    MockProjectController,
    MockProjectPriceGuard,
    MockProjectSwapAdapter
} from "../mocks/MockTreasuryIntegrations.sol";
import {
    MockBasketAsset,
    MockBasketModule,
    MockBasketYieldAdapter
} from "../mocks/MockBasketIntegrations.sol";

contract BasketManagerV2Test is Test {
    uint256 private constant BASKET_ID = 1;
    address private constant ALICE = address(0xA11CE);
    address private constant CREATOR = address(0xC0FFEE);

    MockRegistry private registry;
    MockProjectToken private subject;
    MockProjectController private controller;
    MockBasketModule private treasury;
    MockBasketModule private airdrop;
    MockBasketAsset private asset;
    MockBasketYieldAdapter private adapter;
    BasketVaultV2 private implementation;
    BasketManagerV2 private manager;
    BasketVaultV2 private vault;
    BasketAllocationConfig private allocation;

    function setUp() public {
        registry = new MockRegistry();
        subject = new MockProjectToken(address(registry), address(this), 1_000_000e18);
        controller = new MockProjectController(subject.projectId());
        treasury = new MockBasketModule(
            address(registry),
            address(subject),
            subject.projectId(),
            uint8(BasketEligibilityMode.HOLDERS),
            address(subject)
        );
        airdrop = new MockBasketModule(
            address(registry),
            address(subject),
            subject.projectId(),
            uint8(BasketEligibilityMode.HOLDERS),
            address(subject)
        );
        asset = new MockBasketAsset("Yield Asset", "YLD");
        address[] memory outputs = new address[](1);
        outputs[0] = address(asset);
        adapter = new MockBasketYieldAdapter(address(asset), outputs);
        implementation = new BasketVaultV2();

        address predictedManager =
            vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        bytes32 salt = keccak256(abi.encode(subject.projectId(), BASKET_ID));
        address predictedVault =
            Clones.predictDeterministicAddress(address(implementation), salt, predictedManager);
        adapter.bind(predictedVault);

        bytes32 root = _yieldLeaf(predictedVault, address(adapter), address(asset));
        allocation = _singleAllocation();
        manager = new BasketManagerV2(
            address(registry),
            address(subject),
            CREATOR,
            address(controller),
            address(treasury),
            address(0),
            address(airdrop),
            address(0),
            root,
            address(implementation),
            _config(allocation, true, 0, 0)
        );
        vault = manager.primaryVault();
        assertEq(address(vault), predictedVault);
        manager.finalizePrimaryBasket();
    }

    function testLaunchMintsToTreasuryAndFundingLocksPrincipal() public {
        assertEq(manager.basketNFT().ownerOf(BASKET_ID), address(treasury));
        asset.mint(ALICE, 100e18);
        vm.startPrank(ALICE);
        asset.approve(address(manager), 100e18);
        uint256 received = manager.fund(
            subject.projectId(), address(subject), address(asset), 100e18, abi.encode(BASKET_ID)
        );
        vm.stopPrank();

        assertEq(received, 100e18);
        (,,, uint256 principal, uint256 position,,,,) = vault.targetStatus(0);
        assertEq(principal, 100e18);
        assertEq(position, 100e18);
        assertEq(asset.balanceOf(address(adapter)), 100e18);
    }

    function testSwapApprovalLeafPinsPriceGuardInstance() public {
        MockProjectSwapAdapter swapAdapter = new MockProjectSwapAdapter();
        MockProjectPriceGuard approvedGuard = new MockProjectPriceGuard();
        MockProjectPriceGuard unapprovedGuard = new MockProjectPriceGuard();
        bytes32 routeHash = keccak256(hex"1234");

        assertEq(address(approvedGuard).codehash, address(unapprovedGuard).codehash);
        assertNotEq(
            vault.swapApprovalLeaf(
                address(0), 0, address(swapAdapter), address(approvedGuard), 100, routeHash
            ),
            vault.swapApprovalLeaf(
                address(0), 0, address(swapAdapter), address(unapprovedGuard), 100, routeHash
            )
        );
    }

    function testNativeFundingSwapsAndDepositsWithoutStrandingValue() public {
        BasketVaultV2 newImplementation = new BasketVaultV2();
        address[] memory outputs = new address[](1);
        outputs[0] = address(asset);
        MockBasketYieldAdapter newAdapter = new MockBasketYieldAdapter(address(asset), outputs);
        MockProjectSwapAdapter swapAdapter = new MockProjectSwapAdapter();
        MockProjectPriceGuard guard = new MockProjectPriceGuard();

        address predictedManager =
            vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        bytes32 salt = keccak256(abi.encode(subject.projectId(), BASKET_ID));
        address predictedVault =
            Clones.predictDeterministicAddress(address(newImplementation), salt, predictedManager);
        newAdapter.bind(predictedVault);
        bytes memory route = hex"1234";
        bytes32 yieldLeaf = _yieldLeaf(predictedVault, address(newAdapter), address(asset));
        bytes32 swapLeaf = _swapLeaf(
            predictedVault,
            address(0),
            address(asset),
            address(swapAdapter),
            address(guard),
            100,
            keccak256(route)
        );
        bytes32 root = _hashPair(yieldLeaf, swapLeaf);
        BasketAllocationConfig memory nativeAllocation;
        nativeAllocation.inputAssets = new address[](1);
        nativeAllocation.inputAssets[0] = address(0);
        nativeAllocation.targets = new BasketTarget[](1);
        bytes32[] memory yieldProof = new bytes32[](1);
        yieldProof[0] = swapLeaf;
        nativeAllocation.targets[0] = BasketTarget({
            depositAsset: address(asset),
            yieldAdapter: address(newAdapter),
            targetWeightBps: 10_000,
            rewardAssets: new address[](0),
            yieldApprovalProof: yieldProof
        });
        nativeAllocation.swapLegs = new BasketSwapLeg[](1);
        bytes32[] memory swapProof = new bytes32[](1);
        swapProof[0] = yieldLeaf;
        nativeAllocation.swapLegs[0] = BasketSwapLeg({
            inputAsset: address(0),
            targetIndex: 0,
            swapAdapter: address(swapAdapter),
            priceGuard: address(guard),
            maxSlippageBps: 100,
            routeData: route,
            approvalProof: swapProof
        });

        uint256 amount = 5 ether;
        asset.mint(address(swapAdapter), amount);
        swapAdapter.configure(amount, type(uint256).max, false);
        guard.setQuote(amount, uint48(block.timestamp + 1 days));
        BasketManagerV2 nativeManager = new BasketManagerV2(
            address(registry),
            address(subject),
            CREATOR,
            address(controller),
            address(treasury),
            address(0),
            address(airdrop),
            address(0),
            root,
            address(newImplementation),
            _config(nativeAllocation, false, 0, 0)
        );
        nativeManager.finalizePrimaryBasket();
        vm.deal(ALICE, amount);
        vm.prank(ALICE);
        assertEq(
            nativeManager.fund{ value: amount }(
                subject.projectId(), address(subject), address(0), amount, abi.encode(BASKET_ID)
            ),
            amount
        );
        assertEq(address(nativeManager).balance, 0);
        assertEq(address(nativeManager.primaryVault()).balance, 0);
        assertEq(asset.balanceOf(address(newAdapter)), amount);
    }

    function testPredictedManagerLaunchesWithRealTreasuryAndAutoRegistersNft() public {
        BasketVaultV2 newImplementation = new BasketVaultV2();
        address[] memory outputs = new address[](1);
        outputs[0] = address(asset);
        MockBasketYieldAdapter newAdapter = new MockBasketYieldAdapter(address(asset), outputs);

        uint64 nextNonce = vm.getNonce(address(this));
        address predictedManager = vm.computeCreateAddress(address(this), nextNonce + 2);
        bytes32 salt = keccak256(abi.encode(subject.projectId(), BASKET_ID));
        address predictedVault =
            Clones.predictDeterministicAddress(address(newImplementation), salt, predictedManager);
        newAdapter.bind(predictedVault);
        BasketAllocationConfig memory realAllocation = allocation;
        realAllocation.targets[0].yieldAdapter = address(newAdapter);
        bytes32 root = _yieldLeaf(predictedVault, address(newAdapter), address(asset));

        ProjectTreasuryVaultV2 realTreasury = new ProjectTreasuryVaultV2(
            address(registry),
            address(subject),
            CREATOR,
            address(controller),
            bytes32(0),
            predictedManager
        );
        MockBasketModule realAirdrop = new MockBasketModule(
            address(registry),
            address(subject),
            subject.projectId(),
            uint8(BasketEligibilityMode.HOLDERS),
            address(subject)
        );
        BasketManagerV2 realManager = new BasketManagerV2(
            address(registry),
            address(subject),
            CREATOR,
            address(controller),
            address(realTreasury),
            address(0),
            address(realAirdrop),
            address(0),
            root,
            address(newImplementation),
            _config(realAllocation, false, 0, 0)
        );
        assertEq(address(realManager), predictedManager);
        realManager.finalizePrimaryBasket();

        assertEq(realManager.basketNFT().ownerOf(BASKET_ID), address(realTreasury));
        assertTrue(realTreasury.isOwnedBasketRegistered(BASKET_ID));
        assertEq(realTreasury.ownedBasketCount(), 1);
    }

    function testStakerBasketBindsTheExactProjectStakingEligibilitySource() public {
        MockBasketModule staking = new MockBasketModule(
            address(registry), address(subject), subject.projectId(), 0, address(subject)
        );
        MockBasketModule stakerAirdrop = new MockBasketModule(
            address(registry),
            address(subject),
            subject.projectId(),
            uint8(BasketEligibilityMode.STAKERS),
            address(staking)
        );
        BasketVaultV2 newImplementation = new BasketVaultV2();
        address[] memory outputs = new address[](1);
        outputs[0] = address(asset);
        MockBasketYieldAdapter newAdapter = new MockBasketYieldAdapter(address(asset), outputs);
        address predictedManager =
            vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        bytes32 salt = keccak256(abi.encode(subject.projectId(), BASKET_ID));
        address predictedVault =
            Clones.predictDeterministicAddress(address(newImplementation), salt, predictedManager);
        newAdapter.bind(predictedVault);
        BasketAllocationConfig memory stakerAllocation = allocation;
        stakerAllocation.targets[0].yieldAdapter = address(newAdapter);
        BasketConfig memory stakerConfig = _config(stakerAllocation, false, 0, 0);
        stakerConfig.eligibilityMode = BasketEligibilityMode.STAKERS;
        BasketManagerV2 stakerManager = new BasketManagerV2(
            address(registry),
            address(subject),
            CREATOR,
            address(controller),
            address(treasury),
            address(0),
            address(stakerAirdrop),
            address(staking),
            _yieldLeaf(predictedVault, address(newAdapter), address(asset)),
            address(newImplementation),
            stakerConfig
        );
        stakerManager.finalizePrimaryBasket();

        asset.mint(address(this), 100e18);
        asset.approve(address(stakerManager), 100e18);
        stakerManager.fund(
            subject.projectId(), address(subject), address(asset), 100e18, abi.encode(BASKET_ID)
        );
        asset.mint(address(this), 5e18);
        asset.approve(address(newAdapter), 5e18);
        newAdapter.addYield(address(asset), 5e18);
        vm.warp(block.timestamp + 1 days);
        stakerManager.harvest(BASKET_ID);

        assertEq(stakerAirdrop.eligibilitySource(), address(staking));
        assertEq(stakerAirdrop.funded(address(asset)), 5e18);
    }

    function testHarvestIsCadencedAndAirdropFailureIsRetryable() public {
        _fund(100e18);
        asset.mint(address(this), 10e18);
        asset.approve(address(adapter), 10e18);
        adapter.addYield(address(asset), 10e18);

        vm.expectPartialRevert(BasketVaultV2.HarvestNotDue.selector);
        manager.harvest(BASKET_ID);

        airdrop.setFailFunding(true);
        vm.warp(block.timestamp + 1 days);
        manager.harvest(BASKET_ID);
        assertEq(vault.pendingDividend(address(asset)), 10e18);
        assertEq(airdrop.funded(address(asset)), 0);

        airdrop.setFailFunding(false);
        assertTrue(manager.retryPendingDividend(BASKET_ID, address(asset)));
        assertEq(vault.pendingDividend(address(asset)), 0);
        assertEq(airdrop.funded(address(asset)), 10e18);
    }

    function testLossCannotBeHarvestedAsDividend() public {
        _fund(100e18);
        adapter.realizeLoss(10e18);
        vm.warp(block.timestamp + 1 days);
        vm.expectPartialRevert(BasketVaultV2.PrincipalNotRestored.selector);
        manager.harvest(BASKET_ID);
        assertEq(airdrop.funded(address(asset)), 0);
    }

    function testControllerCanRedirectRejectedDividendAndUnblockReconfigurationAndBurn() public {
        _fund(100e18);
        asset.mint(address(this), 10e18);
        asset.approve(address(adapter), 10e18);
        adapter.addYield(address(asset), 10e18);
        airdrop.setFailFunding(true);
        vm.warp(block.timestamp + 1 days);
        manager.harvest(BASKET_ID);

        vm.expectPartialRevert(BasketVaultV2.PendingDividendsExist.selector);
        treasury.execute(address(manager), abi.encodeCall(manager.beginBurn, (BASKET_ID)));
        assertEq(vault.pendingDividend(address(asset)), 10e18);
        assertFalse(vault.burnBegun());

        controller.execute(
            address(manager),
            abi.encodeCall(manager.redirectPendingDividendToTreasury, (BASKET_ID, address(asset)))
        );
        assertEq(vault.pendingDividend(address(asset)), 0);
        assertEq(vault.pendingDividendAssetCount(), 0);
        assertEq(asset.balanceOf(address(treasury)), 10e18);
        controller.execute(
            address(manager),
            abi.encodeCall(manager.updateConfiguration, (BASKET_ID, abi.encode(allocation)))
        );
        treasury.execute(address(manager), abi.encodeCall(manager.beginBurn, (BASKET_ID)));
        assertTrue(vault.burnBegun());
    }

    function testBasketNftCanNeverBeTransferredToCanonicalBurnAddress() public {
        IERC721 nft = manager.basketNFT();
        address burnAddress = manager.BURN_ADDRESS();
        vm.expectRevert();
        treasury.execute(
            address(nft),
            abi.encodeWithSignature(
                "safeTransferFrom(address,address,uint256)",
                address(treasury),
                burnAddress,
                BASKET_ID
            )
        );
        assertEq(nft.ownerOf(BASKET_ID), address(treasury));
    }

    function testGovernanceUpdatePerformsAtomicInVaultRebalance() public {
        _fund(100e18);
        bytes32 expectedHash = keccak256(abi.encode(allocation));
        controller.execute(
            address(manager),
            abi.encodeCall(manager.updateConfiguration, (BASKET_ID, abi.encode(allocation)))
        );
        assertEq(manager.currentConfigurationHash(), expectedHash);
        assertEq(asset.balanceOf(address(adapter)), 100e18);
        assertEq(asset.balanceOf(address(vault)), 0);
        (,,, uint256 principal,,,,,) = vault.targetStatus(0);
        assertEq(principal, 100e18);
    }

    function testBurnUnlocksOnlyToCurrentNftOwnerAndBurnsPrice() public {
        BasketAllocationConfig memory current = allocation;
        BasketManagerV2 burnManager = _deployManager(current, false, 1_000, 10e18);
        BasketVaultV2 burnVault = burnManager.primaryVault();
        burnManager.finalizePrimaryBasket();

        asset.mint(ALICE, 100e18);
        vm.startPrank(ALICE);
        asset.approve(address(burnManager), 100e18);
        burnManager.fund(
            subject.projectId(), address(subject), address(asset), 100e18, abi.encode(BASKET_ID)
        );
        vm.stopPrank();

        IERC721 nft = burnManager.basketNFT();
        treasury.execute(
            address(nft),
            abi.encodeWithSignature(
                "safeTransferFrom(address,address,uint256)", address(treasury), ALICE, BASKET_ID
            )
        );
        subject.mint(ALICE, 10e18);
        uint256 supplyBefore = subject.totalSupply();
        vm.startPrank(ALICE);
        subject.approve(address(burnManager), 10e18);
        burnManager.beginBurn(BASKET_ID);
        vm.stopPrank();
        burnManager.processBurnTarget(BASKET_ID, 0);
        vm.prank(ALICE);
        burnManager.finalizeBurn(BASKET_ID);

        assertEq(subject.totalSupply(), supplyBefore - 10e18);
        assertEq(asset.balanceOf(ALICE), 90e18);
        assertEq(asset.balanceOf(CREATOR), 10e18);
        assertTrue(burnVault.closed());
        vm.expectRevert();
        nft.ownerOf(BASKET_ID);
    }

    function _deployManager(
        BasketAllocationConfig memory current,
        bool updates,
        uint16 taxBps,
        uint256 burnPrice
    ) private returns (BasketManagerV2 deployed) {
        BasketVaultV2 newImplementation = new BasketVaultV2();
        address predictedManager =
            vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        bytes32 salt = keccak256(abi.encode(subject.projectId(), BASKET_ID));
        address predictedVault =
            Clones.predictDeterministicAddress(address(newImplementation), salt, predictedManager);
        MockBasketYieldAdapter newAdapter;
        address[] memory outputs = new address[](1);
        outputs[0] = address(asset);
        newAdapter = new MockBasketYieldAdapter(address(asset), outputs);
        // The adapter deployment changed the next CREATE address; recompute both predictions.
        predictedManager = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        predictedVault =
            Clones.predictDeterministicAddress(address(newImplementation), salt, predictedManager);
        newAdapter.bind(predictedVault);
        current.targets[0].yieldAdapter = address(newAdapter);
        bytes32 root = _yieldLeaf(predictedVault, address(newAdapter), address(asset));
        deployed = new BasketManagerV2(
            address(registry),
            address(subject),
            CREATOR,
            address(controller),
            address(treasury),
            address(0),
            address(airdrop),
            address(0),
            root,
            address(newImplementation),
            _config(current, updates, taxBps, burnPrice)
        );
    }

    function _fund(uint256 amount) private {
        asset.mint(address(this), amount);
        asset.approve(address(manager), amount);
        manager.fund(
            subject.projectId(), address(subject), address(asset), amount, abi.encode(BASKET_ID)
        );
    }

    function _singleAllocation() private view returns (BasketAllocationConfig memory config_) {
        config_.inputAssets = new address[](1);
        config_.inputAssets[0] = address(asset);
        config_.targets = new BasketTarget[](1);
        config_.targets[0] = BasketTarget({
            depositAsset: address(asset),
            yieldAdapter: address(adapter),
            targetWeightBps: 10_000,
            rewardAssets: new address[](0),
            yieldApprovalProof: new bytes32[](0)
        });
        config_.swapLegs = new BasketSwapLeg[](0);
    }

    function _config(
        BasketAllocationConfig memory allocation_,
        bool updates,
        uint16 taxBps,
        uint256 burnPrice
    ) private pure returns (BasketConfig memory config_) {
        AirdropAccountConfig memory account = AirdropAccountConfig({
            maxPushBatchSize: 32,
            minimumSnapshotConfirmations: 1,
            cadence: AirdropCadence.DAILY,
            dustDestination: AirdropDustDestination.FUNDER
        });
        config_ = BasketConfig({
            cadence: BasketHarvestCadence.ONE_DAY,
            eligibilityMode: BasketEligibilityMode.HOLDERS,
            governanceUpdatesEnabled: updates,
            burnTaxBps: taxBps,
            burnTaxDestination: BasketBurnTaxDestination.CREATOR,
            burnPriceSubject: burnPrice,
            airdropAccountConfig: abi.encode(account),
            allocation: allocation_
        });
    }

    function _yieldLeaf(
        address,
        /* vault_ */
        address adapter_,
        address depositAsset_
    )
        private
        view
        returns (bytes32)
    {
        bytes32 inner = keccak256(
            abi.encode(
                keccak256("SINJOH_V2_BASKET_YIELD_APPROVAL"),
                block.chainid,
                adapter_.codehash,
                depositAsset_,
                adapter_
            )
        );
        return keccak256(bytes.concat(inner));
    }

    function _swapLeaf(
        address, /* vault_ */
        address inputAsset,
        address outputAsset,
        address swapAdapter,
        address guard,
        uint16 slippageBps,
        bytes32 routeHash
    ) private view returns (bytes32) {
        bytes32 inner = keccak256(
            abi.encode(
                keccak256("SINJOH_V2_BASKET_SWAP_APPROVAL"),
                block.chainid,
                inputAsset,
                outputAsset,
                swapAdapter.codehash,
                guard,
                slippageBps,
                routeHash
            )
        );
        return keccak256(bytes.concat(inner));
    }

    function _hashPair(bytes32 a, bytes32 b) private pure returns (bytes32) {
        return a < b ? keccak256(bytes.concat(a, b)) : keccak256(bytes.concat(b, a));
    }
}
