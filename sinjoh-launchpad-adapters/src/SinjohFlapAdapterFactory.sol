// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Clones } from "./libraries/Clones.sol";
import { SinjohFlapAdapter } from "./SinjohFlapAdapter.sol";

/// @notice Deploys one predictable EIP-1167 Sinjoh Flap adapter per launch.
contract SinjohFlapAdapterFactory {
    error InitializationFailed(bytes reason);
    error AdapterMismatch(address expected, address actual);
    error ConfigMismatch();
    error Unauthorized();

    event AdapterDeployed(
        address indexed adapter,
        address indexed creator,
        address indexed router,
        bytes32 userSalt,
        bytes32 derivedSalt,
        uint256 chainId,
        address implementation,
        bool created
    );

    address public immutable implementation;
    address public immutable portal;
    address public immutable taxTokenImplementation;
    address public immutable flapWrappedNative;
    address public immutable weth;
    uint256 public immutable deploymentChainId;

    constructor(
        address portal_,
        address taxTokenImplementation_,
        address flapWrappedNative_,
        address weth_,
        uint256 chainId_
    ) {
        implementation = address(
            new SinjohFlapAdapter(
                portal_, taxTokenImplementation_, flapWrappedNative_, weth_, chainId_
            )
        );
        portal = portal_;
        taxTokenImplementation = taxTokenImplementation_;
        flapWrappedNative = flapWrappedNative_;
        weth = weth_;
        deploymentChainId = chainId_;
    }

    /// @dev The router config names the predicted adapter, so including the
    /// router in this salt would make the two CREATE2 addresses circular. The
    /// creator-only deploy and launch-time mutual checks replace that salt link.
    function deploy(address creator, address router, bytes32 userSalt)
        external
        returns (address adapter)
    {
        if (msg.sender != creator) revert Unauthorized();
        bytes32 salt = derivedSalt(creator, userSalt);
        adapter = Clones.predictDeterministicAddress(implementation, salt, address(this));

        bool created;
        if (adapter.code.length == 0) {
            address deployed = Clones.cloneDeterministic(implementation, salt);
            if (deployed != adapter) revert AdapterMismatch(adapter, deployed);
            try SinjohFlapAdapter(payable(adapter)).initialize(router, creator) { }
            catch (bytes memory reason) {
                revert InitializationFailed(reason);
            }
            created = true;
        } else {
            SinjohFlapAdapter existing = SinjohFlapAdapter(payable(adapter));
            if (existing.router() != router || existing.creator() != creator) {
                revert ConfigMismatch();
            }
        }

        emit AdapterDeployed(
            adapter, creator, router, userSalt, salt, deploymentChainId, implementation, created
        );
    }

    function predictAddress(address creator, bytes32 userSalt) external view returns (address) {
        return Clones.predictDeterministicAddress(
            implementation, derivedSalt(creator, userSalt), address(this)
        );
    }

    function derivedSalt(address creator, bytes32 userSalt) public view returns (bytes32) {
        return keccak256(
            abi.encode(
                "SINJOH_FLAP_ADAPTER",
                address(this),
                implementation,
                creator,
                userSalt,
                deploymentChainId
            )
        );
    }
}
