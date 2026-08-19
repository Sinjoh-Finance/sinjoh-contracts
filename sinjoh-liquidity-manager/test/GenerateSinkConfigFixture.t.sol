// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { SinjohLiquidityManager } from "../src/SinjohLiquidityManager.sol";

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

    function testWriteLiquiditySinkConfigFixture() public {
        SinjohLiquidityManager.Config memory config = SinjohLiquidityManager.Config({
            venue: SinjohLiquidityManager.Venue.UNISWAP_V4,
            quoteAsset: address(0xD101),
            poolFee: 3_000,
            tickSpacing: 60,
            hooks: address(0xD102),
            swapAdapter: address(0xD103),
            priceGuard: address(0xD104),
            swapRouteData: hex"00000000000000000000000000000000000000000000000000000001000276a4",
            quoteSwapBps: 5_000,
            maxMintSlippageBps: 300,
            minNotionalPerMint: 0.01 ether,
            maxNotionalPerMint: 10 ether,
            minMintInterval: 3_600,
            feeMode: SinjohLiquidityManager.FeeMode.RECYCLE,
            feeRecipient: address(0)
        });

        bytes memory encoded = abi.encode(config);
        string memory json = string.concat(
            '{"description":"canonical abi.encode(SinjohLiquidityManager.Config) for the fixed config in GenerateSinkConfigFixture.t.sol",',
            '"encoded":"',
            vmf.toString(encoded),
            '","configHash":"',
            vmf.toString(keccak256(encoded)),
            '"}'
        );
        vmf.writeFile("test/fixtures/liquidity-sink-config.json", json);
    }
}
