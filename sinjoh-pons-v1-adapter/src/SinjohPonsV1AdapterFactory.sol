// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Clones } from "./libraries/Clones.sol";
import { SinjohPonsV1Adapter } from "./SinjohPonsV1Adapter.sol";

contract SinjohPonsV1AdapterFactory {
    error InitializationFailed(bytes reason);

    event AdapterDeployed(
        address indexed adapter,
        address indexed creator,
        address indexed subject,
        address router,
        bytes32 userSalt,
        bytes32 derivedSalt,
        uint256 chainId,
        address implementation,
        bool created
    );

    address public immutable implementation;
    address public immutable ponsLocker;
    address public immutable weth;
    uint256 public immutable deploymentChainId;

    constructor(address ponsLocker_, address weth_, uint256 chainId_) {
        SinjohPonsV1Adapter implementation_ = new SinjohPonsV1Adapter(ponsLocker_, weth_, chainId_);
        implementation = address(implementation_);
        ponsLocker = ponsLocker_;
        weth = weth_;
        deploymentChainId = chainId_;
    }

    function deploy(address creator, address subject, address router, bytes32 userSalt)
        external
        returns (address adapter)
    {
        bytes32 salt = derivedSalt(creator, subject, router, userSalt);
        adapter = Clones.predictDeterministicAddress(implementation, salt, address(this));
        bool created;
        if (adapter.code.length == 0) {
            adapter = Clones.cloneDeterministic(implementation, salt);
            try SinjohPonsV1Adapter(adapter).initialize(subject, router) { }
            catch (bytes memory reason) {
                revert InitializationFailed(reason);
            }
            created = true;
        }
        emit AdapterDeployed(
            adapter,
            creator,
            subject,
            router,
            userSalt,
            salt,
            deploymentChainId,
            implementation,
            created
        );
    }

    function predictAddress(address creator, address subject, address router, bytes32 userSalt)
        external
        view
        returns (address)
    {
        bytes32 salt = derivedSalt(creator, subject, router, userSalt);
        return Clones.predictDeterministicAddress(implementation, salt, address(this));
    }

    function derivedSalt(address creator, address subject, address router, bytes32 userSalt)
        public
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                address(this), implementation, creator, subject, router, userSalt, deploymentChainId
            )
        );
    }
}
