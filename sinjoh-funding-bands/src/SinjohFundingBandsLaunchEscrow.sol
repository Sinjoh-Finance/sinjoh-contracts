// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { ISinjohFeeRouterView } from "./interfaces/ISinjohFeeRouterView.sol";
import { ISinjohPrelaunchVerifier } from "./interfaces/ISinjohPrelaunchVerifier.sol";

interface ISinjohFundingBandsEscrowManager {
    enum Destination {
        CREATOR,
        FEE_ROUTER
    }

    struct BandConfig {
        uint128 lowerMarketCapUsdE8;
        uint128 upperMarketCapUsdE8;
        Destination destination;
        address feeRouter;
    }

    struct BandFunding {
        uint8 bandId;
        uint128 amount;
    }

    function create(
        address subject,
        uint8 profileId,
        BandConfig[] calldata configs,
        bytes calldata launchData,
        bytes calldata guardData
    ) external returns (bytes32);

    function fund(address subject, BandFunding[] calldata funding, bytes calldata guardData)
        external
        returns (uint256);

    function getProfile(uint8 profileId)
        external
        view
        returns (address verifier, address priceGuard, bytes32 hookDataHash);

    function launchEscrow() external view returns (address);

    function weth() external view returns (address);

    function feeRouterCodehash() external view returns (bytes32);
}

