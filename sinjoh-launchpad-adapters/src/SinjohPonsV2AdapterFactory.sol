// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Clones } from "./libraries/Clones.sol";
import { SinjohPonsV2Adapter } from "./SinjohPonsV2Adapter.sol";
import { SinjohPonsV2ProjectAdapter } from "./SinjohPonsV2ProjectAdapter.sol";
import { IPonsV2LaunchFactory } from "./interfaces/IPonsV2.sol";

interface IProjectLauncherBinding {
    function registry() external view returns (address);
}

interface IFactoryAdapterIdentity {
    function creator() external view returns (address);
}

interface IProjectAdapterImplementation {
    function adapterFactory() external view returns (address);
    function launchFactory() external view returns (address);
    function feeEscrow() external view returns (address);
    function weth() external view returns (address);
    function deploymentChainId() external view returns (uint256);
}

/// @notice Deploys per-launch pons v2 adapters as EIP-1167 clones.
///
/// @dev Unlike the v1 factory, the salt does not include the subject token.
/// The redeployed `PonsV2LaunchDeployer` is CREATE2 again, so a v2 token
/// address is predictable from the launch salt — but the launch salt is
/// namespaced per initiating account, which is the adapter itself, so the
/// adapter's address must exist first either way. The adapter is deployed
/// first, bound to the router, and learns its subject when it launches.
contract SinjohPonsV2AdapterFactory {
    error InitializationFailed(bytes reason);
    error AdapterMismatch(address expected, address actual);
    error ConfigMismatch();
    error Unauthorized();
    error InvalidAddress();
    error AlreadyBound();
    error ProjectV2NotBound();
    error LaunchForwarderMismatch(address configured);

    struct ProjectTokenDeploymentData {
        address tokenFactory;
        address registry;
        address votingExclusionConfigurator;
        address[] votingExclusions;
    }

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
    event FundingBandsEscrowBound(address indexed escrow);
    event ProjectV2Bound(
        address indexed launcher, address indexed registry, address indexed tokenFactory
    );

    address public immutable implementation;
    address public immutable launchFactory;
    address public immutable feeEscrow;
    address public immutable weth;
    uint256 public immutable deploymentChainId;
    address public immutable binder;
    address public fundingBandsEscrow;
    address public projectLauncher;
    address public projectRegistry;
    address public projectTokenFactory;
    address public projectImplementation;
    mapping(address adapter => bool approved) public isAdapter;

    constructor(address launchFactory_, address feeEscrow_, address weth_, uint256 chainId_) {
        implementation =
            address(new SinjohPonsV2Adapter(launchFactory_, feeEscrow_, weth_, chainId_));
        launchFactory = launchFactory_;
        feeEscrow = feeEscrow_;
        weth = weth_;
        deploymentChainId = chainId_;
        binder = msg.sender;
    }

    /// @notice One-time binding to the escrow generation that Funding Bands
    /// launches may use. Ordinary Pons v2 launches do not depend on this value.
    function bindFundingBandsEscrow(address escrow) external {
        if (msg.sender != binder) revert Unauthorized();
        if (fundingBandsEscrow != address(0)) revert AlreadyBound();
        if (escrow.code.length == 0) revert InvalidAddress();
        fundingBandsEscrow = escrow;
        emit FundingBandsEscrowBound(escrow);
    }

    /// @notice One-time binding to the immutable Project V2 release used by canonical launches.
    function bindProjectV2(
        address launcher,
        address registry,
        address tokenFactory,
        address projectImplementation_
    ) external {
        if (msg.sender != binder) revert Unauthorized();
        if (projectLauncher != address(0)) revert AlreadyBound();
        if (
            launcher.code.length == 0 || registry.code.length == 0 || tokenFactory.code.length == 0
                || projectImplementation_.code.length == 0
                || IProjectLauncherBinding(launcher).registry() != registry
        ) revert InvalidAddress();
        IProjectAdapterImplementation projectAdapter =
            IProjectAdapterImplementation(projectImplementation_);
        if (
            projectAdapter.adapterFactory() != address(this)
                || projectAdapter.launchFactory() != launchFactory
                || projectAdapter.feeEscrow() != feeEscrow || projectAdapter.weth() != weth
                || projectAdapter.deploymentChainId() != deploymentChainId
        ) revert InvalidAddress();
        projectLauncher = launcher;
        projectRegistry = registry;
        projectTokenFactory = tokenFactory;
        projectImplementation = projectImplementation_;
        emit ProjectV2Bound(launcher, registry, tokenFactory);
    }

    /// @notice Deploys the Project V2-specific adapter that commits to its predicted router.
    function deployProject(address creator, address predictedRouter, bytes32 userSalt)
        external
        returns (address adapter)
    {
        if (msg.sender != creator) revert Unauthorized();
        address implementation_ = projectImplementation;
        if (implementation_ == address(0)) revert ProjectV2NotBound();
        bytes32 salt = derivedProjectSalt(creator, userSalt);
        adapter = Clones.predictDeterministicAddress(implementation_, salt, address(this));
        bool created;
        if (adapter.code.length == 0) {
            address deployed = Clones.cloneDeterministic(implementation_, salt);
            if (deployed != adapter) revert AdapterMismatch(adapter, deployed);
            try SinjohPonsV2ProjectAdapter(payable(adapter))
                .initialize(predictedRouter, creator) { }
            catch (bytes memory reason) {
                revert InitializationFailed(reason);
            }
            isAdapter[adapter] = true;
            created = true;
        } else {
            SinjohPonsV2ProjectAdapter existing = SinjohPonsV2ProjectAdapter(payable(adapter));
            if (existing.router() != predictedRouter || existing.creator() != creator) {
                revert ConfigMismatch();
            }
        }
        emit AdapterDeployed(
            adapter,
            creator,
            predictedRouter,
            userSalt,
            salt,
            deploymentChainId,
            implementation_,
            created
        );
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
            try SinjohPonsV2Adapter(payable(adapter)).initialize(router, creator) { }
            catch (bytes memory reason) {
                revert InitializationFailed(reason);
            }
            created = true;
            isAdapter[adapter] = true;
        } else {
            SinjohPonsV2Adapter existing = SinjohPonsV2Adapter(payable(adapter));
            if (existing.router() != router || existing.creator() != creator) {
                revert ConfigMismatch();
            }
        }

        emit AdapterDeployed(
            adapter, creator, router, userSalt, salt, deploymentChainId, implementation, created
        );
    }

    /// @notice Forwards a canonical-token launch for a clone recorded by this factory.
    function launchProjectTokenFor(
        IPonsV2LaunchFactory.TokenParams calldata params,
        uint256 launchConfigId,
        address pairToken,
        address originalDeployer,
        address[] calldata snipeTaxExemptions
    ) external payable returns (address token, address curve) {
        if (!isAdapter[msg.sender]) revert Unauthorized();
        if (IFactoryAdapterIdentity(msg.sender).creator() != originalDeployer) {
            revert Unauthorized();
        }
        address launcher = projectLauncher;
        if (launcher == address(0)) revert ProjectV2NotBound();
        address configuredForwarder = IPonsV2LaunchFactory(launchFactory).launchForwarder();
        if (configuredForwarder != address(this)) {
            revert LaunchForwarderMismatch(configuredForwarder);
        }

        address[] memory initialExclusions = new address[](0);
        bytes memory projectTokenData = abi.encode(
            ProjectTokenDeploymentData({
                tokenFactory: projectTokenFactory,
                registry: projectRegistry,
                votingExclusionConfigurator: launcher,
                votingExclusions: initialExclusions
            })
        );
        return IPonsV2LaunchFactory(launchFactory).launchProjectTokenFor{ value: msg.value }(
            params,
            launchConfigId,
            pairToken,
            originalDeployer,
            snipeTaxExemptions,
            projectTokenData
        );
    }

    /// @notice The adapter address for a launch, knowable before either the
    /// router or the token exists.
    function predictAddress(address creator, bytes32 userSalt) external view returns (address) {
        return Clones.predictDeterministicAddress(
            implementation, derivedSalt(creator, userSalt), address(this)
        );
    }

    function predictProjectAddress(address creator, bytes32 userSalt)
        external
        view
        returns (address)
    {
        return Clones.predictDeterministicAddress(
            projectImplementation, derivedProjectSalt(creator, userSalt), address(this)
        );
    }

    function derivedProjectSalt(address creator, bytes32 userSalt) public view returns (bytes32) {
        return keccak256(
            abi.encode(
                "SINJOH_PONS_PROJECT_V2_ADAPTER",
                address(this),
                projectImplementation,
                creator,
                userSalt,
                deploymentChainId
            )
        );
    }

    function derivedSalt(address creator, bytes32 userSalt) public view returns (bytes32) {
        return keccak256(
            abi.encode(
                "SINJOH_PONS_V2_ADAPTER",
                address(this),
                implementation,
                creator,
                userSalt,
                deploymentChainId
            )
        );
    }

    /// @notice Runtime code hash shared by every clone this factory deploys.
    /// @dev Funding Bands launch verifiers pin this value so an adapter from a
    /// different implementation generation cannot escrow launch inventory.
    function adapterRuntimeCodehash() public view returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                hex"363d3d373d3d3d363d73", implementation, hex"5af43d82803e903d91602b57fd5bf3"
            )
        );
    }
}
