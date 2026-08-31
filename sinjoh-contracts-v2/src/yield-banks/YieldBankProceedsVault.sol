// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { CollectionPortfolioAllocator } from "./CollectionPortfolioAllocator.sol";

interface IYieldBankWETH is IERC20 {
    function deposit() external payable;
}

interface IYieldBankCollectionPrimaryNotify {
    function notifyOperationsPrimary(uint256 amount) external;
}

/// @notice Collection-specific native-proceeds holding contract with manual allocation only.
contract YieldBankProceedsVault is ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint16 public constant BPS = 10_000;
    uint256 public constant MAX_RECEIPTS_PER_ALLOCATION = 20;
    uint256 public constant MAX_TOKENS_PER_ALLOCATION = 100;
    uint8 public constant PRIMARY_NONE = 0;
    uint8 public constant PRIMARY_PENDING = 1;
    uint8 public constant PRIMARY_ALLOCATED = 2;
    uint8 public constant PRIMARY_CLAIMED = 3;
    uint8 public constant PRIMARY_RELEASED = 4;

    struct PendingMint {
        uint256 firstTokenId;
        uint256 quantity;
    }

    struct Receipt {
        uint256 firstTokenId;
        uint256 quantity;
        uint256 netProceeds;
        uint256 backingRemaining;
        uint256 creatorFee;
        uint256 sinjohFee;
        uint256 operationsFee;
        bool allocated;
    }

    address public immutable collection;
    address public immutable nft;
    address public immutable seaDrop;
    address public immutable creator;
    address public immutable sinjohFeeRecipient;
    address public immutable operationsReserve;
    address public immutable allocator;
    address public immutable timelock;
    address public immutable guardian;
    uint16 public immutable primaryBackingBps;
    uint16 public immutable primaryCreatorBps;
    uint16 public immutable primarySinjohBps;
    uint16 public immutable primaryOperationsBps;
    IYieldBankWETH public immutable weth;
    address[3] public sleeves;

    address public allocationOperator;
    bool public allocationPaused;
    uint256 public receiptCount;
    uint256 public accountedNative;
    uint256 public totalNetProceeds;
    uint256 public totalAllocatedBacking;
    uint256 public totalPendingBacking;
    PendingMint public pendingMint;
    mapping(uint256 => Receipt) public receipts;
    mapping(uint256 => uint256) public receiptOfToken;
    mapping(uint256 => uint256) public pendingBackingOf;
    mapping(uint256 => uint8) public primaryStateOf;
    mapping(uint256 => mapping(address => uint256)) public claimableShares;

    error OnlyCollection(address caller);
    error OnlySeaDrop(address caller);
    error OnlyOperator(address caller);
    error OnlyTimelock(address caller);
    error OnlyGuardian(address caller);
    error InvalidConfiguration();
    error PendingMintExists();
    error NoPendingMint();
    error AllocationIsPaused();
    error InvalidReceipt(uint256 receiptId);
    error InvalidRange(uint256 firstReceiptId, uint256 lastReceiptId);
    error NativeTransferFailed(address recipient, uint256 amount);

    event MintReceiptNoted(uint256 indexed firstTokenId, uint256 quantity);
    event PrimaryProceedsReceived(
        uint256 indexed receiptId,
        uint256 indexed firstTokenId,
        uint256 quantity,
        uint256 netProceeds,
        uint256 backing
    );
    event PrimaryAllocated(
        uint256 indexed firstReceiptId,
        uint256 indexed lastReceiptId,
        uint256 backing,
        uint256 coreShares,
        uint256 marketMakingShares,
        uint256 usdgShares
    );
    event PrimaryFeesReleased(
        uint256 indexed firstReceiptId,
        uint256 indexed lastReceiptId,
        uint256 creatorFee,
        uint256 sinjohFee,
        uint256 operationsFee
    );
    event PrimaryClaimed(
        uint256 indexed tokenId,
        address indexed account,
        uint256 coreShares,
        uint256 marketMakingShares,
        uint256 usdgShares
    );
    event PendingBackingReleased(
        uint256 indexed tokenId, address indexed recipient, uint256 amount
    );
    event AllocationOperatorChanged(address indexed previousOperator, address indexed newOperator);
    event AllocationPauseChanged(bool paused);
    event ExcessNativeSwept(address indexed recipient, uint256 amount);

    constructor(
        address collection_,
        address nft_,
        address seaDrop_,
        address creator_,
        address sinjohFeeRecipient_,
        address operationsReserve_,
        address allocator_,
        address operator_,
        address timelock_,
        address guardian_,
        address weth_,
        address[3] memory sleeves_,
        uint16 primaryBackingBps_,
        uint16 primaryCreatorBps_,
        uint16 primarySinjohBps_,
        uint16 primaryOperationsBps_
    ) {
        if (
            collection_ == address(0) || nft_ == address(0) || seaDrop_.code.length == 0
                || creator_ == address(0) || sinjohFeeRecipient_ == address(0)
                || operationsReserve_ == address(0) || allocator_.code.length == 0
                || operator_ == address(0) || timelock_.code.length == 0 || guardian_ == address(0)
                || weth_.code.length == 0 || sleeves_[0].code.length == 0
                || sleeves_[1].code.length == 0 || sleeves_[2].code.length == 0
                || primaryBackingBps_ == 0
                || uint256(primaryBackingBps_) + primaryCreatorBps_ + primarySinjohBps_
                        + primaryOperationsBps_ != BPS
        ) revert InvalidConfiguration();
        collection = collection_;
        nft = nft_;
        seaDrop = seaDrop_;
        creator = creator_;
        sinjohFeeRecipient = sinjohFeeRecipient_;
        operationsReserve = operationsReserve_;
        allocator = allocator_;
        allocationOperator = operator_;
        timelock = timelock_;
        guardian = guardian_;
        primaryBackingBps = primaryBackingBps_;
        primaryCreatorBps = primaryCreatorBps_;
        primarySinjohBps = primarySinjohBps_;
        primaryOperationsBps = primaryOperationsBps_;
        weth = IYieldBankWETH(weth_);
        sleeves = sleeves_;
    }

    modifier onlyCollection() {
        if (msg.sender != collection) revert OnlyCollection(msg.sender);
        _;
    }

    function noteMint(uint256 firstTokenId, uint256 quantity) external onlyCollection {
        if (pendingMint.quantity != 0) revert PendingMintExists();
        if (firstTokenId == 0 || quantity == 0) revert InvalidConfiguration();
        pendingMint = PendingMint(firstTokenId, quantity);
        emit MintReceiptNoted(firstTokenId, quantity);
    }

    receive() external payable {
        if (msg.sender != seaDrop) revert OnlySeaDrop(msg.sender);
        PendingMint memory note = pendingMint;
        if (note.quantity == 0) revert NoPendingMint();
        if (msg.value == 0) revert InvalidConfiguration();
        delete pendingMint;
        uint256 backing = Math.mulDiv(msg.value, primaryBackingBps, BPS);
        uint256 creatorCumulative =
            Math.mulDiv(msg.value, uint256(primaryBackingBps) + primaryCreatorBps, BPS);
        uint256 creatorFee = creatorCumulative - backing;
        uint256 sinjohCumulative = Math.mulDiv(
            msg.value, uint256(primaryBackingBps) + primaryCreatorBps + primarySinjohBps, BPS
        );
        uint256 sinjohFee = sinjohCumulative - creatorCumulative;
        uint256 operationsFee = msg.value - backing - creatorFee - sinjohFee;
        uint256 receiptId = ++receiptCount;
        receipts[receiptId] = Receipt(
            note.firstTokenId,
            note.quantity,
            msg.value,
            backing,
            creatorFee,
            sinjohFee,
            operationsFee,
            false
        );
        uint256 assigned;
        for (uint256 i; i < note.quantity; ++i) {
            uint256 cumulative = Math.mulDiv(backing, i + 1, note.quantity);
            uint256 tokenBacking = cumulative - assigned;
            assigned = cumulative;
            uint256 tokenId = note.firstTokenId + i;
            receiptOfToken[tokenId] = receiptId;
            pendingBackingOf[tokenId] = tokenBacking;
            primaryStateOf[tokenId] = PRIMARY_PENDING;
        }
        accountedNative += msg.value;
        totalNetProceeds += msg.value;
        totalPendingBacking += backing;
        emit PrimaryProceedsReceived(
            receiptId, note.firstTokenId, note.quantity, msg.value, backing
        );
    }

    function allocateReceipts(
        uint256 firstReceiptId,
        uint256 lastReceiptId,
        CollectionPortfolioAllocator.AllocationCall[3] calldata calls
    ) external nonReentrant {
        if (msg.sender != allocationOperator) {
            revert OnlyOperator(msg.sender);
        }
        if (allocationPaused) revert AllocationIsPaused();
        if (
            firstReceiptId == 0 || lastReceiptId < firstReceiptId
                || lastReceiptId - firstReceiptId + 1 > MAX_RECEIPTS_PER_ALLOCATION
        ) revert InvalidRange(firstReceiptId, lastReceiptId);
        uint256 backing;
        uint256 creatorFees;
        uint256 sinjohFees;
        uint256 operationsFees;
        uint256 tokenCount;
        for (uint256 id = firstReceiptId; id <= lastReceiptId; ++id) {
            Receipt storage receipt = receipts[id];
            if (receipt.netProceeds == 0 || receipt.allocated) revert InvalidReceipt(id);
            receipt.allocated = true;
            backing += receipt.backingRemaining;
            creatorFees += receipt.creatorFee;
            sinjohFees += receipt.sinjohFee;
            operationsFees += receipt.operationsFee;
            tokenCount += receipt.quantity;
        }
        if (tokenCount > MAX_TOKENS_PER_ALLOCATION) {
            revert InvalidRange(firstReceiptId, lastReceiptId);
        }
        accountedNative -= backing + creatorFees + sinjohFees + operationsFees;
        _sendNative(creator, creatorFees);
        _sendNative(sinjohFeeRecipient, sinjohFees);
        _sendNative(operationsReserve, operationsFees);
        if (operationsFees != 0) {
            if (operationsReserve.code.length != 0) {
                IYieldBankCollectionPrimaryNotify(collection)
                    .notifyOperationsPrimary(operationsFees);
            }
        }
        emit PrimaryFeesReleased(
            firstReceiptId, lastReceiptId, creatorFees, sinjohFees, operationsFees
        );
        uint256[3] memory shares;
        if (backing != 0) {
            weth.deposit{ value: backing }();
            IERC20(address(weth)).forceApprove(allocator, backing);
            (address[] memory assets, uint256[] memory amounts) = CollectionPortfolioAllocator(
                    allocator
                ).allocatePrimary(address(weth), backing, address(this), calls);
            IERC20(address(weth)).forceApprove(allocator, 0);
            if (assets.length != 3 || amounts.length != 3) revert InvalidConfiguration();
            for (uint256 i; i < 3; ++i) {
                if (assets[i] != sleeves[i]) revert InvalidConfiguration();
                shares[i] = amounts[i];
            }
            totalAllocatedBacking += backing;
            totalPendingBacking -= backing;
        }
        _recordClaims(firstReceiptId, lastReceiptId, backing, shares);
        emit PrimaryAllocated(
            firstReceiptId, lastReceiptId, backing, shares[0], shares[1], shares[2]
        );
    }

    function claim(uint256 tokenId, address account)
        external
        onlyCollection
        nonReentrant
        returns (address[3] memory assets, uint256[3] memory amounts)
    {
        if (account == address(0)) revert InvalidConfiguration();
        if (primaryStateOf[tokenId] != PRIMARY_ALLOCATED) {
            revert InvalidReceipt(receiptOfToken[tokenId]);
        }
        primaryStateOf[tokenId] = PRIMARY_CLAIMED;
        assets = sleeves;
        for (uint256 i; i < 3; ++i) {
            amounts[i] = claimableShares[tokenId][assets[i]];
            if (amounts[i] != 0) {
                delete claimableShares[tokenId][assets[i]];
                IERC20(assets[i]).safeTransfer(account, amounts[i]);
            }
        }
        emit PrimaryClaimed(tokenId, account, amounts[0], amounts[1], amounts[2]);
    }

    function releasePendingBacking(uint256 tokenId, address recipient)
        external
        onlyCollection
        nonReentrant
        returns (uint256 amount)
    {
        amount = pendingBackingOf[tokenId];
        uint256 receiptId = receiptOfToken[tokenId];
        if (
            primaryStateOf[tokenId] != PRIMARY_PENDING || receiptId == 0
                || receipts[receiptId].allocated || recipient == address(0)
        ) {
            revert InvalidReceipt(receiptId);
        }
        primaryStateOf[tokenId] = PRIMARY_RELEASED;
        delete pendingBackingOf[tokenId];
        receipts[receiptId].backingRemaining -= amount;
        totalPendingBacking -= amount;
        accountedNative -= amount;
        if (amount != 0) {
            weth.deposit{ value: amount }();
            IERC20(address(weth)).safeTransfer(recipient, amount);
        }
        emit PendingBackingReleased(tokenId, recipient, amount);
    }

    function setAllocationOperator(address value) external {
        if (msg.sender != timelock) revert OnlyTimelock(msg.sender);
        if (value == address(0)) revert InvalidConfiguration();
        address previous = allocationOperator;
        allocationOperator = value;
        emit AllocationOperatorChanged(previous, value);
    }

    function pauseAllocations() external {
        if (msg.sender != guardian) revert OnlyGuardian(msg.sender);
        allocationPaused = true;
        emit AllocationPauseChanged(true);
    }

    function resumeAllocations() external {
        if (msg.sender != timelock) revert OnlyTimelock(msg.sender);
        allocationPaused = false;
        emit AllocationPauseChanged(false);
    }

    function pauseFromCollection() external onlyCollection {
        allocationPaused = true;
        emit AllocationPauseChanged(true);
    }

    function resumeFromCollection() external onlyCollection {
        allocationPaused = false;
        emit AllocationPauseChanged(false);
    }

    function excessNative() public view returns (uint256) {
        return address(this).balance - accountedNative;
    }

    function sweepExcessNative(address recipient) external nonReentrant returns (uint256 amount) {
        if (msg.sender != timelock) revert OnlyTimelock(msg.sender);
        if (recipient == address(0)) revert InvalidConfiguration();
        amount = excessNative();
        _sendNative(recipient, amount);
        emit ExcessNativeSwept(recipient, amount);
    }

    function _recordClaims(
        uint256 firstId,
        uint256 lastId,
        uint256 backing,
        uint256[3] memory shares
    ) private {
        uint256 cumulativeWeight;
        uint256[3] memory assigned;
        for (uint256 id = firstId; id <= lastId; ++id) {
            Receipt storage receipt = receipts[id];
            for (uint256 i; i < receipt.quantity; ++i) {
                uint256 tokenId = receipt.firstTokenId + i;
                uint8 primaryState = primaryStateOf[tokenId];
                if (primaryState == PRIMARY_RELEASED) continue;
                if (primaryState != PRIMARY_PENDING) revert InvalidReceipt(id);
                uint256 weight = pendingBackingOf[tokenId];
                if (weight != 0) {
                    cumulativeWeight += weight;
                    for (uint256 sleeveIndex; sleeveIndex < 3; ++sleeveIndex) {
                        uint256 cumulativeShares =
                            Math.mulDiv(shares[sleeveIndex], cumulativeWeight, backing);
                        claimableShares[tokenId][sleeves[sleeveIndex]] =
                            cumulativeShares - assigned[sleeveIndex];
                        assigned[sleeveIndex] = cumulativeShares;
                    }
                }
                primaryStateOf[tokenId] = PRIMARY_ALLOCATED;
                delete pendingBackingOf[tokenId];
            }
            receipt.backingRemaining = 0;
        }
    }

    function _sendNative(address recipient, uint256 amount) private {
        if (amount == 0) return;
        (bool ok,) = payable(recipient).call{ value: amount }("");
        if (!ok) revert NativeTransferFailed(recipient, amount);
    }
}
