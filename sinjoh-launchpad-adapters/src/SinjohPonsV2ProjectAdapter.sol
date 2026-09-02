// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { ISinjohLaunchpadAdapter } from "./interfaces/ISinjohLaunchpadAdapter.sol";
import {
    IPonsV2BondingCurve,
    IPonsV2FeeEscrow,
    IPonsV2LaunchFactory,
    IWETH
} from "./interfaces/IPonsV2.sol";
import { SafeTransferLib } from "./libraries/SafeTransferLib.sol";
import { ISinjohFundingBandsLaunchEscrow } from "./SinjohPonsV2Adapter.sol";
import {
    LaunchGovernanceMode,
    LaunchVoteSource,
    ProjectLaunchConfig,
    ProjectLaunchPreview
} from "@sinjoh-v2/core/ProjectLauncherTypes.sol";

interface IProjectLauncherV2AdapterTarget {
    function predictExistingTokenLaunch(ProjectLaunchConfig calldata config, address subject)
        external
        view
        returns (ProjectLaunchPreview memory);

    function launchExistingToken(
        ProjectLaunchConfig calldata config,
        address subject,
        bytes32[] calldata launchpadApprovalProof
    ) external returns (ProjectLaunchPreview memory);
}

interface IPonsV2ProjectAdapterFactoryView {
    function projectLauncher() external view returns (address);
    function projectRegistry() external view returns (address);
    function projectTokenFactory() external view returns (address);
    function fundingBandsEscrow() external view returns (address);
}

interface ISinjohProjectFeeRouter {
    function launchpadAdapter() external view returns (address);
    function bind(address subject) external;
}

