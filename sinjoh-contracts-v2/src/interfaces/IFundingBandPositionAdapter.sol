// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

/// @notice Vault-bound canonical concentrated-liquidity position surface for Funding Bands.
interface IFundingBandPositionAdapter {
    function bandsContract() external view returns (address);
    function subject() external view returns (address);
    function quoteAsset() external view returns (address);
    function canonicalPool() external view returns (address);
    function factory() external view returns (address);
    function positionManager() external view returns (address);

    function open(
        uint256 bandId,
        uint256 subjectAmount,
        int24 effectiveLowerTick,
        int24 effectiveUpperTick
    ) external returns (uint256 positionId, uint128 liquidity, uint256 subjectResidual);

    function increase(uint256 positionId, uint256 subjectAmount)
        external
        returns (uint128 liquidityAdded, uint256 subjectResidual);

    function exitAll(uint256 positionId, address recipient, bool requireConverted)
        external
        returns (address[] memory assets, uint256[] memory amounts);

    function positionLiquidity(uint256 positionId) external view returns (uint128 liquidity);
}
