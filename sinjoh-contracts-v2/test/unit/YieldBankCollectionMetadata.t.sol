// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { YieldBankCollectionMetadata } from "../../src/yield-banks/YieldBankCollectionMetadata.sol";

contract YieldBankCollectionMetadataTest is Test {
    function testRejectsEmptyIdentity() external {
        vm.expectRevert(YieldBankCollectionMetadata.InvalidConfiguration.selector);
        new YieldBankCollectionMetadata("", "YB");
        vm.expectRevert(YieldBankCollectionMetadata.InvalidConfiguration.selector);
        new YieldBankCollectionMetadata("Collection A", "");
    }

    function testStoresCollectionIdentityWithoutArtworkAssumptions() external {
        YieldBankCollectionMetadata metadata = new YieldBankCollectionMetadata("Collection A", "A");
        assertEq(metadata.collectionName(), "Collection A");
        assertEq(metadata.collectionSymbol(), "A");
    }

    function testAcceptsUtf8CollectionIdentity() external {
        YieldBankCollectionMetadata metadata =
            new YieldBankCollectionMetadata(unicode"Collection — α", unicode"α");
        assertEq(metadata.collectionName(), unicode"Collection — α");
        assertEq(metadata.collectionSymbol(), unicode"α");
    }
}
