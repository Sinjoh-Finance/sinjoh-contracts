// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ISinjohSink } from "sinjoh-fee-router/src/interfaces/ISinjohSink.sol";
import { SafeTransferLib } from "sinjoh-fee-router/src/libraries/SafeTransferLib.sol";
import { IFlapTradePortal } from "./SinjohFlapBuybackAdapter.sol";
import { SinjohSignedFloor } from "./libraries/SinjohSignedFloor.sol";

interface IFlapLiquidityWeth {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

interface IFlapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IFlapV2Pair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves()
        external
        view
        returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function balanceOf(address account) external view returns (uint256);
}

interface IFlapV2Router {
    function factory() external view returns (address);
    function WETH() external view returns (address);
    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountToken, uint256 amountETH, uint256 liquidity);
}

interface IFlapPortalState {
    struct TokenStateV5 {
        uint8 status;
        uint256 reserve;
        uint256 circulatingSupply;
        uint256 price;
        uint8 tokenVersion;
        uint256 r;
        uint256 h;
        uint256 k;
        uint256 dexSupplyThresh;
        address quoteTokenAddress;
        bool nativeToQuoteSwapEnabled;
        bytes32 extensionID;
    }

    function getTokenV5(address token) external view returns (TokenStateV5 memory state);
}

