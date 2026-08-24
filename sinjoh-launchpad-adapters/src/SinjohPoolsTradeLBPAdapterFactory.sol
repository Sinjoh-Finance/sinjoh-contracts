// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Clones } from "./libraries/Clones.sol";
import { SinjohPoolsTradeLBPAdapter } from "./SinjohPoolsTradeLBPAdapter.sol";
import { ProjectVotesToken } from "@sinjoh-v2/token/ProjectVotesToken.sol";
import {
    LaunchpadProjectVotesTokenFactoryV2
} from "@sinjoh-v2/token/LaunchpadProjectVotesTokenFactoryV2.sol";

interface ILBPAdapterIdentity {
    function creator() external view returns (address);
}

interface ILBPProjectLauncherBinding {
    function registry() external view returns (address);
}

/// @notice Deploys per-launch pools.trade LBP adapters as EIP-1167 clones and
/// keeps the subject registry the buyback route resolves pool keys through.
///
/// @dev Unlike the instant shape, an LBP pool's key is launch-configured (fee,
/// spacing, optional hook) rather than static, so a singleton swap adapter
/// cannot rebuild it from pinned constants. Each adapter records its migrated
/// key, and this registry maps a subject to the one adapter that launched it —
/// written exactly once, by a clone this factory itself deployed, inside the
/// launch transaction.
contract SinjohPoolsTradeLBPAdapterFactory {
    error InitializationFailed(bytes reason);
    error AdapterMismatch(address expected, address actual);
    error ConfigMismatch();
    error Unauthorized();
    error SubjectAlreadyRegistered(address subject);
    error InvalidAddress();
    error AlreadyBound();

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
    event SubjectRegistered(address indexed subject, address indexed adapter);

    address public immutable implementation;
    address public immutable launcher;
    address public immutable tokenFactory;
    address public immutable lbpStrategy;
    address public immutable tokenSplitter;
    address public immutable merkleClaimFactory;
    address public immutable weth;
    uint256 public immutable deploymentChainId;
    address public immutable binder;
    address public projectLauncher;
    address public projectRegistry;
    address public projectTokenFactory;
    address public projectRegistrationHelper;

    /// @notice Clones this factory deployed; the only addresses allowed to
    /// register a subject.
    mapping(address => bool) public isAdapter;
    /// @notice The adapter that launched a subject, or zero.
    mapping(address => address) public adapterForSubject;

    constructor(
        address launcher_,
        address tokenFactory_,
        address lbpStrategy_,
        address tokenSplitter_,
        address merkleClaimFactory_,
        address weth_,
        uint256 chainId_
    ) {
        implementation = address(
            new SinjohPoolsTradeLBPAdapter(
                launcher_,
                tokenFactory_,
                lbpStrategy_,
                tokenSplitter_,
                merkleClaimFactory_,
                weth_,
                chainId_,
                address(this)
            )
        );
        launcher = launcher_;
        tokenFactory = tokenFactory_;
        lbpStrategy = lbpStrategy_;
        tokenSplitter = tokenSplitter_;
        merkleClaimFactory = merkleClaimFactory_;
        weth = weth_;
        deploymentChainId = chainId_;
        binder = msg.sender;
    }

    function bindProjectV2(
        address projectLauncher_,
        address registry_,
        address tokenFactory_,
        address registrationHelper_
    ) external {
        if (msg.sender != binder) revert Unauthorized();
        if (projectLauncher != address(0)) revert AlreadyBound();
        if (
            projectLauncher_.code.length == 0 || registry_.code.length == 0
                || tokenFactory_.code.length == 0 || registrationHelper_.code.length == 0
                || ILBPProjectLauncherBinding(projectLauncher_).registry() != registry_
        ) revert InvalidAddress();
        projectLauncher = projectLauncher_;
        projectRegistry = registry_;
        projectTokenFactory = tokenFactory_;
        projectRegistrationHelper = registrationHelper_;
    }

    function deployProjectToken(
        address creator,
        string calldata name,
        string calldata symbol,
        uint128 totalSupply,
        bytes32 salt
    ) external returns (address token) {
        if (!isAdapter[msg.sender] || ILBPAdapterIdentity(msg.sender).creator() != creator) {
            revert Unauthorized();
        }
        return LaunchpadProjectVotesTokenFactoryV2(projectTokenFactory)
            .deploy(_projectTokenDeployment(creator, name, symbol, totalSupply, salt));
    }

    function predictProjectToken(
        address creator,
        string calldata name,
        string calldata symbol,
        uint128 totalSupply,
        bytes32 salt
    ) external view returns (address) {
        return LaunchpadProjectVotesTokenFactoryV2(projectTokenFactory)
            .predict(
                _projectTokenDeployment(creator, name, symbol, totalSupply, salt), address(this)
            );
    }

    function _projectTokenDeployment(
        address creator,
        string calldata name,
        string calldata symbol,
        uint128 totalSupply,
        bytes32 salt
    ) private view returns (LaunchpadProjectVotesTokenFactoryV2.TokenDeployment memory deployment) {
        ProjectVotesToken.TokenAllocation[] memory allocations =
            new ProjectVotesToken.TokenAllocation[](1);
        allocations[0] =
            ProjectVotesToken.TokenAllocation({ recipient: launcher, amount: totalSupply });
        deployment = LaunchpadProjectVotesTokenFactoryV2.TokenDeployment({
            name: name,
            symbol: symbol,
            registry: projectRegistry,
            creator: creator,
            allocations: allocations,
            votingExclusions: new address[](0),
            votingExclusionConfigurator: projectLauncher,
            salt: salt
        });
    }

    /// @notice Deploys the adapter for one launch. Idempotent: a second call
    /// with the same inputs returns the existing adapter rather than reverting,
    /// so an interrupted launch can be resumed.
    ///
    /// @dev Creator-only, for the same reason as every Sinjoh adapter factory:
    /// the salt cannot commit to the router, so an open deploy would let anyone
    /// seize the predicted clone and initialize it against a router of their
    /// choosing. The adapter additionally refuses to launch into a router that
    /// has not named it.
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
            try SinjohPoolsTradeLBPAdapter(payable(adapter)).initialize(router, creator) { }
            catch (bytes memory reason) {
                revert InitializationFailed(reason);
            }
            isAdapter[adapter] = true;
            created = true;
        } else {
            SinjohPoolsTradeLBPAdapter existing = SinjohPoolsTradeLBPAdapter(payable(adapter));
            if (existing.router() != router || existing.creator() != creator) {
                revert ConfigMismatch();
            }
        }

        emit AdapterDeployed(
            adapter, creator, router, userSalt, salt, deploymentChainId, implementation, created
        );
    }

    /// @notice Records the caller as the adapter for `subject`. Called by a
    /// clone during its launch transaction, after the token deployed and
    /// before the router bind.
    function registerSubject(address subject) external {
        if (!isAdapter[msg.sender]) revert Unauthorized();
        if (adapterForSubject[subject] != address(0)) revert SubjectAlreadyRegistered(subject);
        adapterForSubject[subject] = msg.sender;
        emit SubjectRegistered(subject, msg.sender);
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
                "SINJOH_POOLS_TRADE_LBP_ADAPTER",
                address(this),
                implementation,
                creator,
                userSalt,
                deploymentChainId
            )
        );
    }
}
