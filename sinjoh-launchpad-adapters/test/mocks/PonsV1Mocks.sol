// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IPonsV1LaunchFactory } from "../../src/interfaces/IPonsV1.sol";

contract MockPonsV1Token {
    mapping(address => uint256) public balanceOf;
    bool public failTransfers;
    uint16 public transferFeeBps;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function setFailTransfers(bool value) external {
        failTransfers = value;
    }

    function setTransferFeeBps(uint16 value) external {
        transferFeeBps = value;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        if (failTransfers) return false;
        balanceOf[msg.sender] -= amount;
        uint256 received = amount - ((amount * transferFeeBps) / 10_000);
        balanceOf[to] += received;
        return true;
    }
}

/// @dev Uses a fallback for collectFees so tests can model both deployed v1
/// ABIs: successful calls returning no data and successful calls returning two
/// words. The selector is identical in both versions.
contract MockPonsV1Locker {
    error NoFeesToCollect();
    error CollectionFailed(uint256 code);

    bytes4 private constant COLLECT_SELECTOR = bytes4(keccak256("collectFees(address)"));

    mapping(address => address) public feeRedirects;
    address public subject;
    address public weth;
    uint256 public subjectAmount;
    uint256 public wethAmount;
    uint8 public mode; // 0=no-data success, 1=two-word success, 2=idle, 3=unexpected

    function configure(
        address subject_,
        address weth_,
        uint256 subjectAmount_,
        uint256 wethAmount_,
        uint8 mode_
    ) external {
        subject = subject_;
        weth = weth_;
        subjectAmount = subjectAmount_;
        wethAmount = wethAmount_;
        mode = mode_;
    }

    function setFeeRedirect(address token, address redirect) external {
        feeRedirects[token] = redirect;
    }

    fallback() external {
        if (msg.sig != COLLECT_SELECTOR) revert CollectionFailed(404);
        if (mode == 2) revert NoFeesToCollect();
        if (mode == 3) revert CollectionFailed(7);

        uint256 subjectAmount_ = subjectAmount;
        uint256 wethAmount_ = wethAmount;
        subjectAmount = 0;
        wethAmount = 0;
        if (subjectAmount_ != 0) {
            require(MockPonsV1Token(subject).transfer(msg.sender, subjectAmount_));
        }
        if (wethAmount_ != 0) {
            require(MockPonsV1Token(weth).transfer(msg.sender, wethAmount_));
        }

        if (mode == 1) {
            assembly {
                mstore(0, subjectAmount_)
                mstore(0x20, wethAmount_)
                return(0, 0x40)
            }
        }
        assembly {
            return(0, 0)
        }
    }
}

contract MockPonsV1LaunchFactory {
    address public locker;
    uint256 public launchFee = 0.0005 ether;
    bool public launchEnabled = true;

    address public pairToken;
    uint256 public launchVersion = 1;
    address public dexFactory = address(0xD3);
    uint24 public dexFee = 10_000;

    address public predictedToken;
    address public returnedToken;
    uint256 public developerBuyAmount;
    uint256 public refundAmount;
    uint256 public lastValue;
    address public lastFeeWallet;

    constructor(address locker_, address pairToken_, address token_) {
        locker = locker_;
        pairToken = pairToken_;
        predictedToken = token_;
        returnedToken = token_;
    }

    function setLaunchEnabled(bool value) external {
        launchEnabled = value;
    }

    function setPairToken(address value) external {
        pairToken = value;
    }

    function setLaunchVersion(uint256 value) external {
        launchVersion = value;
    }

    function setDexFee(uint24 value) external {
        dexFee = value;
    }

    function setPredictedToken(address value) external {
        predictedToken = value;
    }

    function setReturnedToken(address value) external {
        returnedToken = value;
    }

    function setDeveloperBuyAmount(uint256 value) external {
        developerBuyAmount = value;
    }

    function setRefundAmount(uint256 value) external {
        refundAmount = value;
    }

    function getLaunchConfig(uint256) external view returns (address, uint256) {
        return (pairToken, launchVersion);
    }

    function getDexConfig(uint256) external view returns (address, uint24) {
        return (dexFactory, dexFee);
    }

    function predictTokenAddress(
        IPonsV1LaunchFactory.LaunchParams calldata,
        uint256,
        uint256,
        bytes32,
        address
    ) external view returns (address) {
        return predictedToken;
    }

    function launchToken(
        IPonsV1LaunchFactory.LaunchParams calldata params,
        uint256,
        uint256,
        bytes32
    ) external payable returns (address token) {
        lastValue = msg.value;
        lastFeeWallet = params.feeWallet;
        token = returnedToken;
        if (token != address(0) && developerBuyAmount != 0) {
            MockPonsV1Token(token).mint(params.feeWallet, developerBuyAmount);
        }
        if (refundAmount != 0) {
            (bool sent,) = payable(msg.sender).call{ value: refundAmount }("");
            require(sent, "refund failed");
        }
    }

    receive() external payable { }
}

contract MockPonsV1Router {
    address public creator;
    address public weth;
    address public subject;
    bytes32 public configHash;
    bool public bound;
    address public launchpadAdapter;
    bool public supportSubject = true;
    bool public supportWeth = true;
    bool public failBind;

    constructor(address creator_, address weth_, address adapter_) {
        creator = creator_;
        weth = weth_;
        launchpadAdapter = adapter_;
        configHash = keccak256("router-config");
    }

    function setCreator(address value) external {
        creator = value;
    }

    function setWeth(address value) external {
        weth = value;
    }

    function setLaunchpadAdapter(address value) external {
        launchpadAdapter = value;
    }

    function setConfigHash(bytes32 value) external {
        configHash = value;
    }

    function setSupport(bool subject_, bool weth_) external {
        supportSubject = subject_;
        supportWeth = weth_;
    }

    function setFailBind(bool value) external {
        failBind = value;
    }

    function bind(address subject_) external {
        require(!failBind, "bind failed");
        require(msg.sender == launchpadAdapter, "unauthorized binder");
        subject = subject_;
        bound = true;
    }

    function isIntakeAsset(address asset) external view returns (bool) {
        if (!bound) return false;
        if (asset == subject) return supportSubject;
        if (asset == weth) return supportWeth;
        return false;
    }
}
