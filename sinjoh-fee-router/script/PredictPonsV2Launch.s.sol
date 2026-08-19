// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IPonsV2LaunchFactory } from "../src/interfaces/IPonsV2.sol";
import { PonsV2LaunchPrediction } from "../src/libraries/PonsV2LaunchPrediction.sol";

interface VmPredict {
    function envAddress(string calldata name) external view returns (address);
    function envBytes32(string calldata name) external view returns (bytes32);
    function envOr(string calldata name, uint256 defaultValue) external view returns (uint256);
    function envOr(string calldata name, address defaultValue) external view returns (address);
    function envOr(string calldata name, string calldata defaultValue)
        external
        view
        returns (string memory);
    function toString(address value) external pure returns (string memory);
    function toString(bytes32 value) external pure returns (string memory);
}

/// @notice Prints everything the raffle launch flow needs to know before the
/// launch is sent: the predicted token and curve, and the complete, sorted
/// exclusion list a raffle over this launch must be configured with.
///
/// Read-only; never broadcasts. `ORIGINAL_DEPLOYER` is the account that will
/// initiate the launch at the Pons factory — the launchpad adapter for
/// adapter-owned launches (predict it first with
/// `SinjohPonsV2AdapterFactory.predictAddress`), or a router or EOA that calls
/// `launchToken` itself.
///
/// ```sh
/// PONS_V2_FACTORY=0x… ORIGINAL_DEPLOYER=0x… LAUNCH_SALT=0x… \
///   TOKEN_NAME=… TOKEN_SYMBOL=… CREATOR_TAX_BPS=… FEE_RECIPIENT=0x… \
///   forge script script/PredictPonsV2Launch.s.sol:PredictPonsV2Launch \
///   --rpc-url https://rpc.mainnet.chain.robinhood.com
/// ```
///
/// The prediction only holds while the factory's owner-tunable terms hold.
/// Always pin `expectedEconomics = previewLaunchEconomics(configId, pairToken)`
/// in the launch itself: a launch whose terms moved after this prediction then
/// reverts instead of landing on an unpredicted curve address — which would
/// otherwise leave an already-deployed raffle excluding the wrong contract.
contract PredictPonsV2Launch {
    VmPredict internal constant vm =
        VmPredict(address(uint160(uint256(keccak256("hevm cheat code")))));
    address internal constant CONSOLE = 0x000000000000000000636F6e736F6c652e6c6f67;

    function run() external view returns (address token, address curve) {
        address factory = vm.envAddress("PONS_V2_FACTORY");
        address originalDeployer = vm.envAddress("ORIGINAL_DEPLOYER");
        address pairToken = vm.envOr("PAIR_TOKEN", address(0));
        uint256 launchConfigId = vm.envOr("LAUNCH_CONFIG_ID", uint256(0));

        IPonsV2LaunchFactory.TokenParams memory params = IPonsV2LaunchFactory.TokenParams({
            name: vm.envOr("TOKEN_NAME", string("")),
            symbol: vm.envOr("TOKEN_SYMBOL", string("")),
            logo: vm.envOr("TOKEN_LOGO", string("")),
            description: vm.envOr("TOKEN_DESCRIPTION", string("")),
            socials: IPonsV2LaunchFactory.Socials({
                twitter: vm.envOr("SOCIAL_TWITTER", string("")),
                telegram: vm.envOr("SOCIAL_TELEGRAM", string("")),
                discord: vm.envOr("SOCIAL_DISCORD", string("")),
                website: vm.envOr("SOCIAL_WEBSITE", string("")),
                farcaster: vm.envOr("SOCIAL_FARCASTER", string(""))
            }),
            creatorFeeRecipient: vm.envOr("FEE_RECIPIENT", originalDeployer),
            // forge-lint: disable-next-line(unsafe-typecast)
            creatorTaxBps: uint16(vm.envOr("CREATOR_TAX_BPS", uint256(0))),
            buybackEnabled: false,
            expectedEconomics: bytes32(0),
            salt: vm.envBytes32("LAUNCH_SALT")
        });

        (token, curve) = PonsV2LaunchPrediction.predict(
            factory, params, launchConfigId, pairToken, originalDeployer
        );

        IPonsV2LaunchFactory pons = IPonsV2LaunchFactory(factory);
        _log("=== Pons v2 launch prediction ===");
        _log(string.concat("token: ", vm.toString(token)));
        _log(string.concat("curve: ", vm.toString(curve)));
        _log(
            string.concat(
                "expectedEconomics to pin: ",
                vm.toString(pons.previewLaunchEconomics(launchConfigId, pairToken))
            )
        );
        _log("");
        _log("Raffle exclusion list for this launch (sort ascending before configuring):");
        _log(string.concat("  curve:        ", vm.toString(curve)));
        _log(string.concat("  factory:      ", vm.toString(factory)));
        _log(string.concat("  poolManager:  ", vm.toString(pons.poolManager())));
        _log(string.concat("  buybackVault: ", vm.toString(pons.buybackVault())));
        _log(string.concat("  memeHook:     ", vm.toString(pons.memeHook())));
        _log("The token itself, zero, dEaD, and the raffle are excluded automatically.");
    }

    function _log(string memory line) private view {
        (bool ok,) = CONSOLE.staticcall(abi.encodeWithSignature("log(string)", line));
        ok;
    }
}
