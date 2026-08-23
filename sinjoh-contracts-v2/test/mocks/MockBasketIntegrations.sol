// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { IBasketYieldAdapter } from "../../src/interfaces/IBasketYieldAdapter.sol";
import { IProjectFundable } from "../../src/interfaces/IProjectFundable.sol";
import { IProjectModule } from "../../src/interfaces/IProjectModule.sol";

contract MockBasketAsset is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) { }

    function mint(address recipient, uint256 amount) external {
        _mint(recipient, amount);
    }
}

contract MockBasketSubject is ERC20 {
    address public immutable registry;
    bytes32 public immutable projectId;

    constructor(address registry_, bytes32 projectId_) ERC20("Basket Subject", "BSUB") {
        registry = registry_;
        projectId = projectId_;
    }

    function mint(address recipient, uint256 amount) external {
        _mint(recipient, amount);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}

contract MockBasketModule is IProjectModule, IProjectFundable, IERC721Receiver {
    using SafeERC20 for IERC20;

    address public immutable override registry;
    address public immutable override subject;
    bytes32 public immutable override projectId;
    uint8 public immutable eligibilityMode;
    address public immutable eligibilitySource;
    bool public failFunding;
    mapping(address asset => uint256 amount) public funded;
    mapping(address asset => uint256 amount) public basketRouted;

    error ForcedFailure();

    constructor(
        address registry_,
        address subject_,
        bytes32 projectId_,
        uint8 eligibilityMode_,
        address eligibilitySource_
    ) {
        registry = registry_;
        subject = subject_;
        projectId = projectId_;
        eligibilityMode = eligibilityMode_;
        eligibilitySource = eligibilitySource_;
    }

    receive() external payable { }

    function basketManager() external view returns (address) {
        return eligibilitySource;
    }

    function setFailFunding(bool fail) external {
        failFunding = fail;
    }

    function execute(address target, bytes calldata data)
        external
        payable
        returns (bytes memory result)
    {
        (bool success, bytes memory returned) = target.call{ value: msg.value }(data);
        if (!success) assembly ("memory-safe") { revert(add(returned, 32), mload(returned)) }
        return returned;
    }

    function fund(bytes32 id, address subject_, address asset, uint256 amount, bytes calldata)
        external
        payable
        returns (uint256 received)
    {
        if (failFunding) revert ForcedFailure();
        require(id == projectId && subject_ == subject, "identity");
        if (asset == address(0)) {
            require(msg.value == amount, "native");
        } else {
            IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        }
        funded[asset] += amount;
        return amount;
    }

    function deposit(address asset, uint256 amount, bool routeToBasket) external {
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        funded[asset] += amount;
        if (routeToBasket) basketRouted[asset] += amount;
    }

    function depositNative(bool routeToBasket) external payable {
        funded[address(0)] += msg.value;
        if (routeToBasket) basketRouted[address(0)] += msg.value;
    }

    function onERC721Received(address, address, uint256, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return IERC721Receiver.onERC721Received.selector;
    }
}

    contract MockBasketYieldAdapter is IBasketYieldAdapter {
        using SafeERC20 for IERC20;

        address public override basketVault;
        address public immutable override depositAsset;
        uint256 private _totalAssets;
        address[] private _outputAssets;
        mapping(address asset => uint256 amount) public harvestable;

        error OnlyVault();
        error AlreadyBound();

        constructor(address depositAsset_, address[] memory outputAssets_) {
            depositAsset = depositAsset_;
            _outputAssets = outputAssets_;
        }

        function bind(address vault) external {
            if (basketVault != address(0)) revert AlreadyBound();
            basketVault = vault;
        }

        function yieldSource() external view override returns (address) {
            return address(this);
        }

        function totalAssets() external view returns (uint256) {
            return _totalAssets;
        }

        function deposit(uint256 assets) external returns (uint256 positionUnits) {
            if (msg.sender != basketVault) revert OnlyVault();
            IERC20(depositAsset).safeTransferFrom(msg.sender, address(this), assets);
            _totalAssets += assets;
            return assets;
        }

        function addYield(address asset, uint256 amount) external {
            IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
            harvestable[asset] += amount;
            if (asset == depositAsset) _totalAssets += amount;
        }

        function realizeLoss(uint256 amount) external {
            _totalAssets -= amount;
            IERC20(depositAsset).safeTransfer(address(0xdead), amount);
        }

        function harvest(address recipient)
            external
            returns (address[] memory assets, uint256[] memory amounts)
        {
            if (msg.sender != basketVault || recipient != basketVault) revert OnlyVault();
            assets = _outputAssets;
            amounts = new uint256[](assets.length);
            for (uint256 i; i < assets.length; ++i) {
                address asset = assets[i];
                uint256 amount = harvestable[asset];
                harvestable[asset] = 0;
                amounts[i] = amount;
                if (asset == depositAsset) _totalAssets -= amount;
                if (amount != 0) IERC20(asset).safeTransfer(recipient, amount);
            }
        }

        function exitAll(address recipient)
            external
            returns (address[] memory assets, uint256[] memory amounts)
        {
            if (msg.sender != basketVault || recipient != basketVault) revert OnlyVault();
            assets = _outputAssets;
            amounts = new uint256[](assets.length);
            for (uint256 i; i < assets.length; ++i) {
                address asset = assets[i];
                uint256 amount = IERC20(asset).balanceOf(address(this));
                amounts[i] = amount;
                harvestable[asset] = 0;
                if (amount != 0) IERC20(asset).safeTransfer(recipient, amount);
            }
            _totalAssets = 0;
        }
    }
