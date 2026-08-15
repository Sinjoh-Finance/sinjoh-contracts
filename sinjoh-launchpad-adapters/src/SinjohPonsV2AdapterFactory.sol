// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Clones } from "./libraries/Clones.sol";
import { SinjohPonsV2Adapter } from "./SinjohPonsV2Adapter.sol";

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

    address public immutable implementation;
    address public immutable launchFactory;
    address public immutable feeEscrow;
    address public immutable weth;
    uint256 public immutable deploymentChainId;
    address public immutable binder;
    address public fundingBandsEscrow;

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
