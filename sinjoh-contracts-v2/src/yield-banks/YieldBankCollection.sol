// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import {
    YieldBankCollectionState,
    YieldBankConfig,
    YieldBankTokenState
} from "./YieldBankTypes.sol";
import { IYieldBankEligibilityPolicy } from "./interfaces/IYieldBankEligibilityPolicy.sol";
import { YieldBankAccount } from "./YieldBankAccount.sol";
import { YieldBankDistributor } from "./YieldBankDistributor.sol";
import { YieldBankNFT } from "./YieldBankNFT.sol";
import { YieldBankProceedsVault } from "./YieldBankProceedsVault.sol";

interface IYieldBankRevenueEconomics {
    function primaryBackingBps() external view returns (uint16);
    function primaryCreatorBps() external view returns (uint16);
    function primarySinjohBps() external view returns (uint16);
}

interface IYieldBankBurnableToken is IERC20 {
    function burnFrom(address account, uint256 amount) external;
}

interface IYieldBankPortfolioEconomics {
    function coreWeightBps() external view returns (uint16);
    function marketMakingWeightBps() external view returns (uint16);
    function usdgWeightBps() external view returns (uint16);
    function activeDeltaPoolOf(uint256 tokenId) external view returns (address);
    function isDeltaPoolSleeve(address sleeve) external view returns (bool);
    function deltaPoolController() external view returns (address);
}

