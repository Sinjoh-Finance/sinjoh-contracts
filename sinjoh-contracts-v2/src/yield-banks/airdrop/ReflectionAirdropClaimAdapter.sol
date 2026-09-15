// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;
import { IAirdropClaimAdapter } from "./AirdropAssetRegistry.sol";

interface IReflectionAirdrop {
    function token() external view returns (address);
    function rewardToken() external view returns (address);
    function claimDividend() external;
}

/// @notice The custody is msg.sender at the distributor. No recipient override is possible.
contract ReflectionAirdropClaimAdapter is IAirdropClaimAdapter {
    address public immutable subject;
    address public immutable rewardAsset;
    address public immutable distributor;
    bytes32 public immutable distributorCodeHash;
    error InvalidClaim();

    constructor(address distributor_) {
        if (distributor_.code.length == 0) revert InvalidClaim();
        distributor = distributor_;
        distributorCodeHash = distributor_.codehash;
        subject = IReflectionAirdrop(distributor_).token();
        rewardAsset = IReflectionAirdrop(distributor_).rewardToken();
        if (subject.code.length == 0 || rewardAsset.code.length == 0) revert InvalidClaim();
    }

    function validate() public view {
        if (
            distributor.codehash != distributorCodeHash
                || IReflectionAirdrop(distributor).token() != subject
                || IReflectionAirdrop(distributor).rewardToken() != rewardAsset
        ) revert InvalidClaim();
    }

    function prepare(address recipient, bytes calldata payload)
        external
        view
        returns (address, bytes memory)
    {
        validate();
        if (recipient == address(0) || payload.length != 0) revert InvalidClaim();
        return (distributor, abi.encodeCall(IReflectionAirdrop.claimDividend, ()));
    }
}
