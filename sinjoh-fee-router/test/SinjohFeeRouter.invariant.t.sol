// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { InvariantTestBase } from "./TestBase.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";
import { MockPriceGuard } from "./mocks/MockPriceGuard.sol";
import { MockSink } from "./mocks/MockSink.sol";
import { MockSwapAdapter } from "./mocks/MockSwapAdapter.sol";
import { RouterTypes } from "../src/RouterTypes.sol";
import { SinjohFeeRouter } from "../src/SinjohFeeRouter.sol";
import { SinjohFeeRouterFactory } from "../src/SinjohFeeRouterFactory.sol";

contract FeeRouterHandler {
    SinjohFeeRouter public immutable router;
    MockERC20 public immutable subjectToken;
    MockERC20 public immutable quoteToken;
    MockSwapAdapter public immutable adapter;
    MockSink public immutable sink;
    address public immutable wallet;
    uint256 public totalSubjectGross;
    uint256 public totalQuoteGross;
    uint256 public subjectProtocolSent;
    uint256 public quoteProtocolSent;

    constructor(
        SinjohFeeRouter router_,
        MockERC20 subjectToken_,
        MockERC20 quoteToken_,
        MockSwapAdapter adapter_,
        MockSink sink_,
        address wallet_
    ) {
        router = router_;
        subjectToken = subjectToken_;
        quoteToken = quoteToken_;
        adapter = adapter_;
        sink = sink_;
        wallet = wallet_;
    }

    function donateAndSyncSubject(uint96 rawAmount) external {
        uint256 amount = uint256(rawAmount) % 1e24 + 1;
        subjectToken.mint(address(router), amount);
        router.sync(address(subjectToken));
        totalSubjectGross += amount;
    }

    function donateAndSyncQuote(uint96 rawAmount) external {
        uint256 amount = uint256(rawAmount) % 1e24 + 1;
        quoteToken.mint(address(router), amount);
        router.sync(address(quoteToken));
        totalQuoteGross += amount;
    }

    function processSubject(uint96 rawAmount) external {
        rawAmount;
        uint256 pending = router.bucketInputOwed(0, address(subjectToken));
        if (pending == 0) return;
        router.processBucket(0, address(subjectToken), pending, 0, "");
    }

    function processQuote(uint96 rawAmount) external {
        rawAmount;
        uint256 pending = router.bucketInputOwed(0, address(quoteToken));
        if (pending == 0) return;
        subjectToken.mint(address(adapter), pending);
        router.processBucket(0, address(quoteToken), pending, 0, "");
    }

    function sendSubjectProtocolFee(uint96 rawAmount) external {
        uint256 pending = router.protocolOwed(address(subjectToken));
        if (pending == 0) return;
        uint256 amount = uint256(rawAmount) % pending + 1;
        router.sendProtocolFee(address(subjectToken), amount);
        subjectProtocolSent += amount;
    }

    function sendQuoteProtocolFee(uint96 rawAmount) external {
        uint256 pending = router.protocolOwed(address(quoteToken));
        if (pending == 0) return;
        uint256 amount = uint256(rawAmount) % pending + 1;
        router.sendProtocolFee(address(quoteToken), amount);
        quoteProtocolSent += amount;
    }

    function sendWalletSubject(uint96 rawAmount) external {
        uint256 pending = router.walletOwed(wallet, address(subjectToken));
        if (pending == 0) return;
        router.sendWallet(wallet, address(subjectToken), uint256(rawAmount) % pending + 1);
    }

    function fundSinkSubject(uint96 rawAmount) external {
        uint16 key = router.allocationKey(0, 1);
        uint256 pending = router.sinkOwed(key, address(subjectToken));
        if (pending == 0) return;
        router.fundSink(0, 1, uint256(rawAmount) % pending + 1);
    }
}

