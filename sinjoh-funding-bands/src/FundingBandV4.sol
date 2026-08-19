// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { IPositionManager } from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import { IAllowanceTransfer } from "permit2/src/interfaces/IAllowanceTransfer.sol";

interface IERC721PositionOwner {
    function ownerOf(uint256 tokenId) external view returns (address owner);
}

library FundingBandV4 {
    using SafeERC20 for IERC20;

    uint48 private constant DEADLINE_WINDOW = 300;
    uint8 private constant INCREASE_LIQUIDITY = 0x00;
    uint8 private constant MINT_POSITION = 0x02;
    uint8 private constant BURN_POSITION = 0x03;
    uint8 private constant SETTLE_PAIR = 0x0d;
    uint8 private constant TAKE_PAIR = 0x11;

    error InvalidAmount();
    error InvalidPosition();

    function fund(
        IPositionManager positionManager,
        IAllowanceTransfer permit2,
        address subject,
        PoolKey memory key,
        int24 tickLower,
        int24 tickUpper,
        uint256 existingPositionId,
        uint256 amount,
        uint128 liquidity,
        bytes memory hookData
    ) external returns (uint256 tokenId) {
        if (amount > type(uint128).max || amount > type(uint160).max) {
            revert InvalidAmount();
        }
        IERC20(subject).forceApprove(address(permit2), amount);
        permit2.approve(
            subject,
            address(positionManager),
            // `amount` was bounded to uint160 above.
            // forge-lint: disable-next-line(unsafe-typecast)
            uint160(amount),
            uint48(block.timestamp + DEADLINE_WINDOW)
        );

        bool created = existingPositionId == 0;
        bytes memory actions;
        bytes[] memory params = new bytes[](2);
        address currency0 = Currency.unwrap(key.currency0);
        // `amount` was bounded to uint128 above.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 subjectAmount0 = subject == currency0 ? uint128(amount) : 0;
        // `amount` was bounded to uint128 above.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 subjectAmount1 = subject == currency0 ? 0 : uint128(amount);
        if (created) {
            tokenId = positionManager.nextTokenId();
            actions = abi.encodePacked(MINT_POSITION, SETTLE_PAIR);
            params[0] = abi.encode(
                key,
                tickLower,
                tickUpper,
                uint256(liquidity),
                subjectAmount0,
                subjectAmount1,
                address(this),
                hookData
            );
        } else {
            tokenId = existingPositionId;
            actions = abi.encodePacked(INCREASE_LIQUIDITY, SETTLE_PAIR);
            params[0] =
                abi.encode(tokenId, uint256(liquidity), subjectAmount0, subjectAmount1, hookData);
        }
        params[1] = abi.encode(key.currency0, key.currency1);
        positionManager.modifyLiquidities(
            abi.encode(actions, params), block.timestamp + DEADLINE_WINDOW
        );
        if (
            created
                && IERC721PositionOwner(address(positionManager)).ownerOf(tokenId) != address(this)
        ) revert InvalidPosition();
        permit2.approve(subject, address(positionManager), 0, 0);
        IERC20(subject).forceApprove(address(permit2), 0);
    }

    function settle(
        IPositionManager positionManager,
        PoolKey memory key,
        uint256 positionId,
        bytes memory hookData
    ) external {
        bytes memory actions = abi.encodePacked(BURN_POSITION, TAKE_PAIR);
        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(positionId, uint128(0), uint128(0), hookData);
        params[1] = abi.encode(key.currency0, key.currency1, address(this));
        positionManager.modifyLiquidities(
            abi.encode(actions, params), block.timestamp + DEADLINE_WINDOW
        );
    }
}
