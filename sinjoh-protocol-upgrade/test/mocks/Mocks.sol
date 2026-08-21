// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { IERC5805 } from "@openzeppelin/contracts/interfaces/IERC5805.sol";
import { Checkpoints } from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import { Time } from "@openzeppelin/contracts/utils/types/Time.sol";
import { ISinjohFundable } from "../../src/interfaces/ISinjohFundable.sol";
import { IYieldAdapter } from "../../src/interfaces/IYieldAdapter.sol";
import { ITwapOracle } from "../../src/interfaces/ITwapOracle.sol";

/// @dev Test stand-in for a subject token whose historical wallet balances are IVotes power.
contract MockDirectVotesToken is ERC20, IERC5805 {
    using Checkpoints for Checkpoints.Trace256;

    mapping(address account => Checkpoints.Trace256 checkpoints) private _balanceCheckpoints;
    Checkpoints.Trace256 private _supplyCheckpoints;

    error DelegationUnsupported();
    error FutureLookup(uint256 timepoint, uint48 clock);

    constructor(address holder, uint256 supply) ERC20("Subject Token", "SUBJECT") {
        _mint(holder, supply);
    }

    function clock() public view returns (uint48) {
        return Time.blockNumber();
    }

    function CLOCK_MODE() external pure returns (string memory) {
        return "mode=blocknumber&from=default";
    }

    function getVotes(address account) external view returns (uint256) {
        return balanceOf(account);
    }

    function getPastVotes(address account, uint256 timepoint) external view returns (uint256) {
        _validateTimepoint(timepoint);
        return _balanceCheckpoints[account].upperLookupRecent(timepoint);
    }

    function getPastTotalSupply(uint256 timepoint) external view returns (uint256) {
        _validateTimepoint(timepoint);
        return _supplyCheckpoints.upperLookupRecent(timepoint);
    }

    function delegates(address) external pure returns (address) {
        return address(0);
    }

    function delegate(address) external pure {
        revert DelegationUnsupported();
    }

    function delegateBySig(address, uint256, uint256, uint8, bytes32, bytes32) external pure {
        revert DelegationUnsupported();
    }

    function _update(address from, address to, uint256 value) internal override {
        super._update(from, to, value);
        uint256 timepoint = clock();
        if (from == address(0) || to == address(0)) {
            _supplyCheckpoints.push(timepoint, totalSupply());
        }
        if (from != address(0)) {
            _balanceCheckpoints[from].push(timepoint, balanceOf(from));
        }
        if (to != address(0)) {
            _balanceCheckpoints[to].push(timepoint, balanceOf(to));
        }
    }

    function _validateTimepoint(uint256 timepoint) private view {
        uint48 currentTimepoint = clock();
        if (timepoint >= currentTimepoint) revert FutureLookup(timepoint, currentTimepoint);
    }
}

contract MockERC20 {
    string public name = "Mock";
    string public symbol = "MOCK";
    uint8 public constant decimals = 18;
    uint256 public totalSupply;
    uint16 public feeBps;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
    }

    function setFeeBps(uint16 value) external {
        feeBps = value;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) private {
        balanceOf[from] -= amount;
        uint256 fee = amount * feeBps / 10_000;
        balanceOf[to] += amount - fee;
        totalSupply -= fee;
    }
}

contract MockRebasingERC20 is MockERC20 {
    function rebaseUp(address account, uint256 amount) external {
        totalSupply += amount;
        balanceOf[account] += amount;
    }
}

contract MockERC4626 is ERC4626 {
    constructor(IERC20 asset_) ERC20("Mock Vault Share", "MVS") ERC4626(asset_) { }
}