/// @notice Holds launch-time developer-buy inventory until Pons v2 graduation,
/// then permissionlessly creates and funds the complete immutable band ladder.
contract SinjohFundingBandsLaunchEscrow is ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint16 private constant BPS = 10_000;
    uint8 private constant MAX_BANDS = 10;

    error InvalidAddress();
    error InvalidConfiguration();
    error InvalidLaunch();
    error InvalidAmount();
    error AlreadyPrepared();
    error NotPrepared();
    error AlreadyBound();
    error Unauthorized();
    error UnexpectedBalanceDelta(uint256 expected, uint256 actual);

    struct PreparedAccount {
        address creator;
        uint8 profileId;
        uint8 bandCount;
        uint8 subjectDecimals;
        uint256 launchSupply;
        uint256 escrowedInventory;
        bool exists;
        bool activated;
    }

    event ManagerBound(address indexed manager);
    event InventoryEscrowed(
        bytes32 indexed accountId,
        address indexed subject,
        address indexed creator,
        uint8 profileId,
        uint256 developerBuyTokens,
        uint256 escrowedInventory,
        uint16 inventoryBps
    );
    event EscrowActivated(
        bytes32 indexed accountId,
        address indexed subject,
        address indexed caller,
        uint256 fundedInventory
    );

    ISinjohPrelaunchVerifier public immutable verifier;
    address public immutable binder;
    address public manager;

    mapping(address subject => PreparedAccount account) private _preparedAccounts;
    mapping(
        address subject => mapping(uint8 bandId => ISinjohFundingBandsEscrowManager.BandConfig)
    ) private _configs;
    mapping(address subject => mapping(uint8 bandId => uint128 amount)) private _funding;

    constructor(address verifier_, address binder_) {
        if (verifier_.code.length == 0 || binder_ == address(0)) revert InvalidAddress();
        verifier = ISinjohPrelaunchVerifier(verifier_);
        binder = binder_;
    }

    /// @notice One-time binding after manager deployment. The circular address
    /// dependency is resolved without leaving either side mutable afterward.
    function bindManager(address manager_) external {
        if (msg.sender != binder) revert Unauthorized();
        if (manager != address(0)) revert AlreadyBound();
        if (manager_.code.length == 0) revert InvalidAddress();
        ISinjohFundingBandsEscrowManager candidate = ISinjohFundingBandsEscrowManager(manager_);
        (address managerVerifier,,) = candidate.getProfile(0);
        if (managerVerifier != address(verifier) || candidate.launchEscrow() != address(this)) {
            revert InvalidConfiguration();
        }
        manager = manager_;
        emit ManagerBound(manager_);
    }

    /// @notice Called by the reviewed launch adapter in the same transaction as
    /// the developer buy. It pulls only the configured share; the adapter sends
    /// the remainder to the creator after this call succeeds.
    function prepareFromLaunch(
        address subject,
        uint8 profileId,
        uint16 inventoryBps,
        ISinjohFundingBandsEscrowManager.BandConfig[] calldata configs,
        uint16[] calldata allocationBps,
        uint256 developerBuyTokens,
        bytes calldata launchData
    ) external nonReentrant returns (uint256 escrowedInventory) {
        if (
            manager == address(0) || subject.code.length == 0 || profileId != 0 || inventoryBps == 0
                || inventoryBps > BPS || developerBuyTokens == 0 || configs.length == 0
                || configs.length > MAX_BANDS || configs.length != allocationBps.length
        ) revert InvalidConfiguration();
        if (_preparedAccounts[subject].exists || _preparedAccounts[subject].activated) {
            revert AlreadyPrepared();
        }

        ISinjohPrelaunchVerifier.VerifiedPreparation memory preparation =
            verifier.verifyPreparation(subject, msg.sender, launchData);
        if (
            preparation.subject != subject || preparation.creatorAtLaunch == address(0)
                || preparation.launchSupply == 0
                || IERC20(subject).totalSupply() != preparation.launchSupply
                || IERC20Metadata(subject).decimals() > 36
        ) revert InvalidLaunch();

        ISinjohFundingBandsEscrowManager manager_ = ISinjohFundingBandsEscrowManager(manager);
        address weth_ = manager_.weth();
        bytes32 feeRouterCodehash_ = manager_.feeRouterCodehash();
        uint256 totalAllocation;
        uint128 previousUpper;
        for (uint8 i; i < configs.length; ++i) {
            ISinjohFundingBandsEscrowManager.BandConfig calldata config = configs[i];
            if (
                config.lowerMarketCapUsdE8 == 0
                    || config.lowerMarketCapUsdE8 >= config.upperMarketCapUsdE8
                    || (i != 0 && config.lowerMarketCapUsdE8 < previousUpper)
                    || allocationBps[i] == 0
            ) revert InvalidConfiguration();
            if (config.destination == ISinjohFundingBandsEscrowManager.Destination.CREATOR) {
                if (config.feeRouter != address(0)) revert InvalidConfiguration();
            } else {
                address router = config.feeRouter;
                if (
                    router.codehash != feeRouterCodehash_
                        || ISinjohFeeRouterView(router).creator() != preparation.creatorAtLaunch
                        || ISinjohFeeRouterView(router).subject() != subject
                        || !ISinjohFeeRouterView(router).isIntakeAsset(weth_)
                        || !ISinjohFeeRouterView(router).isIntakeAsset(subject)
                ) revert InvalidConfiguration();
            }
            previousUpper = config.upperMarketCapUsdE8;
            totalAllocation += allocationBps[i];
            _configs[subject][i] = config;
        }
        if (totalAllocation != BPS) revert InvalidConfiguration();

        escrowedInventory = developerBuyTokens * inventoryBps / BPS;
        if (escrowedInventory == 0 || escrowedInventory > type(uint128).max) {
            revert InvalidAmount();
        }
        uint256 allocated;
        for (uint8 i; i < configs.length; ++i) {
            uint256 amount = i + 1 == configs.length
                ? escrowedInventory - allocated
                : escrowedInventory * allocationBps[i] / BPS;
            if (amount == 0 || amount > type(uint128).max) revert InvalidAmount();
            // Bounded immediately above.
            // forge-lint: disable-next-line(unsafe-typecast)
            _funding[subject][i] = uint128(amount);
            allocated += amount;
        }

        uint256 beforeBalance = IERC20(subject).balanceOf(address(this));
        IERC20(subject).safeTransferFrom(msg.sender, address(this), escrowedInventory);
        uint256 received = IERC20(subject).balanceOf(address(this)) - beforeBalance;
        if (received != escrowedInventory) {
            revert UnexpectedBalanceDelta(escrowedInventory, received);
        }
        _preparedAccounts[subject] = PreparedAccount({
            creator: preparation.creatorAtLaunch,
            profileId: profileId,
            bandCount: uint8(configs.length),
            subjectDecimals: IERC20Metadata(subject).decimals(),
            launchSupply: preparation.launchSupply,
            escrowedInventory: escrowedInventory,
            exists: true,
            activated: false
        });
        emit InventoryEscrowed(
            keccak256(abi.encode(subject)),
            subject,
            preparation.creatorAtLaunch,
            profileId,
            developerBuyTokens,
            escrowedInventory,
            inventoryBps
        );
    }

    /// @notice Permissionless after graduation. Manager verification, account
    /// creation, approval, and funding all succeed or revert atomically.
    function activate(address subject) external nonReentrant {
        PreparedAccount storage prepared = _preparedAccounts[subject];
        if (!prepared.exists || prepared.activated) revert NotPrepared();
        address manager_ = manager;
        ISinjohFundingBandsEscrowManager.BandConfig[] memory configs =
            new ISinjohFundingBandsEscrowManager.BandConfig[](prepared.bandCount);
        ISinjohFundingBandsEscrowManager.BandFunding[] memory funding =
            new ISinjohFundingBandsEscrowManager.BandFunding[](prepared.bandCount);
        for (uint8 i; i < prepared.bandCount; ++i) {
            configs[i] = _configs[subject][i];
            funding[i] = ISinjohFundingBandsEscrowManager.BandFunding({
                bandId: i, amount: _funding[subject][i]
            });
        }

        uint256 inventory = prepared.escrowedInventory;
        uint256 beforeBalance = IERC20(subject).balanceOf(address(this));
        if (beforeBalance < inventory) {
            revert UnexpectedBalanceDelta(inventory, beforeBalance);
        }
        IERC20(subject).forceApprove(manager_, inventory);
        ISinjohFundingBandsEscrowManager(manager_)
            .create(subject, 0, configs, abi.encode(prepared.launchSupply), "");
        uint256 received = ISinjohFundingBandsEscrowManager(manager_).fund(subject, funding, "");
        IERC20(subject).forceApprove(manager_, 0);
        uint256 afterBalance = IERC20(subject).balanceOf(address(this));
        uint256 spent = beforeBalance - afterBalance;
        if (received != inventory || spent != inventory) {
            revert UnexpectedBalanceDelta(inventory, spent);
        }

        for (uint8 i; i < prepared.bandCount; ++i) {
            delete _configs[subject][i];
            delete _funding[subject][i];
        }
        prepared.escrowedInventory = 0;
        prepared.exists = false;
        prepared.activated = true;
        emit EscrowActivated(keccak256(abi.encode(subject)), subject, msg.sender, inventory);
    }

    function getPreparedAccount(address subject) external view returns (PreparedAccount memory) {
        return _preparedAccounts[subject];
    }

    function isPrepared(address subject) external view returns (bool) {
        return _preparedAccounts[subject].exists;
    }

    function getPreparedBand(address subject, uint8 bandId)
        external
        view
        returns (ISinjohFundingBandsEscrowManager.BandConfig memory config, uint128 amount)
    {
        PreparedAccount storage prepared = _preparedAccounts[subject];
        if ((!prepared.exists && !prepared.activated) || bandId >= prepared.bandCount) {
            revert NotPrepared();
        }
        return (_configs[subject][bandId], _funding[subject][bandId]);
    }
}
