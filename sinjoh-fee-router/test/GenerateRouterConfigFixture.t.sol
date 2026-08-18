// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { RouterTypes } from "../src/RouterTypes.sol";

interface VmFixtures {
    function writeFile(string calldata path, string calldata data) external;
    function toString(bytes calldata value) external pure returns (string memory);
    function toString(bytes32 value) external pure returns (string memory);
}

/// @notice Emits the canonical `abi.encode(RouterTypes.Config)` and its keccak for a fixed
/// configuration exercising every struct field, so the SDK's TypeScript codec can be pinned
/// byte-for-byte against it. A field added, removed, reordered, or re-widthed on either side
/// changes these bytes and fails the SDK suite before a flow can derive a wrong configHash or
/// CREATE2 address. Regenerate with `forge test --match-contract GenerateRouterConfigFixture`
/// and copy into `sinjoh-sdk/packages/sdk/test/fixtures/`.
contract GenerateRouterConfigFixtureTest {
    VmFixtures internal constant vmf =
        VmFixtures(address(uint160(uint256(keccak256("hevm cheat code")))));

    function testWriteRouterConfigFixture() public {
        RouterTypes.Normalization[] memory normalizations = new RouterTypes.Normalization[](1);
        normalizations[0] = RouterTypes.Normalization({
            asset: RouterTypes.AssetRef({
                kind: RouterTypes.AssetKind.FIXED_ERC20, token: address(0xF100)
            }),
            route: RouterTypes.Route({ adapter: address(0xF101), routeData: hex"1234" }),
            priceGuard: address(0xF102),
            maxAmountInPerCall: 1 ether
        });

        RouterTypes.Allocation[] memory bucketZeroAllocations = new RouterTypes.Allocation[](2);
        bucketZeroAllocations[0] = RouterTypes.Allocation({
            destination: address(0xF201),
            bps: 7_000,
            isSink: false,
            creatorMayRepoint: true,
            sinkConfig: ""
        });
        bucketZeroAllocations[1] = RouterTypes.Allocation({
            destination: address(0xF202),
            bps: 3_000,
            isSink: true,
            creatorMayRepoint: false,
            sinkConfig: hex"deadbeef"
        });

        RouterTypes.Allocation[] memory bucketOneAllocations = new RouterTypes.Allocation[](1);
        bucketOneAllocations[0] = RouterTypes.Allocation({
            destination: address(0xF401),
            bps: 10_000,
            isSink: false,
            creatorMayRepoint: false,
            sinkConfig: ""
        });

        RouterTypes.Bucket[] memory buckets = new RouterTypes.Bucket[](2);
        buckets[0] = RouterTypes.Bucket({
            output: RouterTypes.AssetRef({
                kind: RouterTypes.AssetKind.FIXED_ERC20, token: address(0xEEE1)
            }),
            bps: 6_000,
            route: RouterTypes.Route({ adapter: address(0), routeData: "" }),
            priceGuard: address(0),
            maxAmountInPerCall: 5 ether,
            allocations: bucketZeroAllocations
        });
        buckets[1] = RouterTypes.Bucket({
            output: RouterTypes.AssetRef({
                kind: RouterTypes.AssetKind.SUBJECT, token: address(0)
            }),
            bps: 4_000,
            route: RouterTypes.Route({ adapter: address(0xF301), routeData: hex"abcd" }),
            priceGuard: address(0xF302),
            maxAmountInPerCall: 3 ether,
            allocations: bucketOneAllocations
        });

        RouterTypes.Config memory config = RouterTypes.Config({
            creator: address(0xC0ffee01),
            protocolFeeRecipient: address(0xC0ffee02),
            weth: address(0xEEE1),
            launchpadAdapter: address(0xC0ffee03),
            normalizations: normalizations,
            buckets: buckets
        });

        bytes memory encoded = abi.encode(config);
        string memory json = string.concat(
            '{"description":"canonical abi.encode(RouterTypes.Config) for the fixed config in GenerateRouterConfigFixture.t.sol",',
            '"encoded":"',
            vmf.toString(encoded),
            '","configHash":"',
            vmf.toString(keccak256(encoded)),
            '"}'
        );
        vmf.writeFile("test/fixtures/router-config.json", json);
    }
}
