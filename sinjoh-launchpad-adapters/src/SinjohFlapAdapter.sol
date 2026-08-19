// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { ISinjohLaunchpadAdapter } from "./interfaces/ISinjohLaunchpadAdapter.sol";
import {
    IFlapPortal,
    IFlapPortalTypes,
    IFlapTaxProcessor,
    IFlapTaxTokenV3,
    IFlapWeth
} from "./interfaces/IFlap.sol";
import { Clones } from "./libraries/Clones.sol";
import { SafeTransferLib } from "./libraries/SafeTransferLib.sol";

interface ISinjohFlapRouter {
    function creator() external view returns (address);
    function weth() external view returns (address);
    function subject() external view returns (address);
    function configHash() external view returns (bytes32);
    function bound() external view returns (bool);
    function launchpadAdapter() external view returns (address);
    function isIntakeAsset(address asset) external view returns (bool);
    function bind(address subject) external;
}

/// @notice Launches a native-quote Flap Tax Token V3 and forwards all creator
/// revenue from its TaxProcessor to one immutable Sinjoh router as WETH.
contract SinjohFlapAdapter is ISinjohLaunchpadAdapter {
    using SafeTransferLib for address;

    uint16 private constant BPS = 10_000;
    bytes4 private constant VERSION_SELECTOR = bytes4(keccak256("version()"));
    bytes4 private constant QUOTE_CONFIG_SELECTOR =
        bytes4(keccak256("getQuoteTokenConfiguration(address)"));

    error AlreadyInitialized();
    error AlreadyLaunched();
    error NotLaunched();
    error Unauthorized();
    error WrongChain(uint256 actual);
    error InvalidAddress();
    error InvalidLaunchConfiguration();
    error UnsupportedAsset(address asset);
    error Reentrancy();
    error IncorrectLaunchValue(uint256 expected, uint256 actual);
    error InvalidDeveloperBuy();
    error PortalConfigurationMismatch(bytes32 expected, bytes32 actual);
    error PortalQueryFailed(bytes4 selector);
    error LaunchReturnedNoToken();
    error PredictedTokenAlreadyExists(address token);
    error PredictedTokenMismatch(address expected, address actual);
    error DeveloperBuyBelowMinimum(uint256 minimum, uint256 actual);
    error UnexpectedBalanceDelta(address asset, uint256 expected, uint256 actual);
    error RouterDidNotNameAdapter(address named);
    error RouterCreatorMismatch(address expected, address actual);
    error RouterWethMismatch(address expected, address actual);
    error RouterConfigMismatch(bytes32 expected, bytes32 actual);
    error RouterAlreadyBound();
    error RouterDidNotBindSubject(address expected, address actual);
    error RouterUnsupportedIntake(address asset);
    error InvalidTaxProcessor(address processor);
    error TaxProcessorConfigurationMismatch();
    error FlapFeeRateMismatch(uint16 expected, uint16 actual);

    event Initialized(address indexed router, address indexed creator);
    event Launched(
        address indexed subject,
        address indexed taxProcessor,
        uint256 value,
        uint256 developerBuyAmount
    );
    event DeveloperBuyDelivered(address indexed subject, address indexed creator, uint256 amount);
    event LaunchValueRefunded(address indexed creator, uint256 amount);
    event Collected(
        address indexed subject, address indexed taxProcessor, uint256 wethAmount, address caller
    );
    event Forwarded(
        address indexed asset, address indexed router, uint256 amount, address indexed caller
    );

    address public immutable adapterFactory;
    address public immutable portal;
    address public immutable taxTokenImplementation;
    address public immutable flapWrappedNative;
    address public immutable weth;
    uint256 public immutable deploymentChainId;

    address public router;
    address public creator;
    address public subject;
    address public taxProcessor;
    bytes32 public routerConfigHash;
    uint16 public flapCommissionBps;
    uint16 public flapFeeRate;
    bool public initialized;
    bool public launched;

    uint256 private _reentrancyState;

    constructor(
        address portal_,
        address taxTokenImplementation_,
        address flapWrappedNative_,
        address weth_,
        uint256 chainId_
    ) {
        if (
            portal_.code.length == 0 || taxTokenImplementation_.code.length == 0
                || flapWrappedNative_.code.length == 0 || weth_.code.length == 0
                || portal_ == taxTokenImplementation_ || portal_ == flapWrappedNative_
                || portal_ == weth_ || taxTokenImplementation_ == flapWrappedNative_
                || taxTokenImplementation_ == weth_
        ) revert InvalidAddress();
        if (chainId_ != block.chainid) revert WrongChain(block.chainid);

        adapterFactory = msg.sender;
        portal = portal_;
        taxTokenImplementation = taxTokenImplementation_;
        flapWrappedNative = flapWrappedNative_;
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

    /// @dev Flap's native-quote TaxProcessor unwraps WETH and pays both the
    /// marketing wallet and commission receiver in native ETH. Work is kept out
    /// of this callback and performed by collect() after dispatch returns.
    receive() external payable { }

    function initialize(address router_, address creator_) external {
        if (initialized) revert AlreadyInitialized();
        if (msg.sender != adapterFactory) revert Unauthorized();
        initialized = true;
        if (
            router_.code.length == 0 || creator_ == address(0) || router_ == address(this)
                || creator_ == address(this) || router_ == creator_
        ) revert InvalidAddress();

        ISinjohFlapRouter routerContract = ISinjohFlapRouter(router_);
        address routerCreator = routerContract.creator();
        if (routerCreator != creator_) revert RouterCreatorMismatch(creator_, routerCreator);
        address routerWeth = routerContract.weth();
        if (routerWeth != weth) revert RouterWethMismatch(weth, routerWeth);
        address named = routerContract.launchpadAdapter();
        if (named != address(this)) revert RouterDidNotNameAdapter(named);
        if (routerContract.bound()) revert RouterAlreadyBound();
        bytes32 configHash_ = routerContract.configHash();
        if (configHash_ == bytes32(0)) revert InvalidAddress();

        router = router_;
        creator = creator_;
        routerConfigHash = configHash_;
        emit Initialized(router_, creator_);
    }

    /// @notice Launches the only revenue-bearing Flap path enabled on
    /// Robinhood: native-quote TOKEN_TAXED_V3 through V2_MIGRATOR.
    ///
    /// The Flap-side split is deliberately fixed at 100% marketing to this
    /// adapter, with this adapter also named as commission receiver. User policy
    /// belongs in the Sinjoh router; allowing Flap-side burn/dividend/LP splits
    /// would silently route value around it.
    function launch(
        IFlapPortalTypes.NewTokenV6Params calldata params,
        bytes32 expectedPortalConfigHash,
        uint16 expectedFlapFeeRate,
        uint256 minDeveloperBuyOut
    ) external payable nonReentrant returns (address token) {
        _assertChain();
        if (msg.sender != creator) revert Unauthorized();
        if (launched) revert AlreadyLaunched();
        if (params.quoteAmt != msg.value) {
            revert IncorrectLaunchValue(params.quoteAmt, msg.value);
        }
        if (params.quoteAmt != 0 && minDeveloperBuyOut == 0) revert InvalidDeveloperBuy();
        _validateLaunchParams(params);

        bytes32 actualPortalConfigHash = portalConfigHash();
        if (
            expectedPortalConfigHash == bytes32(0)
                || actualPortalConfigHash != expectedPortalConfigHash
        ) {
            revert PortalConfigurationMismatch(expectedPortalConfigHash, actualPortalConfigHash);
        }

        address router_ = router;
        if (router_ == address(0)) revert InvalidAddress();
        ISinjohFlapRouter routerContract = ISinjohFlapRouter(router_);
        _assertRouterBeforeLaunch(routerContract);

        address predicted = predictSubject(params.salt);
        if (predicted.code.length != 0) revert PredictedTokenAlreadyExists(predicted);

        launched = true;
        uint256 nativeBefore = address(this).balance - msg.value;
        token = IFlapPortal(portal).newTokenV6{ value: msg.value }(params);
        if (token == address(0)) revert LaunchReturnedNoToken();
        if (token != predicted) revert PredictedTokenMismatch(predicted, token);
        if (token.code.length == 0) revert LaunchReturnedNoToken();

        address processor = IFlapTaxTokenV3(token).taxProcessor();
        (uint16 commissionBps_, uint16 feeRate_) =
            _validateCreatedContracts(token, processor, params, expectedFlapFeeRate);
        subject = token;
        taxProcessor = processor;
        flapCommissionBps = commissionBps_;
        flapFeeRate = feeRate_;

        routerContract.bind(token);
        address boundSubject = routerContract.subject();
        if (boundSubject != token) revert RouterDidNotBindSubject(token, boundSubject);
        if (!routerContract.isIntakeAsset(weth)) revert RouterUnsupportedIntake(weth);

        uint256 developerBuy = token.safeBalanceOf(address(this));
        if (developerBuy < minDeveloperBuyOut) {
            revert DeveloperBuyBelowMinimum(minDeveloperBuyOut, developerBuy);
        }
        if (developerBuy != 0) {
            uint256 creatorBefore = token.safeBalanceOf(creator);
            token.safeTransfer(creator, developerBuy);
            uint256 remaining = token.safeBalanceOf(address(this));
            uint256 received = token.safeBalanceOf(creator) - creatorBefore;
            if (remaining != 0 || received != developerBuy) {
                revert UnexpectedBalanceDelta(token, developerBuy, received);
            }
            emit DeveloperBuyDelivered(token, creator, developerBuy);
        }

        uint256 currentBalance = address(this).balance;
        uint256 refund = currentBalance > nativeBefore ? currentBalance - nativeBefore : 0;
        if (refund != 0) {
            (bool sent,) = payable(creator).call{ value: refund }("");
            if (!sent) revert UnexpectedBalanceDelta(address(0), refund, 0);
            emit LaunchValueRefunded(creator, refund);
        }

        emit Launched(token, processor, msg.value, developerBuy);
    }

    /// @notice Permissionlessly asks Flap's TaxProcessor to dispatch accrued
    /// marketing and commission balances, then wraps the native proceeds.
    function collect() external nonReentrant returns (uint256[] memory amounts) {
        _assertChain();
        if (!launched) revert NotLaunched();

        IFlapTaxProcessor(taxProcessor).dispatch();
        // Dispatch is permissionless. Value may already have been pushed here
        // before this call, so wrapping only this call's delta would strand it.
        uint256 nativeAmount = address(this).balance;

        amounts = new uint256[](1);
        if (nativeAmount != 0) {
            uint256 wethBefore = weth.safeBalanceOf(address(this));
            IFlapWeth(weth).deposit{ value: nativeAmount }();
            uint256 wrapped = weth.safeBalanceOf(address(this)) - wethBefore;
            if (wrapped != nativeAmount) {
                revert UnexpectedBalanceDelta(weth, nativeAmount, wrapped);
            }
            amounts[0] = wrapped;
        }

        emit Collected(subject, taxProcessor, amounts[0], msg.sender);
    }

    function forward(address asset) external nonReentrant returns (uint256 amount) {
        _assertChain();
        if (!launched || asset != weth) revert UnsupportedAsset(asset);

        address router_ = router;
        amount = asset.safeBalanceOf(address(this));
        if (amount == 0) return 0;

        uint256 routerBefore = asset.safeBalanceOf(router_);
        asset.safeTransfer(router_, amount);
        uint256 remaining = asset.safeBalanceOf(address(this));
        uint256 received = asset.safeBalanceOf(router_) - routerBefore;
        if (remaining != 0 || received != amount) {
            revert UnexpectedBalanceDelta(asset, amount, received);
        }
        emit Forwarded(asset, router_, amount, msg.sender);
    }

    function intakeAssets() external view returns (address[] memory assets) {
        if (!launched) revert NotLaunched();
        assets = new address[](1);
        assets[0] = weth;
    }

    /// @notice Predicts Flap's EIP-1167 token clone from the pinned V3
    /// implementation, Portal deployer, and caller-selected vanity salt.
    function predictSubject(bytes32 salt) public view returns (address) {
        return Clones.predictDeterministicAddress(taxTokenImplementation, salt, portal);
    }

    /// @notice Commits to the live proxy bytecode, reported Portal version, and
    /// native-quote configuration. Callers pass this value back into launch so
    /// mutable upstream terms cannot move between quote and execution.
    function portalConfigHash() public view returns (bytes32) {
        (bool versionSuccess, bytes memory versionData) =
            portal.staticcall(abi.encodeWithSelector(VERSION_SELECTOR));
        if (!versionSuccess || versionData.length == 0) revert PortalQueryFailed(VERSION_SELECTOR);
        (bool configSuccess, bytes memory configData) =
            portal.staticcall(abi.encodeWithSelector(QUOTE_CONFIG_SELECTOR, address(0)));
        if (!configSuccess || configData.length == 0) {
            revert PortalQueryFailed(QUOTE_CONFIG_SELECTOR);
        }
        return keccak256(abi.encode(portal.codehash, keccak256(versionData), keccak256(configData)));
    }

    /// @notice Whether Flap still routes the full configured creator allocation
    /// and permanent integrator commission to this adapter.
    function feeRoutingIntact() external view returns (bool) {
        if (!launched || taxProcessor.code.length == 0) return false;
        IFlapTaxProcessor processor = IFlapTaxProcessor(taxProcessor);

        try processor.taxToken() returns (address value) {
            if (value != subject) return false;
        } catch {
            return false;
        }
        try processor.portal() returns (address value) {
            if (value != portal) return false;
        } catch {
            return false;
        }
        try processor.owner() returns (address value) {
            if (value != portal) return false;
        } catch {
            return false;
        }
        try processor.getQuoteToken() returns (address value) {
            if (value != flapWrappedNative) return false;
        } catch {
            return false;
        }
        try processor.weth() returns (address value) {
            if (value != flapWrappedNative) return false;
        } catch {
            return false;
        }
        try processor.marketAddress() returns (address value) {
            if (value != address(this)) return false;
        } catch {
            return false;
        }
        try processor.commissionReceiver() returns (address value) {
            if (value != address(this)) return false;
        } catch {
            return false;
        }
        try processor.commissionBps() returns (uint16 value) {
            if (value != flapCommissionBps) return false;
        } catch {
            return false;
        }
        try processor.feeConfig() returns (IFlapTaxProcessor.FeeConfig memory config) {
            return config.marketBps == BPS && config.deflationBps == 0 && config.lpBps == 0
                && config.dividendBps == 0 && config.feeRate == flapFeeRate && config.isWeth;
        } catch {
            return false;
        }
    }

    function _validateLaunchParams(IFlapPortalTypes.NewTokenV6Params calldata params) private view {
        if (
            params.tokenVersion != IFlapPortalTypes.TokenVersion.TOKEN_TAXED_V3
                || params.migratorType != IFlapPortalTypes.MigratorType.V2_MIGRATOR
                || params.quoteToken != address(0) || params.beneficiary != address(this)
                || params.commissionReceiver != address(this)
                || params.dexId != IFlapPortalTypes.DEXId.DEX0
                || params.lpFeeProfile != IFlapPortalTypes.V3LPFeeProfile.LP_FEE_PROFILE_STANDARD
                || params.buyTaxRate == 0 && params.sellTaxRate == 0 || params.mktBps != BPS
                || params.deflationBps != 0 || params.dividendBps != 0 || params.lpBps != 0
                || params.minimumShareBalance != 0 || params.dividendToken != address(0)
                || params.permitData.length != 0 || params.extensionID != bytes32(0)
                || params.extensionData.length != 0
        ) revert InvalidLaunchConfiguration();
    }

    function _assertRouterBeforeLaunch(ISinjohFlapRouter routerContract) private view {
        address named = routerContract.launchpadAdapter();
        if (named != address(this)) revert RouterDidNotNameAdapter(named);
        address routerCreator = routerContract.creator();
        if (routerCreator != creator) revert RouterCreatorMismatch(creator, routerCreator);
        address routerWeth = routerContract.weth();
        if (routerWeth != weth) revert RouterWethMismatch(weth, routerWeth);
        bytes32 actualRouterConfigHash = routerContract.configHash();
        if (actualRouterConfigHash != routerConfigHash) {
            revert RouterConfigMismatch(routerConfigHash, actualRouterConfigHash);
        }
        if (routerContract.bound()) revert RouterAlreadyBound();
    }

    function _validateCreatedContracts(
        address token,
        address processorAddress,
        IFlapPortalTypes.NewTokenV6Params calldata params,
        uint16 expectedFlapFeeRate
    ) private view returns (uint16 commissionBps_, uint16 feeRate_) {
        if (processorAddress.code.length == 0) {
            revert InvalidTaxProcessor(processorAddress);
        }
        IFlapTaxTokenV3 tokenContract = IFlapTaxTokenV3(token);
        if (
            tokenContract.quoteToken() != flapWrappedNative
                || tokenContract.buyTaxRate() != params.buyTaxRate
                || tokenContract.sellTaxRate() != params.sellTaxRate
        ) revert TaxProcessorConfigurationMismatch();

        IFlapTaxProcessor processor = IFlapTaxProcessor(processorAddress);
        if (
            processor.taxToken() != token || processor.portal() != portal
                || processor.owner() != portal || processor.getQuoteToken() != flapWrappedNative
                || processor.weth() != flapWrappedNative
                || processor.marketAddress() != address(this)
                || processor.commissionReceiver() != address(this)
                || processor.commissionBps() != _expectedCommissionBps(params)
        ) revert TaxProcessorConfigurationMismatch();

        commissionBps_ = processor.commissionBps();

        IFlapTaxProcessor.FeeConfig memory config = processor.feeConfig();
        if (config.feeRate != expectedFlapFeeRate) {
            revert FlapFeeRateMismatch(expectedFlapFeeRate, config.feeRate);
        }
        if (
            config.marketBps != BPS || config.deflationBps != 0 || config.lpBps != 0
                || config.dividendBps != 0 || !config.isWeth
        ) revert TaxProcessorConfigurationMismatch();
        feeRate_ = config.feeRate;
    }

    function _expectedCommissionBps(IFlapPortalTypes.NewTokenV6Params calldata params)
        private
        pure
        returns (uint16)
    {
        uint16 effective =
            params.buyTaxRate > params.sellTaxRate ? params.buyTaxRate : params.sellTaxRate;
        return effective <= 100 ? 600 : uint16(uint256(BPS) * 6 / effective);
    }

    function _assertChain() private view {
        if (block.chainid != deploymentChainId) revert WrongChain(block.chainid);
    }
}
