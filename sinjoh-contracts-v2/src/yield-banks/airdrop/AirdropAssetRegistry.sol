// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IAirdropClaimAdapter {
    function subject() external view returns (address);
    function rewardAsset() external view returns (address);
    function prepare(address recipient, bytes calldata proof)
        external
        view
        returns (address target, bytes memory data);
}

/// @notice Release admission is independent of catalog approval. Governance must supply
/// reviewed routes, oracle, custody eligibility and claim evidence before enabling entry.
contract AirdropAssetRegistry is Ownable {
    struct Asset {
        bytes32 codeHash;
        bytes32 evidenceHash;
        uint8 decimals;
        bool enabled;
    }

    struct ClaimRoute {
        address adapter;
        bytes32 codeHash;
        address reward;
    }
    bytes32 public immutable catalogHash;
    mapping(address => Asset) public assets;
    mapping(address => uint256) public minimumHoldingUnits;
    mapping(address => ClaimRoute[]) private _claims;
    address[] public listed;
    error InvalidAsset();
    event AssetRegistered(address indexed asset, bytes32 evidenceHash);
    event EntryEnabled(address indexed asset, bool enabled);
    event ClaimRouteAdded(address indexed asset, uint256 index, address adapter, address reward);

    constructor(address governance, bytes32 catalogHash_) Ownable(governance) {
        if (catalogHash_ == bytes32(0)) revert InvalidAsset();
        catalogHash = catalogHash_;
    }

    function register(address asset, bytes32 evidenceHash) external onlyOwner {
        if (
            asset.code.length == 0 || evidenceHash == bytes32(0)
                || assets[asset].codeHash != bytes32(0) || listed.length >= 100
        ) revert InvalidAsset();
        uint8 decimals = IERC20Metadata(asset).decimals();
        if (decimals > 18) revert InvalidAsset();
        assets[asset] = Asset(asset.codehash, evidenceHash, decimals, false);
        minimumHoldingUnits[asset] = 1;
        listed.push(asset);
        emit AssetRegistered(asset, evidenceHash);
    }

    function addClaimRoute(address asset, address adapter) external onlyOwner {
        requireCurrent(asset, false);
        if (adapter.code.length == 0 || _claims[asset].length >= 8) revert InvalidAsset();
        IAirdropClaimAdapter route = IAirdropClaimAdapter(adapter);
        address reward = route.rewardAsset();
        if (route.subject() != asset || reward.code.length == 0) revert InvalidAsset();
        for (uint256 i; i < _claims[asset].length; ++i) {
            if (_claims[asset][i].adapter == adapter) revert InvalidAsset();
        }
        _claims[asset].push(ClaimRoute(adapter, adapter.codehash, reward));
        emit ClaimRouteAdded(asset, _claims[asset].length - 1, adapter, reward);
    }

    function setMinimumHoldingUnits(address asset, uint256 units) external onlyOwner {
        requireCurrent(asset, false);
        if (units == 0 || assets[asset].enabled) revert InvalidAsset();
        minimumHoldingUnits[asset] = units;
    }

    function setEnabled(address asset, bool enabled) external onlyOwner {
        requireCurrent(asset, false);
        if (enabled && _claims[asset].length == 0) revert InvalidAsset();
        assets[asset].enabled = enabled;
        emit EntryEnabled(asset, enabled);
    }

    function requireCurrent(address asset, bool entering) public view returns (uint8) {
        Asset memory a = assets[asset];
        if (
            a.codeHash == bytes32(0) || asset.codehash != a.codeHash || (entering && !a.enabled)
                || IERC20Metadata(asset).decimals() != a.decimals
        ) revert InvalidAsset();
        return a.decimals;
    }

    function claimRoute(address asset, uint256 index)
        external
        view
        returns (ClaimRoute memory route)
    {
        route = _claims[asset][index];
        if (route.adapter.codehash != route.codeHash) revert InvalidAsset();
    }

    function claimRouteCount(address asset) external view returns (uint256) {
        return _claims[asset].length;
    }
}
