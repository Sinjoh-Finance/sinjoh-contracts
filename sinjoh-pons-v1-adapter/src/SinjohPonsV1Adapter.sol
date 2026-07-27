// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { SafeTransferLib } from "./libraries/SafeTransferLib.sol";

interface IPonsV1Locker {
    function collectFees(address subject) external;
}

contract SinjohPonsV1Adapter {
    using SafeTransferLib for address;

    error AlreadyInitialized();
    error WrongChain(uint256 actual);
    error InvalidAddress();
    error UnsupportedAsset(address asset);
    error Reentrancy();
    error UnexpectedBalanceDelta(address asset, uint256 expected, uint256 actual);

    event Initialized(address indexed subject, address indexed router);
    event Collected(
        address indexed subject, uint256 subjectAmount, uint256 wethAmount, address indexed caller
    );
    event Forwarded(
        address indexed asset, address indexed router, uint256 amount, address indexed caller
    );

    address public immutable ponsLocker;
    address public immutable weth;
    uint256 public immutable deploymentChainId;

    address public subject;
    address public router;
    bool public initialized;
    uint256 private _reentrancyState;

    constructor(address ponsLocker_, address weth_, uint256 chainId_) {
        if (ponsLocker_.code.length == 0 || weth_.code.length == 0) revert InvalidAddress();
        if (chainId_ != block.chainid) revert WrongChain(block.chainid);
        ponsLocker = ponsLocker_;
        weth = weth_;
        deploymentChainId = chainId_;
        initialized = true;
    }

    modifier nonReentrant() {
        if (_reentrancyState == 2) revert Reentrancy();
        _reentrancyState = 2;
        _;
        _reentrancyState = 1;
    }

    function initialize(address subject_, address router_) external {
        if (initialized) revert AlreadyInitialized();
        initialized = true;
        if (
            subject_.code.length == 0 || router_.code.length == 0 || subject_ == weth
                || subject_ == address(this) || router_ == address(this) || subject_ == router_
        ) {
            revert InvalidAddress();
        }
        subject = subject_;
        router = router_;
        emit Initialized(subject_, router_);
    }

    function collect() external nonReentrant {
        _assertChain();
        uint256 subjectBefore = subject.safeBalanceOf(address(this));
        uint256 wethBefore = weth.safeBalanceOf(address(this));
        IPonsV1Locker(ponsLocker).collectFees(subject);
        uint256 subjectAmount = _positiveDelta(subjectBefore, subject.safeBalanceOf(address(this)));
        uint256 wethAmount = _positiveDelta(wethBefore, weth.safeBalanceOf(address(this)));
        emit Collected(subject, subjectAmount, wethAmount, msg.sender);
    }

    function forward(address asset) external nonReentrant returns (uint256 amount) {
        _assertChain();
        if (asset != subject && asset != weth) revert UnsupportedAsset(asset);
        amount = asset.safeBalanceOf(address(this));
        if (amount == 0) return 0;

        uint256 routerBefore = asset.safeBalanceOf(router);
        asset.safeTransfer(router, amount);
        uint256 remaining = asset.safeBalanceOf(address(this));
        uint256 spent = remaining <= amount ? amount - remaining : 0;
        if (remaining != 0) revert UnexpectedBalanceDelta(asset, amount, spent);
        uint256 routerAfter = asset.safeBalanceOf(router);
        uint256 received = routerAfter >= routerBefore ? routerAfter - routerBefore : 0;
        if (received != amount) {
            revert UnexpectedBalanceDelta(asset, amount, received);
        }
        emit Forwarded(asset, router, amount, msg.sender);
    }

    function _assertChain() private view {
        if (block.chainid != deploymentChainId) revert WrongChain(block.chainid);
    }

    function _positiveDelta(uint256 beforeBalance, uint256 afterBalance)
        private
        pure
        returns (uint256)
    {
        return afterBalance >= beforeBalance ? afterBalance - beforeBalance : 0;
    }
}
