// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IProjectBasketManager } from "../../src/interfaces/IProjectBasketManager.sol";
import { IProjectControlled } from "../../src/interfaces/IProjectControlled.sol";
import { IProjectPriceGuard } from "../../src/interfaces/IProjectPriceGuard.sol";
import { IProjectSwapAdapter } from "../../src/interfaces/IProjectSwapAdapter.sol";

contract MockTreasuryERC20 is ERC20 {
    uint16 public transferFeeBps;
    bool public returnFalse;

    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) { }

    function mint(address recipient, uint256 amount) external {
        _mint(recipient, amount);
    }

    function setTransferFeeBps(uint16 newFee) external {
        transferFeeBps = newFee;
    }

    function setReturnFalse(bool enabled) external {
        returnFalse = enabled;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        if (returnFalse) return false;
        return super.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        if (returnFalse) return false;
        return super.transferFrom(from, to, amount);
    }

    function _update(address from, address to, uint256 amount) internal override {
        uint256 fee = from == address(0) || to == address(0) ? 0 : amount * transferFeeBps / 10_000;
        if (fee != 0) super._update(from, address(0xdead), fee);
        super._update(from, to, amount - fee);
    }
}

contract MockProjectController is IProjectControlled {
    bytes32 public immutable override projectId;
    address public immutable override controller;

    constructor(bytes32 projectId_) {
        projectId = projectId_;
        controller = address(this);
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
}

    contract MockProjectPriceGuard is IProjectPriceGuard {
        uint256 public minimumOut;
        uint48 public validUntil;

        function setQuote(uint256 minimumOut_, uint48 validUntil_) external {
            minimumOut = minimumOut_;
            validUntil = validUntil_;
        }

        function minimumOutput(address, address, uint256, bytes32, bytes calldata)
            external
            view
            returns (uint256, uint48)
        {
            return (minimumOut, validUntil);
        }
    }

    contract MockProjectSwapAdapter is IProjectSwapAdapter {
        using SafeERC20 for IERC20;

        uint256 public outputAmount;
        uint256 public spendAmount;
        bool public shouldRevert;

        error ForcedFailure();
        error NativeOutputFailed();

        receive() external payable { }

        function configure(uint256 outputAmount_, uint256 spendAmount_, bool shouldRevert_)
            external
        {
            outputAmount = outputAmount_;
            spendAmount = spendAmount_;
            shouldRevert = shouldRevert_;
        }

        function swap(address assetIn, address assetOut, uint256 amountIn, uint256, bytes calldata)
            external
            payable
            returns (uint256 reportedAmountOut)
        {
            if (shouldRevert) revert ForcedFailure();
            uint256 spend = spendAmount == type(uint256).max ? amountIn : spendAmount;
            if (assetIn == address(0)) {
                require(msg.value == amountIn, "native input");
                if (spend < amountIn) {
                    (bool refunded,) = msg.sender.call{ value: amountIn - spend }("");
                    require(refunded, "refund");
                }
            } else {
                require(msg.value == 0, "unexpected value");
                IERC20(assetIn).safeTransferFrom(msg.sender, address(this), spend);
            }

            if (assetOut == address(0)) {
                (bool sent,) = msg.sender.call{ value: outputAmount }("");
                if (!sent) revert NativeOutputFailed();
            } else {
                IERC20(assetOut).safeTransfer(msg.sender, outputAmount);
            }
            return outputAmount;
        }
    }

    contract MockBasketNFT is ERC721 {
        address public immutable manager;

        error OnlyManager();

        constructor() ERC721("Mock Basket", "MBASK") {
            manager = msg.sender;
        }

        function mint(address owner, uint256 tokenId) external {
            if (msg.sender != manager) revert OnlyManager();
            _safeMint(owner, tokenId);
        }

        function burn(uint256 tokenId) external {
            if (msg.sender != manager) revert OnlyManager();
            _burn(tokenId);
        }
    }

    contract MockProjectBasketManager is IProjectBasketManager {
        using SafeERC20 for IERC20;

        address private constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

        MockBasketNFT private immutable _nft;
        mapping(uint256 basketId => bytes32 id) public override basketProjectId;
        mapping(uint256 basketId => address subject) public basketSubject;
        mapping(uint256 basketId => uint256 price) public override burnPriceSubject;
        mapping(uint256 basketId => bool begun) public burnBegun;
        mapping(uint256 basketId => bytes config) public configuration;
        mapping(uint256 basketId => address[] assets) private _redemptionAssets;
        mapping(uint256 basketId => mapping(address asset => uint256 amount)) public
            redemptionAmount;
        mapping(uint256 basketId => mapping(address asset => uint256 amount)) public funded;

        bool public failFunding;
        bool public reportWrongFunding;
        bool public keepNftAfterFinalize;

        error ForcedFundingFailure();
        error InvalidAttribution();

        receive() external payable { }

        constructor() {
            _nft = new MockBasketNFT();
        }

        function basketNFT() external view returns (IERC721) {
            return _nft;
        }

        function createBasket(
            address owner,
            uint256 basketId,
            bytes32 projectId,
            address subject,
            uint256 burnPrice,
            address[] calldata assets,
            uint256[] calldata amounts
        ) external {
            require(assets.length == amounts.length, "length");
            basketProjectId[basketId] = projectId;
            basketSubject[basketId] = subject;
            burnPriceSubject[basketId] = burnPrice;
            for (uint256 i; i < assets.length; ++i) {
                _redemptionAssets[basketId].push(assets[i]);
                redemptionAmount[basketId][assets[i]] = amounts[i];
            }
            _nft.mint(owner, basketId);
        }

        function setFundingBehavior(bool fail, bool wrongReport) external {
            failFunding = fail;
            reportWrongFunding = wrongReport;
        }

        function setKeepNftAfterFinalize(bool keep) external {
            keepNftAfterFinalize = keep;
        }

        function fund(
            bytes32 projectId,
            address subject,
            address asset,
            uint256 amount,
            bytes calldata config
        ) external payable returns (uint256 received) {
            if (failFunding) revert ForcedFundingFailure();
            uint256 basketId = abi.decode(config, (uint256));
            if (basketProjectId[basketId] != projectId || basketSubject[basketId] != subject) {
                revert InvalidAttribution();
            }
            if (asset == address(0)) {
                require(msg.value == amount, "native amount");
            } else {
                require(msg.value == 0, "unexpected value");
                IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
            }
            funded[basketId][asset] += amount;
            return reportWrongFunding ? amount + 1 : amount;
        }

        function updateConfiguration(uint256 basketId, bytes calldata config) external {
            require(_nft.ownerOf(basketId) == msg.sender, "not owner");
            configuration[basketId] = config;
        }

        function beginBurn(uint256 basketId) external {
            require(_nft.ownerOf(basketId) == msg.sender, "not owner");
            burnBegun[basketId] = true;
        }

        function redemptionAssets(uint256 basketId)
            external
            view
            returns (address[] memory assets)
        {
            return _redemptionAssets[basketId];
        }

        function finalizeBurn(uint256 basketId)
            external
            returns (address[] memory assets, uint256[] memory amounts)
        {
            require(_nft.ownerOf(basketId) == msg.sender, "not owner");
            require(burnBegun[basketId], "not begun");
            uint256 price = burnPriceSubject[basketId];
            if (price != 0) {
                IERC20(basketSubject[basketId]).safeTransferFrom(msg.sender, BURN_ADDRESS, price);
            }
            assets = _redemptionAssets[basketId];
            amounts = new uint256[](assets.length);
            for (uint256 i; i < assets.length; ++i) {
                address asset = assets[i];
                uint256 amount = redemptionAmount[basketId][asset];
                amounts[i] = amount;
                if (asset == address(0)) {
                    (bool success,) = msg.sender.call{ value: amount }("");
                    require(success, "native redemption");
                } else {
                    IERC20(asset).safeTransfer(msg.sender, amount);
                }
            }
            if (!keepNftAfterFinalize) _nft.burn(basketId);
        }
    }

        contract MockRejectNative {
            receive() external payable {
                revert("no native");
            }
        }
