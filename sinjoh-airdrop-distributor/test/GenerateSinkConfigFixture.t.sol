// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { SinjohAirdropDistributor } from "../src/SinjohAirdropDistributor.sol";

interface VmFixtures {
    function writeFile(string calldata path, string calldata data) external;
    function toString(bytes calldata value) external pure returns (string memory);
    function toString(bytes32 value) external pure returns (string memory);
}

/// @notice Emits the canonical `abi.encode(Config)` sink configuration and its keccak for a
/// fixed input, so the SDK's TypeScript codec can be pinned byte-for-byte against the exact
/// bytes `fund()` decodes and hashes. Regenerate with
/// `forge test --match-contract GenerateSinkConfigFixture` and copy into
/// `sinjoh-sdk/packages/sdk/test/fixtures/`.
contract GenerateSinkConfigFixtureTest {
    VmFixtures internal constant vmf =
        VmFixtures(address(uint160(uint256(keccak256("hevm cheat code")))));

    function testWriteAirdropSinkConfigFixture() public {
        address[] memory exclusions = new address[](3);
        exclusions[0] = address(0xE1);
        exclusions[1] = address(0xE2);
        exclusions[2] = address(0xE3);

        SinjohAirdropDistributor.Config memory config = SinjohAirdropDistributor.Config({
            minPayout: 1_000_000, maxBatchSize: 32, minConfirmations: 4, exclusions: exclusions
        });

        bytes memory encoded = abi.encode(config);
        string memory json = string.concat(
            '{"description":"canonical abi.encode(SinjohAirdropDistributor.Config) for the fixed config in GenerateSinkConfigFixture.t.sol",',
            '"encoded":"',
            vmf.toString(encoded),
            '","configHash":"',
            vmf.toString(keccak256(encoded)),
            '"}'
        );
        vmf.writeFile("test/fixtures/airdrop-sink-config.json", json);
    }
}
