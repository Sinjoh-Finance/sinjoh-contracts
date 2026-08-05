// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { TestBase } from "./TestBase.sol";
import {
    IPonsV2LaunchDeployer,
    IPonsV2LaunchFactory,
    PonsV2FeePolicySnapshot,
    PonsV2LaunchDeployment
} from "../src/interfaces/IPonsV2.sol";

interface VmFixtures {
    function writeFile(string calldata path, string calldata data) external;
    function toString(bytes calldata value) external pure returns (string memory);
    function toString(address value) external pure returns (string memory);
    function toString(bytes32 value) external pure returns (string memory);
}

/// @notice Emits the exact `predictLaunchAddresses` calldata for a fixed input,
/// so the keeper's TypeScript twin can be pinned byte-for-byte against it.
/// @dev The prediction is an eth_call whose semantics live in the deployed
/// deployer; the only thing an off-chain caller can get wrong is the encoding
/// of `LaunchDeployment`. A struct field added, removed, or reordered on either
/// side changes these bytes, and the keeper test fails before any launch flow
/// can trust a wrong address. Regenerate with
/// `forge test --match-contract GeneratePonsV2Fixtures` and copy into
/// `sinjoh-keeper/test/fixtures/`.
contract GeneratePonsV2FixturesTest is TestBase {
    VmFixtures internal constant vmf =
        VmFixtures(address(uint160(uint256(keccak256("hevm cheat code")))));

    function testWritePonsV2PredictionFixture() public {
        PonsV2LaunchDeployment memory deployment = PonsV2LaunchDeployment({
            pairToken: address(0),
            creatorFeeRecipient: address(0xAAA1),
            originalDeployer: address(0xAAA2),
            feePolicy: address(0xAAA3),
            policy: PonsV2FeePolicySnapshot({
                protocolFeeRecipient: address(0xAAA4),
                protocolFeeShareBps: 2_500,
                buybackBurnBps: 1_000,
                hookFeeBps: 100,
                maxInternalPriceImpactBps: 300
            }),
            feeEscrow: address(0xAAA5),
            buybackVault: address(0xAAA6),
            phantomQuote: 1 ether,
            curveFeeBps: 100,
            creatorTaxBps: 250,
            buybackEnabled: false,
            graduationThreshold: 4.2 ether,
            supply: 1_000_000_000 ether,
            salt: bytes32("FIXTURE_SALT"),
            name: "Fixture Token",
            symbol: "FXT",
            logo: "ipfs://logo",
            description: "fixture",
            socials: IPonsV2LaunchFactory.Socials({
                twitter: "x",
                telegram: "t",
                discord: "",
                website: "https://example.invalid",
                farcaster: ""
            })
        });

        bytes memory callData =
            abi.encodeCall(IPonsV2LaunchDeployer.predictLaunchAddresses, (deployment));

        string memory json = string.concat(
            '{"description":"predictLaunchAddresses calldata for the fixed LaunchDeployment in GeneratePonsV2Fixtures.t.sol",',
            '"calldata":"',
            vmf.toString(callData),
            '"}'
        );
        vmf.writeFile("test/fixtures/ponsv2-prediction.json", json);
    }
}
