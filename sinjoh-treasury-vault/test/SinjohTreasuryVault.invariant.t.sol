// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { SinjohTreasuryVault } from "../src/SinjohTreasuryVault.sol";
import { InvariantTestBase } from "./TestBase.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";

contract TreasuryVaultHandler {
    SinjohTreasuryVault public immutable vault;
    MockERC20 public immutable token;
    address public constant RECIPIENT = address(0xBEEF);

    uint256 public totalDeposited;
    uint256 public totalWithdrawn;

    constructor(SinjohTreasuryVault vault_, MockERC20 token_) {
        vault = vault_;
        token = token_;
    }

    function acceptGovernorship() external {
        vault.acceptGovernorship();
    }

    function deposit(uint256 rawAmount) external {
        uint256 amount = (rawAmount % 1_000_000 ether) + 1;
        totalDeposited += amount;
        token.mint(address(vault), amount);
    }

    function governorTransfer(uint256 rawAmount) external {
        uint256 balance = token.balanceOf(address(vault));
        if (balance == 0) return;
        uint256 amount = (rawAmount % balance) + 1;
        totalWithdrawn += amount;
        vault.transfer(address(token), amount, RECIPIENT);
    }
}

contract VaultOutsider {
    SinjohTreasuryVault public immutable vault;
    MockERC20 public immutable token;

    constructor(SinjohTreasuryVault vault_, MockERC20 token_) {
        vault = vault_;
        token = token_;
    }

    function transferAttempt(uint256 rawAmount) external {
        try vault.transfer(address(token), (rawAmount % 100 ether) + 1, address(this)) {
            revert("outsider transfer must never succeed");
        } catch { }
    }

    function nominationAttempt() external {
        try vault.nominateGovernor(address(this)) {
            revert("outsider nomination must never succeed");
        } catch { }
    }

    function acceptAttempt() external {
        try vault.acceptGovernorship() {
            revert("outsider acceptance must never succeed");
        } catch { }
    }
}

contract SinjohTreasuryVaultInvariantTest is InvariantTestBase {
    uint256 internal constant HANDOFF_DELAY = 3 days;

    SinjohTreasuryVault internal vault;
    MockERC20 internal token;
    TreasuryVaultHandler internal handler;
    VaultOutsider internal outsider;

    function setUp() public {
        token = new MockERC20();
        vault = new SinjohTreasuryVault(address(this), HANDOFF_DELAY, address(0), 0);
        handler = new TreasuryVaultHandler(vault, token);
        outsider = new VaultOutsider(vault, token);

        vault.nominateGovernor(address(handler));
        vm.warp(block.timestamp + HANDOFF_DELAY);
        handler.acceptGovernorship();

        _targetedContracts.push(address(handler));
        _targetedContracts.push(address(outsider));
    }

    function invariantAccountingBalances() public view {
        assertEq(
            token.balanceOf(address(vault)), handler.totalDeposited() - handler.totalWithdrawn()
        );
        assertEq(token.balanceOf(handler.RECIPIENT()), handler.totalWithdrawn());
        assertEq(token.balanceOf(address(outsider)), 0);
    }

    function invariantGovernorSlotUnchanged() public view {
        assertEq(vault.governor(), address(handler));
        assertEq(vault.pendingGovernor(), address(0));
    }
}
