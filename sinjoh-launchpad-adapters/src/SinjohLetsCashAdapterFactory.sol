// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Clones } from "./libraries/Clones.sol";
import { SinjohLetsCashAdapter } from "./SinjohLetsCashAdapter.sol";

/// @notice Deploys one predictable EIP-1167 letscash.fun adapter per launch.
contract SinjohLetsCashAdapterFactory {
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
    address public immutable poolManager;
    address public immutable hook;
    address public immutable weth;
    uint256 public immutable deploymentChainId;

    constructor(
        address launchFactory_,
        address poolManager_,
        address hook_,
        address weth_,
        uint256 chainId_
    ) {
        implementation = address(
            new SinjohLetsCashAdapter(launchFactory_, poolManager_, hook_, weth_, chainId_)
        );
        launchFactory = launchFactory_;
        poolManager = poolManager_;
        hook = hook_;
        weth = weth_;
        deploymentChainId = chainId_;
    }

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
            try SinjohLetsCashAdapter(payable(adapter)).initialize(router, creator) { }
            catch (bytes memory reason) {
                revert InitializationFailed(reason);
            }
            created = true;
        } else {
            SinjohLetsCashAdapter existing = SinjohLetsCashAdapter(payable(adapter));
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
                "SINJOH_LETSCASH_ADAPTER",
                address(this),
                implementation,
                creator,
                userSalt,
                deploymentChainId
            )
        );
    }
}
