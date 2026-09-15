// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;
import { Test } from "forge-std/Test.sol";
import { AirdropObservationPublisher as Publisher } from "../../src/yield-banks/airdrop/AirdropObservationPublisher.sol";
import { AirdropQuoteReader } from "../../src/yield-banks/airdrop/AirdropQuoteReader.sol";
import { PublisherFeedFixture } from "./AirdropObservationPublisher.t.sol";

contract AirdropSignedPricesTest is Test {
    Publisher publisher;
    PublisherFeedFixture feed;
    AirdropQuoteReader reader;
    uint256 constant FIXTURE_KEY = 12345;
    function setUp() public {
        vm.warp(10000); vm.chainId(4663);
        publisher = new Publisher(address(this), vm.addr(FIXTURE_KEY), new address[](0));
        feed = new PublisherFeedFixture(address(publisher));
        publisher.configureFeed(address(feed), true);
        reader = new AirdropQuoteReader(address(publisher));
    }
    function _rows() internal view returns(Publisher.Observation[] memory rows) {
        rows = new Publisher.Observation[](1);
        rows[0] = Publisher.Observation(address(feed), 1, 9990, 100, keccak256("block"), 100, keccak256("history"));
    }
    function _sign(Publisher target, Publisher.Observation[] memory rows, uint48 expiry) internal view returns(bytes memory) {
        (uint8 v,bytes32 r,bytes32 s) = vm.sign(FIXTURE_KEY,target.preparationDigest(rows,expiry));
        return abi.encodePacked(r,s,v);
    }
    function testAnyWalletCanSubmitAuthenticatedPricesWithoutFundedPublisher() public {
        Publisher.Observation[] memory rows = _rows(); bytes memory sig = _sign(publisher,rows,10090);
        vm.prank(address(0xCAFE));
        assertEq(publisher.publishSigned(rows,10090,sig),1);
        assertEq(feed.received(),1);
        assertEq(vm.addr(FIXTURE_KEY).balance,0);
    }
    function testChangedObservationOrExpiryCannotReuseSignature() public {
        Publisher.Observation[] memory rows = _rows(); bytes memory sig = _sign(publisher,rows,10090);
        rows[0].tick++;
        vm.expectRevert(Publisher.InvalidSignature.selector);publisher.publishSigned(rows,10090,sig);
        rows[0].tick--;
        vm.expectRevert(Publisher.InvalidSignature.selector);publisher.publishSigned(rows,10091,sig);
        assertEq(feed.received(),0);
    }
    function testDifferentChainAndPublisherRejectSignature() public {
        Publisher.Observation[] memory rows = _rows(); bytes memory sig = _sign(publisher,rows,10090);
        vm.chainId(1);
        vm.expectRevert(Publisher.InvalidSignature.selector);publisher.publishSigned(rows,10090,sig);
        vm.chainId(4663);
        Publisher other = new Publisher(address(this),vm.addr(FIXTURE_KEY),new address[](0));
        vm.expectRevert(Publisher.InvalidSignature.selector);other.publishSigned(rows,10090,sig);
    }
    function testExpiredAndLongLivedPreparationsRejected() public {
        Publisher.Observation[] memory rows = _rows(); bytes memory sig = _sign(publisher,rows,10090);
        vm.warp(10091);
        vm.expectRevert(Publisher.ExpiredPreparation.selector);publisher.publishSigned(rows,10090,sig);
        sig = _sign(publisher,rows,11000);
        vm.expectRevert(Publisher.ExpiredPreparation.selector);publisher.publishSigned(rows,11000,sig);
    }
    function testSignerRotationInvalidatesPreviouslySignedPreparations() public {
        Publisher.Observation[] memory rows = _rows(); bytes memory sig = _sign(publisher,rows,10090);
        publisher.setObserver(address(0xB0B));
        vm.expectRevert(Publisher.InvalidSignature.selector);publisher.publishSigned(rows,10090,sig);
    }
    function testReaderReturnsPostPreparationStateAndRejectsWrites() public {
        Publisher.Observation[] memory rows = _rows(); bytes memory sig = _sign(publisher,rows,10090);
        AirdropQuoteReader.Read[] memory calls = new AirdropQuoteReader.Read[](1);
        calls[0] = AirdropQuoteReader.Read(address(feed),abi.encodeCall(feed.received,()));
        bytes[] memory result = reader.read(rows,10090,sig,calls);
        assertEq(abi.decode(result[0],(uint256)),1);
        calls[0].data = abi.encodeCall(feed.setFailure,(true));
        vm.expectRevert();reader.read(rows,10090,sig,calls);
        assertFalse(feed.failing());
        assertEq(feed.received(),1);
    }
    function testReaderRejectsReplacedPublisherCode() public {
        Publisher.Observation[] memory rows = _rows(); bytes memory sig = _sign(publisher,rows,10090);
        vm.etch(address(publisher),hex"00");
        AirdropQuoteReader.Read[] memory calls = new AirdropQuoteReader.Read[](1);
        vm.expectRevert(AirdropQuoteReader.InvalidConfiguration.selector);reader.read(rows,10090,sig,calls);
    }
    function testEmptyAndOversizedSignedBatchRejectedBeforeSignature() public {
        vm.expectRevert(Publisher.InvalidConfiguration.selector);
        publisher.publishSigned(new Publisher.Observation[](0),10090,"");
        vm.expectRevert(Publisher.InvalidConfiguration.selector);
        publisher.publishSigned(new Publisher.Observation[](101),10090,"");
    }
}
