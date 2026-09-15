// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IYieldBankCollection } from "../interfaces/IYieldBankCollection.sol";
import { AirdropAssetRegistry, IAirdropClaimAdapter } from "./AirdropAssetRegistry.sol";

interface IAirdropClosedBank {
    function closed() external view returns (bool);
    function redemptionBeneficiary() external view returns (address);
}

/// @notice A permanent, non-upgradeable holder address for one bank and its entire Airdrop basket.
/// Unclaimed rewards travel with the NFT. Following redemption, the collection's recorded
/// beneficiary can recover delayed payouts. Principal never enters the reward balance.
contract AirdropBankCustody is ReentrancyGuard {
    using SafeERC20 for IERC20;
    address public immutable vault;
    IYieldBankCollection public immutable collection;
    AirdropAssetRegistry public immutable registry;
    uint256 public immutable bank;
    mapping(address => uint256) public principal;
    mapping(address => bool) public hasHeld;
    address[] private _activeAssets;
    mapping(address => uint256) public totalPaid;
    error Unauthorized();
    error InvalidTransfer();
    error ClaimFailed();
    error NoRewardsReceived();
    event RewardPaid(
        uint256 indexed bank, address indexed asset, address indexed beneficiary, uint256 amount
    );
    event ExternalClaim(address indexed subject, uint256 indexed route, address indexed target);

    constructor(
        address vault_,
        address collection_,
        address registry_,
        uint256 bank_
    ) {
        if (
            vault_ == address(0) || collection_.code.length == 0 || registry_.code.length == 0
                || bank_ == 0
        ) revert Unauthorized();
        vault = vault_;
        collection = IYieldBankCollection(collection_);
        registry = AirdropAssetRegistry(registry_);
        bank = bank_;
    }
    receive() external payable { }

    function beneficiary() public view returns (address recipient) {
        address account = collection.accountOf(bank);
        if (account == address(0)) revert Unauthorized();
        if (IAirdropClosedBank(account).closed()) {
            recipient = IAirdropClosedBank(account).redemptionBeneficiary();
        } else {
            recipient = IERC721(collection.nft()).ownerOf(bank);
        }
        if (recipient == address(0) || recipient == address(this)) revert Unauthorized();
    }

    function deposit(address asset, uint256 amount) external nonReentrant {
        if (msg.sender != vault || amount == 0) revert Unauthorized();
        registry.requireCurrent(asset, true);
        if (principal[asset] == 0) {
            if (_activeAssets.length >= 3) revert Unauthorized();
            _activeAssets.push(asset);
        }
        hasHeld[asset] = true;
        uint256 beforeBalance = IERC20(asset).balanceOf(address(this));
        IERC20(asset).safeTransferFrom(vault, address(this), amount);
        if (IERC20(asset).balanceOf(address(this)) != beforeBalance + amount) {
            revert InvalidTransfer();
        }
        principal[asset] += amount;
    }

    function withdraw(address asset, uint256 amount) external nonReentrant {
        if (msg.sender != vault || amount == 0 || amount > principal[asset]) revert Unauthorized();
        principal[asset] -= amount;
        if (principal[asset] == 0) {
            for (uint256 i; i < _activeAssets.length; ++i) {
                if (_activeAssets[i] == asset) {
                    _activeAssets[i] = _activeAssets[_activeAssets.length - 1];
                    _activeAssets.pop();
                    break;
                }
            }
        }
        _send(asset, vault, amount);
    }

    function available(address asset) public view returns (uint256) {
        uint256 balance =
            asset == address(0) ? address(this).balance : IERC20(asset).balanceOf(address(this));
        if (balance < principal[asset]) revert InvalidTransfer();
        return balance - principal[asset];
    }

    /// @notice Permissionless collection, recipient fixed to this custody by a typed adapter.
    /// No delegatecall or approvals; published Merkle proofs are verified by the distributor.
    function collect(address subject, uint256 routeIndex, bytes calldata proof) external nonReentrant {
        AirdropAssetRegistry.ClaimRoute memory route = registry.claimRoute(subject, routeIndex);
        (address target, bytes memory data) =
            IAirdropClaimAdapter(route.adapter).prepare(address(this), proof);
        if (
            target.code.length == 0 || target == subject || target == address(this)
                || target == vault || target == address(collection)
        ) revert Unauthorized();
        uint256[] memory beforePrincipal = new uint256[](_activeAssets.length);
        for (uint256 i; i < _activeAssets.length; ++i) {
            if (target == _activeAssets[i]) revert Unauthorized();
            beforePrincipal[i] = IERC20(_activeAssets[i]).balanceOf(address(this));
        }
        uint256 beforeSubject = IERC20(subject).balanceOf(address(this));
        uint256 beforeReward = IERC20(route.reward).balanceOf(address(this));
        uint256 beforeNative = address(this).balance;
        (bool ok,) = target.call(data);
        if (!ok) revert ClaimFailed();
        if (
            IERC20(subject).balanceOf(address(this)) < beforeSubject
                || IERC20(route.reward).balanceOf(address(this)) < beforeReward
                || address(this).balance < beforeNative
        ) revert InvalidTransfer();
        if (
            IERC20(route.reward).balanceOf(address(this)) == beforeReward
                && address(this).balance == beforeNative
        ) revert NoRewardsReceived();
        for (uint256 i; i < _activeAssets.length; ++i) {
            if (IERC20(_activeAssets[i]).balanceOf(address(this)) < beforePrincipal[i]) {
                revert InvalidTransfer();
            }
        }
        emit ExternalClaim(subject, routeIndex, target);
    }

    /// @notice Only the current beneficiary can initiate delivery; no alternate recipient.
    /// One token per call lets a blocked reward be retried without blocking other rewards.
    function claim(address asset) external nonReentrant returns (uint256 amount) {
        address recipient = beneficiary();
        if (msg.sender != recipient) revert Unauthorized();
        amount = available(asset);
        if (amount == 0) return 0;
        totalPaid[asset] += amount;
        if (asset == address(0)) {
            (bool ok,) = recipient.call{ value: amount }("");
            if (!ok) revert InvalidTransfer();
        } else {
            _send(asset, recipient, amount);
        }
        if (beneficiary() != recipient) revert Unauthorized();
        emit RewardPaid(bank, asset, recipient, amount);
    }

    function _send(address asset, address recipient, uint256 amount) private {
        IERC20 token = IERC20(asset);
        uint256 beforeSender = token.balanceOf(address(this));
        uint256 beforeRecipient = token.balanceOf(recipient);
        token.safeTransfer(recipient, amount);
        if (
            token.balanceOf(address(this)) != beforeSender - amount
                || token.balanceOf(recipient) != beforeRecipient + amount
        ) revert InvalidTransfer();
    }
}
