// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { TestBase } from "./TestBase.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";
import { MockFeeRouter } from "./mocks/MockFeeRouter.sol";
import { MockPonsLocker } from "./mocks/MockPonsLocker.sol";
import { SinjohPonsV1Adapter } from "../src/SinjohPonsV1Adapter.sol";
import { SinjohPonsV1AdapterFactory } from "../src/SinjohPonsV1AdapterFactory.sol";

contract SinjohPonsV1AdapterTest is TestBase {
    MockERC20 internal subject;
    MockERC20 internal weth;
    MockFeeRouter internal router;
    MockPonsLocker internal locker;
    SinjohPonsV1AdapterFactory internal factory;
    SinjohPonsV1Adapter internal adapter;

    function setUp() public {
        subject = new MockERC20("Subject", "SUB");
        weth = new MockERC20("Wrapped Ether", "WETH");
        router = new MockFeeRouter();
        locker = new MockPonsLocker(weth);
        factory = new SinjohPonsV1AdapterFactory(address(locker), address(weth), block.chainid);
        address predicted = factory.predictAddress(
            address(this), address(subject), address(router), bytes32("TEST")
        );
        adapter = SinjohPonsV1Adapter(
            factory.deploy(address(this), address(subject), address(router), bytes32("TEST"))
        );
        assertEq(address(adapter), predicted);
        locker.setFeeRedirect(address(subject), address(adapter));
    }

    function testImplementationAndCloneCannotBeReinitialized() public {
        SinjohPonsV1Adapter implementation = SinjohPonsV1Adapter(factory.implementation());
        vm.expectRevert(SinjohPonsV1Adapter.AlreadyInitialized.selector);
        implementation.initialize(address(subject), address(router));
        vm.expectRevert(SinjohPonsV1Adapter.AlreadyInitialized.selector);
        adapter.initialize(address(subject), address(router));
    }

    function testCreate2FrontRunnerCannotChangeConfiguration() public {
        bytes32 salt = bytes32("FRONT_RUN");
        address predicted =
            factory.predictAddress(address(this), address(subject), address(router), salt);
        vm.prank(address(0xBAD));
        address deployed = factory.deploy(address(this), address(subject), address(router), salt);
        assertEq(deployed, predicted);
        assertEq(SinjohPonsV1Adapter(deployed).subject(), address(subject));
        assertEq(SinjohPonsV1Adapter(deployed).router(), address(router));
        assertEq(SinjohPonsV1Adapter(deployed).ponsLocker(), address(locker));
    }

    function testSubjectCannotAlsoBeTheRouter() public {
        vm.expectRevert();
        factory.deploy(address(this), address(subject), address(subject), bytes32("SELF_ROUTE"));
    }

    function testCollectCallsImmutableLockerWithImmutableSubject() public {
        locker.seedFees(address(subject), 700, 300);
        adapter.collect();
        assertEq(locker.lastSubject(), address(subject));
        assertEq(subject.balanceOf(address(adapter)), 700);
        assertEq(weth.balanceOf(address(adapter)), 300);
    }

    function testUnauthorizedUpstreamConfigurationRevertsWithoutState() public {
        locker.setFeeRedirect(address(subject), address(0xBAD));
        locker.seedFees(address(subject), 700, 300);
        vm.expectRevert();
        adapter.collect();
        assertEq(subject.balanceOf(address(adapter)), 0);
        assertEq(weth.balanceOf(address(adapter)), 0);
    }

    function testDirectLockerAutomationRemainsForwardable() public {
        locker.seedFees(address(subject), 700, 300);
        locker.automate(address(subject));
        adapter.forward(address(subject));
        adapter.forward(address(weth));
        assertEq(subject.balanceOf(address(router)), 700);
        assertEq(weth.balanceOf(address(router)), 300);
    }

    function testOneAssetFailureCannotBlockTheOther() public {
        subject.mint(address(adapter), 700);
        weth.mint(address(adapter), 300);
        subject.setFailTransfers(true);

        vm.expectRevert();
        adapter.forward(address(subject));
        adapter.forward(address(weth));

        assertEq(subject.balanceOf(address(adapter)), 700);
        assertEq(weth.balanceOf(address(adapter)), 0);
        assertEq(weth.balanceOf(address(router)), 300);
    }

    function testUnsupportedAndZeroBalanceForwarding() public {
        MockERC20 unsupported = new MockERC20("Unsupported", "NO");
        vm.expectPartialRevert(SinjohPonsV1Adapter.UnsupportedAsset.selector);
        adapter.forward(address(unsupported));

        uint256 callsBefore = subject.transferCalls();
        assertEq(adapter.forward(address(subject)), 0);
        assertEq(subject.transferCalls(), callsBefore);
    }

    function testForwardingChargesNoFeeAndRouterSyncChargesExactlyOnce() public {
        subject.mint(address(adapter), 10_000);
        assertEq(adapter.forward(address(subject)), 10_000);
        assertEq(subject.balanceOf(address(router)), 10_000);
        assertEq(router.totalLiability(address(subject)), 0);

        router.sync(address(subject));
        assertEq(router.totalLiability(address(subject)), 10_000);
        assertEq(router.protocolOwed(address(subject)), 100);
        router.sync(address(subject));
        assertEq(router.totalLiability(address(subject)), 10_000);
        assertEq(router.protocolOwed(address(subject)), 100);
    }
}
