// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { AddressGovernanceController } from "../src/governance/AddressGovernanceController.sol";
import { IGovernanceController } from "../src/interfaces/IGovernanceController.sol";
import { FeeRouterV2 } from "../src/FeeRouterV2.sol";
import { InvariantTestBase } from "./TestBase.sol";
import { MockERC20 } from "./mocks/Mocks.sol";

contract RouterHandler {
    FeeRouterV2 public immutable router;
    MockERC20 public immutable token;

    constructor(FeeRouterV2 router_, MockERC20 token_) {
        router = router_;
        token = token_;
    }

    function donateAndSync(uint96 rawAmount) external {
        uint256 amount = uint256(rawAmount) + 1;
        token.mint(address(router), amount);
        router.sync(address(token));
    }
}

contract ProtocolUpgradeInvariantTest is InvariantTestBase {
    address private constant PROTOCOL = address(0xFEE);
    address private constant RECIPIENT = address(0xCAFE);

    FeeRouterV2 private router;
    MockERC20 private token;

    function setUp() public {
        token = new MockERC20();
        AddressGovernanceController controller =
            new AddressGovernanceController(address(this), IGovernanceController.Mode.INDIVIDUAL);
        router = new FeeRouterV2(controller, address(0xBEEF), PROTOCOL, 1, 1 days);
        FeeRouterV2.Route[] memory routes = new FeeRouterV2.Route[](1);
        routes[0] = FeeRouterV2.Route({
            inputToken: address(token),
            recipient: RECIPIENT,
            shareBps: 10_000,
            action: FeeRouterV2.Action.SEND,
            config: ""
        });
        uint256 id = router.proposeConfiguration(routes);
        vm.warp(block.timestamp + 1);
        router.activateConfiguration(id);
        RouterHandler handler = new RouterHandler(router, token);
        _targetedContracts.push(address(handler));
    }

    function invariantProtocolFeeIsExactlyOnePercentOfCumulativeIntake() public view {
        assertEq(
            router.cumulativeProtocolFee(address(token)),
            router.cumulativeGrossIntake(address(token)) / 100
        );
    }

    function invariantRouterHasNoUnroutedBalance() public view {
        assertEq(token.balanceOf(address(router)), 0);
    }

    function invariantAllIntakeReachedProtocolOrRecipient() public view {
        assertEq(
            token.balanceOf(PROTOCOL) + token.balanceOf(RECIPIENT),
            router.cumulativeGrossIntake(address(token))
        );
    }
}
