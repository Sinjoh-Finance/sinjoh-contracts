// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

/// @notice Configurable constructor-validation fixture; not a production vote source.
contract MockVoteSource {
    address public immutable registry;
    bytes32 public immutable projectId;
    address public immutable subject;
    string private _clockMode;

    constructor(address registry_, bytes32 projectId_, address subject_, string memory clockMode_) {
        registry = registry_;
        projectId = projectId_;
        subject = subject_;
        _clockMode = clockMode_;
    }

    function clock() external view returns (uint48) {
        return uint48(block.timestamp);
    }

    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() external view returns (string memory) {
        return _clockMode;
    }

    function getVotes(address) external pure returns (uint256) {
        return 0;
    }

    function getPastVotes(address, uint256) external pure returns (uint256) {
        return 0;
    }

    function getPastTotalSupply(uint256) external pure returns (uint256) {
        return 0;
    }

    function delegates(address account) external pure returns (address) {
        return account;
    }

    function delegate(address) external pure { }

    function delegateBySig(address, uint256, uint256, uint8, bytes32, bytes32) external pure { }
}
