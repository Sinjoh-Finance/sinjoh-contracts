// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { TestBase } from "./TestBase.sol";
import { RouterTypes } from "../src/RouterTypes.sol";
import { SinjohFeeRouter } from "../src/SinjohFeeRouter.sol";
import { SinjohFeeRouterFactory } from "../src/SinjohFeeRouterFactory.sol";
import { IPonsV2LaunchFactory } from "../src/interfaces/IPonsV2.sol";
import { PonsV2LaunchPrediction } from "../src/libraries/PonsV2LaunchPrediction.sol";

interface IWETHFork {
    function balanceOf(address account) external view returns (uint256);
}

interface IPonsV2CurveFork {
    function buy(uint256 quoteIn, uint256 minTokensOut, address recipient)
        external
        payable
        returns (uint256 tokensOut);
    function quoteFeeBalance() external view returns (uint256);
    function creatorTaxBalance() external view returns (uint256);
    function snipeTaxSeconds() external view returns (uint256);
    function creatorTaxBps() external view returns (uint256);
}

/// @notice Launches a real token through the real, verified Pons v2 factory on a
/// Robinhood Chain mainnet fork and drives creator revenue the whole way to the
/// router's ordinary accounting: launch -> taxed curve trades -> permissionless
/// curve sweep -> escrow claim -> WETH -> `sync`.
///
/// @dev This is the exact-ABI check the strategy document gates v2 enablement on.
/// The copied interface's `TokenParams` was missing the deployed struct's
/// trailing `salt` field, so every launch encoded selector `0xa41d5f2b` — which
/// exists on no deployed contract — and no mock could ever notice. Only this
/// test exercises the boundary against real bytecode. Set `RH_RPC_URL` to run.
contract SinjohFeeRouterV2ForkTest is TestBase {
    address internal constant PONS_V2_FACTORY = 0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e;
    address internal constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;
    /// @dev The reviewed mainnet swap adapter; unused by these flows but the
    /// router requires a real subject route at initialization.
    address internal constant SWAP_ADAPTER = 0xc9F600ebaf9EE1F4a24568D2e4Af9E8df1e07D7B;
    uint256 internal constant LAUNCH_CONFIG_ID = 0;
    uint16 internal constant CREATOR_TAX_BPS = 250;

    address internal constant PROTOCOL_RECIPIENT = address(0xFEE1);
    address internal constant WALLET = address(0x2002);
    address internal constant TRADER = address(0x7ade);

    bool internal forked;
    SinjohFeeRouter internal router;

    function setUp() public {
        string memory url = vm.envOr("RH_RPC_URL", string(""));
        if (bytes(url).length == 0) return;
        vm.createSelectFork(url);
        forked = true;

        SinjohFeeRouterFactory factory =
            new SinjohFeeRouterFactory(address(new SinjohFeeRouter()));
        router = SinjohFeeRouter(
            payable(factory.deployPons(address(this), bytes32("V2_FORK"), _config()))
        );
    }

    function testForkLaunchTradeSweepClaimAndSyncAgainstRealPons() public {
        if (!forked) return;
        IPonsV2LaunchFactory pons = IPonsV2LaunchFactory(PONS_V2_FACTORY);

        // Launch with a creator trade tax, revenue routed to the router.
        vm.deal(address(this), 1 ether);
        IPonsV2LaunchFactory.TokenParams memory params = IPonsV2LaunchFactory.TokenParams({
            name: "Sinjoh Fork Probe",
            symbol: "SFP",
            logo: "",
            description: "",
            socials: IPonsV2LaunchFactory.Socials({
                twitter: "", telegram: "", discord: "", website: "", farcaster: ""
            }),
            creatorFeeRecipient: address(router),
            creatorTaxBps: CREATOR_TAX_BPS,
            buybackEnabled: false,
            expectedEconomics: pons.previewLaunchEconomics(LAUNCH_CONFIG_ID, address(0)),
            salt: bytes32("SINJOH_FORK_PROBE")
        });

        // The raffle flow's ordering guarantee: both addresses are known here,
        // before anything is deployed.
        (address predictedToken, address predictedCurve) = PonsV2LaunchPrediction.predict(
            PONS_V2_FACTORY, params, LAUNCH_CONFIG_ID, address(0), address(router)
        );

        (address subject, address curveAddress) = router.launchPonsV2Token{
            value: pons.launchFee()
        }(PONS_V2_FACTORY, params, LAUNCH_CONFIG_ID, address(0), new address[](0));

        assertEq(subject, predictedToken);
        assertEq(curveAddress, predictedCurve);
        assertEq(router.subject(), subject);
        assertEq(router.ponsV2Curve(), curveAddress);
        assertTrue(subject.code.length != 0);
        assertTrue(curveAddress.code.length != 0);
        IPonsV2LaunchFactory.LaunchedToken memory launched = pons.getLaunchedToken(subject);
        assertTrue(launched.exists);
        assertEq(launched.deployer, address(router));
        assertEq(launched.creatorFeeRecipient, address(router));
        assertEq(uint256(launched.creatorTaxBps), CREATOR_TAX_BPS);

        // Trade after the snipe window so the fee split is the steady-state one.
        IPonsV2CurveFork curve = IPonsV2CurveFork(curveAddress);
        assertEq(curve.creatorTaxBps(), CREATOR_TAX_BPS);
        vm.warp(block.timestamp + curve.snipeTaxSeconds() + 1);
        vm.deal(TRADER, 2 ether);
        vm.prank(TRADER);
        uint256 tokensOut = curve.buy{ value: 1 ether }(1 ether, 1, TRADER);
        assertTrue(tokensOut != 0);

        // The 2.5% creator tax and the base fee accrued on the curve's quote leg.
        uint256 pendingTax = curve.creatorTaxBalance();
        assertEq(pendingTax, uint256(1 ether) * CREATOR_TAX_BPS / 10_000);
        uint256 pending = curve.quoteFeeBalance() + pendingTax;

        // Anyone moves the pending fees curve -> escrow -> router as WETH.
        vm.prank(address(0xCA11));
        assertEq(router.sweepPonsV2CurveFees(), pending);
        uint256 wethBefore = IWETHFork(WETH).balanceOf(address(router));
        uint256 claimed = router.claimPonsV2Fees();
        assertTrue(claimed != 0);
        // The protocol's share of the base fee stays with Pons; the creator
        // bucket including the whole tax is what reaches the router.
        assertTrue(claimed >= pendingTax);
        assertTrue(claimed < pending);
        assertEq(IWETHFork(WETH).balanceOf(address(router)) - wethBefore, claimed);

        // Ordinary Sinjoh accounting picks the revenue up from here.
        router.sync(WETH);
        assertEq(router.protocolOwed(WETH), claimed / 100);
    }

    /// The identical launch reverts on a reused salt, which is what makes the
    /// curve address stable enough for a raffle's immutable exclusion list.
    function testForkReusedSaltCannotLandADifferentLaunch() public {
        if (!forked) return;
        // A fresh router, same salt namespace test: the namespace is the
        // initiating account, so a second identical launch from this router
        // collides deterministically.
        vm.deal(address(this), 1 ether);
        IPonsV2LaunchFactory pons = IPonsV2LaunchFactory(PONS_V2_FACTORY);
        IPonsV2LaunchFactory.TokenParams memory params = IPonsV2LaunchFactory.TokenParams({
            name: "Sinjoh Fork Probe",
            symbol: "SFP",
            logo: "",
            description: "",
            socials: IPonsV2LaunchFactory.Socials({
                twitter: "", telegram: "", discord: "", website: "", farcaster: ""
            }),
            creatorFeeRecipient: address(this),
            creatorTaxBps: 0,
            buybackEnabled: false,
            expectedEconomics: pons.previewLaunchEconomics(LAUNCH_CONFIG_ID, address(0)),
            salt: bytes32("SINJOH_FORK_COLLISION")
        });
        uint256 fee = pons.launchFee();
        pons.launchToken{ value: fee }(params, LAUNCH_CONFIG_ID, address(0));
        vm.expectRevert();
        pons.launchToken{ value: fee }(params, LAUNCH_CONFIG_ID, address(0));
    }

    function _config() internal view returns (RouterTypes.Config memory config) {
        RouterTypes.Allocation[] memory allocations = new RouterTypes.Allocation[](1);
        allocations[0] = RouterTypes.Allocation({
            destination: WALLET, bps: 10_000, isSink: false, creatorMayRepoint: true, sinkConfig: ""
        });
        RouterTypes.Bucket[] memory buckets = new RouterTypes.Bucket[](1);
        buckets[0] = RouterTypes.Bucket({
            output: RouterTypes.AssetRef(RouterTypes.AssetKind.FIXED_ERC20, WETH),
            bps: 10_000,
            route: RouterTypes.Route(address(0), ""),
            allocations: allocations
        });
        config = RouterTypes.Config({
            creator: address(this),
            protocolFeeRecipient: PROTOCOL_RECIPIENT,
            weth: WETH,
            subjectToWeth: RouterTypes.Route(SWAP_ADAPTER, abi.encode(uint24(10_000))),
            buckets: buckets
        });
    }
}
