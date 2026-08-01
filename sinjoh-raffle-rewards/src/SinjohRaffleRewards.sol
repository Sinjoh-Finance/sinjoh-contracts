// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { SafeTransferLib } from "./libraries/SafeTransferLib.sol";
import { RaffleTypes } from "./RaffleTypes.sol";

interface IArbSys {
    function arbBlockNumber() external view returns (uint256);
    function arbBlockHash(uint256 arbBlockNum) external view returns (bytes32);
}

/// @dev Copied, never imported. Any adapter satisfying `sinjoh-ccip-vrf/SPEC.md` may be used.
interface ISinjohRaffleRandomness {
    function requestRandomness(uint64 roundId) external returns (bytes32 requestId);
}

/// @notice One immutable raffle for one subject token. Holders never sign, approve, or register.
/// @dev Clone-initialized once; every parameter is frozen afterwards. No owner, upgrade, sweep,
/// rescue, arbitrary call, or configuration setter exists.
contract SinjohRaffleRewards {
    using SafeTransferLib for address;

    uint16 public constant BPS = 10_000;
    uint16 public constant PROTOCOL_FEE_BPS = 100;
    uint16 public constant MAX_PAYOUT_TAX_BPS = 5_000;
    uint8 public constant MAX_WINNERS_PER_ROUND = 16;
    uint8 public constant MAX_PENDING_ROUNDS = 4;
    uint8 public constant MAX_EXCLUSIONS = 32;
    uint8 public constant MAX_PROOF_LENGTH = 64;
    uint32 public constant MIN_ROUND_INTERVAL = 600;
    uint32 public constant MAX_ROUND_INTERVAL = 604_800;
    uint32 public constant MAX_WEIGHT_WINDOW_BLOCKS = 1_000_000;
    uint32 public constant MIN_RANDOMNESS_TIMEOUT = 900;
    uint32 public constant MAX_RANDOMNESS_TIMEOUT = 86_400;
    uint32 public constant MIN_CLAIM_WINDOW = 3_600;
    uint32 public constant MAX_CLAIM_WINDOW = 2_592_000;

    address public constant ARBSYS = address(0x64);
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    bytes32 public constant LEAF_DOMAIN = keccak256("SINJOH_RAFFLE_LEAF_V1");
    bytes32 public constant NODE_DOMAIN = keccak256("SINJOH_RAFFLE_NODE_V1");
    bytes32 public constant EMPTY_DOMAIN = keccak256("SINJOH_RAFFLE_EMPTY_V1");
    bytes32 public constant SLOT_DOMAIN = keccak256("SINJOH_RAFFLE_SLOT_V1");

    error AlreadyInitialized();
    error NotInitialized();
    error Unauthorized();
    error OnlySelf();
    error Reentrancy();
    error InvalidAddress();
    error InvalidAmount();
    error InvalidValue();
    error InvalidConfiguration();
    error ConfigurationMismatch();
    error NonCanonicalConfiguration();
    error SubjectNotBound();
    error SubjectAlreadyBound();
    error InvalidRound();
    error InvalidSnapshot();
    error InvalidRoot();
    error TooManyPendingRounds();
    error RoundTooSoon();
    error PrizeBelowFloor();
    error InvalidRequest();
    error InvalidSeed();
    error InvalidSlot();
    error SlotAlreadyPaid();
    error ClaimWindowClosed();
    error ClaimWindowOpen();
    error RandomnessPending();
    error InvalidProof();
    error NotWinningLeaf();
    error ExcludedHolder();
    error NothingOwed();
    error Insolvent();
    error UnexpectedBalanceDelta(uint256 expected, uint256 actual);
    error InvariantViolation();

    event RaffleInitialized(
        bytes32 configHash,
        address indexed creator,
        address indexed attestor,
        address indexed randomness,
        address prizeAsset,
        address[] exclusions
    );
    event SubjectBound(address indexed subject);
    event Deposited(
        address indexed source, uint256 gross, uint256 fee, uint256 net, bool attributed
    );
    event RoundCommitted(
        uint64 indexed roundId,
        uint64 snapshotBlock,
        bytes32 snapshotBlockHash,
        bytes32 rootHash,
        uint256 totalTickets,
        uint256 prize,
        bytes32 requestId
    );
    event RandomnessReceived(uint64 indexed roundId, bytes32 requestId, uint256 seed);
    event PrizePaid(
        uint64 indexed roundId,
        uint8 indexed slot,
        address indexed holder,
        uint256 gross,
        uint256 recipientTax,
        uint256 recycleTax,
        uint256 net
    );
    event PaymentDeferred(
        uint64 indexed roundId,
        uint8 indexed slot,
        address indexed holder,
        uint256 amount,
        bytes reason
    );
    event OwedDelivered(address indexed holder, uint256 amount, address indexed caller);
    event RoundExpired(uint64 indexed roundId, uint256 returned);
    event RoundAbandoned(uint64 indexed roundId, uint256 returned);
    event ProtocolFeeSent(address indexed recipient, uint256 amount, address indexed caller);
    event TaxSent(address indexed recipient, uint256 amount, address indexed caller);

    RaffleTypes.Settings public settings;
    bytes32 public configHash;
    address public subject;
    bool public initialized;

    uint64 public latestRoundId;
    uint64 public latestSnapshotBlock;
    uint64 public lastCommitAt;
    uint8 public pendingRounds;

    uint256 public availablePool;
    uint256 public totalReserved;
    uint256 public totalOwed;
    uint256 public protocolOwed;
    uint256 public taxOwed;
    uint256 public totalIntake;
    uint16 private _feeRemainder;

    mapping(uint64 roundId => RaffleTypes.Round round) public rounds;
    mapping(bytes32 requestId => uint64 roundId) public roundOfRequest;
    mapping(address holder => bool excluded) public isExcluded;
    mapping(address holder => uint256 amount) public owed;

    uint256 private _reentrancyState = 1;

    modifier nonReentrant() {
        if (_reentrancyState == 2) revert Reentrancy();
        _reentrancyState = 2;
        _;
        _reentrancyState = 1;
    }

    modifier onlyAttestor() {
        if (msg.sender != settings.attestor) revert Unauthorized();
        _;
    }

    /// @notice Native prize assets accept unattributed deposits; `sync()` credits them.
    receive() external payable {
        if (settings.prizeAsset != address(0)) revert InvalidValue();
    }

    // --------------------------------------------------------------------------------
    // Initialization
    // --------------------------------------------------------------------------------

    /// @notice Freezes every parameter. Called by the factory inside the deployment transaction.
    function initialize(RaffleTypes.Config calldata config) external {
        if (initialized) revert AlreadyInitialized();
        _validate(config);

        initialized = true;
        configHash = keccak256(abi.encode(config));
        settings = RaffleTypes.Settings({
            creator: config.creator,
            attestor: config.attestor,
            randomness: config.randomness,
            prizeAsset: config.prizeAsset,
            protocolFeeRecipient: config.protocolFeeRecipient,
            taxRecipient: config.taxRecipient,
            tokensPerTicket: config.tokensPerTicket,
            maxTicketsPerHolder: config.maxTicketsPerHolder,
            minPrize: config.minPrize,
            maxPrize: config.maxPrize,
            prizeBps: config.prizeBps,
            recipientTaxBps: config.recipientTaxBps,
            recycleTaxBps: config.recycleTaxBps,
            minConfirmations: config.minConfirmations,
            winnersPerRound: config.winnersPerRound,
            minRoundInterval: config.minRoundInterval,
            weightWindowBlocks: config.weightWindowBlocks,
            randomnessTimeout: config.randomnessTimeout,
            claimWindow: config.claimWindow,
            basis: config.basis
        });

        uint256 exclusionLength = config.exclusions.length;
        for (uint256 i; i < exclusionLength; ++i) {
            isExcluded[config.exclusions[i]] = true;
        }
        isExcluded[address(0)] = true;
        isExcluded[BURN_ADDRESS] = true;
        isExcluded[address(this)] = true;

        emit RaffleInitialized(
            configHash,
            config.creator,
            config.attestor,
            config.randomness,
            config.prizeAsset,
            config.exclusions
        );
    }

    /// @notice Binds the subject token once. The raffle address exists before the token does.
    function bind(address subject_) external {
        if (!initialized) revert NotInitialized();
        if (msg.sender != settings.creator) revert Unauthorized();
        if (subject != address(0)) revert SubjectAlreadyBound();
        if (
            subject_ == address(0) || subject_ == address(this) || subject_ == settings.prizeAsset
                || subject_.code.length == 0
        ) revert InvalidAddress();

        subject = subject_;
        isExcluded[subject_] = true;
        emit SubjectBound(subject_);
    }

    // --------------------------------------------------------------------------------
    // Deposits
    // --------------------------------------------------------------------------------

    /// @notice Atomic sink funding. `msg.sender` is measured, never trusted.
    function fund(address subject_, address asset, uint256 amount, bytes calldata configData)
        external
        payable
        nonReentrant
        returns (uint256 received)
    {
        address boundSubject = subject;
        if (boundSubject == address(0)) revert SubjectNotBound();
        if (subject_ != boundSubject) revert InvalidAddress();
        address prizeAsset = settings.prizeAsset;
        if (asset != prizeAsset) revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();
        if (configData.length != 0 && keccak256(configData) != configHash) {
            revert ConfigurationMismatch();
        }

        if (prizeAsset == address(0)) {
            if (msg.value != amount) revert InvalidValue();
            received = amount;
        } else {
            if (msg.value != 0) revert InvalidValue();
            uint256 beforeBalance = prizeAsset.safeBalanceOf(address(this));
            prizeAsset.safeTransferFrom(msg.sender, address(this), amount);
            uint256 afterBalance = prizeAsset.safeBalanceOf(address(this));
            received = afterBalance >= beforeBalance ? afterBalance - beforeBalance : 0;
            if (received != amount) revert UnexpectedBalanceDelta(amount, received);
        }

        (uint256 fee, uint256 net) = _credit(received);
        _assertSolvent();
        emit Deposited(msg.sender, received, fee, net, true);
    }

    /// @notice Credits every unaccounted unit held by the raffle into the prize pool.
    /// @dev This is the deposit account for platform fees and donations. Value that is already
    /// a liability can never be re-credited.
    function sync() external nonReentrant returns (uint256 credited, uint256 fee) {
        if (!initialized) revert NotInitialized();
        uint256 currentLiabilities = _liabilities();
        uint256 balance = _balance();
        if (balance <= currentLiabilities) return (0, 0);

        uint256 gross = balance - currentLiabilities;
        uint256 net;
        (fee, net) = _credit(gross);
        credited = gross;
        _assertSolvent();
        emit Deposited(msg.sender, gross, fee, net, false);
    }

    function sendProtocolFee(uint256 amount) external nonReentrant {
        if (amount == 0 || amount > protocolOwed) revert InvalidAmount();
        protocolOwed -= amount;
        address recipient = settings.protocolFeeRecipient;
        _sendExact(recipient, amount);
        _assertSolvent();
        emit ProtocolFeeSent(recipient, amount, msg.sender);
    }

    function sendTax(uint256 amount) external nonReentrant {
        if (amount == 0 || amount > taxOwed) revert InvalidAmount();
        taxOwed -= amount;
        address recipient = settings.taxRecipient;
        _sendExact(recipient, amount);
        _assertSolvent();
        emit TaxSent(recipient, amount, msg.sender);
    }

    // --------------------------------------------------------------------------------
    // Rounds
    // --------------------------------------------------------------------------------

    /// @notice Commits one snapshot and requests randomness for it in the same transaction.
    /// @dev The prize is reserved here, before any seed exists.
    function commitRound(
        uint64 roundId,
        uint64 snapshotBlock,
        bytes32 snapshotBlockHash,
        bytes32 rootHash,
        uint256 totalTickets
    ) external onlyAttestor nonReentrant returns (uint256 prize) {
        if (subject == address(0)) revert SubjectNotBound();
        if (roundId != latestRoundId + 1) revert InvalidRound();
        if (snapshotBlock <= latestSnapshotBlock) revert InvalidSnapshot();
        if (rootHash == bytes32(0) || totalTickets == 0) revert InvalidRoot();
        if (pendingRounds >= MAX_PENDING_ROUNDS) revert TooManyPendingRounds();
        // The cadence is measured from the previous commitment; the first round is not gated.
        // Second-level sequencer drift cannot shorten an hour-scale window materially.
        if (lastCommitAt != 0) {
            // forge-lint: disable-next-line(block-timestamp)
            if (block.timestamp < uint256(lastCommitAt) + settings.minRoundInterval) {
                revert RoundTooSoon();
            }
        }

        uint256 currentL2Block = IArbSys(ARBSYS).arbBlockNumber();
        if (currentL2Block < uint256(snapshotBlock) + settings.minConfirmations) {
            revert InvalidSnapshot();
        }
        if (currentL2Block > uint256(snapshotBlock) + 255) revert InvalidSnapshot();
        if (IArbSys(ARBSYS).arbBlockHash(snapshotBlock) != snapshotBlockHash) {
            revert InvalidSnapshot();
        }

        prize = _prizeFor(availablePool);
        if (prize < settings.minPrize) revert PrizeBelowFloor();

        availablePool -= prize;
        totalReserved += prize;
        latestRoundId = roundId;
        latestSnapshotBlock = snapshotBlock;
        // forge-lint: disable-next-line(unsafe-typecast)
        lastCommitAt = uint64(block.timestamp);
        pendingRounds += 1;

        bytes32 requestId = ISinjohRaffleRandomness(settings.randomness).requestRandomness(roundId);
        if (requestId == bytes32(0) || roundOfRequest[requestId] != 0) revert InvalidRequest();
        roundOfRequest[requestId] = roundId;

        RaffleTypes.Round storage round = rounds[roundId];
        round.rootHash = rootHash;
        round.requestId = requestId;
        round.totalTickets = totalTickets;
        round.prize = prize;
        round.snapshotBlock = snapshotBlock;
        // forge-lint: disable-next-line(unsafe-typecast)
        round.committedAt = uint64(block.timestamp);
        round.state = RaffleTypes.RoundState.COMMITTED;

        _assertSolvent();
        emit RoundCommitted(
            roundId, snapshotBlock, snapshotBlockHash, rootHash, totalTickets, prize, requestId
        );
    }

    /// @notice Randomness delivery. Performs no transfer and calls nothing external.
    function receiveRandomness(bytes32 requestId, uint256 seed) external {
        if (msg.sender != settings.randomness) revert Unauthorized();
        if (seed == 0) revert InvalidSeed();
        uint64 roundId = roundOfRequest[requestId];
        if (roundId == 0) revert InvalidRequest();

        RaffleTypes.Round storage round = rounds[roundId];
        if (round.state != RaffleTypes.RoundState.COMMITTED) revert InvalidRound();

        round.seed = seed;
        // forge-lint: disable-next-line(unsafe-typecast)
        round.drawnAt = uint64(block.timestamp);
        round.state = RaffleTypes.RoundState.DRAWN;
        pendingRounds -= 1;

        emit RandomnessReceived(roundId, requestId, seed);
    }

    /// @notice Pays one slot to the holder whose committed ticket interval contains its index.
    function claim(
        uint64 roundId,
        uint8 slot,
        RaffleTypes.Leaf calldata leaf,
        RaffleTypes.ProofElement[] calldata proof
    ) external nonReentrant returns (uint256 paid) {
        RaffleTypes.Round storage round = rounds[roundId];
        if (round.state != RaffleTypes.RoundState.DRAWN) revert InvalidRound();
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp > uint256(round.drawnAt) + settings.claimWindow) {
            revert ClaimWindowClosed();
        }

        uint8 winners = settings.winnersPerRound;
        if (slot >= winners) revert InvalidSlot();
        uint16 mask = round.slotsPaidMask;
        // forge-lint: disable-next-line(unsafe-typecast)
        uint16 bit = uint16(uint256(1) << slot);
        if (mask & bit != 0) revert SlotAlreadyPaid();
        if (leaf.tickets == 0) revert InvalidProof();
        if (isExcluded[leaf.holder]) revert ExcludedHolder();
        if (proof.length > MAX_PROOF_LENGTH) revert InvalidProof();

        (bool valid, uint256 offset) =
            _verify(roundId, round.snapshotBlock, round.rootHash, round.totalTickets, leaf, proof);
        if (!valid) revert InvalidProof();

        uint256 index = winningIndex(roundId, slot);
        if (index < offset || index >= offset + leaf.tickets) revert NotWinningLeaf();

        round.slotsPaidMask = mask | bit;
        uint256 share = _slotPrize(round.prize, winners, slot);
        round.paidTotal += share;
        if (round.paidTotal > round.prize) revert InvariantViolation();
        if (round.slotsPaidMask == _fullMask(winners)) {
            round.state = RaffleTypes.RoundState.SETTLED;
        }

        totalReserved -= share;
        // Each share is floored independently, so neither can round into the other and any
        // rounding dust stays with the winner.
        uint256 recipientTax = (share * settings.recipientTaxBps) / BPS;
        uint256 recycleTax = (share * settings.recycleTaxBps) / BPS;
        uint256 net = share - recipientTax - recycleTax;
        if (recipientTax != 0) taxOwed += recipientTax;
        if (recycleTax != 0) availablePool += recycleTax;

        if (net != 0) {
            try this.payWinner(leaf.holder, net) {
                paid = net;
                emit PrizePaid(roundId, slot, leaf.holder, share, recipientTax, recycleTax, net);
            } catch (bytes memory reason) {
                owed[leaf.holder] += net;
                totalOwed += net;
                emit PaymentDeferred(roundId, slot, leaf.holder, net, reason);
            }
        } else {
            emit PrizePaid(roundId, slot, leaf.holder, share, recipientTax, recycleTax, 0);
        }

        _assertSolvent();
    }

    /// @dev Isolated so a reverting winner cannot roll back an already-settled slot.
    function payWinner(address holder, uint256 amount) external {
        if (msg.sender != address(this)) revert OnlySelf();
        _sendExact(holder, amount);
    }

    /// @notice Delivers value that a winner's transfer previously rejected. Retryable forever.
    function deliverOwed(address holder) external nonReentrant returns (uint256 amount) {
        amount = owed[holder];
        if (amount == 0) revert NothingOwed();
        owed[holder] = 0;
        totalOwed -= amount;
        _sendExact(holder, amount);
        _assertSolvent();
        emit OwedDelivered(holder, amount, msg.sender);
    }

    /// @notice Returns an unclaimed reserve to the pool once the claim window closes.
    function expireRound(uint64 roundId) external nonReentrant returns (uint256 returned) {
        RaffleTypes.Round storage round = rounds[roundId];
        if (round.state != RaffleTypes.RoundState.DRAWN) revert InvalidRound();
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp <= uint256(round.drawnAt) + settings.claimWindow) {
            revert ClaimWindowOpen();
        }

        returned = round.prize - round.paidTotal;
        round.state = RaffleTypes.RoundState.EXPIRED;
        if (returned != 0) {
            totalReserved -= returned;
            availablePool += returned;
        }
        emit RoundExpired(roundId, returned);
    }

    /// @notice Returns a reserve to the pool when randomness never arrived.
    /// @dev The round is closed permanently: no snapshot can ever be re-rolled.
    function abandonRound(uint64 roundId) external nonReentrant returns (uint256 returned) {
        RaffleTypes.Round storage round = rounds[roundId];
        if (round.state != RaffleTypes.RoundState.COMMITTED) revert InvalidRound();
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp <= uint256(round.committedAt) + settings.randomnessTimeout) {
            revert RandomnessPending();
        }

        returned = round.prize;
        round.state = RaffleTypes.RoundState.ABANDONED;
        pendingRounds -= 1;
        if (returned != 0) {
            totalReserved -= returned;
            availablePool += returned;
        }
        emit RoundAbandoned(roundId, returned);
    }

    // --------------------------------------------------------------------------------
    // Views
    // --------------------------------------------------------------------------------

    function winningIndex(uint64 roundId, uint8 slot) public view returns (uint256) {
        RaffleTypes.Round storage round = rounds[roundId];
        uint256 seed = round.seed;
        if (seed == 0) revert RandomnessPending();
        return uint256(
            keccak256(abi.encode(SLOT_DOMAIN, block.chainid, address(this), roundId, slot, seed))
        ) % round.totalTickets;
    }

    function leafHash(uint64 roundId, uint64 snapshotBlock, address holder, uint256 tickets)
        public
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                LEAF_DOMAIN, block.chainid, address(this), roundId, snapshotBlock, holder, tickets
            )
        );
    }

    function nodeHash(bytes32 leftHash, uint256 leftSum, bytes32 rightHash, uint256 rightSum)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(NODE_DOMAIN, leftHash, leftSum, rightHash, rightSum));
    }

    function emptyLeafHash(uint64 roundId) public pure returns (bytes32) {
        return keccak256(abi.encode(EMPTY_DOMAIN, roundId));
    }

    /// @notice Verifies a proof and returns the leaf's derived ticket-interval start.
    function verify(
        uint64 roundId,
        RaffleTypes.Leaf calldata leaf,
        RaffleTypes.ProofElement[] calldata proof
    ) external view returns (bool valid, uint256 offset) {
        RaffleTypes.Round storage round = rounds[roundId];
        return
            _verify(roundId, round.snapshotBlock, round.rootHash, round.totalTickets, leaf, proof);
    }

    function slotPrize(uint64 roundId, uint8 slot) external view returns (uint256) {
        return _slotPrize(rounds[roundId].prize, settings.winnersPerRound, slot);
    }

    /// @notice Total payout tax in basis points: the recipient share plus the recycled share.
    function payoutTaxBps() external view returns (uint256) {
        return uint256(settings.recipientTaxBps) + settings.recycleTaxBps;
    }

    function nextPrize() external view returns (uint256) {
        return _prizeFor(availablePool);
    }

    function liabilities() external view returns (uint256) {
        return _liabilities();
    }

    function ticketsFor(uint256 weight) external view returns (uint256 tickets) {
        tickets = weight / settings.tokensPerTicket;
        uint256 cap = settings.maxTicketsPerHolder;
        if (cap != 0 && tickets > cap) tickets = cap;
    }

    // --------------------------------------------------------------------------------
    // Internal
    // --------------------------------------------------------------------------------

    function _validate(RaffleTypes.Config calldata config) private pure {
        if (
            config.creator == address(0) || config.attestor == address(0)
                || config.randomness == address(0) || config.protocolFeeRecipient == address(0)
        ) revert InvalidAddress();
        if (config.recipientTaxBps != 0 && config.taxRecipient == address(0)) {
            revert InvalidAddress();
        }
        if (config.tokensPerTicket == 0) revert InvalidConfiguration();
        if (config.prizeBps == 0 || config.prizeBps > BPS) revert InvalidConfiguration();
        if (uint256(config.recipientTaxBps) + config.recycleTaxBps > MAX_PAYOUT_TAX_BPS) {
            revert InvalidConfiguration();
        }
        if (config.minPrize == 0) revert InvalidConfiguration();
        if (config.maxPrize != 0 && config.maxPrize < config.minPrize) {
            revert InvalidConfiguration();
        }
        if (config.winnersPerRound == 0 || config.winnersPerRound > MAX_WINNERS_PER_ROUND) {
            revert InvalidConfiguration();
        }
        if (
            config.minRoundInterval < MIN_ROUND_INTERVAL
                || config.minRoundInterval > MAX_ROUND_INTERVAL
        ) revert InvalidConfiguration();
        if (config.minConfirmations == 0 || config.minConfirmations > 255) {
            revert InvalidConfiguration();
        }
        if (config.basis == RaffleTypes.TicketBasis.SNAPSHOT) {
            if (config.weightWindowBlocks != 0) revert InvalidConfiguration();
        } else if (
            config.weightWindowBlocks == 0 || config.weightWindowBlocks > MAX_WEIGHT_WINDOW_BLOCKS
        ) {
            revert InvalidConfiguration();
        }
        if (
            config.randomnessTimeout < MIN_RANDOMNESS_TIMEOUT
                || config.randomnessTimeout > MAX_RANDOMNESS_TIMEOUT
        ) revert InvalidConfiguration();
        if (config.claimWindow < MIN_CLAIM_WINDOW || config.claimWindow > MAX_CLAIM_WINDOW) {
            revert InvalidConfiguration();
        }

        uint256 exclusionLength = config.exclusions.length;
        if (exclusionLength > MAX_EXCLUSIONS) revert InvalidConfiguration();
        address previous;
        for (uint256 i; i < exclusionLength; ++i) {
            address excluded = config.exclusions[i];
            if (excluded == address(0) || excluded <= previous) revert InvalidConfiguration();
            previous = excluded;
        }
    }

    function _credit(uint256 gross) private returns (uint256 fee, uint256 net) {
        uint16 remainder = _feeRemainder;
        uint256 scaledRemainder = (gross % BPS) * PROTOCOL_FEE_BPS + remainder;
        // Quotient/remainder decomposition avoids overflow without losing precision.
        // forge-lint: disable-next-line(divide-before-multiply)
        fee = (gross / BPS) * PROTOCOL_FEE_BPS + scaledRemainder / BPS;
        // The modulo result is strictly below BPS and therefore fits uint16.
        // forge-lint: disable-next-line(unsafe-typecast)
        _feeRemainder = uint16(scaledRemainder % BPS);

        net = gross - fee;
        protocolOwed += fee;
        availablePool += net;
        totalIntake += gross;
    }

    function _prizeFor(uint256 pool) private view returns (uint256 prize) {
        prize = (pool * settings.prizeBps) / BPS;
        uint256 cap = settings.maxPrize;
        if (cap != 0 && prize > cap) prize = cap;
    }

    function _slotPrize(uint256 prize, uint8 winners, uint8 slot) private pure returns (uint256) {
        uint256 base = prize / winners;
        return slot == 0 ? base + (prize % winners) : base;
    }

    function _fullMask(uint8 winners) private pure returns (uint16) {
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint16((uint256(1) << winners) - 1);
    }

    function _verify(
        uint64 roundId,
        uint64 snapshotBlock,
        bytes32 rootHash,
        uint256 totalTickets,
        RaffleTypes.Leaf calldata leaf,
        RaffleTypes.ProofElement[] calldata proof
    ) private view returns (bool valid, uint256 offset) {
        if (rootHash == bytes32(0)) return (false, 0);
        bytes32 hash = leafHash(roundId, snapshotBlock, leaf.holder, leaf.tickets);
        uint256 sum = leaf.tickets;
        uint256 proofLength = proof.length;
        for (uint256 i; i < proofLength; ++i) {
            RaffleTypes.ProofElement calldata element = proof[i];
            if (element.siblingIsLeft) {
                hash = nodeHash(element.siblingHash, element.siblingSum, hash, sum);
                offset += element.siblingSum;
            } else {
                hash = nodeHash(hash, sum, element.siblingHash, element.siblingSum);
            }
            sum += element.siblingSum;
        }
        valid = hash == rootHash && sum == totalTickets;
        if (!valid) offset = 0;
    }

    function _balance() private view returns (uint256) {
        address prizeAsset = settings.prizeAsset;
        return
            prizeAsset == address(0)
                ? address(this).balance
                : prizeAsset.safeBalanceOf(address(this));
    }

    function _liabilities() private view returns (uint256) {
        return availablePool + totalReserved + totalOwed + protocolOwed + taxOwed;
    }

    function _sendExact(address recipient, uint256 amount) private {
        address prizeAsset = settings.prizeAsset;
        uint256 beforeBalance = _balance();
        if (prizeAsset == address(0)) {
            SafeTransferLib.safeTransferETH(recipient, amount);
        } else {
            uint256 recipientBefore = prizeAsset.safeBalanceOf(recipient);
            prizeAsset.safeTransfer(recipient, amount);
            uint256 recipientAfter = prizeAsset.safeBalanceOf(recipient);
            uint256 received =
                recipientAfter >= recipientBefore ? recipientAfter - recipientBefore : 0;
            if (received != amount) revert UnexpectedBalanceDelta(amount, received);
        }
        uint256 afterBalance = _balance();
        uint256 spent = beforeBalance >= afterBalance ? beforeBalance - afterBalance : 0;
        if (spent != amount) revert UnexpectedBalanceDelta(amount, spent);
    }

    function _assertSolvent() private view {
        if (_balance() < _liabilities()) revert Insolvent();
    }
}
