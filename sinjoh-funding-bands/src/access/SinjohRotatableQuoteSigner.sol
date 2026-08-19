// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @notice Governance-recoverable ECDSA authority for price observations.
/// @dev Governance can only rotate the signer. It cannot move Funding Bands
/// inventory, edit bands, settle positions, or redirect proceeds.
abstract contract SinjohRotatableQuoteSigner is Ownable2Step {
    error InvalidQuoteSigner(address signer);
    error OwnershipRenunciationDisabled();

    event QuoteSignerUpdated(address indexed previousSigner, address indexed newSigner);

    address public quoteSigner;

    constructor(address initialGovernance, address initialQuoteSigner) Ownable(initialGovernance) {
        _setQuoteSigner(initialQuoteSigner);
    }

    /// @notice Replaces the ECDSA signer used for future observations.
    function setQuoteSigner(address newSigner) external onlyOwner {
        _setQuoteSigner(newSigner);
    }

    /// @notice Disabled so the recovery path cannot be removed accidentally.
    function renounceOwnership() public pure override {
        revert OwnershipRenunciationDisabled();
    }

    function _setQuoteSigner(address newSigner) private {
        if (newSigner == address(0) || newSigner == address(this) || newSigner.code.length != 0) {
            revert InvalidQuoteSigner(newSigner);
        }
        address previousSigner = quoteSigner;
        quoteSigner = newSigner;
        emit QuoteSignerUpdated(previousSigner, newSigner);
    }
}
