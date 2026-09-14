// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @notice Delivers funded Stock dividends to the NFT owner at conversion settlement.
/// @dev A settlement credit vests in that wallet. Later NFT transfer or burn cannot strand or
/// redirect a failed payout. The immutable settler must be the verified dividend-only sleeve,
/// not a general keeper. This contract neither values positions nor authenticates dividends.
contract StockDividendEscrow is ReentrancyGuard {
    using SafeERC20 for IERC20;

    error InvalidConfiguration();
    error UnauthorizedSettler();
    error InvalidSettlement();
    error UnsupportedTransfer();
    error NothingToPay();

    IERC721 public immutable nft;
    IERC20 public immutable payoutAsset;
    address public immutable settler;
    mapping(bytes32 settlementId => bool) public settled;
    mapping(address wallet => uint256) public creditOf;
    uint256 public totalCredits;

    event DividendCredited(
        bytes32 indexed settlementId,
        uint256 indexed tokenId,
        address indexed wallet,
        uint256 amount
    );
    event DividendPaid(address indexed wallet, uint256 amount);
    event DividendPaymentPending(address indexed wallet);

    constructor(address nft_, address payoutAsset_, address settler_) {
        if (
            nft_.code.length == 0 || payoutAsset_.code.length == 0 || settler_ == address(0)
                || payoutAsset_ == nft_
        ) revert InvalidConfiguration();
        nft = IERC721(nft_);
        payoutAsset = IERC20(payoutAsset_);
        settler = settler_;
    }

    /// @notice Pull exact realized proceeds and credit the current NFT owner.
    /// @dev No arbitrary beneficiary or minting of unfunded credit. IDs must identify a unique
    /// conversion, allowing separately identified partial conversions of one dividend reserve.
    function settle(uint256 tokenId, bytes32 settlementId, uint256 amount)
        public
        nonReentrant
        returns (address wallet)
    {
        if (msg.sender != settler) revert UnauthorizedSettler();
        if (settlementId == bytes32(0) || settled[settlementId] || amount == 0) {
            revert InvalidSettlement();
        }
        wallet = nft.ownerOf(tokenId);
        if (wallet == address(0) || wallet == address(this)) revert InvalidSettlement();
        uint256 beforeBalance = payoutAsset.balanceOf(address(this));
        settled[settlementId] = true;
        payoutAsset.safeTransferFrom(msg.sender, address(this), amount);
        if (payoutAsset.balanceOf(address(this)) != beforeBalance + amount) {
            revert UnsupportedTransfer();
        }
        // A nonstandard token callback must not change who is receiving this settlement.
        if (nft.ownerOf(tokenId) != wallet) revert InvalidSettlement();
        creditOf[wallet] += amount;
        totalCredits += amount;
        emit DividendCredited(settlementId, tokenId, wallet, amount);
    }

    /// @notice Best-effort delivery after successful funding. A blocked wallet retains its credit.
    function settleAndPay(uint256 tokenId, bytes32 settlementId, uint256 amount) external {
        address wallet = settle(tokenId, settlementId, amount);
        try this.pay(wallet) { }
        catch {
            emit DividendPaymentPending(wallet);
        }
    }

    /// @notice Anyone may retry delivery, always to the credited wallet itself.
    /// @dev Reverts roll back the debit. There is deliberately no redirect or admin sweep.
    function pay(address wallet) external nonReentrant {
        uint256 amount = creditOf[wallet];
        if (amount == 0) revert NothingToPay();
        uint256 beforeBalance = payoutAsset.balanceOf(address(this));
        uint256 beforeRecipient = payoutAsset.balanceOf(wallet);
        creditOf[wallet] = 0;
        totalCredits -= amount;
        payoutAsset.safeTransfer(wallet, amount);
        if (
            payoutAsset.balanceOf(address(this)) != beforeBalance - amount
                || payoutAsset.balanceOf(wallet) != beforeRecipient + amount
        ) revert UnsupportedTransfer();
        emit DividendPaid(wallet, amount);
    }
}
