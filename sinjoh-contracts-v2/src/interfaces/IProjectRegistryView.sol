// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

interface IProjectRegistryView {
    function projectIdBySubject(address subject) external view returns (bytes32);
    function isProjectModule(bytes32 projectId, address candidate) external view returns (bool);
}