/// @notice Coordinator for one configurable-supply Yield Banks collection.
contract YieldBankCollection is ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant MAX_SETTLE_BATCH = 20;
    uint16 public constant BPS = 10_000;
    uint16 public constant EXIT_TAX_BPS = 500;

    bytes32 public immutable collectionId;
    uint256 public immutable maxSupply;
    uint96 public immutable secondaryRoyaltyBps;
    uint16 public immutable primaryBackingBps;
    uint16 public immutable primaryCreatorBps;
    uint16 public immutable primarySinjohBps;
    uint16 public immutable coreWeightBps;
    uint16 public immutable marketMakingWeightBps;
    uint16 public immutable usdgWeightBps;
    address public immutable creator;
    address public immutable openSeaManager;
    address public immutable sinjohFeeRecipient;
    IYieldBankBurnableToken public immutable redemptionToken;
    uint256 public immutable redemptionTokenAmount;
    bytes32 public immutable redemptionTokenCodeHash;
    address public immutable revenueRouter;
    IYieldBankEligibilityPolicy public immutable eligibilityPolicy;
    address public immutable portfolioAllocator;
    address public immutable collectionTimelock;
    address public immutable guardian;
    IERC20 public immutable weth;
    address public immutable seaDrop;
    address public immutable accountImplementation;
    bytes32 public immutable integrationBindingHash;
    YieldBankNFT public immutable nft;
    YieldBankDistributor public immutable distributor;
    YieldBankProceedsVault public immutable proceedsVault;

    YieldBankCollectionState public state;
    uint256 public mintedSupply;
    uint256 public liveSupply;
    mapping(uint256 => address) public accountOf;
    mapping(uint256 => YieldBankTokenState) private _tokenStates;
    mapping(address => bool) public isSleeveAsset;

    error InvalidConfiguration();
    error InvalidState(YieldBankCollectionState current);
    error InvalidTokenState(uint256 tokenId, YieldBankTokenState current);
    error Ineligible(address account);
    error OnlyNFT(address caller);
    error OnlyProceedsVault(address caller);
    error OnlyRevenueRouter(address caller);
    error OnlyGuardian(address caller);
    error OnlyTimelock(address caller);
    error InvalidTokenOwner(uint256 tokenId, address caller);
    error InvalidBatchSize(uint256 supplied);
    error PrimaryPayoutPending();
    error InvalidSleeveAsset(address asset);
    error OnlyDeltaPoolController(address caller);
    error ActiveDeltaPositionRequiresRebalance(uint256 tokenId, address pool);
    error RedemptionTokenBurnMismatch(
        uint256 expected, uint256 balanceBurned, uint256 supplyBurned
    );

    event CollectionStateChanged(
        YieldBankCollectionState indexed previousState, YieldBankCollectionState indexed newState
    );
    event CollectionComponents(
        bytes32 indexed collectionId,
        address indexed nft,
        address indexed proceedsVault,
        address distributor,
        address accountImplementation
    );
    event YieldBankMinted(uint256 indexed tokenId, address indexed owner, address indexed account);
    event DistributionSettled(uint256 indexed tokenId, address indexed account);
    event PrimarySharesClaimed(uint256 indexed tokenId, address indexed account);
    event YieldBankRedeemed(
        uint256 indexed tokenId, address indexed beneficiary, bool terminal, uint256 pendingBacking
    );
    event DistributionAssetRegistered(address indexed asset);
    event DynamicSleeveRegistered(address indexed sleeve);
    event RedemptionTokenBurned(
        uint256 indexed tokenId, address indexed owner, address indexed token, uint256 amount
    );

    constructor(YieldBankConfig memory config) {
        _validateConfig(config);
        collectionId = config.collectionId;
        maxSupply = config.maxSupply;
        secondaryRoyaltyBps = config.secondaryRoyaltyBps;
        primaryBackingBps = config.primaryBackingBps;
        primaryCreatorBps = config.primaryCreatorBps;
        primarySinjohBps = config.primarySinjohBps;
        coreWeightBps = config.coreWeightBps;
        marketMakingWeightBps = config.marketMakingWeightBps;
        usdgWeightBps = config.usdgWeightBps;
        creator = config.creator;
        openSeaManager = config.openSeaManager;
        sinjohFeeRecipient = config.sinjohFeeRecipient;
        redemptionToken = IYieldBankBurnableToken(config.redemptionToken);
        redemptionTokenAmount = config.redemptionTokenAmount;
        redemptionTokenCodeHash = config.redemptionTokenCodeHash;
        revenueRouter = config.revenueRouter;
        eligibilityPolicy = IYieldBankEligibilityPolicy(config.eligibilityPolicy);
        portfolioAllocator = config.portfolioAllocator;
        collectionTimelock = config.collectionTimelock;
        guardian = config.guardian;
        weth = IERC20(config.weth);
        seaDrop = config.seaDrop;
        integrationBindingHash = keccak256(abi.encode(config));

        YieldBankDistributor distributor_ = new YieldBankDistributor(address(this));
        distributor = distributor_;
        YieldBankNFT nft_ = new YieldBankNFT(
            address(this),
            config.openSeaManager,
            config.revenueRouter,
            config.renderer,
            config.seaDrop,
            config.maxSupply,
            config.secondaryRoyaltyBps
        );
        nft = nft_;
        accountImplementation = config.accountImplementation;
        address[3] memory sleeveList =
            [config.coreSleeve, config.marketMakingSleeve, config.usdgSleeve];
        YieldBankProceedsVault proceedsVault_ = new YieldBankProceedsVault(
            address(this),
            address(nft_),
            config.seaDrop,
            config.creator,
            config.sinjohFeeRecipient,
            config.portfolioAllocator,
            config.allocationOperator,
            config.collectionTimelock,
            config.guardian,
            config.weth,
            sleeveList,
            config.primaryBackingBps,
            config.primaryCreatorBps,
            config.primarySinjohBps
        );
        proceedsVault = proceedsVault_;
        nft_.setProceedsVault(address(proceedsVault_));
        distributor_.registerAsset(config.weth);
        _registerSleeve(config.coreSleeve);
        _registerSleeve(config.marketMakingSleeve);
        _registerSleeve(config.usdgSleeve);
        emit CollectionComponents(
            config.collectionId,
            address(nft_),
            address(proceedsVault_),
            address(distributor_),
            config.accountImplementation
        );
        state = YieldBankCollectionState.ACTIVE;
        emit CollectionStateChanged(YieldBankCollectionState.DEPLOYED, state);
    }

    function prepareSeaDropMint(address minter, uint256 quantity)
        external
        returns (uint256 firstTokenId)
    {
        if (msg.sender != address(nft)) revert OnlyNFT(msg.sender);
        if (
            state != YieldBankCollectionState.ACTIVE
                && state != YieldBankCollectionState.INVESTMENT_PAUSED
        ) revert InvalidState(state);
        if (!eligibilityPolicy.canMint(minter, "")) revert Ineligible(minter);
        if (quantity == 0 || mintedSupply + quantity > maxSupply) revert InvalidConfiguration();
        firstTokenId = mintedSupply + 1;
        for (uint256 i; i < quantity; ++i) {
            uint256 tokenId = firstTokenId + i;
            address account =
                Clones.cloneDeterministic(accountImplementation, _accountSalt(tokenId));
            YieldBankAccount(account)
                .initialize(address(this), address(nft), tokenId, address(distributor));
            accountOf[tokenId] = account;
            _tokenStates[tokenId] = YieldBankTokenState.ACTIVE;
            distributor.initializeTokenDebt(tokenId);
            emit YieldBankMinted(tokenId, minter, account);
        }
        mintedSupply += quantity;
        liveSupply += quantity;
        proceedsVault.noteMint(firstTokenId, quantity);
    }

    function claimPrimary(uint256 tokenId) external nonReentrant {
        _claimPrimary(tokenId);
    }

    function settle(uint256 tokenId) external nonReentrant {
        _settle(tokenId);
    }

    function settleBatch(uint256[] calldata tokenIds) external nonReentrant {
        if (tokenIds.length == 0 || tokenIds.length > MAX_SETTLE_BATCH) {
            revert InvalidBatchSize(tokenIds.length);
        }
        for (uint256 i; i < tokenIds.length; ++i) {
            _settle(tokenIds[i]);
        }
    }

    function burnToken(uint256 tokenId, bytes calldata proof) external nonReentrant {
        if (
            state != YieldBankCollectionState.ACTIVE
                && state != YieldBankCollectionState.INVESTMENT_PAUSED
        ) revert InvalidState(state);
        (, uint256 pendingMintQuantity) = proceedsVault.pendingMint();
        if (pendingMintQuantity != 0) revert PrimaryPayoutPending();
        if (nft.ownerOf(tokenId) != msg.sender) revert InvalidTokenOwner(tokenId, msg.sender);
        address activeDeltaPool =
            IYieldBankPortfolioEconomics(portfolioAllocator).activeDeltaPoolOf(tokenId);
        if (activeDeltaPool != address(0)) {
            revert ActiveDeltaPositionRequiresRebalance(tokenId, activeDeltaPool);
        }
        if (!eligibilityPolicy.canRedeem(msg.sender, proof)) revert Ineligible(msg.sender);
        if (!eligibilityPolicy.canReceiveRestrictedShares(msg.sender, proof)) {
            revert Ineligible(msg.sender);
        }
        _burnRedemptionToken(tokenId, msg.sender);
        _burnOwned(tokenId, msg.sender, proof);
    }

    function accrueDistribution(address asset, uint256 amount) external nonReentrant {
        if (msg.sender != revenueRouter) revert OnlyRevenueRouter(msg.sender);
        if (liveSupply == 0) revert InvalidConfiguration();
        distributor.accrueFrom(asset, msg.sender, amount, liveSupply);
    }

    function registerDistributionAsset(address asset) external {
        if (msg.sender != collectionTimelock) revert OnlyTimelock(msg.sender);
        distributor.registerAsset(asset);
        emit DistributionAssetRegistered(asset);
    }

    function pauseInvestments() external {
        if (msg.sender != guardian) revert OnlyGuardian(msg.sender);
        if (state != YieldBankCollectionState.ACTIVE) revert InvalidState(state);
        proceedsVault.pauseFromCollection();
        _setState(YieldBankCollectionState.INVESTMENT_PAUSED);
    }

    function resumeInvestments() external {
        if (msg.sender != collectionTimelock) revert OnlyTimelock(msg.sender);
        if (state != YieldBankCollectionState.INVESTMENT_PAUSED) revert InvalidState(state);
        proceedsVault.resumeFromCollection();
        _setState(YieldBankCollectionState.ACTIVE);
    }

    function approvalsAllowed() external view returns (bool) {
        return state == YieldBankCollectionState.ACTIVE
            || state == YieldBankCollectionState.INVESTMENT_PAUSED;
    }

    function canTransfer(uint256 tokenId, address recipient) external view returns (bool) {
        return msg.sender == address(nft) && _tokenStates[tokenId] == YieldBankTokenState.ACTIVE
            && (state == YieldBankCollectionState.ACTIVE
                || state == YieldBankCollectionState.INVESTMENT_PAUSED)
            && eligibilityPolicy.canReceiveNFT(recipient, "");
    }

    function tokenState(uint256 tokenId) external view returns (uint8) {
        return uint8(_tokenStates[tokenId]);
    }

    function predictAccount(uint256 tokenId) external view returns (address) {
        return Clones.predictDeterministicAddress(accountImplementation, _accountSalt(tokenId));
    }

    function _settle(uint256 tokenId) private {
        if (_tokenStates[tokenId] != YieldBankTokenState.ACTIVE) {
            revert InvalidTokenState(tokenId, _tokenStates[tokenId]);
        }
        distributor.settle(tokenId, accountOf[tokenId], false);
        emit DistributionSettled(tokenId, accountOf[tokenId]);
    }

    function _claimPrimary(uint256 tokenId) private {
        if (_tokenStates[tokenId] != YieldBankTokenState.ACTIVE) {
            revert InvalidTokenState(tokenId, _tokenStates[tokenId]);
        }
        YieldBankAccount account = YieldBankAccount(accountOf[tokenId]);
        (address[3] memory assets, uint256[3] memory amounts) =
            proceedsVault.claim(tokenId, address(account));
        for (uint256 i; i < 3; ++i) {
            if (amounts[i] != 0) account.trackAsset(assets[i]);
        }
        emit PrimarySharesClaimed(tokenId, address(account));
    }

    function _burnOwned(uint256 tokenId, address beneficiary, bytes calldata proof) private {
        if (_tokenStates[tokenId] != YieldBankTokenState.ACTIVE) {
            revert InvalidTokenState(tokenId, _tokenStates[tokenId]);
        }
        uint256 pendingBacking = proceedsVault.pendingBackingOf(tokenId);
        uint8 primaryState = proceedsVault.primaryStateOf(tokenId);
        if (primaryState == proceedsVault.PRIMARY_ALLOCATED()) _claimPrimary(tokenId);
        bool terminal = liveSupply == 1;
        YieldBankAccount account = YieldBankAccount(accountOf[tokenId]);
        distributor.settle(tokenId, address(account), terminal);
        address[] memory assets = account.trackedAssets();
        _tokenStates[tokenId] = YieldBankTokenState.BURNING;
        nft.burn(tokenId);
        liveSupply -= 1;
        distributor.retireToken(tokenId);
        for (uint256 i; i < assets.length; ++i) {
            address asset = assets[i];
            uint256 balance = IERC20(asset).balanceOf(address(account));
            uint256 tax = terminal ? 0 : Math.mulDiv(balance, EXIT_TAX_BPS, BPS);
            if (tax != 0) {
                account.approveDistribution(asset, tax);
                distributor.accrueFrom(asset, address(account), tax, liveSupply);
                account.clearDistributionApproval(asset);
            }
            if (isSleeveAsset[asset]) {
                account.releaseRestrictedRemainder(asset, beneficiary, tax, proof);
            } else {
                account.releaseRemainder(asset, beneficiary, tax);
            }
        }
        if (primaryState == proceedsVault.PRIMARY_PENDING()) {
            uint256 released = proceedsVault.releasePendingBacking(tokenId, address(this));
            uint256 tax = terminal ? 0 : Math.mulDiv(released, EXIT_TAX_BPS, BPS);
            if (tax != 0) {
                weth.forceApprove(address(distributor), tax);
                distributor.accrueFrom(address(weth), address(this), tax, liveSupply);
                weth.forceApprove(address(distributor), 0);
            }
            weth.safeTransfer(beneficiary, released - tax);
        }
        account.close();
        _tokenStates[tokenId] = YieldBankTokenState.BURNED;
        if (terminal && mintedSupply == maxSupply) _setState(YieldBankCollectionState.CLOSED);
        emit YieldBankRedeemed(tokenId, beneficiary, terminal, pendingBacking);
    }

    function _registerSleeve(address asset) private {
        if (isSleeveAsset[asset]) revert InvalidSleeveAsset(asset);
        isSleeveAsset[asset] = true;
        distributor.registerAsset(asset);
    }

    /// @notice Marks an operator-materialized, source-verified pool sleeve as restricted backing.
    /// @dev Dynamic sleeves are not global distributor assets: an NFT must fully rebalance out of
    ///      its active Delta pool before redemption, so dynamic sleeve shares cannot enter the
    ///      burn-time distribution loop.
    function registerDynamicSleeve(address asset) external {
        address controller = IYieldBankPortfolioEconomics(portfolioAllocator).deltaPoolController();
        if (msg.sender != controller) revert OnlyDeltaPoolController(msg.sender);
        if (!IYieldBankPortfolioEconomics(portfolioAllocator).isDeltaPoolSleeve(asset)) {
            revert InvalidSleeveAsset(asset);
        }
        if (isSleeveAsset[asset]) revert InvalidSleeveAsset(asset);
        isSleeveAsset[asset] = true;
        emit DynamicSleeveRegistered(asset);
    }

    function _burnRedemptionToken(uint256 tokenId, address owner) private {
        uint256 amount = redemptionTokenAmount;
        if (amount == 0) return;
        IYieldBankBurnableToken token = redemptionToken;
        uint256 balanceBefore = token.balanceOf(owner);
        uint256 supplyBefore = token.totalSupply();
        token.burnFrom(owner, amount);
        uint256 balanceAfter = token.balanceOf(owner);
        uint256 supplyAfter = token.totalSupply();
        uint256 balanceBurned = balanceAfter <= balanceBefore ? balanceBefore - balanceAfter : 0;
        uint256 supplyBurned = supplyAfter <= supplyBefore ? supplyBefore - supplyAfter : 0;
        if (balanceBurned != amount || supplyBurned != amount) {
            revert RedemptionTokenBurnMismatch(amount, balanceBurned, supplyBurned);
        }
        emit RedemptionTokenBurned(tokenId, owner, address(token), amount);
    }

    function _accountSalt(uint256 tokenId) private view returns (bytes32) {
        return keccak256(abi.encode(block.chainid, address(this), collectionId, tokenId));
    }

    function _setState(YieldBankCollectionState value) private {
        YieldBankCollectionState old = state;
        state = value;
        emit CollectionStateChanged(old, value);
    }

    function _validateConfig(YieldBankConfig memory c) private view {
        bool redemptionDisabled = c.redemptionToken == address(0) && c.redemptionTokenAmount == 0
            && c.redemptionTokenCodeHash == bytes32(0);
        bool redemptionEnabled = c.redemptionToken.code.length != 0 && c.redemptionTokenAmount != 0
            && c.redemptionToken.codehash == c.redemptionTokenCodeHash;
        if (
            c.collectionId == bytes32(0) || c.maxSupply == 0 || c.maxSupply > type(uint64).max
                || c.secondaryRoyaltyBps > BPS || c.creator == address(0)
                || c.openSeaManager == address(0) || c.sinjohFeeRecipient == address(0)
                || c.revenueRouter.code.length == 0 || c.eligibilityPolicy.code.length == 0
                || c.portfolioAllocator.code.length == 0 || c.allocationOperator == address(0)
                || c.collectionTimelock.code.length == 0 || c.guardian == address(0)
                || c.renderer.code.length == 0 || c.weth.code.length == 0
                || c.seaDrop.code.length == 0 || c.coreSleeve.code.length == 0
                || c.marketMakingSleeve.code.length == 0 || c.usdgSleeve.code.length == 0
                || c.accountImplementation.code.length == 0 || c.coreSleeve == c.marketMakingSleeve
                || c.coreSleeve == c.usdgSleeve || c.marketMakingSleeve == c.usdgSleeve
                || c.primaryBackingBps == 0
                || uint256(c.primaryBackingBps) + c.primaryCreatorBps + c.primarySinjohBps != BPS
                || c.coreWeightBps == 0 || c.marketMakingWeightBps == 0 || c.usdgWeightBps == 0
                || uint256(c.coreWeightBps) + c.marketMakingWeightBps + c.usdgWeightBps != BPS
                || (!redemptionDisabled && !redemptionEnabled)
        ) revert InvalidConfiguration();
        bytes32[10] memory h = c.integrationCodeHashes;
        if (
            c.revenueRouter.codehash != h[0] || c.eligibilityPolicy.codehash != h[1]
                || c.portfolioAllocator.codehash != h[2] || c.collectionTimelock.codehash != h[3]
                || c.renderer.codehash != h[4] || c.weth.codehash != h[5]
                || c.seaDrop.codehash != h[6] || c.coreSleeve.codehash != h[7]
                || c.marketMakingSleeve.codehash != h[8] || c.usdgSleeve.codehash != h[9]
        ) revert InvalidConfiguration();
        IYieldBankRevenueEconomics revenueEconomics = IYieldBankRevenueEconomics(c.revenueRouter);
        IYieldBankPortfolioEconomics portfolioEconomics =
            IYieldBankPortfolioEconomics(c.portfolioAllocator);
        if (
            revenueEconomics.primaryBackingBps() != c.primaryBackingBps
                || revenueEconomics.primaryCreatorBps() != c.primaryCreatorBps
                || revenueEconomics.primarySinjohBps() != c.primarySinjohBps
                || portfolioEconomics.coreWeightBps() != c.coreWeightBps
                || portfolioEconomics.marketMakingWeightBps() != c.marketMakingWeightBps
                || portfolioEconomics.usdgWeightBps() != c.usdgWeightBps
        ) revert InvalidConfiguration();
    }
}
