// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Clones } from "./libraries/Clones.sol";
import { SinjohPonsV1LaunchAdapter } from "./SinjohPonsV1LaunchAdapter.sol";

/// @notice Deploys per-launch pons v1 adapters as EIP-1167 clones.
///
/// @dev Mirrors `SinjohPonsV2AdapterFactory` exactly, including the salt shape.
/// v1 does take a launch salt, so its token address is predictable — but the
/// adapter address still cannot commit to the router, because the router's
/// config names the adapter. Both derive from `(creator, userSalt)` alone and
/// the binding is proved at launch instead.
contract SinjohPonsV1LaunchAdapterFactory {
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
    address public immutable launchFactory;
    address public immutable locker;
    address public immutable weth;
    uint256 public immutable deploymentChainId;

    constructor(address launchFactory_, address locker_, address weth_, uint256 chainId_) {
        implementation =
            address(new SinjohPonsV1LaunchAdapter(launchFactory_, locker_, weth_, chainId_));
        launchFactory = launchFactory_;
        locker = locker_;
        weth = weth_;
        deploymentChainId = chainId_;
    }

    /// @notice Deploys the adapter for one launch. Creator-only, and idempotent
    /// so an interrupted launch can be resumed.
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
            try SinjohPonsV1LaunchAdapter(payable(adapter)).initialize(router, creator) { }
            catch (bytes memory reason) {
                revert InitializationFailed(reason);
            }
            created = true;
        } else {
            SinjohPonsV1LaunchAdapter existing = SinjohPonsV1LaunchAdapter(payable(adapter));
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
                "SINJOH_PONS_V1_LAUNCH_ADAPTER",
                address(this),
                implementation,
                creator,
                userSalt,
                deploymentChainId
            )
        );
    }
}