/// @notice Atomic Pons v2 → Project V2 launch adapter.
/// @dev The one Pons token is registered as the Project subject before a developer buy executes.
contract SinjohPonsV2ProjectAdapter is ISinjohLaunchpadAdapter {
    using SafeTransferLib for address;

    struct FundingBandsPlan {
        address escrow;
        uint8 profileId;
        uint16 inventoryBps;
        ISinjohFundingBandsLaunchEscrow.BandConfig[] configs;
        uint16[] allocationBps;
    }

    struct LaunchRequest {
        IPonsV2LaunchFactory.TokenParams token;
        uint256 launchConfigId;
        address pairToken;
        uint256 developerBuy;
        uint256 minTokensOut;
        address[] snipeTaxExemptions;
        ProjectLaunchConfig project;
        bytes32[] launchpadApprovalProof;
        FundingBandsPlan fundingBands;
    }

    error AlreadyInitialized();
    error AlreadyLaunched();
    error NotLaunched();
    error Unauthorized();
    error WrongChain(uint256 actual);
    error InvalidAddress();
    error UnsupportedAsset(address asset);
    error Reentrancy();
    error PairTokenNotApproved(address pairToken);
    error PairTokenDecimalsChanged(address pairToken, uint8 expected, uint8 actual);
    error EconomicsMismatch(bytes32 expected, bytes32 actual);
    error FeeRecipientNotAdapter();
    error LaunchesDisabled();
    error InvalidDeveloperBuy();
    error NativeValueMismatch(uint256 expected, uint256 actual);
    error UnexpectedBalanceDelta(address asset, uint256 expected, uint256 actual);
    error LaunchReturnedNoToken();
    error BuybackMustBeDisabled();
    error InvalidProjectV2Configuration();
    error MissingProjectCustodyExclusion(address account);
    error RouterDidNotNameAdapter(address configured);
    error ProjectLaunchMismatch(address expected, address actual);
    error InvalidFundingBandsPlan();
    error FundingBandsEscrowMismatch(uint256 reported, uint256 spent);

    event Initialized(address indexed router, address indexed creator);
    event Launched(
        address indexed subject,
        address indexed curve,
        address indexed pairToken,
        uint256 launchConfigId,
        uint256 launchFee
    );
    event DeveloperBuyDelivered(
        address indexed subject, address indexed creator, uint256 quoteIn, uint256 tokensOut
    );
    event DeveloperBuyEscrowed(
        address indexed subject,
        address indexed escrow,
        uint256 developerBuyTokens,
        uint256 escrowedInventory
    );
    event DeveloperBuyRefunded(address indexed asset, address indexed creator, uint256 amount);
    event Collected(
        address indexed subject, address indexed asset, uint256 amount, address indexed caller
    );
    event Forwarded(
        address indexed asset, address indexed router, uint256 amount, address indexed caller
    );

    bytes4 private constant NO_BALANCE_SELECTOR = bytes4(keccak256("NoBalance()"));
    bytes4 private constant ALREADY_GRADUATED_SELECTOR = bytes4(keccak256("AlreadyGraduated()"));

    address public immutable launchFactory;
    address public immutable feeEscrow;
    address public immutable weth;
    uint256 public immutable deploymentChainId;
    address public immutable adapterFactory;

    address public router;
    address public creator;
    address public subject;
    address public curve;
    address public pairToken;
    bool public initialized;
    bool public launched;
    uint256 private _reentrancyState;

    constructor(
        address adapterFactory_,
        address launchFactory_,
        address feeEscrow_,
        address weth_,
        uint256 chainId_
    ) {
        if (
            adapterFactory_.code.length == 0 || launchFactory_.code.length == 0
                || feeEscrow_.code.length == 0 || weth_.code.length == 0
        ) revert InvalidAddress();
        if (chainId_ != block.chainid) revert WrongChain(block.chainid);
        if (IPonsV2LaunchFactory(launchFactory_).feeEscrow() != feeEscrow_) {
            revert InvalidAddress();
        }
        adapterFactory = adapterFactory_;
        launchFactory = launchFactory_;
        feeEscrow = feeEscrow_;
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

    receive() external payable { }

    function initialize(address router_, address creator_) external {
        if (initialized) revert AlreadyInitialized();
        if (msg.sender != adapterFactory) revert Unauthorized();
        initialized = true;
        if (
            router_ == address(0) || creator_ == address(0) || router_ == address(this)
                || creator_ == address(this) || router_ == creator_
        ) revert InvalidAddress();
        router = router_;
        creator = creator_;
        emit Initialized(router_, creator_);
    }

    function launch(LaunchRequest calldata request)
        external
        payable
        nonReentrant
        returns (address token, address curve_)
    {
        _assertChain();
        if (msg.sender != creator) revert Unauthorized();
        if (launched) revert AlreadyLaunched();
        launched = true;

        IPonsV2LaunchFactory factory = IPonsV2LaunchFactory(launchFactory);
        _validate(request, factory);
        uint256 launchFee = factory.launchFee();
        bool native = request.pairToken == address(0);
        uint256 requiredValue = native ? launchFee + request.developerBuy : launchFee;
        if (msg.value != requiredValue) revert NativeValueMismatch(requiredValue, msg.value);

        (token, curve_) = factory.launchToken{ value: launchFee }(
            request.token, request.launchConfigId, request.pairToken, request.snipeTaxExemptions
        );
        if (token == address(0) || curve_ == address(0)) revert LaunchReturnedNoToken();
        subject = token;
        curve = curve_;
        pairToken = request.pairToken;

        address configuredAdapter = ISinjohProjectFeeRouter(router).launchpadAdapter();
        if (configuredAdapter != address(this)) revert RouterDidNotNameAdapter(configuredAdapter);
        ISinjohProjectFeeRouter(router).bind(token);
        _registerProject(token, curve_, request.project, request.launchpadApprovalProof);
        emit Launched(token, curve_, request.pairToken, request.launchConfigId, launchFee);

        uint256 tokensOut;
        if (request.developerBuy != 0) {
            tokensOut = _developerBuy(
                token, curve_, request.pairToken, native, request.developerBuy, request.minTokensOut
            );
        }
        uint256 delivered = _deliverDeveloperBuy(token, tokensOut, request.fundingBands);
        emit DeveloperBuyDelivered(token, creator, request.developerBuy, delivered);
    }

    function _validate(LaunchRequest calldata request, IPonsV2LaunchFactory factory) private view {
        if (!factory.launchEnabled()) revert LaunchesDisabled();
        if (request.token.creatorFeeRecipient != address(this)) {
            revert FeeRecipientNotAdapter();
        }
        if (request.token.buybackEnabled) revert BuybackMustBeDisabled();
        if (request.developerBuy != 0 && request.minTokensOut == 0) {
            revert InvalidDeveloperBuy();
        }
        if (request.pairToken != address(0)) {
            if (!factory.approvedPairTokens(request.pairToken)) {
                revert PairTokenNotApproved(request.pairToken);
            }
            (,, uint8 recorded) = factory.pairTokenEconomics(request.pairToken);
            uint8 actual = request.pairToken.safeDecimals();
            if (actual != recorded) {
                revert PairTokenDecimalsChanged(request.pairToken, recorded, actual);
            }
        }
        bytes32 economics =
            factory.previewLaunchEconomics(request.launchConfigId, request.pairToken);
        if (request.token.expectedEconomics != economics) {
            revert EconomicsMismatch(request.token.expectedEconomics, economics);
        }
        ProjectLaunchConfig calldata config = request.project;
        if (
            config.creator != creator
                || keccak256(bytes(config.name)) != keccak256(bytes(request.token.name))
                || keccak256(bytes(config.symbol)) != keccak256(bytes(request.token.symbol))
                || config.totalSupply != factory.getLaunchConfig(request.launchConfigId).supply
                || config.modules.router || config.routerRoutes.length != 0
                || (config.governanceMode == LaunchGovernanceMode.TOKEN_HOLDER
                    && config.voteSource == LaunchVoteSource.STAKED
                    && !config.modules.staking)
        ) revert InvalidProjectV2Configuration();
        FundingBandsPlan calldata bands = request.fundingBands;
        if (bands.escrow != address(0)) {
            if (
                request.pairToken != address(0) || bands.profileId != 0
                    || bands.inventoryBps > 10_000 || bands.configs.length > 10
                    || bands.escrow.code.length == 0
                    || bands.escrow
                        != IPonsV2ProjectAdapterFactoryView(adapterFactory).fundingBandsEscrow()
                    || bands.inventoryBps == 0 || request.developerBuy == 0
                    || bands.configs.length == 0
                    || bands.configs.length != bands.allocationBps.length
            ) revert InvalidFundingBandsPlan();
        } else if (
            bands.inventoryBps != 0 || bands.configs.length != 0 || bands.allocationBps.length != 0
        ) {
            revert InvalidFundingBandsPlan();
        }
        IPonsV2ProjectAdapterFactoryView projectFactory =
            IPonsV2ProjectAdapterFactoryView(adapterFactory);
        if (
            projectFactory.projectLauncher().code.length == 0
                || projectFactory.projectRegistry().code.length == 0
                || projectFactory.projectTokenFactory().code.length == 0
        ) revert InvalidProjectV2Configuration();
    }

    function _registerProject(
        address token,
        address curve_,
        ProjectLaunchConfig calldata config,
        bytes32[] calldata proof
    ) private {
        if (!_contains(config.launchProfile.additionalCustodyExclusions, address(this))) {
            revert MissingProjectCustodyExclusion(address(this));
        }
        if (!_contains(config.launchProfile.additionalCustodyExclusions, curve_)) {
            revert MissingProjectCustodyExclusion(curve_);
        }
        IPonsV2LaunchFactory factory = IPonsV2LaunchFactory(launchFactory);
        address graduationLocker = factory.locker();
        address poolManager = factory.poolManager();
        if (
            graduationLocker.code.length == 0 || poolManager.code.length == 0
                || graduationLocker == poolManager
        ) revert InvalidProjectV2Configuration();
        if (!_contains(config.launchProfile.additionalCustodyExclusions, graduationLocker)) {
            revert MissingProjectCustodyExclusion(graduationLocker);
        }
        if (!_contains(config.launchProfile.additionalCustodyExclusions, poolManager)) {
            revert MissingProjectCustodyExclusion(poolManager);
        }
        IProjectLauncherV2AdapterTarget launcher = IProjectLauncherV2AdapterTarget(
            IPonsV2ProjectAdapterFactoryView(adapterFactory).projectLauncher()
        );
        ProjectLaunchPreview memory predicted = launcher.predictExistingTokenLaunch(config, token);
        ProjectLaunchPreview memory result = launcher.launchExistingToken(config, token, proof);
        if (
            result.addresses.subject != token
                || keccak256(abi.encode(result)) != keccak256(abi.encode(predicted))
        ) revert ProjectLaunchMismatch(token, result.addresses.subject);
    }

    function _deliverDeveloperBuy(address token, uint256 tokensOut, FundingBandsPlan calldata plan)
        private
        returns (uint256 delivered)
    {
        if (tokensOut == 0) return 0;
        if (plan.escrow == address(0)) {
            token.safeTransfer(creator, tokensOut);
            return tokensOut;
        }

        uint256 beforeBalance = token.safeBalanceOf(address(this));
        token.safeApprove(plan.escrow, tokensOut);
        uint256 escrowed = ISinjohFundingBandsLaunchEscrow(plan.escrow)
            .prepareFromLaunch(
                token,
                plan.profileId,
                plan.inventoryBps,
                plan.configs,
                plan.allocationBps,
                tokensOut,
                ""
            );
        token.safeApprove(plan.escrow, 0);
        uint256 spent = beforeBalance - token.safeBalanceOf(address(this));
        if (escrowed == 0 || spent != escrowed || escrowed > tokensOut) {
            revert FundingBandsEscrowMismatch(escrowed, spent);
        }
        delivered = tokensOut - escrowed;
        if (delivered != 0) token.safeTransfer(creator, delivered);
        emit DeveloperBuyEscrowed(token, plan.escrow, tokensOut, escrowed);
    }

    function _developerBuy(
        address token,
        address curve_,
        address pairToken_,
        bool native,
        uint256 developerBuy,
        uint256 minTokensOut
    ) private returns (uint256 tokensOut) {
        uint256 tokensBefore = token.safeBalanceOf(address(this));
        if (native) {
            IPonsV2BondingCurve(curve_).buy{ value: developerBuy }(
                developerBuy, minTokensOut, address(this)
            );
        } else {
            uint256 pairBefore = pairToken_.safeBalanceOf(address(this));
            pairToken_.safeTransferFrom(creator, address(this), developerBuy);
            uint256 pulled = pairToken_.safeBalanceOf(address(this)) - pairBefore;
            if (pulled != developerBuy) {
                revert UnexpectedBalanceDelta(pairToken_, developerBuy, pulled);
            }
            pairToken_.safeApprove(curve_, developerBuy);
            IPonsV2BondingCurve(curve_).buy(developerBuy, minTokensOut, address(this));
            pairToken_.safeApprove(curve_, 0);
        }
        tokensOut = token.safeBalanceOf(address(this)) - tokensBefore;
        _refundClamp(pairToken_, native);
    }

    function _refundClamp(address pairToken_, bool native) private {
        uint256 refund = native ? address(this).balance : pairToken_.safeBalanceOf(address(this));
        if (refund == 0) return;
        if (native) {
            (bool sent,) = payable(creator).call{ value: refund }("");
            if (!sent) revert UnexpectedBalanceDelta(address(0), refund, 0);
            emit DeveloperBuyRefunded(address(0), creator, refund);
        } else {
            pairToken_.safeTransfer(creator, refund);
            emit DeveloperBuyRefunded(pairToken_, creator, refund);
        }
    }

    function collect() external nonReentrant returns (uint256[] memory amounts) {
        _assertChain();
        if (!launched) revert NotLaunched();
        _trySweepCurve();
        amounts = new uint256[](1);
        address pairToken_ = pairToken;
        if (pairToken_ == address(0)) {
            uint256 beforeBalance = address(this).balance;
            if (_tryClaimNative()) {
                uint256 amount = address(this).balance - beforeBalance;
                if (amount != 0) IWETH(weth).deposit{ value: amount }();
                amounts[0] = amount;
            }
        } else {
            uint256 beforeBalance = pairToken_.safeBalanceOf(address(this));
            if (_tryClaimToken(pairToken_)) {
                amounts[0] = pairToken_.safeBalanceOf(address(this)) - beforeBalance;
            }
        }
        emit Collected(subject, _intakeAsset(), amounts[0], msg.sender);
    }

    function forward(address asset) external nonReentrant returns (uint256 amount) {
        _assertChain();
        if (!_isIntakeAsset(asset)) revert UnsupportedAsset(asset);
        amount = asset.safeBalanceOf(address(this));
        if (amount == 0) return 0;
        uint256 beforeBalance = asset.safeBalanceOf(router);
        asset.safeTransfer(router, amount);
        uint256 received = asset.safeBalanceOf(router) - beforeBalance;
        if (asset.safeBalanceOf(address(this)) != 0 || received != amount) {
            revert UnexpectedBalanceDelta(asset, amount, received);
        }
        emit Forwarded(asset, router, amount, msg.sender);
    }

    function intakeAssets() external view returns (address[] memory assets) {
        assets = new address[](1);
        assets[0] = pairToken == address(0) ? weth : pairToken;
    }

    function _trySweepCurve() private {
        try IPonsV2BondingCurve(curve).sweepFees(0) { }
        catch (bytes memory reason) {
            if (_hasSelector(reason, ALREADY_GRADUATED_SELECTOR)) return;
            _bubble(reason);
        }
    }

    function _tryClaimNative() private returns (bool) {
        try IPonsV2FeeEscrow(feeEscrow).claim() returns (uint256) {
            return true;
        } catch (bytes memory reason) {
            if (_hasSelector(reason, NO_BALANCE_SELECTOR)) return false;
            _bubble(reason);
        }
    }

    function _tryClaimToken(address token) private returns (bool) {
        try IPonsV2FeeEscrow(feeEscrow).claimToken(token) returns (uint256) {
            return true;
        } catch (bytes memory reason) {
            if (_hasSelector(reason, NO_BALANCE_SELECTOR)) return false;
            _bubble(reason);
        }
    }

    function _intakeAsset() private view returns (address) {
        return pairToken == address(0) ? weth : pairToken;
    }

    function _isIntakeAsset(address asset) private view returns (bool) {
        return launched && asset == _intakeAsset();
    }

    function _contains(address[] calldata values, address expected) private pure returns (bool) {
        for (uint256 i; i < values.length; ++i) {
            if (values[i] == expected) return true;
        }
        return false;
    }

    function _hasSelector(bytes memory reason, bytes4 selector) private pure returns (bool) {
        return reason.length >= 4 && bytes4(reason) == selector;
    }

    function _bubble(bytes memory reason) private pure {
        if (reason.length == 0) revert();
        assembly {
            revert(add(reason, 0x20), mload(reason))
        }
    }

    function _assertChain() private view {
        if (block.chainid != deploymentChainId) revert WrongChain(block.chainid);
    }
}
