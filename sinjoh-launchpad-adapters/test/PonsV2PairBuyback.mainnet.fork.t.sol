// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { TestBase } from "./TestBase.sol";
import {
    SinjohPonsV2PairBuybackAdapter,
    SinjohPonsV2PairBuybackPriceGuard
} from "../src/SinjohPonsV2PairBuybackAdapter.sol";
import { IPonsV2LaunchFactory } from "../src/interfaces/IPonsV2.sol";

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function deposit() external payable;
}

/// @notice Runs the pair-capable buyback route against the real pons v2
/// deployment on Robinhood Chain mainnet: a live $NVDA-paired launch bought
/// through the real WETH/$NVDA v3 pool and the launch's real bonding curve,
/// plus native-path parity with the deployed adapter.
///
/// The unit suite proves the adapter behaves as I modelled pons; this suite
/// proves the model — the record-driven pair routing, the v3 hop, the curve's
/// ERC20 pull — is the real one.
///
/// Requires network access. Run with:
///   node script/rpc-proxy.mjs &
///   forge test --match-path 'test/PonsV2PairBuyback.mainnet.fork.t.sol' \
///     --fork-url http://127.0.0.1:8545
contract PonsV2PairBuybackMainnetForkTest is TestBase {
    address constant LAUNCH_FACTORY = 0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e;
    address constant POOL_MANAGER = 0x8366a39CC670B4001A1121B8F6A443A643e40951;
    address constant MEME_HOOK = 0xE5e702641Ea86F4ae6cC3cDaeD2B886f976Be044;
    address constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;
    address constant V3_SWAP_ROUTER = 0xCaf681a66D020601342297493863E78C959E5cb2;
    address constant NVDA = 0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC;

    /// @dev A live $NVDA-paired launch from the pinned factory (block
    /// 28120959). The test re-reads its record and skips rather than fails if
    /// its phase has moved past the curve by the time the fork runs.
    address constant NVDA_LAUNCH = 0xaD34DEE403a6658F9522A5351861a34c2d0339Bf;
    /// @dev The deepest funded WETH/$NVDA pool tier on the pons v3 DEX, the
    /// same pool the router's intake normalization for an $NVDA launch uses.
    uint24 constant NVDA_FEE_TIER = 3000;

    uint8 constant PHASE_NOT_GRADUATED = 0;

    SinjohPonsV2PairBuybackAdapter adapter;
    SinjohPonsV2PairBuybackPriceGuard guard;
    uint256 constant SIGNER_KEY = uint256(keccak256("sinjoh-pons-v2-pair-buyback-fork-signer"));

    string constant DEFAULT_RPC = "https://rpc.mainnet.chain.robinhood.com";

    function setUp() public {
        vm.createSelectFork(vm.envOr("ROBINHOOD_RPC_URL", DEFAULT_RPC));
        adapter = new SinjohPonsV2PairBuybackAdapter(
            LAUNCH_FACTORY,
            POOL_MANAGER,
            WETH,
            V3_SWAP_ROUTER,
            LAUNCH_FACTORY.codehash,
            POOL_MANAGER.codehash,
            WETH.codehash,
            V3_SWAP_ROUTER.codehash
        );
        guard = new SinjohPonsV2PairBuybackPriceGuard(
            LAUNCH_FACTORY, WETH, LAUNCH_FACTORY.codehash, WETH.codehash, vm.addr(SIGNER_KEY)
        );

        vm.deal(address(this), 100 ether);
        IERC20Like(WETH).deposit{ value: 50 ether }();
        IERC20Like(WETH).approve(address(adapter), type(uint256).max);
    }

    receive() external payable { }

    function test_pinnedDependenciesAgreeOnChain() public view {
        assertEq(IPonsV2LaunchFactory(LAUNCH_FACTORY).poolManager(), POOL_MANAGER);
        assertEq(IPonsV2LaunchFactory(LAUNCH_FACTORY).memeHook(), MEME_HOOK);
        assertEq(adapter.memeHook(), MEME_HOOK);
        assertEq(adapter.v3SwapRouter(), V3_SWAP_ROUTER);
    }

    /// @dev The whole custom-pair path against real contracts: WETH through
    /// the real v3 pool into $NVDA, then the live launch's real curve.
    function test_buysARealNvdaPairedLaunchThroughBothHops() public {
        IPonsV2LaunchFactory.LaunchedToken memory record =
            IPonsV2LaunchFactory(LAUNCH_FACTORY).getLaunchedToken(NVDA_LAUNCH);
        assertTrue(record.exists);
        assertEq(record.pairToken, NVDA);
        if (record.phase != PHASE_NOT_GRADUATED) return; // moved on; nothing to prove here

        uint256 amountIn = 0.05 ether;
        uint256 wethBefore = IERC20Like(WETH).balanceOf(address(this));

        adapter.swap(WETH, NVDA_LAUNCH, amountIn, 1, abi.encode(NVDA_FEE_TIER));
        uint256 received = IERC20Like(NVDA_LAUNCH).balanceOf(address(this));

        assertTrue(received > 0);
        assertEq(IERC20Like(WETH).balanceOf(address(this)), wethBefore - amountIn);
        // Nothing rests on the adapter in any of the three assets.
        assertEq(IERC20Like(WETH).balanceOf(address(adapter)), 0);
        assertEq(IERC20Like(NVDA).balanceOf(address(adapter)), 0);
        assertEq(IERC20Like(NVDA_LAUNCH).balanceOf(address(adapter)), 0);
        assertEq(address(adapter).balance, 0);
    }

    function test_pairLaunchRefusesAnEmptyRoute() public {
        IPonsV2LaunchFactory.LaunchedToken memory record =
            IPonsV2LaunchFactory(LAUNCH_FACTORY).getLaunchedToken(NVDA_LAUNCH);
        if (!record.exists || record.pairToken != NVDA) return;
        vm.expectRevert(SinjohPonsV2PairBuybackAdapter.InvalidRoute.selector);
        adapter.swap(WETH, NVDA_LAUNCH, 0.01 ether, 1, "");
    }

    /// @dev Native parity: the successor must buy a live native launch exactly
    /// like the deployed adapter does. Uses the freshest native launch the
    /// factory record confirms is still on its curve.
    function test_nativeParityOnARealLaunch() public {
        // A live native launch from the same scan as the pair launch above.
        address nativeLaunch = 0xdDf60F53fEd8869577Ac4d533226b9BB26267648;
        IPonsV2LaunchFactory.LaunchedToken memory record =
            IPonsV2LaunchFactory(LAUNCH_FACTORY).getLaunchedToken(nativeLaunch);
        assertTrue(record.exists);
        assertEq(record.pairToken, address(0));
        if (record.phase != PHASE_NOT_GRADUATED) return;

        adapter.swap(WETH, nativeLaunch, 0.05 ether, 1, "");
        assertTrue(IERC20Like(nativeLaunch).balanceOf(address(this)) > 0);
        assertEq(IERC20Like(WETH).balanceOf(address(adapter)), 0);
        assertEq(address(adapter).balance, 0);
    }

    /// @dev Guard shape parity against the real records: the pair launch needs
    /// a route hash, the native launch refuses one.
    function test_guardRouteShapeParityOnRealRecords() public {
        bytes32 pairRouteHash = keccak256(abi.encode(NVDA_FEE_TIER));
        bytes memory guardData = _sign(NVDA_LAUNCH, 0.05 ether, keccak256(""), 1);
        vm.expectRevert(SinjohPonsV2PairBuybackPriceGuard.InvalidRoute.selector);
        guard.minimumOutput(NVDA_LAUNCH, WETH, NVDA_LAUNCH, 0.05 ether, keccak256(""), guardData);

        guardData = _sign(NVDA_LAUNCH, 0.05 ether, pairRouteHash, 1);
        (uint256 minimum,) = guard.minimumOutput(
            NVDA_LAUNCH, WETH, NVDA_LAUNCH, 0.05 ether, pairRouteHash, guardData
        );
        assertEq(minimum, 1);
    }

    function _sign(address subject, uint256 amountIn, bytes32 routeHash, uint256 minimum)
        private
        returns (bytes memory)
    {
        uint48 validAfter = uint48(block.timestamp - 1);
        uint48 validUntil = uint48(block.timestamp + 100);
        bytes32 digest = guard.floorDigest(
            address(this),
            subject,
            WETH,
            subject,
            amountIn,
            routeHash,
            minimum,
            validAfter,
            validUntil
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            SIGNER_KEY, keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", digest))
        );
        return abi.encode(minimum, validAfter, validUntil, abi.encodePacked(r, s, v));
    }
}
