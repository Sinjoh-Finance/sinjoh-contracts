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
import { ERC4626BasketYieldAdapter } from "../../src/adapters/ERC4626BasketYieldAdapter.sol";
import { BasketManagerV2 } from "../../src/basket/BasketManagerV2.sol";
import { BasketVaultV2 } from "../../src/basket/BasketVaultV2.sol";
import {
    BasketAllocationConfig,
    BasketBurnTaxDestination,
    BasketConfig,
    BasketEligibilityMode,
    BasketHarvestCadence,
    BasketSwapLeg,
    BasketTarget
} from "../../src/basket/BasketTypes.sol";
import { MockRegistry } from "../mocks/MockRegistry.sol";
import { MockProjectToken } from "../mocks/MockProjectToken.sol";
import { MockProjectController } from "../mocks/MockTreasuryIntegrations.sol";
import { MockBasketAsset, MockBasketModule } from "../mocks/MockBasketIntegrations.sol";
import { MockERC4626 } from "../mocks/MockERC4626.sol";

contract ERC4626BasketYieldAdapterV2IntegrationTest is Test {
    uint256 private constant BASKET_ID = 1;
    address private constant CREATOR = address(0xC0FFEE);

    function testE2EBasketYieldHarvestTransferAndPricedTaxedBurn() public {
        MockRegistry registry = new MockRegistry();
        MockProjectToken subject =
            new MockProjectToken(address(registry), address(this), 1_000_000e18);
        MockProjectController controller = new MockProjectController(subject.projectId());
        MockBasketModule treasury = new MockBasketModule(
            address(registry),
            address(subject),
            subject.projectId(),
            uint8(BasketEligibilityMode.HOLDERS),
            address(subject)
        );
        MockBasketModule airdrop = new MockBasketModule(
            address(registry),
            address(subject),
            subject.projectId(),
            uint8(BasketEligibilityMode.HOLDERS),
            address(subject)
        );
        MockBasketAsset asset = new MockBasketAsset("Yield Asset", "YIELD");
        MockERC4626 erc4626 = new MockERC4626(IERC20(address(asset)));
        BasketVaultV2 implementation = new BasketVaultV2();

        uint64 nonce = vm.getNonce(address(this));
        address predictedManager = vm.computeCreateAddress(address(this), nonce + 1);
        address predictedVault = Clones.predictDeterministicAddress(
            address(implementation),
            keccak256(abi.encode(subject.projectId(), BASKET_ID)),
            predictedManager
        );
        ERC4626BasketYieldAdapter adapter =
            new ERC4626BasketYieldAdapter(predictedVault, address(erc4626));
        bytes32 approvalRoot = _yieldLeaf(address(adapter), address(asset));

        BasketManagerV2 manager = new BasketManagerV2(
            address(registry),
            address(subject),
            CREATOR,
            address(controller),
            address(treasury),
            address(0),
            address(airdrop),
            address(0),
            approvalRoot,
            address(implementation),
            _config(address(asset), address(adapter))
        );
        assertEq(address(manager), predictedManager);
        assertEq(address(manager.primaryVault()), predictedVault);
        manager.finalizePrimaryBasket();

        asset.mint(address(this), 1_100e18);
        asset.approve(address(manager), 1_000e18);
        manager.fund(
            subject.projectId(), address(subject), address(asset), 1_000e18, abi.encode(BASKET_ID)
        );
        assertEq(adapter.managedPrincipal(), 1_000e18);
        asset.transfer(address(erc4626), 100e18);

        vm.warp(block.timestamp + 1 days);
        manager.harvest(BASKET_ID);
        assertGt(airdrop.funded(address(asset)), 0);
        assertGe(adapter.totalAssets(), adapter.managedPrincipal());

        treasury.execute(
            address(manager.basketNFT()),
            abi.encodeCall(IERC721.transferFrom, (address(treasury), address(this), BASKET_ID))
        );
        assertEq(manager.basketNFT().ownerOf(BASKET_ID), address(this));
        uint256 subjectSupplyBefore = subject.totalSupply();
        subject.approve(address(manager), 10e18);
        manager.beginBurn(BASKET_ID);
        manager.processBurnTarget(BASKET_ID, 0);
        manager.finalizeBurn(BASKET_ID);
        assertEq(adapter.totalAssets(), 0);
        assertEq(erc4626.balanceOf(address(adapter)), 0);
        assertEq(subject.totalSupply(), subjectSupplyBefore - 10e18);
        assertApproxEqAbs(asset.balanceOf(address(this)), 900e18, 3);
        assertApproxEqAbs(asset.balanceOf(CREATOR), 100e18, 3);
        assertApproxEqAbs(airdrop.funded(address(asset)), 100e18, 3);
        assertApproxEqAbs(
            asset.balanceOf(address(this)) + asset.balanceOf(CREATOR)
                + airdrop.funded(address(asset)),
            1_100e18,
            3
        );
    }

    function _config(address asset, address adapter)
        private
        pure
        returns (BasketConfig memory config)
    {
        BasketAllocationConfig memory allocation;
        allocation.inputAssets = new address[](1);
        allocation.inputAssets[0] = asset;
        allocation.targets = new BasketTarget[](1);
        allocation.targets[0] = BasketTarget({
            depositAsset: asset,
            yieldAdapter: adapter,
            targetWeightBps: 10_000,
            rewardAssets: new address[](0),
            yieldApprovalProof: new bytes32[](0)
        });
        allocation.swapLegs = new BasketSwapLeg[](0);
        AirdropAccountConfig memory account = AirdropAccountConfig({
            maxPushBatchSize: 32,
            minimumSnapshotConfirmations: 1,
            cadence: AirdropCadence.DAILY,
            dustDestination: AirdropDustDestination.FUNDER
        });
        config = BasketConfig({
            cadence: BasketHarvestCadence.ONE_DAY,
            eligibilityMode: BasketEligibilityMode.HOLDERS,
            governanceUpdatesEnabled: false,
            burnTaxBps: 1_000,
            burnTaxDestination: BasketBurnTaxDestination.CREATOR,
            burnPriceSubject: 10e18,
            airdropAccountConfig: abi.encode(account),
            allocation: allocation
        });
    }

    function _yieldLeaf(address adapter, address asset) private view returns (bytes32) {
        return keccak256(
            bytes.concat(
                keccak256(
                    abi.encode(
                        keccak256("SINJOH_V2_BASKET_YIELD_APPROVAL"),
                        block.chainid,
                        adapter.codehash,
                        asset
                    )
                )
            )
        );
    }
}
