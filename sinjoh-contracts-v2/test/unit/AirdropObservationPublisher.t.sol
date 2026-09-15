// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;
import {Test} from "forge-std/Test.sol";
import {AirdropObservationPublisher} from "../../src/yield-banks/airdrop/AirdropObservationPublisher.sol";
contract PublisherFeedFixture {
    address public quoteSigner;
    uint256 public received;
    bool public failing;
    constructor(address signer){quoteSigner=signer;}
    function setFailure(bool value) external {failing=value;}
    function observe(int24,uint48,uint64,bytes32,uint128,bytes32) external {
        require(msg.sender==quoteSigner);require(!failing);++received;
    }
}
contract AirdropObservationPublisherTest is Test {
    AirdropObservationPublisher publisher;
    PublisherFeedFixture first;
    PublisherFeedFixture second;
    address observer=address(0xB0B);
    function setUp() public {
        publisher=new AirdropObservationPublisher(address(this),observer,new address[](0));
        first=new PublisherFeedFixture(address(publisher));second=new PublisherFeedFixture(address(publisher));
        publisher.configureFeed(address(first),true);publisher.configureFeed(address(second),true);
    }
    function batch() private view returns(AirdropObservationPublisher.Observation[] memory rows){
        rows=new AirdropObservationPublisher.Observation[](2);
        rows[0]=AirdropObservationPublisher.Observation(address(first),0,10000,1000,keccak256("block"),100,keccak256("evidence"));
        rows[1]=AirdropObservationPublisher.Observation(address(second),0,10000,1000,keccak256("block"),100,keccak256("evidence"));
    }
    function testOnlyObserverCanPublish() public {vm.expectRevert(AirdropObservationPublisher.NotObserver.selector);publisher.publish(batch());}
    function testBatchPublishesEveryAdmittedFeed() public {vm.prank(observer);assertEq(publisher.publish(batch()),2);assertEq(first.received(),1);assertEq(second.received(),1);}
    function testRevertingFeedDoesNotBlockOtherTokens() public {first.setFailure(true);vm.prank(observer);assertEq(publisher.publish(batch()),1);assertEq(first.received(),0);assertEq(second.received(),1);}
    function testDisabledFeedCannotReceiveObservations() public {publisher.configureFeed(address(first),false);vm.prank(observer);assertEq(publisher.publish(batch()),1);assertEq(first.received(),0);}
    function testChangedRuntimeFailsClosed() public {vm.etch(address(first),hex"00");vm.prank(observer);assertEq(publisher.publish(batch()),1);assertEq(second.received(),1);}
    function testObserverCannotAdmitFeeds() public {vm.prank(observer);vm.expectRevert();publisher.configureFeed(address(first),true);}
    function testFeedMustAuthorizePublisher() public {PublisherFeedFixture unrelated=new PublisherFeedFixture(observer);vm.expectRevert(AirdropObservationPublisher.InvalidConfiguration.selector);publisher.configureFeed(address(unrelated),true);}
    function testObserverRotationRevokesPreviousSigner() public {publisher.setObserver(address(0xCAFE));vm.prank(observer);vm.expectRevert(AirdropObservationPublisher.NotObserver.selector);publisher.publish(batch());}
    function testInsufficientBatchGasRevertsBeforeAnyPublication() public {vm.prank(observer);vm.expectRevert(AirdropObservationPublisher.InvalidConfiguration.selector);publisher.publish{gas:300000}(batch());assertEq(first.received(),0);assertEq(second.received(),0);}
    function testConstructorAdmitsPreboundFeedsWithoutAnotherGovernanceRound() public {
        address predicted=vm.computeCreateAddress(address(this),vm.getNonce(address(this))+1);
        PublisherFeedFixture prebound=new PublisherFeedFixture(predicted);
        address[] memory feeds=new address[](1);feeds[0]=address(prebound);
        AirdropObservationPublisher deployed=new AirdropObservationPublisher(address(this),observer,feeds);
        assertEq(address(deployed),predicted);assertEq(deployed.feedCodeHash(address(prebound)),address(prebound).codehash);
    }
    function testBatchCountBounded() public {AirdropObservationPublisher.Observation[] memory rows=new AirdropObservationPublisher.Observation[](17);vm.prank(observer);vm.expectRevert(AirdropObservationPublisher.InvalidConfiguration.selector);publisher.publish(rows);}
}
