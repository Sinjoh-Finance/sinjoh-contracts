// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Governed } from "./governance/Governed.sol";
import { IGovernanceController } from "./interfaces/IGovernanceController.sol";
import { ISinjohFundable } from "./interfaces/ISinjohFundable.sol";

/// @notice Governed, versioned fee router. Sinjoh's protocol fee is immutable and removed before
/// project-governed routes are evaluated.
contract FeeRouterV2 is Governed, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint16 public constant BPS = 10_000;
    uint16 public constant PROTOCOL_FEE_BPS = 100;
    uint8 public constant MAX_ROUTES = 32;
    uint8 public constant MAX_INPUT_ASSETS = 16;
    uint16 public constant MAX_CONFIG_BYTES = 2_048;
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    enum Action {
        SEND,
        TREASURY,
        BURN,
        FUND_AIRDROP,
        FUND_BASKET,
        FUND_RAFFLE,
        FUND_BAND,
        SWAP_AND_SEND,
        ADD_LIQUIDITY
    }

    struct Route {
        address inputToken;
        address recipient;
        uint16 shareBps;
        Action action;
        bytes config;
    }

    struct Configuration {
        bytes32 hash;
        uint48 proposedAt;
        uint48 activatesAt;
        bool exists;
    }

    error InvalidAddress();
    error InvalidConfiguration();
    error ConfigurationNotReady(uint256 activatesAt);
    error InvalidConfigurationId();
    error ConfigurationAlreadyActive(uint256 configId);
    error RollbackUnavailable();
    error RoutePaused(uint256 routeIndex);
    error InvalidAmount();
    error InexactTransfer(address asset, uint256 expected, uint256 received);
    error SinkReceiptMismatch(uint256 expected, uint256 received);

    event ConfigurationProposed(
        uint256 indexed configId, bytes32 indexed configHash, uint48 activatesAt
    );
    event ConfigurationActivated(
        uint256 indexed configId, uint256 indexed previousConfigId, uint48 rollbackUntil
    );
    event ConfigurationRolledBack(uint256 indexed fromConfigId, uint256 indexed toConfigId);
    event RoutePauseChanged(uint256 indexed configId, uint256 indexed routeIndex, bool paused);
    event Synchronized(address indexed token, uint256 gross, uint256 protocolFee, uint256 net);
    event Routed(
        uint256 indexed configId,
        uint256 indexed routeIndex,
        address indexed token,
        address recipient,
        Action action,
        uint256 amount
    );

    address public immutable protocolFeeRecipient;
    uint48 public immutable configurationDelay;
    uint48 public immutable rollbackWindow;

    uint256 public configurationCount;
    uint256 public activeConfigurationId;
    uint256 public previousConfigurationId;
    uint48 public rollbackUntil;

    mapping(uint256 configId => Configuration) public configurations;
    mapping(uint256 configId => Route[]) private _routes;
    mapping(uint256 configId => mapping(uint256 routeIndex => bool)) public isRoutePaused;
    mapping(address token => uint16 remainder) public protocolFeeRemainder;
    mapping(address token => uint256 amount) public cumulativeGrossIntake;
    mapping(address token => uint256 amount) public cumulativeProtocolFee;

    constructor(
        IGovernanceController controller,
        address guardian,
        address protocolFeeRecipient_,
        uint48 configurationDelay_,
        uint48 rollbackWindow_
    ) Governed(controller, guardian) {
        if (
            protocolFeeRecipient_ == address(0) || protocolFeeRecipient_ == address(this)
                || configurationDelay_ == 0 || rollbackWindow_ == 0
        ) revert InvalidAddress();
        protocolFeeRecipient = protocolFeeRecipient_;
        configurationDelay = configurationDelay_;
        rollbackWindow = rollbackWindow_;
    }

    function proposeConfiguration(Route[] calldata routes)
        external
        onlyGovernance
        returns (uint256 configId)
    {
        _validate(routes);
        configId = ++configurationCount;
        bytes32 configHash = keccak256(abi.encode(routes));
        uint48 activatesAt = _timestamp48() + configurationDelay;
        configurations[configId] = Configuration({
            hash: configHash, proposedAt: _timestamp48(), activatesAt: activatesAt, exists: true
        });
        for (uint256 i; i < routes.length; ++i) {
            _routes[configId].push(routes[i]);
        }
        emit ConfigurationProposed(configId, configHash, activatesAt);
    }

    function activateConfiguration(uint256 configId) external onlyGovernance {
        Configuration storage configuration = configurations[configId];
        if (!configuration.exists) revert InvalidConfigurationId();
        if (configId == activeConfigurationId) revert ConfigurationAlreadyActive(configId);
        if (block.timestamp < configuration.activatesAt) {
            revert ConfigurationNotReady(configuration.activatesAt);
        }
        uint256 oldActive = activeConfigurationId;
        previousConfigurationId = oldActive;
        activeConfigurationId = configId;
        rollbackUntil = _timestamp48() + rollbackWindow;
        emit ConfigurationActivated(configId, oldActive, rollbackUntil);
    }

    function rollbackConfiguration() external onlyGovernance {
        uint256 oldActive = activeConfigurationId;
        uint256 previous = previousConfigurationId;
        if (previous == 0 || block.timestamp > rollbackUntil) revert RollbackUnavailable();
        activeConfigurationId = previous;
        previousConfigurationId = 0;
        rollbackUntil = 0;
        emit ConfigurationRolledBack(oldActive, previous);
    }

    function pauseRoute(uint256 routeIndex) external {
        if (
            msg.sender != emergencyGuardian
                && !governanceController.canCall(msg.sender, address(this), msg.sig)
        ) revert Unauthorized();
        uint256 configId = activeConfigurationId;
        if (routeIndex >= _routes[configId].length) revert InvalidConfiguration();
        isRoutePaused[configId][routeIndex] = true;
        emit RoutePauseChanged(configId, routeIndex, true);
    }

    function resumeRoute(uint256 routeIndex) external onlyGovernance {
        uint256 configId = activeConfigurationId;
        if (routeIndex >= _routes[configId].length) revert InvalidConfiguration();
        isRoutePaused[configId][routeIndex] = false;
        emit RoutePauseChanged(configId, routeIndex, false);
    }

    /// @notice Routes the entire unaccounted balance. The 1% fee is charged first and cannot be
    /// changed by project governance. A failing destination reverts the whole atomic distribution.
    function sync(address token) external nonReentrant whenNotPaused returns (uint256 gross) {
        uint256 configId = activeConfigurationId;
        if (configId == 0 || token.code.length == 0) revert InvalidConfiguration();
        gross = IERC20(token).balanceOf(address(this));
        if (gross == 0) revert InvalidAmount();

        (uint256 fee, uint16 nextRemainder) = _protocolFee(gross, protocolFeeRemainder[token]);
        protocolFeeRemainder[token] = nextRemainder;
        cumulativeGrossIntake[token] += gross;
        cumulativeProtocolFee[token] += fee;
        _sendExact(token, protocolFeeRecipient, fee);

        uint256 net = gross - fee;
        Route[] storage routes = _routes[configId];
        uint256 remaining = net;
        uint256 finalMatchingIndex = type(uint256).max;
        for (uint256 i; i < routes.length; ++i) {
            if (routes[i].inputToken == token) finalMatchingIndex = i;
        }
        if (finalMatchingIndex == type(uint256).max) revert InvalidConfiguration();

        for (uint256 i; i < routes.length; ++i) {
            Route storage route = routes[i];
            if (route.inputToken != token) continue;
            if (isRoutePaused[configId][i]) revert RoutePaused(i);
            uint256 amount = i == finalMatchingIndex ? remaining : net * route.shareBps / BPS;
            remaining -= amount;
            _execute(route, token, amount);
            emit Routed(configId, i, token, route.recipient, route.action, amount);
        }
        emit Synchronized(token, gross, fee, net);
    }

    function routeCount(uint256 configId) external view returns (uint256) {
        return _routes[configId].length;
    }

    function getRoute(uint256 configId, uint256 routeIndex) external view returns (Route memory) {
        return _routes[configId][routeIndex];
    }

    function _execute(Route storage route, address token, uint256 amount) private {
        if (amount == 0) return;
        if (route.action == Action.BURN) {
            _sendExact(token, BURN_ADDRESS, amount);
        } else if (route.action == Action.SEND || route.action == Action.TREASURY) {
            _sendExact(token, route.recipient, amount);
        } else {
            IERC20 asset = IERC20(token);
            uint256 beforeBalance = asset.balanceOf(address(this));
            asset.forceApprove(route.recipient, amount);
            uint256 received = ISinjohFundable(route.recipient).fund(token, amount, route.config);
            asset.forceApprove(route.recipient, 0);
            if (received != amount) revert SinkReceiptMismatch(amount, received);
            uint256 afterBalance = asset.balanceOf(address(this));
            uint256 spent = beforeBalance >= afterBalance ? beforeBalance - afterBalance : 0;
            if (spent != amount) revert InexactTransfer(token, amount, spent);
        }
    }

    function _validate(Route[] calldata routes) private view {
        if (routes.length == 0 || routes.length > MAX_ROUTES) revert InvalidConfiguration();
        address[] memory assets = new address[](MAX_INPUT_ASSETS);
        uint256[] memory shares = new uint256[](MAX_INPUT_ASSETS);
        uint256 assetCount;
        for (uint256 i; i < routes.length; ++i) {
            Route calldata route = routes[i];
            if (
                route.inputToken.code.length == 0 || route.recipient == address(0)
                    || route.recipient == address(this) || route.shareBps == 0
                    || route.config.length > MAX_CONFIG_BYTES
            ) revert InvalidConfiguration();
            bool direct = route.action == Action.SEND || route.action == Action.TREASURY
                || route.action == Action.BURN;
            if (direct && route.config.length != 0) revert InvalidConfiguration();
            if (route.action == Action.BURN && route.recipient != BURN_ADDRESS) {
                revert InvalidConfiguration();
            }
            if (!direct && route.recipient.code.length == 0) revert InvalidConfiguration();

            uint256 assetIndex = type(uint256).max;
            for (uint256 j; j < assetCount; ++j) {
                if (assets[j] == route.inputToken) assetIndex = j;
            }
            if (assetIndex == type(uint256).max) {
                if (assetCount == MAX_INPUT_ASSETS) revert InvalidConfiguration();
                assetIndex = assetCount++;
                assets[assetIndex] = route.inputToken;
            }
            shares[assetIndex] += route.shareBps;
        }
        for (uint256 i; i < assetCount; ++i) {
            if (shares[i] != BPS) revert InvalidConfiguration();
        }
    }

    function _protocolFee(uint256 amount, uint16 remainder)
        private
        pure
        returns (uint256 fee, uint16 nextRemainder)
    {
        uint256 scaledRemainder = (amount % BPS) * PROTOCOL_FEE_BPS + remainder;
        fee = (amount / BPS) * PROTOCOL_FEE_BPS + scaledRemainder / BPS;
        nextRemainder = uint16(scaledRemainder % BPS);
    }

    function _sendExact(address token, address recipient, uint256 amount) private {
        if (amount == 0) return;
        IERC20 asset = IERC20(token);
        uint256 beforeBalance = asset.balanceOf(recipient);
        asset.safeTransfer(recipient, amount);
        uint256 afterBalance = asset.balanceOf(recipient);
        uint256 received = afterBalance >= beforeBalance ? afterBalance - beforeBalance : 0;
        if (received != amount) revert InexactTransfer(token, amount, received);
    }

    function _timestamp48() private view returns (uint48) {
        return uint48(block.timestamp);
    }
}
