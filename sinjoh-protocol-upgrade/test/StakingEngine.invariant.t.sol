// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AddressGovernanceController } from "../src/governance/AddressGovernanceController.sol";
import { IGovernanceController } from "../src/interfaces/IGovernanceController.sol";
import { StakingEngine } from "../src/StakingEngine.sol";
import { InvariantTestBase } from "./TestBase.sol";
import { MockERC20 } from "./mocks/Mocks.sol";

contract StakingHandler {
    MockERC20 public immutable token;
    StakingEngine public immutable staking;

    constructor(MockERC20 token_, StakingEngine staking_) {
        token = token_;
        staking = staking_;
        token_.approve(address(staking_), type(uint256).max);
    }

    function stake(uint96 rawAmount) external {
        uint256 amount = uint256(rawAmount) + 1;
        token.mint(address(this), amount);
        staking.stake(amount);
    }

    function unstake(uint96 rawAmount) external {
        uint256 available = staking.balanceOf(address(this));
        if (available == 0) return;
        uint256 amount = uint256(rawAmount) % available + 1;
        staking.unstake(amount);
    }
}

contract StakingEngineInvariantTest is InvariantTestBase {
    MockERC20 private token;
    StakingEngine private staking;
    StakingHandler private handler;

    function setUp() public {
        token = new MockERC20();
        AddressGovernanceController controller =
            new AddressGovernanceController(address(this), IGovernanceController.Mode.INDIVIDUAL);
        staking = new StakingEngine(controller, address(0xBEEF), IERC20(address(token)));
        handler = new StakingHandler(token, staking);
        _targetedContracts.push(address(handler));
    }

    function invariantEveryRecordedStakeIsFullyBacked() public view {
        assertEq(token.balanceOf(address(staking)), staking.totalStaked());
    }

    function invariantAccountAndAggregateBalancesMatch() public view {
        assertEq(staking.balanceOf(address(handler)), staking.totalStaked());
    }
}
