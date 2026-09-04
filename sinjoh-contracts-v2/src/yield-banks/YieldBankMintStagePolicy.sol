// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { YieldBankMintStage } from "./YieldBankTypes.sol";

/// @notice Optional collection-specific enforcement for ordered paid SeaDrop stages.
/// @dev The NFT pins one policy before minting. Stage values are constructor inputs so the generic
///      protocol contains no collection names, prices, supplies, or wallet limits.
contract YieldBankMintStagePolicy {
    uint16 private constant BPS = 10_000;
    uint256 private constant MAX_STAGES = 16;

    address public immutable nft;
    uint256 public immutable maxSupply;
    YieldBankMintStage[] private _stages;
    mapping(uint256 stageIndex => mapping(address minter => uint256 quantity)) public
        numberMintedByStage;

    error InvalidConfiguration();
    error OnlyNFT(address caller);
    error StageBoundary(uint256 stageIndex, uint256 requestedLastTokenId, uint256 stageEndTokenId);
    error StageWalletLimit(
        uint256 stageIndex, address minter, uint256 requestedTotal, uint256 stageLimit
    );
    error InsufficientSeaDropPayment(uint256 expectedGrossProceeds, uint256 availableBalance);

    constructor(address nft_, uint256 maxSupply_, YieldBankMintStage[] memory stages) {
        uint256 length = stages.length;
        if (nft_.code.length == 0 || maxSupply_ == 0 || length == 0 || length > MAX_STAGES) {
            revert InvalidConfiguration();
        }
        nft = nft_;
        maxSupply = maxSupply_;
        uint64 previousEnd;
        for (uint256 i; i < length; ++i) {
            YieldBankMintStage memory configuredStage = stages[i];
            if (
                configuredStage.endTokenId <= previousEnd || configuredStage.mintPrice == 0
                    || configuredStage.maxMintsPerWallet == 0 || configuredStage.feeBps >= BPS
            ) revert InvalidConfiguration();
            _stages.push(configuredStage);
            previousEnd = configuredStage.endTokenId;
        }
        if (previousEnd != maxSupply_) revert InvalidConfiguration();
    }

    function recordMint(
        address minter,
        uint256 quantity,
        uint256 currentTotalMinted,
        uint256 seaDropBalance
    ) external returns (uint256 expectedNetProceeds) {
        if (msg.sender != nft) revert OnlyNFT(msg.sender);
        uint256 stageIndex = _activeStageIndex(currentTotalMinted);
        YieldBankMintStage memory configuredStage = _stages[stageIndex];
        uint256 requestedLastTokenId = currentTotalMinted + quantity;
        if (requestedLastTokenId > configuredStage.endTokenId) {
            revert StageBoundary(stageIndex, requestedLastTokenId, configuredStage.endTokenId);
        }
        uint256 requestedTotal = numberMintedByStage[stageIndex][minter] + quantity;
        if (requestedTotal > configuredStage.maxMintsPerWallet) {
            revert StageWalletLimit(
                stageIndex, minter, requestedTotal, configuredStage.maxMintsPerWallet
            );
        }
        uint256 expectedGrossProceeds = uint256(configuredStage.mintPrice) * quantity;
        if (seaDropBalance < expectedGrossProceeds) {
            revert InsufficientSeaDropPayment(expectedGrossProceeds, seaDropBalance);
        }
        numberMintedByStage[stageIndex][minter] = requestedTotal;
        expectedNetProceeds =
            expectedGrossProceeds - (expectedGrossProceeds * configuredStage.feeBps / BPS);
    }

    function mintStats(address minter, uint256 currentTotalMinted)
        external
        view
        returns (uint256 stageMints, uint256 stageSupply)
    {
        uint256 stageIndex = _activeStageIndex(currentTotalMinted);
        return (numberMintedByStage[stageIndex][minter], _stages[stageIndex].endTokenId);
    }

    function stageCount() external view returns (uint256) {
        return _stages.length;
    }

    function stage(uint256 stageIndex) external view returns (YieldBankMintStage memory) {
        return _stages[stageIndex];
    }

    function _activeStageIndex(uint256 currentTotalMinted) private view returns (uint256 low) {
        uint256 tokenId = currentTotalMinted + 1;
        uint256 high = _stages.length;
        while (low < high) {
            uint256 mid = (low + high) >> 1;
            if (tokenId <= _stages[mid].endTokenId) high = mid;
            else low = mid + 1;
        }
    }
}