contract SinjohFeeRouterInvariantTest is InvariantTestBase {
    address internal constant PROTOCOL_RECIPIENT = address(0x1001);
    address internal constant WALLET = address(0x2002);

    MockERC20 internal subjectToken;
    MockERC20 internal quoteToken;
    MockSwapAdapter internal adapter;
    MockSink internal sink;
    SinjohFeeRouter internal router;
    FeeRouterHandler internal handler;

    function setUp() public {
        subjectToken = new MockERC20("Subject", "SUB");
        quoteToken = new MockERC20("Wrapped Ether", "WETH");
        MockPriceGuard guard = new MockPriceGuard(1, type(uint48).max);
        adapter = new MockSwapAdapter();
        sink = new MockSink();
        SinjohFeeRouter implementation = new SinjohFeeRouter();
        SinjohFeeRouterFactory factory = new SinjohFeeRouterFactory(address(implementation));

        RouterTypes.Config memory config = _config(guard);
        router =
            SinjohFeeRouter(payable(factory.deploy(address(this), bytes32("INVARIANT"), config)));
        router.bind(address(subjectToken));

        handler = new FeeRouterHandler(router, subjectToken, quoteToken, adapter, sink, WALLET);
        _targetedContracts.push(address(handler));
    }

    function invariantLiabilitiesNeverExceedBalances() public view {
        assertTrue(
            router.totalLiability(address(subjectToken)) <= subjectToken.balanceOf(address(router))
        );
        assertTrue(
            router.totalLiability(address(quoteToken)) <= quoteToken.balanceOf(address(router))
        );
    }

    function invariantAggregateEqualsDetailedSubjectLedgers() public view {
        uint256 detailed = router.protocolOwed(address(subjectToken))
            + router.bucketInputOwed(0, address(subjectToken))
            + router.walletOwed(WALLET, address(subjectToken))
            + router.sinkOwed(router.allocationKey(0, 1), address(subjectToken));
        assertEq(router.totalLiability(address(subjectToken)), detailed);
    }

    function invariantAggregateEqualsDetailedQuoteLedgers() public view {
        uint256 detailed = router.protocolOwed(address(quoteToken))
            + router.bucketInputOwed(0, address(quoteToken))
            + router.walletOwed(WALLET, address(quoteToken))
            + router.sinkOwed(router.allocationKey(0, 1), address(quoteToken));
        assertEq(router.totalLiability(address(quoteToken)), detailed);
    }

    function invariantProtocolFeesEqualOnePercentOfCumulativeIntake() public view {
        assertEq(
            router.protocolOwed(address(subjectToken)) + handler.subjectProtocolSent(),
            handler.totalSubjectGross() * router.PROTOCOL_FEE_BPS() / router.BPS()
        );
        assertEq(
            router.protocolOwed(address(quoteToken)) + handler.quoteProtocolSent(),
            handler.totalQuoteGross() * router.PROTOCOL_FEE_BPS() / router.BPS()
        );
    }

    function _config(MockPriceGuard guard)
        internal
        view
        returns (RouterTypes.Config memory config)
    {
        RouterTypes.AssetRef[] memory intakeAssets = new RouterTypes.AssetRef[](2);
        intakeAssets[0] =
            RouterTypes.AssetRef({ kind: RouterTypes.AssetKind.SUBJECT, token: address(0) });
        intakeAssets[1] = RouterTypes.AssetRef({
            kind: RouterTypes.AssetKind.FIXED_ERC20, token: address(quoteToken)
        });

        RouterTypes.Conversion[] memory conversions = new RouterTypes.Conversion[](2);
        conversions[0] = RouterTypes.Conversion({
            input: intakeAssets[0],
            adapter: address(0),
            priceGuard: address(0),
            routeData: "",
            maxAmountInPerCall: type(uint128).max,
            minInterval: 0
        });
        conversions[1] = RouterTypes.Conversion({
            input: intakeAssets[1],
            adapter: address(adapter),
            priceGuard: address(guard),
            routeData: hex"1234",
            maxAmountInPerCall: type(uint128).max,
            minInterval: 0
        });

        RouterTypes.Allocation[] memory allocations = new RouterTypes.Allocation[](2);
        allocations[0] = RouterTypes.Allocation({
            destination: WALLET, bps: 5_000, isSink: false, creatorMayRepoint: false, sinkConfig: ""
        });
        allocations[1] = RouterTypes.Allocation({
            destination: address(sink),
            bps: 5_000,
            isSink: true,
            creatorMayRepoint: false,
            sinkConfig: hex"01"
        });

        RouterTypes.Bucket[] memory buckets = new RouterTypes.Bucket[](1);
        buckets[0] = RouterTypes.Bucket({
            output: intakeAssets[0], bps: 10_000, conversions: conversions, allocations: allocations
        });

        config = RouterTypes.Config({
            creator: address(this),
            protocolFeeRecipient: PROTOCOL_RECIPIENT,
            weth: address(quoteToken),
            intakeAssets: intakeAssets,
            buckets: buckets
        });
    }
}
