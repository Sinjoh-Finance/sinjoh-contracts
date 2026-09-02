// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { YieldBankAdapterState } from "./YieldBankTypes.sol";
import { IStrategyAdapter } from "./interfaces/IStrategyAdapter.sol";
import { IntegrationBinding } from "./libraries/IntegrationBinding.sol";

/// @notice Append-only catalog of reviewed synchronous Yield Banks adapters.
contract StrategyRegistry is Ownable2Step {
    struct StrategyRecord {
        address implementation;
        bytes32 runtimeCodeHash;
        bytes32 sleeveCategory;
        address accountingAsset;
        YieldBankAdapterState state;
        uint48 registeredAt;
    }

    mapping(address adapter => StrategyRecord record) private _records;
    mapping(address registrar => bool allowed) public isRegistrar;

    error InvalidStrategy(address adapter);
    error AlreadyRegistered(address adapter);
    error InvalidState(YieldBankAdapterState state);

    event StrategyRegistered(
        address indexed adapter,
        bytes32 indexed sleeveCategory,
        address indexed accountingAsset,
        bytes32 runtimeCodeHash
    );
    event StrategyRejected(address indexed adapter);
    event RegistrarSet(address indexed registrar, bool allowed);

    constructor(address owner_) Ownable(owner_) { }

    function setRegistrar(address registrar, bool allowed) external onlyOwner {
        if (registrar == address(0)) revert InvalidStrategy(registrar);
        isRegistrar[registrar] = allowed;
        emit RegistrarSet(registrar, allowed);
    }

    function register(address adapter, bytes32 sleeveCategory) external {
        if (msg.sender != owner() && !isRegistrar[msg.sender]) {
            revert OwnableUnauthorizedAccount(msg.sender);
        }
        if (adapter.code.length == 0 || sleeveCategory == bytes32(0)) {
            revert InvalidStrategy(adapter);
        }
        if (_records[adapter].state != YieldBankAdapterState.UNREGISTERED) {
            revert AlreadyRegistered(adapter);
        }
        IStrategyAdapter strategy = IStrategyAdapter(adapter);
        address asset = strategy.accountingAsset();
        if (asset.code.length == 0 || strategy.sleeve() == address(0)) {
            revert InvalidStrategy(adapter);
        }
        bytes32 codeHash = IntegrationBinding.runtimeCodeHash(adapter);
        // Timestamp is deployment provenance, never a price or economic calculation.
        // forge-lint: disable-next-line(block-timestamp)
        uint48 registeredAt = uint48(block.timestamp);
        _records[adapter] = StrategyRecord({
            implementation: adapter,
            runtimeCodeHash: codeHash,
            sleeveCategory: sleeveCategory,
            accountingAsset: asset,
            state: YieldBankAdapterState.REGISTERED,
            registeredAt: registeredAt
        });
        emit StrategyRegistered(adapter, sleeveCategory, asset, codeHash);
    }

    function reject(address adapter) external onlyOwner {
        StrategyRecord storage record = _records[adapter];
        if (record.state != YieldBankAdapterState.REGISTERED) revert InvalidState(record.state);
        record.state = YieldBankAdapterState.REJECTED;
        emit StrategyRejected(adapter);
    }

    function recordOf(address adapter) external view returns (StrategyRecord memory) {
        return _records[adapter];
    }

    function isRuntimeValid(address adapter) external view returns (bool) {
        StrategyRecord storage record = _records[adapter];
        return record.state == YieldBankAdapterState.REGISTERED && adapter.code.length != 0
            && IntegrationBinding.runtimeCodeHash(adapter) == record.runtimeCodeHash;
    }
}
