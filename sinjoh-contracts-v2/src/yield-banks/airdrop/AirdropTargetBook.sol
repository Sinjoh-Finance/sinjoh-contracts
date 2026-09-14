// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IYieldBankCollection } from "../interfaces/IYieldBankCollection.sol";
import { StockStrategyMath } from "../stock/StockStrategyMath.sol";
import { StockDividendVault } from "../stock/StockDividendVault.sol";
import { AirdropVault } from "./AirdropVault.sol";
import { AirdropExecution } from "./AirdropExecution.sol";

interface IAirdropTargetSleeve {
    function collection() external view returns (IYieldBankCollection);
    function stockVault() external view returns (address);
    function airdropVault() external view returns (address);
    function stockEntryRoute(address) external view returns (AirdropExecution.Route memory);
    function airdropEntryRoute(address) external view returns (AirdropExecution.Route memory);
}

/// @notice Owner-signed preferences kept outside execution bytecode. No funds or allowances.
contract AirdropTargetBook is ReentrancyGuard {
    IAirdropTargetSleeve public immutable sleeve;
    IYieldBankCollection public immutable collection;
    mapping(uint256 => Target) private _targets;
    error Unauthorized();
    error InvalidTarget();

    constructor(address sleeve_) {
        sleeve = IAirdropTargetSleeve(sleeve_);
        collection = sleeve.collection();
    }

    struct Target {
        address owner;
        uint64 nonce;
        uint48 validUntil;
        uint16 lpWeightBps;
        uint16 stockWeightBps;
        address[] assets;
        uint16[] weights;
        uint16 airdropWeightBps;
        address[] airdropAssets;
        uint16[] airdropWeights;
    }

    struct Basket {
        address[] assets;
        uint16[] weights;
    }

    struct TargetInput {
        uint16 lp;
        uint16 stock;
        uint16 airdrop;
        Basket stocks;
        Basket airdrops;
        uint48 validUntil;
    }
    event AirdropTargetSet(
        uint256 indexed bank, address indexed owner, uint64 nonce, bytes32 targetHash
    );

    function setTarget(uint256 bank, TargetInput calldata input) external nonReentrant {
        address owner = IERC721(collection.nft()).ownerOf(bank);
        if (msg.sender != owner || collection.accountOf(bank) == address(0)) revert Unauthorized();
        uint256 combined = uint256(input.lp) + input.stock + input.airdrop;
        if (
            combined == 0 || combined > 10000 || input.validUntil <= block.timestamp
                || input.validUntil > block.timestamp + 1 days
        ) revert InvalidTarget();
        _validateBasket(input.stock, input.stocks);
        _validateBasket(input.airdrop, input.airdrops);
        for (uint256 i; i < input.stocks.assets.length; ++i) {
            if (sleeve.stockEntryRoute(input.stocks.assets[i]).route == address(0)) {
                revert InvalidTarget();
            }
            StockDividendVault(sleeve.stockVault()).registry()
                .requireCurrent(input.stocks.assets[i], true);
        }
        for (uint256 i; i < input.airdrops.assets.length; ++i) {
            if (sleeve.airdropEntryRoute(input.airdrops.assets[i]).route == address(0)) {
                revert InvalidTarget();
            }
            AirdropVault(sleeve.airdropVault()).registry()
                .requireCurrent(input.airdrops.assets[i], true);
        }
        Target storage target = _targets[bank];
        target.owner = owner;
        ++target.nonce;
        target.validUntil = input.validUntil;
        target.lpWeightBps = input.lp;
        target.stockWeightBps = input.stock;
        target.airdropWeightBps = input.airdrop;
        target.assets = input.stocks.assets;
        target.weights = input.stocks.weights;
        target.airdropAssets = input.airdrops.assets;
        target.airdropWeights = input.airdrops.weights;
        emit AirdropTargetSet(bank, owner, target.nonce, keccak256(abi.encode(input)));
    }

    function _validateBasket(uint16 weight, Basket calldata basket) private pure {
        if (weight == 0) {
            if (basket.assets.length != 0 || basket.weights.length != 0) revert InvalidTarget();
        } else {
            StockStrategyMath.validate(basket.assets.length > 1, basket.assets, basket.weights);
        }
    }

    function targetOf(uint256 bank) external view returns (Target memory) {
        return _targets[bank];
    }
}
