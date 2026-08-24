// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IProjectFundable } from "../../src/interfaces/IProjectFundable.sol";
import { IProjectControlled } from "../../src/interfaces/IProjectControlled.sol";
import { IProjectModule } from "../../src/interfaces/IProjectModule.sol";

contract MockReentrantController is IProjectControlled {
    bytes32 public immutable override projectId;
    address public immutable override controller;
    address public reentryTarget;
    bytes public reentryData;
    bool public lastReentrySucceeded;

    constructor(bytes32 projectId_) {
        projectId = projectId_;
        controller = address(this);
    }

    receive() external payable {
        (lastReentrySucceeded,) = reentryTarget.call(reentryData);
    }

    function configureReentry(address target, bytes calldata data) external {
        reentryTarget = target;
        reentryData = data;
    }
}

    contract MockRouterSink is IProjectModule, IProjectFundable {
        using SafeERC20 for IERC20;

        address public immutable override registry;
        address public immutable override subject;
        bytes32 public immutable override projectId;

        mapping(address asset => uint256 amount) public funded;
        bool public shouldRevert;
        bool public wrongReport;
        uint256 public revertDataSize;

        error ForcedFailure();
        error InvalidAttribution();

        receive() external payable { }

        constructor(address registry_, address subject_, bytes32 projectId_) {
            registry = registry_;
            subject = subject_;
            projectId = projectId_;
        }

        function setBehavior(bool shouldRevert_, bool wrongReport_, uint256 revertDataSize_)
            external
        {
            shouldRevert = shouldRevert_;
            wrongReport = wrongReport_;
            revertDataSize = revertDataSize_;
        }

        function fund(
            bytes32 projectId_,
            address subject_,
            address asset,
            uint256 amount,
            bytes calldata
        ) external payable returns (uint256 received) {
            if (shouldRevert) {
                uint256 size = revertDataSize;
                if (size == 0) revert ForcedFailure();
                assembly ("memory-safe") { revert(0, size) }
            }
            if (projectId_ != projectId || subject_ != subject) revert InvalidAttribution();
            if (asset == address(0)) {
                require(msg.value == amount, "native amount");
            } else {
                require(msg.value == 0, "unexpected value");
                IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
            }
            funded[asset] += amount;
            return wrongReport ? amount + 1 : amount;
        }
    }
