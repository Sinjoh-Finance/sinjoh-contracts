// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IGovernanceController } from "../interfaces/IGovernanceController.sol";

/// @notice Shared authorization adapter for an EOA, Safe/Joint, or governor/timelock executor.
/// @dev The authority type is disclosure metadata. The authority contract remains responsible
/// for its own quorum, voting, delegation, and execution-delay rules. The authority can
/// irreversibly freeze the shared controller after all governed modules are configured.
contract AddressGovernanceController is IGovernanceController {
    Mode public override mode;
    address public override authority;

    error InvalidAuthority();
    error InvalidMode();

    event GovernanceFrozen(address indexed previousAuthority, Mode indexed previousMode);

    constructor(address authority_, Mode mode_) {
        if (authority_ == address(0)) revert InvalidAuthority();
        if (mode_ == Mode.IMMUTABLE) revert InvalidMode();
        if (mode_ != Mode.INDIVIDUAL && authority_.code.length == 0) {
            revert InvalidAuthority();
        }
        authority = authority_;
        mode = mode_;
    }

    function canCall(address caller, address, bytes4) external view returns (bool) {
        return caller == authority;
    }

    function freeze() external {
        address previousAuthority = authority;
        Mode previousMode = mode;
        if (msg.sender != previousAuthority || previousMode == Mode.IMMUTABLE) {
            revert InvalidAuthority();
        }
        authority = address(0);
        mode = Mode.IMMUTABLE;
        emit GovernanceFrozen(previousAuthority, previousMode);
    }
}
