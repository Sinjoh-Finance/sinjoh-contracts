// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { ProjectTreasuryVaultV2 } from "../../src/treasury/ProjectTreasuryVaultV2.sol";
import { TreasuryTestBase } from "../TreasuryTestBase.sol";

contract ProjectTreasuryVaultV2FuzzTest is TreasuryTestBase {
    function setUp() public {
        _setUpTreasury();
    }

    function testFuzzExactDepositAccounting(uint128 rawAmount) public {
        uint256 amount = bound(uint256(rawAmount), 1, 1_000_000e18);
        _deposit(address(assetA), amount, false);
        assertEq(vault.accountedBalance(address(assetA)), amount);
        assertEq(vault.availableBalance(address(assetA)), amount);
        assertEq(assetA.balanceOf(address(vault)), amount);
    }

    function testFuzzNativeDepositAccounting(uint96 rawAmount) public {
        uint256 amount = bound(uint256(rawAmount), 1, 1_000 ether);
        vm.prank(DEPOSITOR);
        vault.depositNative{ value: amount }(false);
        assertEq(vault.accountedBalance(address(0)), amount);
        assertEq(address(vault).balance, amount);
    }

    function testFuzzPolicyReservationRoundsDownWithoutOverreserving(
        uint128 rawAmount,
        uint16 rawBps
    ) public {
        uint256 amount = bound(uint256(rawAmount), 1, 1_000_000e18);
        uint16 bps = uint16(bound(uint256(rawBps), 1, 10_000));
        _configureSingleAssetRoute(address(assetA), bps);
        _deposit(address(assetA), amount, true);
        uint256 expected = amount * bps / 10_000;
        assertEq(vault.reservedForBasket(address(assetA)), expected);
        assertEq(vault.availableBalance(address(assetA)), amount - expected);
    }

    function testFuzzPartialKeeperExecutionPreservesAccounting(
        uint128 rawAmount,
        uint128 rawMaximum
    ) public {
        uint256 amount = bound(uint256(rawAmount), 1, 1_000_000e18);
        _configureSingleAssetRoute(address(assetA), 10_000);
        _deposit(address(assetA), amount, true);
        uint256 maximum = bound(uint256(rawMaximum), 1, amount);
        uint256 executed = vault.executeBasketRoute(address(assetA), maximum);
        assertEq(executed, maximum);
        assertEq(vault.reservedForBasket(address(assetA)), amount - maximum);
        assertEq(vault.accountedBalance(address(assetA)), amount - maximum);
        assertEq(assetA.balanceOf(address(vault)), amount - maximum);
        assertEq(basketManager.funded(BASKET_ID, address(assetA)), maximum);
    }

    function testFuzzControllerSendConservesExactBalances(uint128 rawDeposit, uint128 rawSend)
        public
    {
        uint256 deposited = bound(uint256(rawDeposit), 1, 1_000_000e18);
        uint256 sent = bound(uint256(rawSend), 1, deposited);
        _deposit(address(assetA), deposited, false);
        _controllerCall(abi.encodeCall(vault.send, (address(assetA), sent, RECIPIENT)));
        assertEq(vault.accountedBalance(address(assetA)), deposited - sent);
        assertEq(assetA.balanceOf(address(vault)), deposited - sent);
        assertEq(assetA.balanceOf(RECIPIENT), sent);
    }

    function testFuzzRawTransferSyncCreditsOnlyMeasuredSurplus(
        uint128 rawDeposit,
        uint128 rawSurplus
    ) public {
        uint256 deposited = bound(uint256(rawDeposit), 1, 1_000_000e18);
        uint256 surplus = bound(uint256(rawSurplus), 1, 1_000_000e18);
        _deposit(address(assetA), deposited, false);
        assetA.mint(address(vault), surplus);
        assertEq(vault.syncAsset(address(assetA)), surplus);
        assertEq(vault.accountedBalance(address(assetA)), deposited + surplus);
    }

    function testFuzzApprovedSwapCreditsExactMeasuredOutput(uint128 rawInput, uint128 rawOutput)
        public
    {
        uint256 amountIn = bound(uint256(rawInput), 1, 1_000_000e18);
        uint256 amountOut = bound(uint256(rawOutput), 1, 1_000_000e18);
        _deposit(address(assetA), amountIn, false);
        assetB.mint(address(adapter), amountOut);
        adapter.configure(amountOut, type(uint256).max, false);
        priceGuard.setQuote(amountOut, uint48(block.timestamp + 1 hours));
        bytes32[] memory proof = new bytes32[](0);
        bytes memory result = _controllerCall(
            abi.encodeCall(
                vault.swap,
                (
                    address(adapter),
                    address(priceGuard),
                    address(assetA),
                    address(assetB),
                    amountIn,
                    amountOut,
                    ROUTE_DATA,
                    bytes(""),
                    proof
                )
            )
        );
        assertEq(abi.decode(result, (uint256)), amountOut);
        assertEq(vault.accountedBalance(address(assetA)), 0);
        assertEq(vault.accountedBalance(address(assetB)), amountOut);
    }
}
