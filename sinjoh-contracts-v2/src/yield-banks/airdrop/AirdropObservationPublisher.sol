// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

interface IAirdropObservedFeed {
    function quoteSigner() external view returns (address);
    function observe(int24,uint48,uint64,bytes32,uint128,bytes32) external;
}

/// @notice Bounded publication to governance-admitted feeds, with per-feed failure isolation.
/// @dev The observer remains trusted for history accuracy. This contract only limits its
/// capabilities to authenticated observations; it cannot move bank assets or configure feeds.
contract AirdropObservationPublisher is Ownable2Step, ReentrancyGuard, EIP712 {
    struct Observation {
        address feed;
        int24 tick;
        uint48 timestamp;
        uint64 blockNumber;
        bytes32 blockHash;
        uint128 lowestLiquidity;
        bytes32 evidenceHash;
    }
    uint256 public constant MAX_BATCH=16;
    uint256 public constant MAX_SIGNED_BATCH=100;
    uint256 public constant FEED_GAS=250_000;
    bytes32 public constant QUOTE_TYPEHASH=keccak256("PricePreparation(bytes32 observationsHash,uint48 validUntil)");
    address public observer;
    mapping(address=>bytes32) public feedCodeHash;
    error InvalidConfiguration();
    error NotObserver();
    error InvalidSignature();
    error ExpiredPreparation();
    event ObserverChanged(address indexed observer);
    event FeedConfigured(address indexed feed,bytes32 codeHash);
    event Published(address indexed feed,bytes32 indexed evidenceHash,bool success);

    constructor(address governance,address observer_,address[] memory initialFeeds) Ownable(governance) EIP712("Sinjoh Airdrop Prices", "1") {
        _setObserver(observer_);
        if(initialFeeds.length>100)revert InvalidConfiguration();
        for(uint256 i;i<initialFeeds.length;++i){
            if(feedCodeHash[initialFeeds[i]]!=bytes32(0))revert InvalidConfiguration();
            _configureFeed(initialFeeds[i],true);
        }
    }
    function setObserver(address observer_) external onlyOwner { _setObserver(observer_); }
    function _setObserver(address observer_) private {
        if(observer_==address(0)||observer_==address(this))revert InvalidConfiguration();
        observer=observer_;emit ObserverChanged(observer_);
    }
    function configureFeed(address feed,bool enabled) external onlyOwner { _configureFeed(feed,enabled); }
    function _configureFeed(address feed,bool enabled) private {
        if(enabled&&(feed.code.length==0||IAirdropObservedFeed(feed).quoteSigner()!=address(this)))revert InvalidConfiguration();
        feedCodeHash[feed]=enabled?feed.codehash:bytes32(0);
        emit FeedConfigured(feed,feedCodeHash[feed]);
    }
    function publish(Observation[] calldata observations) external nonReentrant returns(uint256 accepted) {
        if(msg.sender!=observer)revert NotObserver();
        if(observations.length==0||observations.length>MAX_BATCH)revert InvalidConfiguration();
        return _publish(observations);
    }

    /// @notice A wallet can include an observer-signed preparation when rebalancing.
    /// Signing is offchain. There is no funded publisher or continuous transaction loop.
    /// The feed's monotonic block/time checks prevent old preparations replacing newer prices.
    function publishSigned(Observation[] calldata observations,uint48 validUntil,bytes calldata signature)
        external nonReentrant returns(uint256 accepted)
    {
        if(observations.length==0||observations.length>MAX_SIGNED_BATCH)revert InvalidConfiguration();
        if(block.timestamp>validUntil||validUntil>block.timestamp+2 minutes)revert ExpiredPreparation();
        if(ECDSA.recover(preparationDigest(observations,validUntil),signature)!=observer)revert InvalidSignature();
        return _publish(observations);
    }

    function preparationDigest(Observation[] calldata observations,uint48 validUntil) public view returns(bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(QUOTE_TYPEHASH,keccak256(abi.encode(observations)),validUntil)));
    }

    function _publish(Observation[] calldata observations) private returns(uint256 accepted) {
        // Reserve sufficient gas for every feed and every result event. A caller must not
        // silently starve later feeds while reporting a successful batch transaction.
        if(gasleft()<observations.length*(FEED_GAS+30_000)+50_000)revert InvalidConfiguration();
        for(uint256 i;i<observations.length;++i){
            Observation calldata o=observations[i];
            bytes32 codeHash=feedCodeHash[o.feed];
            bool ok;
            if(codeHash!=bytes32(0)&&o.feed.codehash==codeHash){
                // Ignore untrusted return data: a failed feed cannot allocate unbounded memory.
                bytes memory data=abi.encodeCall(IAirdropObservedFeed.observe,(o.tick,o.timestamp,o.blockNumber,o.blockHash,o.lowestLiquidity,o.evidenceHash));
                address feed=o.feed;uint256 limit=FEED_GAS;
                assembly ("memory-safe") { ok := call(limit,feed,0,add(data,32),mload(data),0,0) }
            }
            if(ok)++accepted;
            emit Published(o.feed,o.evidenceHash,ok);
        }
    }
}
