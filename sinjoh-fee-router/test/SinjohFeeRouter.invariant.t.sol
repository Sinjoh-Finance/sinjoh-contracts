// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { InvariantTestBase } from "./TestBase.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";
import { MockPriceGuard } from "./mocks/MockPriceGuard.sol";
import { MockSwapAdapter } from "./mocks/MockSwapAdapter.sol";
import { RouterTypes } from "../src/RouterTypes.sol";
import { SinjohFeeRouter } from "../src/SinjohFeeRouter.sol";
import { SinjohFeeRouterFactory } from "../src/SinjohFeeRouterFactory.sol";

contract FeeRouterHandler {
    SinjohFeeRouter public immutable router;
    MockERC20 public immutable subject;
    MockERC20 public immutable weth;
    MockSwapAdapter public immutable adapter;
    address public immutable wallet;
    uint256 public normalizedGross;
    uint256 public protocolSent;

    constructor(
        SinjohFeeRouter router_,
        MockERC20 subject_,
        MockERC20 weth_,
        MockSwapAdapter adapter_,
        address wallet_
    ) {
        router = router_;
        subject = subject_;
        weth = weth_;
        adapter = adapter_;
        wallet = wallet_;
    }

    function donateSubject(uint96 rawAmount) external {
        uint256 amount = uint256(rawAmount) % 1e24 + 1;
        subject.mint(address(router), amount);
        weth.mint(address(adapter), amount);
        router.sync(address(subject), 1);
        normalizedGross += amount;
    }

    function donateWeth(uint96 rawAmount) external {
        uint256 amount = uint256(rawAmount) % 1e24 + 1;
        weth.mint(address(router), amount);
        router.sync(address(weth));
        normalizedGross += amount;
    }

    function process(uint96 rawAmount) external {
        uint256 pending = router.bucketInputOwed(0, address(weth));
        if (pending == 0) return;
        router.processBucket(0, address(weth), uint256(rawAmount) % pending + 1, 0, "");
    }

    function sendWallet(uint96 rawAmount) external {
        uint256 pending = router.walletOwed(wallet, address(weth));
        if (pending == 0) return;
        router.sendWallet(wallet, address(weth), uint256(rawAmount) % pending + 1);
    }

    function sendProtocol(uint96 rawAmount) external {
        uint256 pending = router.protocolOwed(address(weth));
        if (pending == 0) return;
        uint256 amount = uint256(rawAmount) % pending + 1;
        router.sendProtocolFee(address(weth), amount);
        protocolSent += amount;
    }
}

contract SinjohFeeRouterInvariantTest is InvariantTestBase {
    address internal constant PROTOCOL_RECIPIENT = address(0x1001);
    address internal constant WALLET = address(0x2002);

    MockERC20 internal subject;
    MockERC20 internal weth;
    MockSwapAdapter internal adapter;
    SinjohFeeRouter internal router;
    FeeRouterHandler internal handler;

    function setUp() public {
        subject = new MockERC20("Subject", "SUB");
        weth = new MockERC20("Wrapped Ether", "WETH");
        adapter = new MockSwapAdapter();
        MockPriceGuard priceGuard = new MockPriceGuard(1, type(uint48).max);
        SinjohFeeRouterFactory factory = new SinjohFeeRouterFactory(address(new SinjohFeeRouter()));

        RouterTypes.Allocation[] memory allocations = new RouterTypes.Allocation[](1);
        allocations[0] = RouterTypes.Allocation({
            destination: WALLET,
            bps: 10_000,
            isSink: false,
            creatorMayRepoint: false,
            sinkConfig: ""
        });
        RouterTypes.Bucket[] memory buckets = new RouterTypes.Bucket[](1);
        buckets[0] = RouterTypes.Bucket({
            output: RouterTypes.AssetRef(RouterTypes.AssetKind.FIXED_ERC20, address(weth)),
            bps: 10_000,
            route: RouterTypes.Route(address(0), ""),
            allocations: allocations
        });
        RouterTypes.Normalization[] memory normalizations = new RouterTypes.Normalization[](1);
        normalizations[0] = RouterTypes.Normalization({
            asset: RouterTypes.AssetRef(RouterTypes.AssetKind.SUBJECT, address(0)),
            route: RouterTypes.Route(address(adapter), hex"01"),
            priceGuard: address(priceGuard)
        });
        RouterTypes.Config memory config = RouterTypes.Config({
            creator: address(this),
            protocolFeeRecipient: PROTOCOL_RECIPIENT,
            weth: address(weth),
            launchpadAdapter: address(0),
            normalizations: normalizations,
            buckets: buckets
        });
        router =
            SinjohFeeRouter(payable(factory.deploy(address(this), bytes32("INVARIANT"), config)));
        router.bind(address(subject));
        handler = new FeeRouterHandler(router, subject, weth, adapter, WALLET);
        _targetedContracts.push(address(handler));
    }

    function invariantLiabilitiesNeverExceedBalances() public view {
        assertTrue(router.totalLiability(address(subject)) <= subject.balanceOf(address(router)));
        assertTrue(router.totalLiability(address(weth)) <= weth.balanceOf(address(router)));
    }

    function invariantWethLedgerEqualsAggregateLiability() public view {
        uint256 detailed = router.protocolOwed(address(weth))
            + router.bucketInputOwed(0, address(weth)) + router.walletOwed(WALLET, address(weth));
        assertEq(router.totalLiability(address(weth)), detailed);
    }

    function invariantSubjectNeverRemainsAccounted() public view {
        assertEq(router.totalLiability(address(subject)), 0);
    }

    function invariantProtocolFeeIsOnePercentOfNormalizedIntake() public view {
        assertEq(
            router.protocolOwed(address(weth)) + handler.protocolSent(),
            handler.normalizedGross() * router.PROTOCOL_FEE_BPS() / router.BPS()
        );
    }
}
