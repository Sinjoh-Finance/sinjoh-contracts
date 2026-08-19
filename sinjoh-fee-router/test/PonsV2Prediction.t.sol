// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { TestBase } from "./TestBase.sol";
import {
    IPonsV2BondingCurve,
    IPonsV2FeeEscrow,
    IPonsV2LaunchFactory
} from "../src/interfaces/IPonsV2.sol";

/// @notice Pins every selector crossing the Pons v2 boundary against the
/// literal signatures of the deployed, verified contracts.
/// @dev The copied `TokenParams` was once missing its trailing `salt` field,
/// which changed both `launchToken` selectors and made every launch revert
/// against the real factory — a silent incompatibility no mock could notice.
/// The launch itself now goes through `SinjohPonsV2Adapter`; this interface
/// remains the prediction library's view of the factory, and these constants
/// are the selectors read from the deployed factory's verified ABI. The
/// prediction end-to-end proof lives in
/// `sinjoh-integration/test/ProductionPonsV2Raffle.fork.t.sol`.
contract PonsV2PredictionTest is TestBase {
    function testPonsV2SelectorsArePinnedToTheDeployedContracts() public pure {
        string memory tokenParams =
            "(string,string,string,string,(string,string,string,string,string),address,uint16,bool,bytes32,bytes32)";
        assertEq(
            uint256(
                uint32(
                    bytes4(
                        keccak256(
                            abi.encodePacked("launchToken(", tokenParams, ",uint256,address)")
                        )
                    )
                )
            ),
            0xf35abbcf
        );
        assertEq(
            uint256(
                uint32(
                    bytes4(
                        keccak256(
                            abi.encodePacked(
                                "launchToken(", tokenParams, ",uint256,address,address[])"
                            )
                        )
                    )
                )
            ),
            0xa72101af
        );
        assertEq(
            uint256(uint32(IPonsV2BondingCurve.sweepFees.selector)),
            uint256(uint32(bytes4(keccak256("sweepFees(uint256)"))))
        );
        assertEq(
            uint256(uint32(IPonsV2FeeEscrow.claim.selector)),
            uint256(uint32(bytes4(keccak256("claim()"))))
        );
        assertEq(
            uint256(uint32(IPonsV2FeeEscrow.claimToken.selector)),
            uint256(uint32(bytes4(keccak256("claimToken(address)"))))
        );
        assertEq(
            uint256(uint32(IPonsV2LaunchFactory.getLaunchedToken.selector)),
            uint256(uint32(bytes4(keccak256("getLaunchedToken(address)"))))
        );
    }
}
