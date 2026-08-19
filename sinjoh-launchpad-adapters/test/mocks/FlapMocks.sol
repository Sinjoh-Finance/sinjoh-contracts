// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IFlapPortalTypes, IFlapTaxProcessor } from "../../src/interfaces/IFlap.sol";
import { Clones } from "../../src/libraries/Clones.sol";

contract MockFlapWeth {
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

    function deposit() external payable {
        balanceOf[msg.sender] += msg.value;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        if (failTransfers) return false;
        balanceOf[msg.sender] -= amount;
        uint256 received = amount - (amount * transferFeeBps / 10_000);
        balanceOf[to] += received;
        return true;
    }
}

contract MockFlapTaxTokenV3 {
    mapping(address => uint256) public balanceOf;
    address public taxProcessor;
    address public quoteToken;
    uint16 public buyTaxRate;
    uint16 public sellTaxRate;
    bool public initialized;
    bool public failTransfers;
    uint16 public transferFeeBps;

    function initialize(
        address processor_,
        address quoteToken_,
        uint16 buyTaxRate_,
        uint16 sellTaxRate_
    ) external {
        require(!initialized, "initialized");
        initialized = true;
        taxProcessor = processor_;
        quoteToken = quoteToken_;
        buyTaxRate = buyTaxRate_;
        sellTaxRate = sellTaxRate_;
    }

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
        uint256 received = amount - (amount * transferFeeBps / 10_000);
        balanceOf[to] += received;
        return true;
    }
}

contract MockFlapTaxProcessor {
    address public taxToken;
    address public portal;
    address public owner;
    address public quoteToken;
    address public weth;
    address public marketAddress;
    address public commissionReceiver;
    uint16 public commissionBps;
    IFlapTaxProcessor.FeeConfig private _feeConfig;

    uint256 public marketPending;
    uint256 public commissionPending;
    bool public failDispatch;
    bool public reenter;

    constructor(
        address portal_,
        address taxToken_,
        address quoteToken_,
        address marketAddress_,
        address commissionReceiver_,
        uint16 commissionBps_,
        uint16 flapFeeRate_
    ) {
        portal = portal_;
        owner = portal_;
        taxToken = taxToken_;
        quoteToken = quoteToken_;
        weth = quoteToken_;
        marketAddress = marketAddress_;
        commissionReceiver = commissionReceiver_;
        commissionBps = commissionBps_;
        _feeConfig = IFlapTaxProcessor.FeeConfig({
            marketBps: 10_000,
            deflationBps: 0,
            lpBps: 0,
            dividendBps: 0,
            feeRate: flapFeeRate_,
            isWeth: true
        });
    }

    function getQuoteToken() external view returns (address) {
        return quoteToken;
    }

    function feeConfig() external view returns (IFlapTaxProcessor.FeeConfig memory) {
        return _feeConfig;
    }

    function configurePending(uint256 marketAmount, uint256 commissionAmount) external payable {
        require(msg.value == marketAmount + commissionAmount, "wrong value");
        marketPending += marketAmount;
        commissionPending += commissionAmount;
    }

    function setFailDispatch(bool value) external {
        failDispatch = value;
    }

    function setReenter(bool value) external {
        reenter = value;
    }

    function setMarketAddress(address value) external {
        marketAddress = value;
    }

    function setCommissionReceiver(address value) external {
        commissionReceiver = value;
    }

    function setCommissionBps(uint16 value) external {
        commissionBps = value;
    }

    function setPortal(address value) external {
        portal = value;
    }

    function setOwner(address value) external {
        owner = value;
    }

    function setQuoteToken(address value) external {
        quoteToken = value;
    }

    function setFeeConfig(IFlapTaxProcessor.FeeConfig calldata value) external {
        _feeConfig = value;
    }

    function dispatch() external {
        require(!failDispatch, "dispatch failed");
        if (reenter) {
            (bool success, bytes memory reason) =
                msg.sender.call(abi.encodeWithSignature("collect()"));
            if (!success) {
                assembly ("memory-safe") {
                    revert(add(reason, 32), mload(reason))
                }
            }
        }

        uint256 marketAmount = marketPending;
        uint256 commissionAmount = commissionPending;
        marketPending = 0;
        commissionPending = 0;
        if (marketAmount != 0) {
            (bool sent,) = payable(marketAddress).call{ value: marketAmount }("");
            require(sent, "market failed");
        }
        if (commissionAmount != 0) {
            (bool sent,) = payable(commissionReceiver).call{ value: commissionAmount }("");
            require(sent, "commission failed");
        }
    }
}

