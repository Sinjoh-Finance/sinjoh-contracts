// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { YieldBankAccount } from "../../src/yield-banks/YieldBankAccount.sol";
import { YieldBankCollection } from "../../src/yield-banks/YieldBankCollection.sol";
import {
    CollectionPortfolioAllocator
} from "../../src/yield-banks/CollectionPortfolioAllocator.sol";

/// @notice Reproducible compatibility evidence; never broadcasts or modifies mainnet.
/// @dev Set ROBINHOOD_MAINNET_RPC_URL to opt in. A passing suite proves restrictions,
///      not that a Stock strategy has been deployed or can execute. Direct authority rejection
///      does not rule out dynamic sleeves; see PiggyBanksDynamicSleeveExtensionForkTest.
contract PiggyBanksStockCompatibilityForkTest is Test {
    uint256 private constant SNAPSHOT_BLOCK = 62_559_575;
    uint256 private constant TOKEN_ID = 334;
    YieldBankCollection private constant COLLECTION =
        YieldBankCollection(0xc275fa302Cd53DFa42D41b1C5b770661d923ba43);
    address private constant ALLOCATOR = 0x42e14eA9f926ad7b530ce49d433CB6f748f8D0a1;
    address private constant IMPLEMENTATION = 0x962C7D4cEcad73c363Cb40D1Db420353261F7e5f;
    address private constant STOCK = 0x5F8537A02B3c236E526A213C3e65A4251317E7E0;

    function setUp() public {
        string memory rpc = vm.envOr("ROBINHOOD_MAINNET_RPC_URL", string(""));
        if (bytes(rpc).length == 0) vm.skip(true);
        vm.createSelectFork(rpc, SNAPSHOT_BLOCK);
        assertEq(block.chainid, 4663);
    }

    function testDeployedIdentityAndFixedAccountImplementation() public view {
        assertEq(COLLECTION.portfolioAllocator(), ALLOCATOR);
        assertEq(COLLECTION.accountImplementation(), IMPLEMENTATION);
        assertEq(
            address(COLLECTION).codehash,
            0x4a019003aefe312456d9d3f0c1bcf18eacda2abd08e9a917e3db7e26345fbec0
        );
        assertEq(
            ALLOCATOR.codehash, 0xeb5c377653415dcbff4aa866cefa4b97aa7c0a37092b1f8ad46182e1118db95b
        );
        assertEq(
            IMPLEMENTATION.codehash,
            0xda75673701e3e849c9b46753d4e508448f391cfb8837ef0e248d2ef16f78bb39
        );
        assertEq(
            COLLECTION.accountOf(TOKEN_ID).code,
            abi.encodePacked(
                hex"363d3d373d3d3d363d73", IMPLEMENTATION, hex"5af43d82803e903d91602b57fd5bf3"
            )
        );
        assertEq(CollectionPortfolioAllocator(ALLOCATOR).sleeves(0), STOCK);
    }

    function testOwnerCannotGrantNewStockControllerRebalanceAuthority() public {
        address owner = IERC721(address(COLLECTION.nft())).ownerOf(TOKEN_ID);
        _assertRebalanceRejected(owner);
        _assertRebalanceRejected(makeAddr("new-stock-controller"));
        _assertRebalanceRejected(COLLECTION.collectionTimelock());
        _assertRebalanceRejected(CollectionPortfolioAllocator(ALLOCATOR).allocationOperator());
    }

    function testExistingAllocatorStillHasTheRequiredAuthority() public {
        YieldBankAccount account = YieldBankAccount(COLLECTION.accountOf(TOKEN_ID));
        address[] memory assets = account.trackedAssets();
        assertGt(assets.length, 0);
        vm.prank(ALLOCATOR);
        account.approveRebalance(assets[0], 1);
        assertEq(IERC20(assets[0]).allowance(address(account), ALLOCATOR), 1);
        vm.prank(ALLOCATOR);
        account.clearRebalanceApproval(assets[0]);
        assertEq(IERC20(assets[0]).allowance(address(account), ALLOCATOR), 0);
    }

    function testOwnerCannotWithdrawBackingWhileKeepingTheNFT() public {
        address owner = IERC721(address(COLLECTION.nft())).ownerOf(TOKEN_ID);
        YieldBankAccount account = YieldBankAccount(COLLECTION.accountOf(TOKEN_ID));
        address asset = CollectionPortfolioAllocator(ALLOCATOR).sleeves(2);
        vm.expectRevert(abi.encodeWithSelector(YieldBankAccount.OnlyCollection.selector, owner));
        vm.prank(owner);
        account.releaseDirectAsset(asset, owner);
        assertFalse(account.closed());
        assertEq(IERC721(address(COLLECTION.nft())).ownerOf(TOKEN_ID), owner);
    }

    function testTimelockHasNoCollectionAllocatorOrAccountReplacementSetter() public {
        address timelock = COLLECTION.collectionTimelock();
        address replacement = makeAddr("replacement");
        vm.prank(timelock);
        (bool changedAllocator,) = address(COLLECTION)
            .call(abi.encodeWithSignature("setPortfolioAllocator(address)", replacement));
        assertFalse(changedAllocator);
        vm.prank(timelock);
        (bool changedAccount,) = address(COLLECTION)
            .call(abi.encodeWithSignature("setAccountImplementation(address)", replacement));
        assertFalse(changedAccount);
        assertEq(COLLECTION.portfolioAllocator(), ALLOCATOR);
        assertEq(COLLECTION.accountImplementation(), IMPLEMENTATION);
    }

    function _assertRebalanceRejected(address caller) private {
        YieldBankAccount account = YieldBankAccount(COLLECTION.accountOf(TOKEN_ID));
        address asset = CollectionPortfolioAllocator(ALLOCATOR).sleeves(2);
        vm.expectRevert(
            abi.encodeWithSelector(YieldBankAccount.OnlyPortfolioAllocator.selector, caller)
        );
        vm.prank(caller);
        account.approveRebalance(asset, 1);
    }
}
