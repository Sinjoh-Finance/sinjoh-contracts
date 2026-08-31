// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IPriceHub } from "./interfaces/IPriceHub.sol";
import { IYieldBankSleeve } from "./interfaces/IYieldBankSleeve.sol";

interface IYieldBankSleevePriceHub {
    function priceHub() external view returns (address);
}

/// @notice Stateless valuation guard kept separate so the allocator remains deployable under EIP-170.
contract RebalanceValueGuard {
    error InvalidPortfolioValue();

    function accountValueUsd18(
        address account,
        address weth,
        address[3] calldata baseSleeves,
        address extraSleeve
    ) external view returns (uint256 value) {
        uint256 sleeveCount = extraSleeve == address(0) || extraSleeve == baseSleeves[1] ? 3 : 4;
        for (uint256 i; i < sleeveCount; ++i) {
            address sleeve = i < 3 ? baseSleeves[i] : extraSleeve;
            uint256 shares = IERC20(sleeve).balanceOf(account);
            if (shares == 0) continue;
            uint256 supply = IERC20(sleeve).totalSupply();
            (uint256 nav,) = IYieldBankSleeve(sleeve).totalAssetsUsd18();
            if (supply == 0 || nav == 0) revert InvalidPortfolioValue();
            value += Math.mulDiv(nav, shares, supply);
        }
        uint256 looseWeth = IERC20(weth).balanceOf(account);
        if (looseWeth != 0) {
            (uint256 price,, IPriceHub.FailureReason failure) =
                IPriceHub(IYieldBankSleevePriceHub(baseSleeves[0]).priceHub()).quoteUsd18(weth);
            if (failure != IPriceHub.FailureReason.NONE || price == 0) {
                revert InvalidPortfolioValue();
            }
            value += Math.mulDiv(looseWeth, price, 10 ** IERC20Metadata(weth).decimals());
        }
        if (value == 0) revert InvalidPortfolioValue();
    }

    function mintedValueUsd18(uint256[3] calldata minted, address[3] calldata targetSleeves)
        external
        view
        returns (uint256 value)
    {
        for (uint256 i; i < 3; ++i) {
            if (minted[i] == 0) continue;
            uint256 supply = IERC20(targetSleeves[i]).totalSupply();
            (uint256 nav,) = IYieldBankSleeve(targetSleeves[i]).totalAssetsUsd18();
            if (supply == 0 || nav == 0) revert InvalidPortfolioValue();
            value += Math.mulDiv(nav, minted[i], supply);
        }
    }
}
