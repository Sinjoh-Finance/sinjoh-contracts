// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Script } from "forge-std/Script.sol";

interface IPonsV2PairTokenAdministration {
    function owner() external view returns (address);
    function approvedPairTokens(address pairToken) external view returns (bool);
    function pairTokenEconomics(address pairToken)
        external
        view
        returns (uint256 phantomQuote, uint256 graduationThreshold, uint8 decimals);
    function setPairTokenEconomics(
        address pairToken,
        uint256 phantomQuote,
        uint256 graduationThreshold,
        uint8 decimals
    ) external;
    function setPairTokenApproved(address pairToken, bool approved) external;
}

/// @notice Configures and approves every paired asset exposed by the production Pons V2 launch UI.
/// @dev Re-running is safe: already-correct economics and approvals are skipped, then all state is
/// verified after broadcast. Economics must be committed before approval because the factory rejects
/// approval for an asset whose economics have not been configured.
contract ApprovePonsV2PairTokens is Script {
    address private constant USDG = 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168;
    address private constant NVDA = 0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC;
    address private constant SPCX = 0x4a0E65A3EcceC6dBe60AE065F2e7bb85Fae35eEa;
    address private constant GME = 0x1b0E319c6A659F002271B69dB8A7df2F911c153E;
    address private constant AAPL = 0xaF3D76f1834A1d425780943C99Ea8A608f8a93f9;
    address private constant TSLA = 0x322F0929c4625eD5bAd873c95208D54E1c003b2d;
    address private constant SPY = 0x117cc2133c37B721F49dE2A7a74833232B3B4C0C;

    uint256 private constant PHANTOM_QUOTE_WHOLE = 1_680_000_000_000_000_000;
    uint256 private constant GRADUATION_THRESHOLD_WHOLE = 4_200_000_000_000_000_000;

    function run() external {
        IPonsV2PairTokenAdministration factory =
            IPonsV2PairTokenAdministration(vm.envAddress("PONS_V2_LAUNCH_FACTORY"));
        address deployer = vm.envAddress("DEPLOYER_ADDRESS");
        require(factory.owner() == deployer, "DEPLOYER_NOT_FACTORY_OWNER");

        address[7] memory tokens = [USDG, NVDA, SPCX, GME, AAPL, TSLA, SPY];
        uint8[7] memory decimals = [uint8(6), 18, 18, 18, 18, 18, 18];

        vm.startBroadcast();
        for (uint256 i; i < tokens.length; ++i) {
            uint256 scale = 10 ** decimals[i];
            uint256 phantomQuote = PHANTOM_QUOTE_WHOLE * scale / 1e18;
            uint256 graduationThreshold = GRADUATION_THRESHOLD_WHOLE * scale / 1e18;
            (uint256 currentPhantom, uint256 currentThreshold, uint8 currentDecimals) =
                factory.pairTokenEconomics(tokens[i]);
            if (
                currentPhantom != phantomQuote || currentThreshold != graduationThreshold
                    || currentDecimals != decimals[i]
            ) {
                factory.setPairTokenEconomics(
                    tokens[i], phantomQuote, graduationThreshold, decimals[i]
                );
            }
            if (!factory.approvedPairTokens(tokens[i])) {
                factory.setPairTokenApproved(tokens[i], true);
            }
        }
        vm.stopBroadcast();

        for (uint256 i; i < tokens.length; ++i) {
            uint256 scale = 10 ** decimals[i];
            (uint256 phantomQuote, uint256 graduationThreshold, uint8 recordedDecimals) =
                factory.pairTokenEconomics(tokens[i]);
            require(phantomQuote == PHANTOM_QUOTE_WHOLE * scale / 1e18, "BAD_PHANTOM_QUOTE");
            require(
                graduationThreshold == GRADUATION_THRESHOLD_WHOLE * scale / 1e18,
                "BAD_GRADUATION_THRESHOLD"
            );
            require(recordedDecimals == decimals[i], "BAD_DECIMALS");
            require(factory.approvedPairTokens(tokens[i]), "PAIR_TOKEN_NOT_APPROVED");
        }
    }
}
