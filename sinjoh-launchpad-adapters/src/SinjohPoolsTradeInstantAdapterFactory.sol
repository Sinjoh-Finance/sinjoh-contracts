// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Clones } from "./libraries/Clones.sol";
import { SinjohPoolsTradeInstantAdapter } from "./SinjohPoolsTradeInstantAdapter.sol";

/// @notice Deploys per-launch pools.trade instant-launch adapters as EIP-1167
/// clones.
///
/// @dev One factory per strategy variant: the implementation pins exactly one
/// InstantLaunchStrategy, so the creator-fee and no-creator-fee variants get
/// separate factory deployments rather than a launch-time strategy parameter —
/// a caller-supplied strategy would be an arbitrary-target surface.
///
/// The salt does not include the subject token. The UERC20 token address is
/// predictable from (name, symbol) once the adapter address exists — the
/// graffiti hashes the adapter — so the adapter must be deployed first either
/// way. It is deployed, bound to the router, and learns its subject when it
/// launches.
contract SinjohPoolsTradeInstantAdapterFactory {
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
    address public immutable launcher;
    address public immutable tokenFactory;
    address public immutable strategy;
    address public immutable weth;
    uint256 public immutable deploymentChainId;

    constructor(
        address launcher_,
        address tokenFactory_,
        address strategy_,
        address weth_,
        uint256 chainId_
    ) {
        implementation = address(
            new SinjohPoolsTradeInstantAdapter(launcher_, tokenFactory_, strategy_, weth_, chainId_)
        );
        launcher = launcher_;
        tokenFactory = tokenFactory_;
        strategy = strategy_;
        weth = weth_;
        deploymentChainId = chainId_;
    }

    /// @notice Deploys the adapter for one launch. Idempotent: a second call
    /// with the same inputs returns the existing adapter rather than reverting,
    /// so an interrupted launch can be resumed.
    ///
    /// @dev Creator-only. The salt cannot commit to the router — the router's
    /// own config must name this adapter as its authorized binder, and putting
    /// the router in the salt would make each address depend on the other. With
    /// the cycle broken, an open `deploy` would let anyone seize the predicted
    /// clone and initialize it against a router of their choosing, so the
    /// caller is restricted instead. The adapter additionally refuses to launch
    /// into a router that has not named it.
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
            // The prediction is what the router committed to as its authorized
            // binder before either contract existed. A mismatch means the two
            // disagree, and the launch must not proceed.
            if (deployed != adapter) revert AdapterMismatch(adapter, deployed);
            try SinjohPoolsTradeInstantAdapter(payable(adapter)).initialize(router, creator) { }
            catch (bytes memory reason) {
                revert InitializationFailed(reason);
            }
            created = true;
        } else {
            SinjohPoolsTradeInstantAdapter existing =
                SinjohPoolsTradeInstantAdapter(payable(adapter));
            if (existing.router() != router || existing.creator() != creator) {
                revert ConfigMismatch();
            }
        }

        emit AdapterDeployed(
            adapter, creator, router, userSalt, salt, deploymentChainId, implementation, created
        );
    }

    /// @notice The adapter address for a launch, knowable before either the
    /// router or the token exists.
    function predictAddress(address creator, bytes32 userSalt) external view returns (address) {
        return Clones.predictDeterministicAddress(
            implementation, derivedSalt(creator, userSalt), address(this)
        );
    }

    function derivedSalt(address creator, bytes32 userSalt) public view returns (bytes32) {
        return keccak256(
            abi.encode(
                "SINJOH_POOLS_TRADE_INSTANT_ADAPTER",
                address(this),
                implementation,
                creator,
                userSalt,
                deploymentChainId
            )
        );
    }
}
