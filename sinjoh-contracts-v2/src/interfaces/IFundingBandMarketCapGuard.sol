// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { FundingBandObservation } from "../bands/FundingBandTypes.sol";

/// @notice Platform-approved TWAP and quote/USD observation source for one canonical project pool.
interface IFundingBandMarketCapGuard {
    function bandsContract() external view returns (address);
    function subject() external view returns (address);
    function canonicalPool() external view returns (address);
    function referenceSupply() external view returns (uint256);
    function minimumTwapWindow() external view returns (uint32);
    function observe(uint128 lowerMarketCapUsdE8, uint128 upperMarketCapUsdE8, bytes calldata data)
        external
        view
        returns (FundingBandObservation memory observation);
}