/// @notice Accumulates a launch's WETH allocation and, after Flap graduates
/// the subject, converts it into permanently burned V2 liquidity.
contract SinjohFlapV2LiquidityManager is ISinjohSink {
    using SafeTransferLib for address;

    uint16 public constant BPS = 10_000;
    uint8 public constant DEX_STATUS = 4;
    uint48 public constant MAXIMUM_VALIDITY = 5 minutes;
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    bytes32 public constant FLOOR_TYPEHASH = keccak256(
        "SinjohFlapLiquidityFloor(uint256 chainId,address manager,address funder,address subject,uint256 notional,uint256 minimumSwapOutput,uint48 validAfter,uint48 validUntil)"
    );

    error InvalidAddress();
    error InvalidAmount();
    error InvalidConfiguration();
    error DependencyChanged();
    error NotGraduated();
    error PoolUnavailable();
    error QuoteFailed();
    error InsufficientOutput(uint256 minimum, uint256 actual);
    error UnexpectedBalance();
    error Insolvent(address asset);
    error Reentrancy();

    struct Account {
        uint256 pendingWeth;
        uint256 pendingSubject;
        uint256 burnedLiquidity;
    }

    event Funded(
        bytes32 indexed accountId, address indexed funder, address indexed subject, uint256 amount
    );
    event LiquidityBurned(
        bytes32 indexed accountId,
        address indexed subject,
        address indexed pair,
        uint256 wethFunded,
        uint256 subjectSwapped,
        uint256 tokenUsed,
        uint256 nativeUsed,
        uint256 liquidity
    );

    address public immutable portal;
    address public immutable weth;
    address public immutable v2Factory;
    address public immutable v2Router;
    bytes32 public immutable portalCodehash;
    bytes32 public immutable wethCodehash;
    bytes32 public immutable portalConfigHash;
    bytes32 public immutable factoryCodehash;
    bytes32 public immutable routerCodehash;
    address public immutable quoteSigner;
    uint16 public immutable quoteSwapBps;
    uint16 public immutable maxSlippageBps;
    uint128 public immutable minNotional;
    uint128 public immutable maxNotional;

    mapping(bytes32 accountId => Account account) private _accounts;
    uint256 public totalWethLiability;
    mapping(address subject => uint256 amount) public totalSubjectLiability;
    uint256 private _reentrancyState = 1;

    constructor(
        address portal_,
        address weth_,
        address v2Factory_,
        address v2Router_,
        bytes32 portalCodehash_,
        bytes32 wethCodehash_,
        bytes32 portalConfigHash_,
        bytes32 factoryCodehash_,
        bytes32 routerCodehash_,
        address quoteSigner_,
        uint16 quoteSwapBps_,
        uint16 maxSlippageBps_,
        uint128 minNotional_,
        uint128 maxNotional_
    ) {
        if (
            portal_.code.length == 0 || weth_.code.length == 0 || v2Factory_.code.length == 0
                || v2Router_.code.length == 0 || portal_.codehash != portalCodehash_
                || weth_.codehash != wethCodehash_ || v2Factory_.codehash != factoryCodehash_
                || v2Router_.codehash != routerCodehash_ || quoteSigner_ == address(0)
                || portal_ == weth_ || portal_ == v2Factory_ || portal_ == v2Router_
                || IFlapV2Router(v2Router_).factory() != v2Factory_
                || IFlapV2Router(v2Router_).WETH() != weth_
        ) revert InvalidAddress();
        if (
            portalConfigHash_ == bytes32(0) || quoteSwapBps_ < 4_000 || quoteSwapBps_ > 6_000
                || maxSlippageBps_ == 0 || maxSlippageBps_ > 1_000 || minNotional_ == 0
                || maxNotional_ < minNotional_
        ) revert InvalidConfiguration();
        portal = portal_;
        weth = weth_;
        v2Factory = v2Factory_;
        v2Router = v2Router_;
        portalCodehash = portalCodehash_;
        wethCodehash = wethCodehash_;
        portalConfigHash = portalConfigHash_;
        factoryCodehash = factoryCodehash_;
        routerCodehash = routerCodehash_;
        quoteSigner = quoteSigner_;
        quoteSwapBps = quoteSwapBps_;
        maxSlippageBps = maxSlippageBps_;
        minNotional = minNotional_;
        maxNotional = maxNotional_;
    }

    receive() external payable { }

    modifier nonReentrant() {
        if (_reentrancyState != 1) revert Reentrancy();
        _reentrancyState = 2;
        _;
        _reentrancyState = 1;
    }

    function accountId(address funder, address subject) public pure returns (bytes32) {
        return keccak256(abi.encode(funder, subject));
    }

    function account(address funder, address subject) external view returns (Account memory) {
        return _accounts[accountId(funder, subject)];
    }

    function floorDigest(
        address funder,
        address subject,
        uint256 notional,
        uint256 minimumSwapOutput,
        uint48 validAfter,
        uint48 validUntil
    ) public view returns (bytes32) {
        return keccak256(
            abi.encode(
                FLOOR_TYPEHASH,
                block.chainid,
                address(this),
                funder,
                subject,
                notional,
                minimumSwapOutput,
                validAfter,
                validUntil
            )
        );
    }

    function fund(address subject, address asset, uint256 amount, bytes calldata config)
        external
        payable
        nonReentrant
        returns (uint256 received)
    {
        if (
            msg.value != 0 || subject.code.length == 0 || asset != weth || amount == 0
                || config.length != 0
        ) revert InvalidAmount();
        _assertDependencies();
        uint256 beforeBalance = weth.safeBalanceOf(address(this));
        weth.safeTransferFrom(msg.sender, address(this), amount);
        received = weth.safeBalanceOf(address(this)) - beforeBalance;
        if (received != amount) revert UnexpectedBalance();
        bytes32 id = accountId(msg.sender, subject);
        _accounts[id].pendingWeth += received;
        totalWethLiability += received;
        _assertSolvent(subject);
        emit Funded(id, msg.sender, subject, received);
    }

    function mint(address funder, address subject, uint256 notional, bytes calldata guardData)
        external
        nonReentrant
        returns (uint256 liquidity)
    {
        _assertDependencies();
        if (notional < minNotional || notional > maxNotional) revert InvalidAmount();
        bytes32 id = accountId(funder, subject);
        Account storage entry = _accounts[id];
        if (notional > entry.pendingWeth) revert InvalidAmount();
        IFlapPortalState.TokenStateV5 memory state = IFlapPortalState(portal).getTokenV5(subject);
        if (state.status != DEX_STATUS || state.quoteTokenAddress != address(0)) {
            revert NotGraduated();
        }
        address pair = IFlapV2Factory(v2Factory).getPair(subject, weth);
        if (pair.code.length == 0) revert PoolUnavailable();
        (uint256 reserveSubject, uint256 reserveWeth) = _reserves(pair, subject);
        if (reserveSubject == 0 || reserveWeth == 0) revert PoolUnavailable();

        uint256 oldSubject = entry.pendingSubject;
        entry.pendingWeth -= notional;
        totalWethLiability -= notional;
        entry.pendingSubject = 0;
        totalSubjectLiability[subject] -= oldSubject;

        uint256 nativeBefore = address(this).balance;
        uint256 subjectBefore = subject.safeBalanceOf(address(this));
        uint256 swapAmount = notional * quoteSwapBps / BPS;
        uint256 nativeForLiquidity = notional - swapAmount;
        (uint256 signedMinimum, uint48 validAfter, uint48 validUntil, bytes memory signature) =
            abi.decode(guardData, (uint256, uint48, uint48, bytes));
        if (signedMinimum == 0) revert InvalidAmount();
        SinjohSignedFloor.validate(
            floorDigest(funder, subject, notional, signedMinimum, validAfter, validUntil),
            quoteSigner,
            validAfter,
            validUntil,
            MAXIMUM_VALIDITY,
            signature
        );
        uint256 quoted = _quote(subject, swapAmount);
        uint256 enforcedMinimum = quoted * (BPS - maxSlippageBps) / BPS;
        if (signedMinimum > enforcedMinimum) enforcedMinimum = signedMinimum;
        if (enforcedMinimum == 0) revert QuoteFailed();

        IFlapLiquidityWeth(weth).withdraw(swapAmount);
        uint256 reported = IFlapTradePortal(portal).swapExactInput{ value: swapAmount }(
            IFlapTradePortal.ExactInputParams({
                inputToken: address(0),
                outputToken: subject,
                inputAmount: swapAmount,
                minOutputAmount: enforcedMinimum,
                permitData: ""
            })
        );
        uint256 swapped = subject.safeBalanceOf(address(this)) - subjectBefore;
        if (swapped < enforcedMinimum || reported != swapped) {
            revert InsufficientOutput(enforcedMinimum, swapped);
        }

        IFlapLiquidityWeth(weth).withdraw(nativeForLiquidity);
        uint256 tokenDesired = oldSubject + swapped;
        uint256 subjectAfterSwap = subject.safeBalanceOf(address(this));
        (reserveSubject, reserveWeth) = _reserves(pair, subject);
        (uint256 expectedToken, uint256 expectedNative) =
            _optimal(tokenDesired, nativeForLiquidity, reserveSubject, reserveWeth);
        uint256 tokenMinimum = expectedToken * (BPS - maxSlippageBps) / BPS;
        uint256 nativeMinimum = expectedNative * (BPS - maxSlippageBps) / BPS;
        uint256 burnedBefore = IFlapV2Pair(pair).balanceOf(BURN_ADDRESS);
        subject.safeApprove(v2Router, tokenDesired);
        (uint256 tokenUsed, uint256 nativeUsed, uint256 reportedLiquidity) = IFlapV2Router(v2Router)
        .addLiquidityETH{ value: nativeForLiquidity }(
            subject, tokenDesired, tokenMinimum, nativeMinimum, BURN_ADDRESS, block.timestamp
        );
        subject.safeApprove(v2Router, 0);
        liquidity = IFlapV2Pair(pair).balanceOf(BURN_ADDRESS) - burnedBefore;
        if (liquidity == 0 || liquidity != reportedLiquidity) revert UnexpectedBalance();

        uint256 nativeRefund = address(this).balance - nativeBefore;
        if (nativeRefund > 0) IFlapLiquidityWeth(weth).deposit{ value: nativeRefund }();
        uint256 subjectAfter = subject.safeBalanceOf(address(this));
        uint256 subjectSpent = subjectAfterSwap - subjectAfter;
        if (subjectSpent != tokenUsed) revert UnexpectedBalance();
        uint256 subjectRemainder = oldSubject + swapped - subjectSpent;
        entry.pendingWeth += nativeRefund;
        totalWethLiability += nativeRefund;
        entry.pendingSubject = subjectRemainder;
        totalSubjectLiability[subject] += subjectRemainder;
        entry.burnedLiquidity += liquidity;
        _assertSolvent(subject);
        emit LiquidityBurned(id, subject, pair, notional, swapped, tokenUsed, nativeUsed, liquidity);
    }

    function _quote(address subject, uint256 amountIn) private view returns (uint256 quoted) {
        (bool ok, bytes memory result) = portal.staticcall(
            abi.encodeCall(
                IFlapTradePortal.quoteExactInput,
                (IFlapTradePortal.QuoteExactInputParams({
                        inputToken: address(0), outputToken: subject, inputAmount: amountIn
                    }))
            )
        );
        if (!ok || result.length != 32) revert QuoteFailed();
        quoted = abi.decode(result, (uint256));
    }

    function _reserves(address pair, address subject)
        private
        view
        returns (uint256 reserveSubject, uint256 reserveWeth)
    {
        address token0 = IFlapV2Pair(pair).token0();
        address token1 = IFlapV2Pair(pair).token1();
        if (!((token0 == subject && token1 == weth) || (token0 == weth && token1 == subject))) {
            revert PoolUnavailable();
        }
        (uint112 reserve0, uint112 reserve1,) = IFlapV2Pair(pair).getReserves();
        (reserveSubject, reserveWeth) = token0 == subject
            ? (uint256(reserve0), uint256(reserve1))
            : (uint256(reserve1), uint256(reserve0));
    }

    function _optimal(
        uint256 tokenDesired,
        uint256 nativeDesired,
        uint256 reserveToken,
        uint256 reserveNative
    ) private pure returns (uint256 tokenAmount, uint256 nativeAmount) {
        uint256 tokenOptimal = nativeDesired * reserveToken / reserveNative;
        if (tokenOptimal <= tokenDesired) return (tokenOptimal, nativeDesired);
        return (tokenDesired, tokenDesired * reserveNative / reserveToken);
    }

    function _assertDependencies() private view {
        if (
            portal.codehash != portalCodehash || v2Factory.codehash != factoryCodehash
                || weth.codehash != wethCodehash || v2Router.codehash != routerCodehash
                || _currentPortalConfigHash() != portalConfigHash
                || IFlapV2Router(v2Router).factory() != v2Factory
                || IFlapV2Router(v2Router).WETH() != weth
        ) revert DependencyChanged();
    }

    function _currentPortalConfigHash() private view returns (bytes32) {
        (bool versionSuccess, bytes memory versionData) =
            portal.staticcall(abi.encodeWithSignature("version()"));
        (bool configSuccess, bytes memory configData) = portal.staticcall(
            abi.encodeWithSignature("getQuoteTokenConfiguration(address)", address(0))
        );
        if (!versionSuccess || !configSuccess || versionData.length == 0 || configData.length == 0)
        {
            revert DependencyChanged();
        }
        return keccak256(abi.encode(portal.codehash, keccak256(versionData), keccak256(configData)));
    }

    function _assertSolvent(address subject) private view {
        if (weth.safeBalanceOf(address(this)) < totalWethLiability) revert Insolvent(weth);
        if (subject.safeBalanceOf(address(this)) < totalSubjectLiability[subject]) {
            revert Insolvent(subject);
        }
    }
}
