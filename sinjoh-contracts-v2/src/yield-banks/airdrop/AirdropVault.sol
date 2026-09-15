// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IYieldBankCollection } from "../interfaces/IYieldBankCollection.sol";
import { AirdropAssetRegistry } from "./AirdropAssetRegistry.sol";
import { AirdropBankCustody } from "./AirdropBankCustody.sol";

contract AirdropVault is ReentrancyGuard {
    using SafeERC20 for IERC20;
    address public immutable controller;
    IYieldBankCollection public immutable collection;
    AirdropAssetRegistry public immutable registry;
    mapping(uint256 => AirdropBankCustody) public treasuryOf;
    // Retain subject discovery, including exited positions, for delayed issuer claims.
    mapping(uint256 => mapping(address => AirdropBankCustody)) public custodyOf;
    mapping(address => uint256) public totalPrincipal;
    error Unauthorized();
    error InvalidTransfer();
    event CustodyCreated(uint256 indexed bank, address indexed asset, address custody);
    event PrincipalChanged(uint256 indexed bank, address indexed asset, uint256 units);

    constructor(address controller_, address collection_, address registry_) {
        if (
            controller_.code.length == 0 || collection_.code.length == 0
                || registry_.code.length == 0
        ) revert Unauthorized();
        controller = controller_;
        collection = IYieldBankCollection(collection_);
        registry = AirdropAssetRegistry(registry_);
    }

    function principalOf(uint256 bank, address asset) external view returns (uint256) {
        AirdropBankCustody custody = custodyOf[bank][asset];
        return address(custody) == address(0) ? 0 : custody.principal(asset);
    }

    function deposit(uint256 bank, address asset, uint256 units) external nonReentrant {
        if (
            msg.sender != controller || units == 0 || bank == 0
                || collection.accountOf(bank) == address(0)
        ) revert Unauthorized();
        registry.requireCurrent(asset, true);
        AirdropBankCustody custody = treasuryOf[bank];
        if (address(custody) == address(0)) {
            custody = new AirdropBankCustody{ salt: keccak256(abi.encode(bank)) }(
                address(this), address(collection), address(registry), bank
            );
            treasuryOf[bank] = custody;
        }
        if (address(custodyOf[bank][asset]) == address(0)) {
            custodyOf[bank][asset] = custody;
            emit CustodyCreated(bank, asset, address(custody));
        }
        if (custody.principal(asset) + units < registry.minimumHoldingUnits(asset)) {
            revert InvalidTransfer();
        }
        IERC20 token = IERC20(asset);
        uint256 beforeBalance = token.balanceOf(address(this));
        token.safeTransferFrom(controller, address(this), units);
        if (token.balanceOf(address(this)) != beforeBalance + units) revert InvalidTransfer();
        token.forceApprove(address(custody), units);
        custody.deposit(asset, units);
        token.forceApprove(address(custody), 0);
        if (token.balanceOf(address(this)) != beforeBalance) revert InvalidTransfer();
        totalPrincipal[asset] += units;
        emit PrincipalChanged(bank, asset, custody.principal(asset));
    }

    function withdraw(uint256 bank, address asset, uint256 units) external nonReentrant {
        if (msg.sender != controller || units == 0) revert Unauthorized();
        AirdropBankCustody custody = custodyOf[bank][asset];
        IERC20 token = IERC20(asset);
        uint256 beforeBalance = token.balanceOf(address(this));
        uint256 beforeController = token.balanceOf(controller);
        custody.withdraw(asset, units);
        totalPrincipal[asset] -= units;
        token.safeTransfer(controller, units);
        if (
            token.balanceOf(address(this)) != beforeBalance
                || token.balanceOf(controller) != beforeController + units
        ) revert InvalidTransfer();
        emit PrincipalChanged(bank, asset, custody.principal(asset));
    }
}
