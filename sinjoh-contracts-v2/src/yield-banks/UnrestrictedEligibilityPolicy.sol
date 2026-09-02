// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IYieldBankEligibilityPolicy } from "./interfaces/IYieldBankEligibilityPolicy.sol";

/// @notice Immutable eligibility policy that permits every address and proof.
/// @dev Intended for collections that do not impose transfer, mint, share, or redemption gates.
contract UnrestrictedEligibilityPolicy is IYieldBankEligibilityPolicy {
    function canMint(address, bytes calldata) external pure returns (bool) {
        return true;
    }

    function canReceiveNFT(address, bytes calldata) external pure returns (bool) {
        return true;
    }

    function canReceiveRestrictedShares(address, bytes calldata) external pure returns (bool) {
        return true;
    }

    function canRedeem(address, bytes calldata) external pure returns (bool) {
        return true;
    }
}
