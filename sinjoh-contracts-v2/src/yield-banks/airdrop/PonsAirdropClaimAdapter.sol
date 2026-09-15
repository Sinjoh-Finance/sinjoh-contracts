// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;
import { IAirdropClaimAdapter } from "./AirdropAssetRegistry.sol";

interface IPonsAirdropDistributor {
    struct Claim {
        uint256 epoch;
        address account;
        uint256 quoteAmount;
        uint256 nativeAmount;
        bytes32[] proof;
    }
    function token() external view returns (address);
    function quoteToken() external view returns (address);
    function claimMany(Claim[] calldata claims) external;
}

interface IAirdropBeacon {
    function implementation() external view returns (address);
}

/// @notice ABI verified against live claimMany calldata. Pins the reviewed proxy AND
/// beacon implementation; an upstream upgrade requires a separately reviewed adapter.
contract PonsAirdropClaimAdapter is IAirdropClaimAdapter {
    address public immutable subject;
    address public immutable rewardAsset;
    address public immutable distributor;
    address public immutable beacon;
    address public immutable implementation;
    bytes32 public immutable distributorCodeHash;
    bytes32 public immutable beaconCodeHash;
    bytes32 public immutable implementationCodeHash;
    error InvalidClaim();

    constructor(address distributor_, address beacon_) {
        if (distributor_.code.length == 0 || beacon_.code.length == 0) revert InvalidClaim();
        distributor = distributor_;
        beacon = beacon_;
        address impl = IAirdropBeacon(beacon_).implementation();
        if (impl.code.length == 0) revert InvalidClaim();
        implementation = impl;
        implementationCodeHash = impl.codehash;
        distributorCodeHash = distributor_.codehash;
        beaconCodeHash = beacon_.codehash;
        subject = IPonsAirdropDistributor(distributor_).token();
        rewardAsset = IPonsAirdropDistributor(distributor_).quoteToken();
        if (subject.code.length == 0 || rewardAsset.code.length == 0) revert InvalidClaim();
    }

    function validate() public view {
        if (
            distributor.codehash != distributorCodeHash || beacon.codehash != beaconCodeHash
                || IAirdropBeacon(beacon).implementation() != implementation
                || implementation.codehash != implementationCodeHash
                || IPonsAirdropDistributor(distributor).token() != subject
                || IPonsAirdropDistributor(distributor).quoteToken() != rewardAsset
        ) revert InvalidClaim();
    }

    function prepare(address recipient, bytes calldata payload)
        external
        view
        returns (address, bytes memory)
    {
        validate();
        if (recipient == address(0) || payload.length > 4096) revert InvalidClaim();
        (uint256 epoch, uint256 quoteAmount, uint256 nativeAmount, bytes32[] memory proof) =
            abi.decode(payload, (uint256, uint256, uint256, bytes32[]));
        if (proof.length > 64 || (quoteAmount == 0 && nativeAmount == 0)) revert InvalidClaim();
        IPonsAirdropDistributor.Claim[] memory claims = new IPonsAirdropDistributor.Claim[](1);
        claims[0] =
            IPonsAirdropDistributor.Claim(epoch, recipient, quoteAmount, nativeAmount, proof);
        return (distributor, abi.encodeCall(IPonsAirdropDistributor.claimMany, (claims)));
    }
}
