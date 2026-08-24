// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

/// @notice Inert bytecode container used by one immutable Launcher release manifest.
/// @dev A leading STOP byte prevents accidental calls from executing stored creation code.
contract CreationCodeChunkV2 {
    constructor(bytes memory data) {
        bytes memory runtime = bytes.concat(hex"00", data);
        assembly ("memory-safe") {
            return(add(runtime, 0x20), mload(runtime))
        }
    }
}

/// @notice Ownerless, immutable storage for one module's exact creation code.
/// @dev Chunking avoids the EIP-170 runtime limit while keeping launch transactions small.
contract CreationCodeStoreV2 {
    uint256 public constant MAX_CHUNK_BYTES = 24_000;

    bytes32 public immutable creationCodeHash;
    uint256 public immutable creationCodeLength;
    address[] private _chunks;

    error EmptyCreationCode();
    error CreationCodeTooLarge(uint256 supplied);

    constructor(bytes memory creationCode_) {
        uint256 length = creationCode_.length;
        if (length == 0) revert EmptyCreationCode();
        // A module creation payload must still fit the protocol's bounded launch transaction.
        if (length > 49_000) revert CreationCodeTooLarge(length);

        creationCodeHash = keccak256(creationCode_);
        creationCodeLength = length;

        for (uint256 offset; offset < length; offset += MAX_CHUNK_BYTES) {
            uint256 chunkLength = length - offset;
            if (chunkLength > MAX_CHUNK_BYTES) chunkLength = MAX_CHUNK_BYTES;
            bytes memory chunk = new bytes(chunkLength);
            for (uint256 i; i < chunkLength; ++i) {
                chunk[i] = creationCode_[offset + i];
            }
            _chunks.push(address(new CreationCodeChunkV2(chunk)));
        }
    }

    function chunkCount() external view returns (uint256) {
        return _chunks.length;
    }

    function chunkAt(uint256 index) external view returns (address) {
        return _chunks[index];
    }

    function creationCode() external view returns (bytes memory result) {
        result = new bytes(creationCodeLength);
        uint256 outputOffset;
        uint256 count = _chunks.length;
        for (uint256 i; i < count; ++i) {
            address chunk = _chunks[i];
            uint256 length = chunk.code.length - 1;
            assembly ("memory-safe") {
                extcodecopy(chunk, add(add(result, 0x20), outputOffset), 1, length)
            }
            outputOffset += length;
        }
    }
}
