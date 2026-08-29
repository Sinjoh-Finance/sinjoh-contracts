// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IProjectControlled } from "../interfaces/IProjectControlled.sol";
import { IProjectFundable } from "../interfaces/IProjectFundable.sol";
import { IProjectModule } from "../interfaces/IProjectModule.sol";
import { IYieldBankFundable } from "./interfaces/IYieldBankFundable.sol";
import { YieldBankIds } from "./libraries/YieldBankIds.sol";
import { IntegrationBinding } from "./libraries/IntegrationBinding.sol";

interface IYieldBankRevenueRouterView {
    function collection() external view returns (address);
}

interface IYieldBankCollectionIdentity {
    function collectionId() external view returns (bytes32);
}

/// @notice Exact, identity-bound Project V2 revenue sink for one Yield Bank collection.
/// @dev Configure as a ProjectRouterV2 FUND_PROJECT_SINK recipient. The Yield Bank revenue router
///      must separately authorize this bridge for the PROJECT_REVENUE source type.
contract YieldBankProjectRevenueBridge is
    IProjectModule,
    IProjectControlled,
    IProjectFundable,
    ReentrancyGuard
{
    using SafeERC20 for IERC20;

    address public immutable override registry;
    bytes32 public immutable override(IProjectModule, IProjectControlled) projectId;
    address public immutable override subject;
    address public immutable override controller;
    address public immutable projectRouter;
    address public immutable yieldBankRevenueRouter;
    bytes32 public immutable yieldBankRevenueRouterCodeHash;
    bytes32 public immutable collectionId;

    error OnlyProjectRouter(address caller);
    error InvalidConfiguration();
    error InvalidFundingIdentity(bytes32 projectId, address subject);
    error InexactReceipt(uint256 expected, uint256 measured);
    error InexactForward(uint256 expected, uint256 measured);

    event ProjectRevenueForwarded(
        bytes32 indexed projectId,
        bytes32 indexed collectionId,
        address indexed asset,
        uint256 amount
    );

    constructor(
        address registry_,
        bytes32 projectId_,
        address subject_,
        address controller_,
        address projectRouter_,
        address yieldBankRevenueRouter_,
        bytes32 yieldBankRevenueRouterCodeHash_,
        bytes32 collectionId_
    ) {
        if (
            registry_.code.length == 0 || projectId_ == bytes32(0) || subject_.code.length == 0
                || controller_.code.length == 0 || projectRouter_.code.length == 0
                || collectionId_ == bytes32(0)
        ) revert InvalidConfiguration();
        IntegrationBinding.requireBound(yieldBankRevenueRouter_, yieldBankRevenueRouterCodeHash_);
        address collection = IYieldBankRevenueRouterView(yieldBankRevenueRouter_).collection();
        if (
            collection.code.length == 0
                || IYieldBankCollectionIdentity(collection).collectionId() != collectionId_
        ) revert InvalidConfiguration();
        registry = registry_;
        projectId = projectId_;
        subject = subject_;
        controller = controller_;
        projectRouter = projectRouter_;
        yieldBankRevenueRouter = yieldBankRevenueRouter_;
        yieldBankRevenueRouterCodeHash = yieldBankRevenueRouterCodeHash_;
        collectionId = collectionId_;
    }

    function fund(
        bytes32 suppliedProjectId,
        address suppliedSubject,
        address asset,
        uint256 amount,
        bytes calldata config
    ) external payable nonReentrant returns (uint256 received) {
        if (msg.sender != projectRouter) revert OnlyProjectRouter(msg.sender);
        if (suppliedProjectId != projectId || suppliedSubject != subject) {
            revert InvalidFundingIdentity(suppliedProjectId, suppliedSubject);
        }
        if (msg.value != 0 || asset.code.length == 0 || amount == 0) {
            revert InvalidConfiguration();
        }
        IntegrationBinding.requireBound(yieldBankRevenueRouter, yieldBankRevenueRouterCodeHash);
        IERC20 token = IERC20(asset);
        uint256 beforeBalance = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), amount);
        received = token.balanceOf(address(this)) - beforeBalance;
        if (received != amount) revert InexactReceipt(amount, received);
        token.forceApprove(yieldBankRevenueRouter, amount);
        uint256 reported = IYieldBankFundable(yieldBankRevenueRouter)
            .fund(collectionId, asset, amount, YieldBankIds.PROJECT_REVENUE, config);
        token.forceApprove(yieldBankRevenueRouter, 0);
        uint256 afterBalance = token.balanceOf(address(this));
        if (reported != amount || beforeBalance != afterBalance) {
            revert InexactForward(amount, reported);
        }
        emit ProjectRevenueForwarded(projectId, collectionId, asset, amount);
    }
}