contract MockFlapPortal {
    using Clones for address;

    struct QuoteConfiguration {
        uint8 enabled;
        uint8 defaultCurve;
        uint8 alternativeCurve;
        uint8 nativeToQuoteSwapType;
        uint8 dexId;
    }

    address public immutable flapWrappedNative;
    address public launchImplementation;
    string private _version = "v5.15.2";
    QuoteConfiguration private _quoteConfiguration = QuoteConfiguration(1, 25, 25, 0, 0);
    uint16 public flapFeeRate = 6_000;
    uint256 public developerBuyAmount;
    uint256 public refundAmount;
    bool public returnZero;
    uint8 public processorMutationMode;

    address public lastToken;
    address public lastProcessor;
    uint256 public lastValue;

    constructor(address implementation_, address flapWrappedNative_) {
        launchImplementation = implementation_;
        flapWrappedNative = flapWrappedNative_;
    }

    function version() external view returns (string memory) {
        return _version;
    }

    function getQuoteTokenConfiguration(address) external view returns (QuoteConfiguration memory) {
        return _quoteConfiguration;
    }

    function setVersion(string calldata value) external {
        _version = value;
    }

    function setQuoteConfiguration(QuoteConfiguration calldata value) external {
        _quoteConfiguration = value;
    }

    function setLaunchImplementation(address value) external {
        launchImplementation = value;
    }

    function setFlapFeeRate(uint16 value) external {
        flapFeeRate = value;
    }

    function setDeveloperBuyAmount(uint256 value) external {
        developerBuyAmount = value;
    }

    function setRefundAmount(uint256 value) external {
        refundAmount = value;
    }

    function setReturnZero(bool value) external {
        returnZero = value;
    }

    function setProcessorMutationMode(uint8 value) external {
        processorMutationMode = value;
    }

    function newTokenV6(IFlapPortalTypes.NewTokenV6Params calldata params)
        external
        payable
        returns (address token)
    {
        require(msg.value == params.quoteAmt, "wrong quote amount");
        lastValue = msg.value;
        address implementation_ = launchImplementation;
        address predicted =
            Clones.predictDeterministicAddress(implementation_, params.salt, address(this));
        uint16 effective =
            params.buyTaxRate > params.sellTaxRate ? params.buyTaxRate : params.sellTaxRate;
        uint16 commission = effective <= 100 ? 600 : uint16(uint256(10_000) * 6 / effective);
        MockFlapTaxProcessor processor = new MockFlapTaxProcessor(
            address(this),
            predicted,
            flapWrappedNative,
            params.beneficiary,
            params.commissionReceiver,
            commission,
            flapFeeRate
        );
        token = Clones.cloneDeterministic(implementation_, params.salt);
        MockFlapTaxTokenV3(token)
            .initialize(
                address(processor), flapWrappedNative, params.buyTaxRate, params.sellTaxRate
            );
        if (processorMutationMode == 1) processor.setMarketAddress(address(0xBAD));
        if (processorMutationMode == 2) processor.setCommissionReceiver(address(0xBAD));
        if (processorMutationMode == 3) processor.setQuoteToken(address(0xBAD));
        if (processorMutationMode == 4) processor.setPortal(address(0xBAD));
        if (processorMutationMode == 5) processor.setOwner(address(0xBAD));
        lastToken = token;
        lastProcessor = address(processor);

        if (developerBuyAmount != 0) {
            MockFlapTaxTokenV3(token).mint(msg.sender, developerBuyAmount);
        }
        if (refundAmount != 0) {
            (bool sent,) = payable(msg.sender).call{ value: refundAmount }("");
            require(sent, "refund failed");
        }
        if (returnZero) return address(0);
    }

    receive() external payable { }
}

contract MockFlapRouter {
    address public creator;
    address public weth;
    address public subject;
    bytes32 public configHash = keccak256("flap-router-config");
    bool public bound;
    address public launchpadAdapter;
    bool public supportWeth = true;
    bool public failBind;

    constructor(address creator_, address weth_, address adapter_) {
        creator = creator_;
        weth = weth_;
        launchpadAdapter = adapter_;
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

    function setSupportWeth(bool value) external {
        supportWeth = value;
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
        return bound && supportWeth && asset == weth;
    }
}
