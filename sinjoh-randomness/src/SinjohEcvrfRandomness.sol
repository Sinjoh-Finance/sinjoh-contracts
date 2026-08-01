// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { VRF } from "./libraries/VRF.sol";
import { ISinjohRandomnessConsumer } from "./interfaces/ISinjohRandomness.sol";

interface IArbSys {
    function arbBlockNumber() external view returns (uint256);
    function arbBlockHash(uint256 arbBlockNum) external view returns (bytes32);
}

/// @notice Randomness from an ECVRF proof verified on-chain against one immutable public key.
/// @dev Settles in seconds and needs no external protocol, oracle network, or second chain.
///
/// The cost is a different trust boundary. ECVRF output is deterministic: the key holder can
/// compute a result the moment its input is known, and can decline to publish. Two mitigations
/// are structural rather than advisory:
///
/// 1. The proof input is bound to the hash of the block the request landed in. Nobody knows that
///    hash while building the requesting transaction, so a consumer cannot grind its own
///    committed data against a known key, and the key holder cannot precompute an output for a
///    future round.
/// 2. Sealing that block hash is permissionless and must happen inside the 255-block window.
///
/// What remains: once sealed, the key holder sees the outcome before anyone else and may refuse
/// to publish, forcing the consumer's own timeout. The key must therefore be held by a party
/// that does not also control the consumer's committed data. Holding both permits offline
/// grinding and defeats the whole construction.
contract SinjohEcvrfRandomness is VRF {
    bytes32 public constant ALPHA_DOMAIN = keccak256("SINJOH_ECVRF_ALPHA_V1");
    bytes32 public constant SEED_DOMAIN = keccak256("SINJOH_ECVRF_SEED_V1");
    address public constant ARBSYS = address(0x64);
    uint256 public constant BLOCK_HASH_WINDOW = 255;

    error Unauthorized();
    error Reentrancy();
    error InvalidAddress();
    error InvalidPublicKey();
    error AlreadyRequested();
    error UnknownRequest();
    error AlreadySealed();
    error NotSealed();
    error SealTooEarly();
    error SealWindowClosed();
    error MissingBlockHash();
    error AlreadyFulfilled();
    error NotFulfilled();
    error AlreadyDelivered();
    error WrongPublicKey();
    error WrongSeed();

    event RandomnessRequested(
        bytes32 indexed requestId, address indexed consumer, uint64 roundId, uint64 requestBlock
    );
    event RequestSealed(bytes32 indexed requestId, bytes32 entropy, uint256 alpha);
    event ProofAccepted(bytes32 indexed requestId, uint256 output, address indexed prover);
    event SeedDelivered(bytes32 indexed requestId, address indexed consumer, uint256 seed);

    struct Request {
        address consumer;
        uint64 roundId;
        uint64 requestBlock;
        bool isSealed;
        bool fulfilled;
        bool delivered;
        bytes32 entropy;
        uint256 output;
    }

    uint256 public immutable publicKeyX;
    uint256 public immutable publicKeyY;
    uint256 public immutable deploymentChainId;

    mapping(bytes32 requestId => Request request) public requests;

    uint256 private _reentrancyState = 1;

    constructor(uint256 publicKeyX_, uint256 publicKeyY_, uint256 chainId_) {
        if (block.chainid != chainId_) revert InvalidAddress();
        // Rejects the point at infinity and any coordinate pair off the curve.
        if (publicKeyX_ == 0 || publicKeyY_ == 0) revert InvalidPublicKey();
        if (!_isOnCurve([publicKeyX_, publicKeyY_])) revert InvalidPublicKey();

        publicKeyX = publicKeyX_;
        publicKeyY = publicKeyY_;
        deploymentChainId = chainId_;
    }

    modifier nonReentrant() {
        if (_reentrancyState == 2) revert Reentrancy();
        _reentrancyState = 2;
        _;
        _reentrancyState = 1;
    }

    // --------------------------------------------------------------------------------
    // Consumer entrypoint
    // --------------------------------------------------------------------------------

    /// @notice Records a request and pins it to the current block. Makes no external call.
    /// @dev The requesting transaction cannot know the hash of the block it lands in, so a
    /// consumer cannot choose committed data with knowledge of the resulting output.
    function requestRandomness(uint64 roundId) external returns (bytes32 requestId) {
        requestId = requestIdFor(msg.sender, roundId);
        if (requests[requestId].consumer != address(0)) revert AlreadyRequested();

        // forge-lint: disable-next-line(unsafe-typecast)
        uint64 requestBlock = uint64(IArbSys(ARBSYS).arbBlockNumber());
        requests[requestId] = Request({
            consumer: msg.sender,
            roundId: roundId,
            requestBlock: requestBlock,
            isSealed: false,
            fulfilled: false,
            delivered: false,
            entropy: bytes32(0),
            output: 0
        });

        emit RandomnessRequested(requestId, msg.sender, roundId, requestBlock);
    }

    function requestIdFor(address consumer, uint64 roundId) public view returns (bytes32) {
        return keccak256(abi.encode(block.chainid, address(this), consumer, roundId));
    }

    // --------------------------------------------------------------------------------
    // Seal
    // --------------------------------------------------------------------------------

    /// @notice Pins the request's proof input to the hash of the block it landed in.
    /// @dev Permissionless, and the tightest operational deadline in the design: it must run
    /// inside the L2's 255-block hash window. A missed window kills the request, and the
    /// consumer falls back to its own timeout.
    function seal(bytes32 requestId) external returns (uint256 alpha) {
        Request storage request = requests[requestId];
        if (request.consumer == address(0)) revert UnknownRequest();
        if (request.isSealed) revert AlreadySealed();

        uint256 current = IArbSys(ARBSYS).arbBlockNumber();
        if (current <= request.requestBlock) revert SealTooEarly();
        if (current > uint256(request.requestBlock) + BLOCK_HASH_WINDOW) revert SealWindowClosed();

        bytes32 entropy = IArbSys(ARBSYS).arbBlockHash(request.requestBlock);
        if (entropy == bytes32(0)) revert MissingBlockHash();

        request.isSealed = true;
        request.entropy = entropy;
        alpha = _alpha(request.consumer, request.roundId, entropy);

        emit RequestSealed(requestId, entropy, alpha);
    }

    /// @notice The VRF input for a sealed request. This is what the prover signs.
    function alphaFor(bytes32 requestId) public view returns (uint256) {
        Request storage request = requests[requestId];
        if (!request.isSealed) revert NotSealed();
        return _alpha(request.consumer, request.roundId, request.entropy);
    }

    // --------------------------------------------------------------------------------
    // Proof
    // --------------------------------------------------------------------------------

    /// @notice Verifies an ECVRF proof and stores its output. Makes no external call.
    /// @dev Permissionless: the proof is self-authenticating against the immutable public key,
    /// so who submits it is irrelevant. Verification and consumer delivery are separated so a
    /// reverting consumer never forces the proof to be verified again.
    function fulfill(bytes32 requestId, Proof calldata proof) external returns (uint256 output) {
        Request storage request = requests[requestId];
        if (request.consumer == address(0)) revert UnknownRequest();
        if (!request.isSealed) revert NotSealed();
        if (request.fulfilled) revert AlreadyFulfilled();

        if (proof.pk[0] != publicKeyX || proof.pk[1] != publicKeyY) revert WrongPublicKey();

        uint256 alpha = _alpha(request.consumer, request.roundId, request.entropy);
        if (proof.seed != alpha) revert WrongSeed();

        output = _randomValueFromVRFProof(proof, alpha);

        request.fulfilled = true;
        request.output = output;

        emit ProofAccepted(requestId, output, msg.sender);
    }

    /// @notice Delivers the derived seed to the consumer. Retryable forever.
    function deliver(bytes32 requestId) external nonReentrant {
        Request storage request = requests[requestId];
        if (request.consumer == address(0)) revert UnknownRequest();
        if (!request.fulfilled) revert NotFulfilled();
        if (request.delivered) revert AlreadyDelivered();

        uint256 seed = seedFor(requestId, request.output);
        // Marked delivered only if the consumer call succeeds; a revert rolls the flag back.
        request.delivered = true;
        ISinjohRandomnessConsumer(request.consumer).receiveRandomness(requestId, seed);

        emit SeedDelivered(requestId, request.consumer, seed);
    }

    function seedFor(bytes32 requestId, uint256 output) public view returns (uint256) {
        return uint256(
            keccak256(abi.encode(SEED_DOMAIN, block.chainid, address(this), requestId, output))
        );
    }

    function pendingSeed(bytes32 requestId) external view returns (bool ready, uint256 seed) {
        Request storage request = requests[requestId];
        if (request.consumer == address(0) || request.delivered || !request.fulfilled) {
            return (false, 0);
        }
        return (true, seedFor(requestId, request.output));
    }

    function _alpha(address consumer, uint64 roundId, bytes32 entropy)
        private
        view
        returns (uint256)
    {
        return uint256(
            keccak256(
                abi.encode(ALPHA_DOMAIN, block.chainid, address(this), consumer, roundId, entropy)
            )
        );
    }
}
