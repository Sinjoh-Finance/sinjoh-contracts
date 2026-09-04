// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { ERC721Royalty } from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Royalty.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { IYieldBankCollectionView } from "./interfaces/IYieldBankCollectionView.sol";
import { IYieldBankCollectionMetadata } from "./interfaces/IYieldBankCollectionMetadata.sol";
import { ISeaDrop } from "./interfaces/ISeaDrop.sol";
import {
    INonFungibleSeaDropToken,
    ISeaDropTokenContractMetadata
} from "./interfaces/INonFungibleSeaDropToken.sol";
import {
    AllowListData,
    PublicDrop,
    SignedMintValidationParams,
    TokenGatedDropStage
} from "./interfaces/SeaDropStructs.sol";

interface IYieldBankSeaDropCollection {
    function prepareSeaDropMint(
        address minter,
        uint256 quantity,
        uint256 expectedNetProceeds,
        uint256 firstTokenId
    ) external returns (uint256 assignedFirstTokenId);
}

interface IYieldBankMintPolicy {
    function nft() external view returns (address);
    function maxSupply() external view returns (uint256);
    function recordMint(
        address minter,
        uint256 quantity,
        uint256 currentTotalMinted,
        uint256 seaDropBalance
    ) external returns (uint256 expectedNetProceeds, uint256 firstTokenId);
    function mintStats(address minter, uint256 currentTotalMinted)
        external
        view
        returns (uint256 stageMints, uint256 stageMinted, uint256 stageSupply);
}

