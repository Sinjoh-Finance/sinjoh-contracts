// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IRaffleRandomnessConsumer {
    function receiveRandomness(bytes32 requestId, uint256 seed) external;
}

contract MockRaffleArbSys {
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

contract MockRaffleRandomness {
    mapping(bytes32 requestId => address consumer) public consumerOf;
    mapping(address consumer => mapping(uint64 roundId => bytes32 requestId)) public requestOf;

    function requestRandomness(uint64 roundId) external returns (bytes32 requestId) {
        requestId = keccak256(abi.encode(block.chainid, address(this), msg.sender, roundId));
        require(consumerOf[requestId] == address(0), "requested");
        consumerOf[requestId] = msg.sender;
        requestOf[msg.sender][roundId] = requestId;
    }

    function deliver(bytes32 requestId, uint256 word) external {
        IRaffleRandomnessConsumer(consumerOf[requestId])
            .receiveRandomness(requestId, uint256(keccak256(abi.encode(requestId, word))));
    }
}

contract MockRaffleERC20 is ERC20 {
    mapping(address recipient => bool fails) public failRecipient;
    uint256 public revertSize;

    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) { }

    function mint(address recipient, uint256 amount) external {
        _mint(recipient, amount);
    }

    function setFailRecipient(address recipient, bool fails) external {
        failRecipient[recipient] = fails;
    }

    function setRevertSize(uint256 size) external {
        revertSize = size;
    }

    function _update(address from, address to, uint256 amount) internal override {
        if (failRecipient[to]) {
            uint256 size = revertSize;
            if (size == 0) revert("recipient");
            assembly ("memory-safe") {
                revert(0, size)
            }
        }
        super._update(from, to, amount);
    }
}

contract MockRaffleStockGuard {
    uint256 public multiplier = 2e18;
    bool public expired;

    function setExpired(bool value) external {
        expired = value;
    }

    function minimumOutput(
        address subject,
        address assetIn,
        address assetOut,
        uint256 amountIn,
        bytes32,
        bytes calldata
    ) external view returns (uint256 minimum, uint48 validUntil) {
        require(subject == assetOut && assetIn != assetOut, "pair");
        minimum = amountIn * multiplier / 1e18;
        validUntil = expired ? uint48(block.timestamp - 1) : type(uint48).max;
    }
}

contract MockRaffleStockAdapter {
    using SafeERC20 for IERC20;

    uint256 public multiplier = 2e18;

    function swap(address assetIn, address assetOut, uint256 amountIn, uint256, bytes calldata)
        external
        payable
    {
        require(msg.value == 0, "value");
        IERC20(assetIn).safeTransferFrom(msg.sender, address(this), amountIn);
        MockRaffleERC20(assetOut).mint(msg.sender, amountIn * multiplier / 1e18);
    }
}
