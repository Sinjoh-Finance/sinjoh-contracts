// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

contract MockArbSys {
    uint256 public currentBlockNumber;
    mapping(uint256 blockNumber => bytes32 blockHash) public hashes;

    function setBlockNumber(uint256 newBlockNumber) external {
        currentBlockNumber = newBlockNumber;
    }

    function setBlockHash(uint256 blockNumber, bytes32 blockHash) external {
        hashes[blockNumber] = blockHash;
    }

    function arbBlockNumber() external view returns (uint256) {
        return currentBlockNumber;
    }

    function arbBlockHash(uint256 blockNumber) external view returns (bytes32) {
        return hashes[blockNumber];
    }
}