contract YieldBankNFT is ERC721Royalty, Ownable2Step, ReentrancyGuard, INonFungibleSeaDropToken {
    uint256 public constant MAX_MINT_QUANTITY = 20;
    uint16 private constant BPS = 10_000;
    address public immutable collection;
    address public immutable metadata;
    address public immutable seaDrop;
    address public immutable royaltyReceiver;
    uint96 public immutable royaltyBps;
    uint256 public immutable override maxSupply;
    uint256 public totalMinted;
    mapping(address => uint256) public numberMinted;
    string private _baseTokenURI;
    string private _contractMetadataURI;
    bytes32 public override provenanceHash;
    address public proceedsVault;
    address public mintPolicy;

    error OnlyCollection(address caller);
    error OnlyAllowedSeaDrop(address caller);
    error InvalidConfiguration();
    error InvalidMintPrice();
    error PaidMintRequired();
    error IneligibleRecipient(address recipient);
    error ImmutableMaxSupply(uint256 supplied);
    error ProceedsVaultAlreadySet();
    error ProvenanceLocked();
    error ImmutableRoyaltyInfo(address receiver, uint96 bps);
    error MintPolicyAlreadySet();

    event AllowedSeaDropUpdated(address[] allowedSeaDrop);
    event ContractURIUpdated(string newContractURI);
    event MaxSupplyUpdated(uint256 newMaxSupply);
    event ProvenanceHashUpdated(bytes32 previousHash, bytes32 newHash);
    event RoyaltyInfoUpdated(address receiver, uint256 bps);
    event BatchMetadataUpdate(uint256 fromTokenId, uint256 toTokenId);
    event ProceedsVaultSet(address indexed proceedsVault);

    modifier onlyCollection() {
        if (msg.sender != collection) revert OnlyCollection(msg.sender);
        _;
    }

    constructor(
        address collection_,
        address owner_,
        address revenueRouter_,
        address metadata_,
        address seaDrop_,
        uint256 maxSupply_,
        uint96 royaltyBps_
    ) ERC721("", "") Ownable(owner_) {
        if (
            collection_ == address(0) || owner_ == address(0) || revenueRouter_ == address(0)
                || metadata_.code.length == 0 || seaDrop_.code.length == 0 || maxSupply_ == 0
                || maxSupply_ > type(uint64).max || royaltyBps_ > BPS
        ) revert InvalidConfiguration();
        collection = collection_;
        metadata = metadata_;
        seaDrop = seaDrop_;
        royaltyReceiver = revenueRouter_;
        royaltyBps = royaltyBps_;
        maxSupply = maxSupply_;
        _setDefaultRoyalty(revenueRouter_, royaltyBps_);
        address[] memory allowed = new address[](1);
        allowed[0] = seaDrop_;
        emit AllowedSeaDropUpdated(allowed);
        emit MaxSupplyUpdated(maxSupply_);
    }

    function name() public view override returns (string memory) {
        return IYieldBankCollectionMetadata(metadata).collectionName();
    }

    function symbol() public view override returns (string memory) {
        return IYieldBankCollectionMetadata(metadata).collectionSymbol();
    }

    function setProceedsVault(address value) external onlyCollection {
        if (proceedsVault != address(0)) revert ProceedsVaultAlreadySet();
        if (value.code.length == 0) revert InvalidConfiguration();
        proceedsVault = value;
        emit ProceedsVaultSet(value);
    }

    function mintSeaDrop(address minter, uint256 quantity) external override nonReentrant {
        if (msg.sender != seaDrop) revert OnlyAllowedSeaDrop(msg.sender);
        if (proceedsVault == address(0) || quantity == 0 || quantity > MAX_MINT_QUANTITY) {
            revert InvalidConfiguration();
        }
        uint256 expectedNetProceeds;
        uint256 firstTokenId;
        address policy = mintPolicy;
        if (policy != address(0)) {
            (expectedNetProceeds, firstTokenId) = IYieldBankMintPolicy(policy)
                .recordMint(minter, quantity, totalMinted, seaDrop.balance);
        }
        uint256 first = IYieldBankSeaDropCollection(collection)
            .prepareSeaDropMint(minter, quantity, expectedNetProceeds, firstTokenId);
        numberMinted[minter] += quantity;
        totalMinted += quantity;
        for (uint256 i; i < quantity; ++i) {
            _safeMint(minter, first + i);
        }
    }

    function burn(uint256 tokenId) external onlyCollection {
        _burn(tokenId);
    }

    function getMintStats(address minter)
        external
        view
        override
        returns (uint256, uint256, uint256)
    {
        address policy = mintPolicy;
        if (policy == address(0) || totalMinted == maxSupply) {
            return (numberMinted[minter], totalMinted, maxSupply);
        }
        return IYieldBankMintPolicy(policy).mintStats(minter, totalMinted);
    }

    /// @notice Permanently pins an optional collection-specific mint policy before the first mint.
    function setMintPolicy(address policy) external onlyOwner {
        if (mintPolicy != address(0)) revert MintPolicyAlreadySet();
        if (
            totalMinted != 0 || policy.code.length == 0
                || IYieldBankMintPolicy(policy).nft() != address(this)
                || IYieldBankMintPolicy(policy).maxSupply() != maxSupply
        ) revert InvalidConfiguration();
        mintPolicy = policy;
    }

    function updateAllowedSeaDrop(address[] calldata values) external override onlyOwner {
        if (values.length != 1 || values[0] != seaDrop) revert InvalidConfiguration();
        emit AllowedSeaDropUpdated(values);
    }

    function updatePublicDrop(address impl, PublicDrop calldata value) external override onlyOwner {
        _requireSeaDrop(impl);
        _requirePaidMint(value.mintPrice, value.feeBps);
        ISeaDrop(seaDrop).updatePublicDrop(value);
    }

    function updateAllowList(address impl, AllowListData calldata value)
        external
        override
        onlyOwner
    {
        // A pinned mint policy independently enforces the active supply boundary, wallet
        // limit, gross payment present in SeaDrop, and exact net payout. Collections without that
        // schedule retain the original fail-closed behavior for nonempty allow lists.
        if (
            mintPolicy == address(0)
                && (value.merkleRoot != bytes32(0)
                    || value.publicKeyURIs.length != 0
                    || bytes(value.allowListURI).length != 0)
        ) {
            revert PaidMintRequired();
        }
        _requireSeaDrop(impl);
        ISeaDrop(seaDrop).updateAllowList(value);
    }

    function updateTokenGatedDrop(address impl, address token, TokenGatedDropStage calldata value)
        external
        override
        onlyOwner
    {
        _requireSeaDrop(impl);
        _requirePaidMint(value.mintPrice, value.feeBps);
        ISeaDrop(seaDrop).updateTokenGatedDrop(token, value);
    }

    function updateDropURI(address impl, string calldata value) external override onlyOwner {
        _requireSeaDrop(impl);
        ISeaDrop(seaDrop).updateDropURI(value);
    }

    function updateCreatorPayoutAddress(address impl, address value) external override onlyOwner {
        _requireSeaDrop(impl);
        if (value == address(0) || value != proceedsVault) revert InvalidConfiguration();
        ISeaDrop(seaDrop).updateCreatorPayoutAddress(value);
    }

    function updateAllowedFeeRecipient(address impl, address value, bool allowed)
        external
        override
        onlyOwner
    {
        _requireSeaDrop(impl);
        ISeaDrop(seaDrop).updateAllowedFeeRecipient(value, allowed);
    }

    function updateSignedMintValidationParams(
        address impl,
        address signer,
        SignedMintValidationParams memory value
    ) external override onlyOwner {
        _requireSeaDrop(impl);
        _requirePaidMint(value.minMintPrice, value.maxFeeBps);
        ISeaDrop(seaDrop).updateSignedMintValidationParams(signer, value);
    }

    function updatePayer(address impl, address payer, bool allowed) external override onlyOwner {
        _requireSeaDrop(impl);
        ISeaDrop(seaDrop).updatePayer(payer, allowed);
    }

    function setBaseURI(string calldata value) external override onlyOwner {
        _baseTokenURI = value;
        emit BatchMetadataUpdate(1, maxSupply);
    }

    function setContractURI(string calldata value) external override onlyOwner {
        _contractMetadataURI = value;
        emit ContractURIUpdated(value);
    }

    function setMaxSupply(uint256 value) external view override onlyOwner {
        if (value != maxSupply) revert ImmutableMaxSupply(value);
    }

    function setProvenanceHash(bytes32 value) external override onlyOwner {
        if (totalMinted != 0) revert ProvenanceLocked();
        bytes32 old = provenanceHash;
        provenanceHash = value;
        emit ProvenanceHashUpdated(old, value);
    }

    function setRoyaltyInfo(ISeaDropTokenContractMetadata.SeaDropRoyaltyInfo calldata value)
        external
        override
        onlyOwner
    {
        if (value.royaltyAddress != royaltyReceiver || value.royaltyBps != royaltyBps) {
            revert ImmutableRoyaltyInfo(value.royaltyAddress, value.royaltyBps);
        }
        _setDefaultRoyalty(value.royaltyAddress, value.royaltyBps);
        emit RoyaltyInfoUpdated(value.royaltyAddress, value.royaltyBps);
    }

    function baseURI() external view override returns (string memory) {
        return _baseTokenURI;
    }

    function contractURI() external view override returns (string memory) {
        return _contractMetadataURI;
    }

    function royaltyAddress() external view override returns (address receiver) {
        (receiver,) = royaltyInfo(1, 10_000);
    }

    function royaltyBasisPoints() external view override returns (uint256 amount) {
        (, amount) = royaltyInfo(1, 10_000);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Royalty, IERC165)
        returns (bool)
    {
        return interfaceId == type(INonFungibleSeaDropToken).interfaceId
            || interfaceId == type(ISeaDropTokenContractMetadata).interfaceId
            || super.supportsInterface(interfaceId);
    }

    function _update(address to, uint256 tokenId, address auth)
        internal
        override
        returns (address from)
    {
        from = _ownerOf(tokenId);
        if (
            from != address(0) && to != address(0)
                && !IYieldBankCollectionView(collection).canTransfer(tokenId, to)
        ) {
            revert IneligibleRecipient(to);
        }
        return super._update(to, tokenId, auth);
    }

    function _requireSeaDrop(address impl) private view {
        if (impl != seaDrop) revert OnlyAllowedSeaDrop(impl);
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    function _requirePaidMint(uint256 mintPrice, uint256 feeBps) private pure {
        if (mintPrice == 0) revert InvalidMintPrice();
        if (feeBps >= BPS) revert PaidMintRequired();
    }
}