contract MockFundable is ISinjohFundable {
    mapping(address => uint256) public funded;
    bool public pullFunds = true;
    bool public shouldRevert;

    function setPullFunds(bool value) external {
        pullFunds = value;
    }

    function setShouldRevert(bool value) external {
        shouldRevert = value;
    }

    function fund(address asset, uint256 amount, bytes calldata)
        external
        returns (uint256 received)
    {
        require(!shouldRevert, "REVERTING_DISTRIBUTOR");
        if (pullFunds) {
            require(IERC20(asset).transferFrom(msg.sender, address(this), amount));
        }
        funded[asset] += amount;
        return amount;
    }
}

contract MockYieldAdapter is IYieldAdapter {
    address public immutable asset;
    MockERC20 public immutable reward;
    MockERC20 public secondReward;
    address public basket;
    uint256 public totalAssets;
    uint256 public shares;
    uint256 public nextReward;
    uint256 public nextSecondReward;
    uint16 public withdrawBps = 10_000;
    bool public mintReward = true;
    bool public pullFunds = true;
    bool public revertDeposit;
    bool public revertWithdraw;
    bool public revertHarvest;

    constructor(address asset_, MockERC20 reward_) {
        asset = asset_;
        reward = reward_;
    }

    function setBasket(address value) external {
        basket = value;
    }

    function setNextReward(uint256 value) external {
        nextReward = value;
    }

    function setSecondReward(MockERC20 token, uint256 value) external {
        secondReward = token;
        nextSecondReward = value;
    }

    function setWithdrawBps(uint16 value) external {
        withdrawBps = value;
    }

    function setTotalAssets(uint256 value) external {
        totalAssets = value;
    }

    function setMintReward(bool value) external {
        mintReward = value;
    }

    function setPullFunds(bool value) external {
        pullFunds = value;
    }

    function setReverts(bool deposit_, bool withdraw_, bool harvest_) external {
        revertDeposit = deposit_;
        revertWithdraw = withdraw_;
        revertHarvest = harvest_;
    }

    function deposit(uint256 amount) external returns (uint256 mintedShares) {
        require(!revertDeposit, "REVERTING_DEPOSIT");
        if (pullFunds) require(IERC20(asset).transferFrom(msg.sender, address(this), amount));
        totalAssets += amount;
        shares += amount;
        return amount;
    }

    function withdraw(uint256 shareAmount) external returns (uint256 assets) {
        require(!revertWithdraw, "REVERTING_WITHDRAW");
        shares -= shareAmount;
        totalAssets -= shareAmount;
        assets = shareAmount * withdrawBps / 10_000;
        uint256 balance = IERC20(asset).balanceOf(address(this));
        if (assets > balance) MockERC20(asset).mint(address(this), assets - balance);
        require(IERC20(asset).transfer(msg.sender, assets));
    }

    function harvest() external returns (address[] memory rewardTokens, uint256[] memory amounts) {
        require(!revertHarvest, "REVERTING_HARVEST");
        uint256 amount = nextReward;
        nextReward = 0;
        if (mintReward) reward.mint(basket, amount);
        uint256 secondAmount = nextSecondReward;
        nextSecondReward = 0;
        bool hasSecond = address(secondReward) != address(0);
        if (hasSecond && mintReward) secondReward.mint(basket, secondAmount);
        rewardTokens = new address[](hasSecond ? 2 : 1);
        amounts = new uint256[](hasSecond ? 2 : 1);
        rewardTokens[0] = address(reward);
        amounts[0] = amount;
        if (hasSecond) {
            rewardTokens[1] = address(secondReward);
            amounts[1] = secondAmount;
        }
    }
}

contract MockTwapOracle is ITwapOracle {
    uint256 public price = 100e18;
    uint48 public updatedAt;

    constructor() {
        updatedAt = uint48(block.timestamp);
    }

    function setPrice(uint256 value) external {
        price = value;
        updatedAt = uint48(block.timestamp);
    }

    function refresh() external {
        updatedAt = uint48(block.timestamp);
    }

    function twapPrice(address, uint32) external view returns (uint256, uint48) {
        return (price, updatedAt);
    }
}
