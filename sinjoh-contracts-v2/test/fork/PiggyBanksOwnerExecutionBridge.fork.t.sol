// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    CollectionPortfolioAllocator
} from "../../src/yield-banks/CollectionPortfolioAllocator.sol";
import {
    YieldBankOwnerExecutionBridge
} from "../../src/yield-banks/YieldBankOwnerExecutionBridge.sol";
import {
    IYieldBankManagedSleeve
} from "../../src/yield-banks/interfaces/IYieldBankManagedSleeve.sol";
import { YieldBankProceedsVault } from "../../src/yield-banks/YieldBankProceedsVault.sol";

interface IPiggyBanksOwnerCollection {
    function accountOf(uint256 tokenId) external view returns (address);
}

interface IPiggyBanksOwnerNFT {
    function ownerOf(uint256 tokenId) external view returns (address);
}

contract PiggyBanksOwnerExecutionBridgeForkTest is Test {
    uint256 private constant CHAIN_ID = 4663;
    uint256 private constant TOKEN_ID = 502;
    address private constant COLLECTION = 0xc275fa302Cd53DFa42D41b1C5b770661d923ba43;
    address private constant NFT = 0xF39D4C50a08E0FdafC51d37FC92Bd2c25191DA6a;
    address private constant ALLOCATOR = 0x42e14eA9f926ad7b530ce49d433CB6f748f8D0a1;
    address private constant PROCEEDS_VAULT = 0xa9653463ffdE4e2352b4659334f785159d7525FD;
    address private constant TIMELOCK = 0x7C15804A2d7F5981035895CAb953e5E76393E1B8;
    address private constant USDG = 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168;
    address private constant USDG_SLEEVE = 0x9e02f4E267fcEf8c1DC89f148529D20F1aD040A1;
    address private constant INJOH = 0x2cC0FAC44B8252f6B10208B091aFf2c94B4da77D;
    address private constant INJOH_WETH_POOL = 0xB09fa4f04032b9d9e690ac4a1d29523b5f9A72DC;
    address private constant INJOH_WETH_SLEEVE = 0x5Be0D22d85fef441D11E279D6DC7c78817F1Ce9F;

    function testCurrentOwnerExecutesLivePiggyBankWithoutDeploymentWalletAsOperator() external {
        string memory rpcUrl =
            vm.envOr("ROBINHOOD_MAINNET_RPC_URL", string("https://app.sinjoh.com/api/rpc"));
        vm.createSelectFork(rpcUrl);
        assertEq(block.chainid, CHAIN_ID);

        CollectionPortfolioAllocator allocator = CollectionPortfolioAllocator(ALLOCATOR);
        YieldBankOwnerExecutionBridge bridge = new YieldBankOwnerExecutionBridge(ALLOCATOR);
        vm.prank(TIMELOCK);
        YieldBankProceedsVault(payable(PROCEEDS_VAULT)).setAllocationOperator(address(bridge));
        assertEq(allocator.allocationOperator(), address(bridge));

        address owner = IPiggyBanksOwnerNFT(NFT).ownerOf(TOKEN_ID);
        address account = IPiggyBanksOwnerCollection(COLLECTION).accountOf(TOKEN_ID);
        uint256 directInjohBefore = IERC20(INJOH).balanceOf(account);
        uint16[3] memory weights = [uint16(0), uint16(10_000), uint16(0)];
        vm.prank(owner);
        uint64 revision = allocator.setTargetAllocation(
            TOKEN_ID, weights, INJOH_WETH_POOL, 100, uint48(block.timestamp + 2 hours)
        );

        CollectionPortfolioAllocator.RebalanceExecution memory execution;
        uint256 usdgShares = IERC20(USDG_SLEEVE).balanceOf(account);
        assertGt(usdgShares, 0);
        address[] memory inventory = IYieldBankManagedSleeve(USDG_SLEEVE).inventoryAssets();
        assertEq(inventory.length, 1);
        assertEq(inventory[0], USDG);
        execution.redemptions[2].minimumOutputs = new uint256[](1);
        execution.redemptions[2].minimumOutputs[0] = 1;
        execution.conversions = new CollectionPortfolioAllocator.ConversionCall[](1);
        execution.conversions[0] = CollectionPortfolioAllocator.ConversionCall({
            asset: USDG, minimumWethOut: 1, routeData: ""
        });
        execution.allocations[1].minimumOutput = 1;
        execution.allocations[1].minimumShares = 1;
        execution.minimumWethRecovered = 1;
        execution.deadline = block.timestamp + 1 hours;

        vm.prank(owner);
        (uint256 wethRecovered, uint256[3] memory shares) =
            bridge.executeOwnerAllocation(TOKEN_ID, revision, execution);

        assertGt(wethRecovered, 0);
        assertEq(shares[0], 0);
        assertGt(shares[1], 0);
        assertEq(shares[2], 0);
        assertEq(IERC20(USDG_SLEEVE).balanceOf(account), 0);
        assertEq(IERC20(INJOH_WETH_SLEEVE).balanceOf(account), shares[1]);
        assertEq(IERC20(INJOH).balanceOf(account), directInjohBefore);
        assertEq(allocator.activeDeltaPoolOf(TOKEN_ID), INJOH_WETH_POOL);
        assertEq(allocator.allocationTargetOf(TOKEN_ID).executedRevision, revision);
    }
}
