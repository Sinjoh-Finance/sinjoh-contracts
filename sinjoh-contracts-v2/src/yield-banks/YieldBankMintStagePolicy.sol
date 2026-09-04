// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { YieldBankMintStage } from "./YieldBankTypes.sol";
import { ISeaDrop } from "./interfaces/ISeaDrop.sol";
import { MintParams, PublicDrop } from "./interfaces/SeaDropStructs.sol";

interface IYieldBankMintPolicyNFT {
    function seaDrop() external view returns (address);
}

/// @notice Optional collection-specific enforcement for fixed-price, fixed-inventory tiers.
/// @dev Initial allowlist windows cannot overlap because SeaDrop omits the selected stage from its
///      NFT callback. After those windows, one live SeaDrop public drop may expose any unsold tier
///      whose price, wallet cap, fee, and fee-recipient rule match exactly. Rotating that single
///      public drop preserves every tier's original economics without a custom mint gateway.
contract YieldBankMintStagePolicy {
    uint16 private constant BPS = 10_000;
    uint256 private constant MAX_STAGES = 16;

    address public immutable nft;
    address public immutable seaDrop;
    uint256 public immutable maxSupply;
    uint256 public immutable publicSaleStart;
    YieldBankMintStage[] private _stages;
    uint256[] public mintedByStage;
    mapping(uint256 stageIndex => mapping(address minter => uint256 quantity)) public
        numberMintedByStage;

    error InvalidConfiguration();
    error OnlyNFT(address caller);
    error NoActiveStage(uint256 timestamp);
    error StageSoldOut(uint256 stageIndex, uint256 requestedTotal, uint256 stageCapacity);
    error StageWalletLimit(
        uint256 stageIndex, address minter, uint256 requestedTotal, uint256 stageLimit
    );
    error InsufficientSeaDropPayment(uint256 expectedGrossProceeds, uint256 availableBalance);
    error InvalidPublicDrop();

    event StageMintRecorded(
        uint256 indexed stageIndex, address indexed minter, uint256 quantity, uint256 firstTokenId
    );

    constructor(address nft_, uint256 maxSupply_, YieldBankMintStage[] memory stages) {
        uint256 length = stages.length;
        if (nft_.code.length == 0 || maxSupply_ == 0 || length == 0 || length > MAX_STAGES) {
            revert InvalidConfiguration();
        }
        nft = nft_;
        seaDrop = IYieldBankMintPolicyNFT(nft_).seaDrop();
        if (seaDrop.code.length == 0) revert InvalidConfiguration();
        maxSupply = maxSupply_;

        uint64 previousSupplyEnd;
        uint48 previousTimeEnd;
        for (uint256 i; i < length; ++i) {
            YieldBankMintStage memory configuredStage = stages[i];
            if (
                configuredStage.endTokenId == 0 || configuredStage.endTokenId <= previousSupplyEnd
                    || configuredStage.mintPrice == 0 || configuredStage.startTime == 0
                    || configuredStage.endTime < configuredStage.startTime
                    || (i != 0 && configuredStage.startTime <= previousTimeEnd)
                    || configuredStage.maxMintsPerWallet == 0 || configuredStage.feeBps >= BPS
            ) revert InvalidConfiguration();
            uint256 capacity = configuredStage.endTokenId - previousSupplyEnd;
            if (configuredStage.maxMintsPerWallet > capacity) revert InvalidConfiguration();
            for (uint256 j; j < i; ++j) {
                if (
                    configuredStage.dropStageIndex == stages[j].dropStageIndex
                        || _samePublicTerms(configuredStage, stages[j])
                ) revert InvalidConfiguration();
            }
            _stages.push(configuredStage);
            mintedByStage.push(0);
            previousSupplyEnd = configuredStage.endTokenId;
            previousTimeEnd = configuredStage.endTime;
        }
        if (previousSupplyEnd != maxSupply_ || previousTimeEnd == type(uint48).max) {
            revert InvalidConfiguration();
        }
        publicSaleStart = uint256(previousTimeEnd) + 1;
    }

    function recordMint(address minter, uint256 quantity, uint256, uint256 seaDropBalance)
        external
        returns (uint256 expectedNetProceeds, uint256 firstTokenId)
    {
        if (msg.sender != nft) revert OnlyNFT(msg.sender);
        uint256 stageIndex = _activeStage();
        YieldBankMintStage memory configuredStage = _stages[stageIndex];
        uint256 capacity = _stageCapacity(stageIndex);
        uint256 requestedStageTotal = mintedByStage[stageIndex] + quantity;
        if (requestedStageTotal > capacity) {
            revert StageSoldOut(stageIndex, requestedStageTotal, capacity);
        }
        uint256 requestedWalletTotal = numberMintedByStage[stageIndex][minter] + quantity;
        if (requestedWalletTotal > configuredStage.maxMintsPerWallet) {
            revert StageWalletLimit(
                stageIndex, minter, requestedWalletTotal, configuredStage.maxMintsPerWallet
            );
        }

        uint256 expectedGrossProceeds = uint256(configuredStage.mintPrice) * quantity;
        if (seaDropBalance < expectedGrossProceeds) {
            revert InsufficientSeaDropPayment(expectedGrossProceeds, seaDropBalance);
        }
        firstTokenId = _stageStartTokenId(stageIndex) + mintedByStage[stageIndex];
        mintedByStage[stageIndex] = requestedStageTotal;
        numberMintedByStage[stageIndex][minter] = requestedWalletTotal;
        expectedNetProceeds =
            expectedGrossProceeds - (expectedGrossProceeds * configuredStage.feeBps / BPS);
        emit StageMintRecorded(stageIndex, minter, quantity, firstTokenId);
    }

    function mintStats(address minter, uint256)
        external
        view
        returns (uint256 stageMints, uint256 stageMinted, uint256 stageSupply)
    {
        uint256 stageIndex = _activeStage();
        return (
            numberMintedByStage[stageIndex][minter],
            mintedByStage[stageIndex],
            _stageCapacity(stageIndex)
        );
    }

    function activeStage() external view returns (uint256) {
        return _activeStage();
    }

    function stageCount() external view returns (uint256) {
        return _stages.length;
    }

    function stage(uint256 stageIndex) external view returns (YieldBankMintStage memory) {
        return _stages[stageIndex];
    }

    function stageStartTokenId(uint256 stageIndex) external view returns (uint256) {
        return _stageStartTokenId(stageIndex);
    }

    function stageCapacity(uint256 stageIndex) external view returns (uint256) {
        return _stageCapacity(stageIndex);
    }

    function mintParams(uint256 stageIndex) external view returns (MintParams memory params) {
        YieldBankMintStage memory configuredStage = _stages[stageIndex];
        params = MintParams({
            mintPrice: configuredStage.mintPrice,
            maxTotalMintableByWallet: configuredStage.maxMintsPerWallet,
            startTime: configuredStage.startTime,
            endTime: configuredStage.endTime,
            dropStageIndex: configuredStage.dropStageIndex,
            maxTokenSupplyForStage: _stageCapacity(stageIndex),
            feeBps: configuredStage.feeBps,
            restrictFeeRecipients: configuredStage.restrictFeeRecipients
        });
    }

    function publicDropForStage(uint256 stageIndex, uint48 startTime, uint48 endTime)
        external
        view
        returns (PublicDrop memory publicDrop)
    {
        if (stageIndex >= _stages.length || startTime < publicSaleStart || endTime < startTime) {
            revert InvalidConfiguration();
        }
        YieldBankMintStage memory configuredStage = _stages[stageIndex];
        publicDrop = PublicDrop({
            mintPrice: configuredStage.mintPrice,
            startTime: startTime,
            endTime: endTime,
            maxTotalMintableByWallet: configuredStage.maxMintsPerWallet,
            feeBps: configuredStage.feeBps,
            restrictFeeRecipients: configuredStage.restrictFeeRecipients
        });
    }

    function _activeStage() private view returns (uint256 stageIndex) {
        if (block.timestamp >= publicSaleStart) return _activePublicStage();
        uint256 length = _stages.length;
        for (uint256 i; i < length; ++i) {
            YieldBankMintStage memory configuredStage = _stages[i];
            if (
                block.timestamp >= configuredStage.startTime
                    && block.timestamp <= configuredStage.endTime
            ) return i;
        }
        revert NoActiveStage(block.timestamp);
    }

    function _activePublicStage() private view returns (uint256 matchedStage) {
        PublicDrop memory publicDrop = ISeaDrop(seaDrop).getPublicDrop(nft);
        if (block.timestamp < publicDrop.startTime || block.timestamp > publicDrop.endTime) {
            revert NoActiveStage(block.timestamp);
        }
        bool matched;
        uint256 length = _stages.length;
        for (uint256 i; i < length; ++i) {
            if (_matchesPublicDrop(_stages[i], publicDrop)) {
                if (matched) revert InvalidPublicDrop();
                matched = true;
                matchedStage = i;
            }
        }
        if (!matched) revert InvalidPublicDrop();
    }

    function _stageStartTokenId(uint256 stageIndex) private view returns (uint256) {
        return stageIndex == 0 ? 1 : uint256(_stages[stageIndex - 1].endTokenId) + 1;
    }

    function _stageCapacity(uint256 stageIndex) private view returns (uint256) {
        return uint256(_stages[stageIndex].endTokenId) - _stageStartTokenId(stageIndex) + 1;
    }

    function _samePublicTerms(YieldBankMintStage memory left, YieldBankMintStage memory right)
        private
        pure
        returns (bool)
    {
        return left.mintPrice == right.mintPrice
            && left.maxMintsPerWallet == right.maxMintsPerWallet && left.feeBps == right.feeBps
            && left.restrictFeeRecipients == right.restrictFeeRecipients;
    }

    function _matchesPublicDrop(
        YieldBankMintStage memory configuredStage,
        PublicDrop memory publicDrop
    ) private pure returns (bool) {
        return publicDrop.mintPrice == configuredStage.mintPrice
            && publicDrop.maxTotalMintableByWallet == configuredStage.maxMintsPerWallet
            && publicDrop.feeBps == configuredStage.feeBps
            && publicDrop.restrictFeeRecipients == configuredStage.restrictFeeRecipients;
    }
}
