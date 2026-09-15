// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;
import { IAirdropClaimAdapter } from "./AirdropAssetRegistry.sol";

interface ISinjohHolderAirdrop {
    struct ProofElement {
        bytes32 siblingHash;
        uint256 siblingSum;
        bool siblingIsLeft;
    }

    struct Leaf {
        address holder;
        uint256 cumulativeAmount;
    }
    function push(
        address funder,
        address subject,
        address asset,
        uint64 epoch,
        Leaf[] calldata leaves,
        ProofElement[][] calldata proofs
    ) external;
}

contract SinjohAirdropClaimAdapter is IAirdropClaimAdapter {
    address public immutable distributor;
    bytes32 public immutable distributorCodeHash;
    address public immutable funder;
    address public immutable subject;
    address public immutable rewardAsset;
    bytes32 public immutable accountId;
    error InvalidClaim();

    constructor(address distributor_, address funder_, address subject_, address reward_) {
        if (
            distributor_.code.length == 0 || funder_ == address(0) || subject_.code.length == 0
                || reward_.code.length == 0
        ) revert InvalidClaim();
        distributor = distributor_;
        distributorCodeHash = distributor_.codehash;
        funder = funder_;
        subject = subject_;
        rewardAsset = reward_;
        accountId = keccak256(abi.encode(funder_, subject_, reward_));
    }

    function validate() public view {
        if (distributor.codehash != distributorCodeHash) revert InvalidClaim();
    }

    function prepare(address recipient, bytes calldata payload)
        external
        view
        returns (address, bytes memory)
    {
        validate();
        if (recipient == address(0) || payload.length > 8192) revert InvalidClaim();
        (uint64 epoch, uint256 amount, ISinjohHolderAirdrop.ProofElement[] memory proof) =
            abi.decode(payload, (uint64, uint256, ISinjohHolderAirdrop.ProofElement[]));
        if (epoch == 0 || amount == 0 || proof.length > 64) revert InvalidClaim();
        ISinjohHolderAirdrop.Leaf[] memory leaves = new ISinjohHolderAirdrop.Leaf[](1);
        leaves[0] = ISinjohHolderAirdrop.Leaf(recipient, amount);
        ISinjohHolderAirdrop.ProofElement[][] memory proofs =
            new ISinjohHolderAirdrop.ProofElement[][](1);
        proofs[0] = proof;
        return (
            distributor,
            abi.encodeCall(
                ISinjohHolderAirdrop.push, (funder, subject, rewardAsset, epoch, leaves, proofs)
            )
        );
    }
}
