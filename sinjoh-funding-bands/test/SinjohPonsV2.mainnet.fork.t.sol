// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { PoolId } from "@uniswap/v4-core/src/types/PoolId.sol";

import { FundingBandMath } from "../src/FundingBandMath.sol";
import { IV4StateView, SinjohFundingBands } from "../src/SinjohFundingBands.sol";
import { SinjohFundingBandsLaunchEscrow } from "../src/SinjohFundingBandsLaunchEscrow.sol";
import { ISinjohLaunchVerifier } from "../src/interfaces/ISinjohLaunchVerifier.sol";
import { SinjohV3EthUsdOracle } from "../src/oracles/SinjohV3EthUsdOracle.sol";
import { SinjohPonsV2LaunchVerifier } from "../src/profiles/SinjohPonsV2LaunchVerifier.sol";
import {
    SinjohV4ConfirmedBandPriceGuard
} from "../src/profiles/SinjohV4ConfirmedBandPriceGuard.sol";
import { TestBase } from "./TestBase.sol";
import {
    ISinjohFundingBandsLaunchEscrow,
    SinjohPonsV2Adapter
} from "sinjoh-launchpad-adapters/src/SinjohPonsV2Adapter.sol";
import {
    SinjohPonsV2AdapterFactory
} from "sinjoh-launchpad-adapters/src/SinjohPonsV2AdapterFactory.sol";
import { IPonsV2LaunchFactory } from "sinjoh-launchpad-adapters/src/interfaces/IPonsV2.sol";

contract FundingBandsForkRouter {
    address public immutable launchpadAdapter;
    address public immutable creator;
    address public immutable weth;
    address public subject;

    constructor(address launchpadAdapter_, address creator_, address weth_) {
        launchpadAdapter = launchpadAdapter_;
        creator = creator_;
        weth = weth_;
    }

    function bind(address subject_) external {
        require(msg.sender == launchpadAdapter && subject == address(0));
        subject = subject_;
    }

    function isIntakeAsset(address asset) external view returns (bool) {
        return asset == weth || asset == subject;
    }
}

interface IPonsV2LaunchFactoryFork {
    struct Socials {
        string twitter;
        string telegram;
        string discord;
        string website;
        string farcaster;
    }

    struct TokenParams {
        string name;
        string symbol;
        string logo;
        string description;
        Socials socials;
        address creatorFeeRecipient;
        uint16 creatorTaxBps;
        bool buybackEnabled;
        bytes32 expectedEconomics;
        bytes32 salt;
    }

    function launchToken(
        TokenParams calldata params,
        uint256 launchConfigId,
        address pairToken,
        address[] calldata snipeTaxExemptions
    ) external payable returns (address token, address curve);

    function launchFee() external view returns (uint256);
    function launchEnabled() external view returns (bool);

    function previewLaunchEconomics(uint256 launchConfigId, address pairToken)
        external
        view
        returns (bytes32);
}

interface IPonsV2BondingCurveFork {
    function buy(uint256 quoteIn, uint256 minTokensOut, address recipient)
        external
        payable
        returns (uint256);

    function graduated() external view returns (bool);
}

interface IWETHFork is IERC20 {
    function deposit() external payable;
}

interface ISwapAdapterFork {
    function swap(
        address assetIn,
        address assetOut,
        uint256 amountIn,
        uint256 minAmountOut,
        bytes calldata routeData
    ) external payable;
}

interface IPonsV2FactoryGraduationFork {
    function createGraduatedPool(address token) external returns (uint256 positionId);
}

interface IPonsV2SnipeTaxViewsFork {
    function snipeTaxSeconds() external view returns (uint256);
}

/// @notice Exercises Funding Bands against the current Pons v2 deployment,
/// its real meme hook, and the canonical Uniswap v4 singleton on a state fork.
contract SinjohPonsV2MainnetForkTest is TestBase {
    string internal constant DEFAULT_RPC = "https://rpc.mainnet.chain.robinhood.com";
    uint256 internal constant SIGNER_KEY = uint256(keccak256("funding-bands-observer"));

    address internal constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;
    address internal constant USDG = 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168;
    address internal constant V3_FACTORY = 0x1f7d7550B1b028f7571E69A784071F0205FD2EfA;
    address internal constant V3_POSITION_MANAGER = 0x73991a25C818Bf1f1128dEAaB1492D45638DE0D3;
    address internal constant V4_POSITION_MANAGER = 0x58daec3116aae6D93017bAAea7749052E8a04fA7;
    address internal constant V4_STATE_VIEW = 0xF3334192D15450CdD385c8B70e03f9A6bD9E673b;
    address internal constant V4_POOL_MANAGER = 0x8366a39CC670B4001A1121B8F6A443A643e40951;
    address internal constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address internal constant PONS_FACTORY = 0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e;
    address internal constant PONS_HOOK = 0xE5e702641Ea86F4ae6cC3cDaeD2B886f976Be044;
    address internal constant PONS_BUYBACK_ADAPTER = 0x39217172A3F07E827557093989039F968A571D43;
    address internal constant CREATOR = address(0xC4EA704);
    address internal constant ACTIVATOR = address(0xAC71A7E);

    receive() external payable { }

    function testPonsV2RealHookMintIncreaseCrossAndNativeSettlement() public {
        _exerciseLifecycle();
    }

    function _exerciseLifecycle() private {
        vm.createSelectFork(vm.envOr("ROBINHOOD_RPC_URL", DEFAULT_RPC));
        assertTrue(IPonsV2LaunchFactoryFork(PONS_FACTORY).launchEnabled());
        vm.deal(CREATOR, 100 ether);
        address probeSubject = _launchAndGraduateProbe();

        SinjohPonsV2AdapterFactory adapterFactory = new SinjohPonsV2AdapterFactory(
            PONS_FACTORY, IPonsV2LaunchFactory(PONS_FACTORY).feeEscrow(), WETH, block.chainid
        );
        bytes32 adapterSalt = keccak256("funding-bands-mainnet-fork-adapter");
        address predictedAdapter = adapterFactory.predictAddress(CREATOR, adapterSalt);
        FundingBandsForkRouter router = new FundingBandsForkRouter(predictedAdapter, CREATOR, WETH);
        SinjohPonsV2LaunchVerifier verifier = new SinjohPonsV2LaunchVerifier(
            PONS_FACTORY, PONS_HOOK, WETH, adapterFactory.adapterRuntimeCodehash()
        );
        SinjohFundingBandsLaunchEscrow escrow =
            new SinjohFundingBandsLaunchEscrow(address(verifier), address(this));
        SinjohV4ConfirmedBandPriceGuard guard = new SinjohV4ConfirmedBandPriceGuard(
            V4_STATE_VIEW,
            V4_STATE_VIEW.codehash,
            V4_POOL_MANAGER.codehash,
            address(this),
            vm.addr(SIGNER_KEY)
        );
        SinjohV3EthUsdOracle oracle =
            new SinjohV3EthUsdOracle(V3_FACTORY, WETH, USDG, 100, 15 minutes, 500, 1e18);
        (, int256 ethUsdAnswer,,,) = oracle.latestRoundData();
        assertTrue(ethUsdAnswer > 1_000e8 && ethUsdAnswer < 5_000e8);
        SinjohFundingBands.ProfileInput[] memory profiles = new SinjohFundingBands.ProfileInput[](1);
        profiles[0] = SinjohFundingBands.ProfileInput({
            verifier: address(verifier), priceGuard: address(guard), hookData: ""
        });
        SinjohFundingBands manager = new SinjohFundingBands(
            WETH,
            V3_FACTORY,
            V3_POSITION_MANAGER,
            V4_POSITION_MANAGER,
            V4_STATE_VIEW,
            PERMIT2,
            address(oracle),
            address(router).codehash,
            address(0xFEE),
            address(escrow),
            1 hours,
            profiles
        );
        escrow.bindManager(address(manager));
        adapterFactory.bindFundingBandsEscrow(address(escrow));

        ISinjohLaunchVerifier.VerifiedLaunch memory probe = verifier.verify(probeSubject, "");
        (uint160 sqrtPriceX96, int24 spotTick,,) =
            IV4StateView(V4_STATE_VIEW).getSlot0(PoolId.wrap(probe.poolId));
        assertTrue(sqrtPriceX96 != 0);

        (
            uint128 lowerMarketCap,
            uint128 upperMarketCap,
            int24 lowerBoundary,
            int24 upperBoundary
        ) = _bandAboveSpot(
            probe.launchSupply,
            probe.tickSpacing,
            spotTick,
            // The live oracle answer was bounded to a positive range above.
            // forge-lint: disable-next-line(unsafe-typecast)
            uint256(ethUsdAnswer),
            false
        );
        assertTrue(spotTick > lowerBoundary);
        SinjohFundingBands.BandConfig[] memory configs = new SinjohFundingBands.BandConfig[](1);
        configs[0] = SinjohFundingBands.BandConfig({
            lowerMarketCapUsdE8: lowerMarketCap,
            upperMarketCapUsdE8: upperMarketCap,
            destination: SinjohFundingBands.Destination.FEE_ROUTER,
            feeRouter: address(router)
        });

        (address subject, address curve, uint256 escrowedInventory) =
            _launchWithEscrow(adapterFactory, escrow, configs, router, adapterSalt);
        assertEq(IERC20(subject).balanceOf(CREATOR), 0);
        assertEq(IERC20(subject).balanceOf(address(escrow)), escrowedInventory);
        _graduateAfterDeveloperBuy(subject, curve);

        vm.prank(ACTIVATOR);
        escrow.activate(subject);
        assertEq(IERC20(subject).balanceOf(address(escrow)), 0);
        SinjohFundingBandsLaunchEscrow.PreparedAccount memory prepared =
            escrow.getPreparedAccount(subject);
        assertTrue(!prepared.exists);
        assertTrue(prepared.activated);

        ISinjohLaunchVerifier.VerifiedLaunch memory launch = verifier.verify(subject, "");
        assertEq(launch.creatorAtLaunch, CREATOR);
        assertEq(launch.quoteAsset, address(0));
        assertTrue(launch.poolId != bytes32(0));
        SinjohFundingBands.Account memory account = manager.getAccount(subject);
        assertEq(account.creator, CREATOR);
        assertTrue(account.exists);
        SinjohFundingBands.Band memory active = manager.getBand(subject, 0);
        assertTrue(active.positionId != 0 && active.liquidity != 0);

        vm.deal(address(this), 10 ether);
        IWETHFork(WETH).deposit{ value: 10 ether }();
        IERC20(WETH).approve(PONS_BUYBACK_ADAPTER, 10 ether);
        ISwapAdapterFork(PONS_BUYBACK_ADAPTER).swap(WETH, subject, 10 ether, 1, "");

        (, int24 crossedTick,,) = IV4StateView(V4_STATE_VIEW).getSlot0(PoolId.wrap(launch.poolId));
        assertTrue(crossedTick <= upperBoundary);
        manager.armSettlement(subject, 0, "");
        SinjohV4ConfirmedBandPriceGuard.Observation[] memory observations =
            new SinjohV4ConfirmedBandPriceGuard.Observation[](1);
        observations[0] = SinjohV4ConfirmedBandPriceGuard.Observation({
            manager: address(manager),
            subject: subject,
            bandId: 0,
            poolId: launch.poolId,
            subjectIsToken0: false,
            boundaryTick: upperBoundary,
            above: true
        });
        vm.prank(vm.addr(SIGNER_KEY));
        guard.observe(observations);

        vm.expectRevert(SinjohFundingBands.SettlementConfirmationPending.selector);
        manager.settle(subject, 0, "");

        vm.warp(block.timestamp + manager.V4_SETTLEMENT_DELAY());
        vm.prank(vm.addr(SIGNER_KEY));
        guard.observe(observations);
        manager.settle(subject, 0, "");

        SinjohFundingBands.Band memory settled = manager.getBand(subject, 0);
        assertEq(uint256(settled.status), uint256(SinjohFundingBands.BandStatus.SETTLED));
        assertEq(settled.liquidity, 0);
        assertTrue(settled.cumulativeRealizedWeth > 0);
        assertEq(settled.protocolFeeCharged, settled.cumulativeRealizedWeth * 100 / 10_000);
        assertEq(
            manager.proceedsOwed(subject, 0, WETH) + manager.protocolOwed(),
            settled.cumulativeRealizedWeth
        );
        uint256 routerWethBefore = IERC20(WETH).balanceOf(address(router));
        uint256 routerSubjectBefore = IERC20(subject).balanceOf(address(router));
        uint256 creatorWethBefore = IERC20(WETH).balanceOf(CREATOR);
        uint256 creatorSubjectBefore = IERC20(subject).balanceOf(CREATOR);
        uint256 protocolBefore = IERC20(WETH).balanceOf(address(0xFEE));
        uint256 wethOwed = manager.proceedsOwed(subject, 0, WETH);
        uint256 subjectOwed = manager.proceedsOwed(subject, 0, subject);
        uint256 protocolOwed = manager.protocolOwed();
        if (wethOwed != 0) manager.sendProceeds(subject, 0, WETH, wethOwed);
        if (subjectOwed != 0) manager.sendProceeds(subject, 0, subject, subjectOwed);
        if (protocolOwed != 0) manager.sendProtocolFee(protocolOwed);
        assertEq(IERC20(WETH).balanceOf(address(router)), routerWethBefore + wethOwed);
        assertEq(IERC20(subject).balanceOf(address(router)), routerSubjectBefore + subjectOwed);
        assertEq(IERC20(WETH).balanceOf(CREATOR), creatorWethBefore);
        assertEq(IERC20(subject).balanceOf(CREATOR), creatorSubjectBefore);
        assertEq(IERC20(WETH).balanceOf(address(0xFEE)), protocolBefore + protocolOwed);
        assertEq(
            uint256(manager.getBand(subject, 0).status),
            uint256(SinjohFundingBands.BandStatus.DELIVERED)
        );
    }

    function _launchAndGraduateProbe() private returns (address token) {
        IPonsV2LaunchFactoryFork factory = IPonsV2LaunchFactoryFork(PONS_FACTORY);
        IPonsV2LaunchFactoryFork.TokenParams memory params;
        params.name = "Funding Bands Probe";
        params.symbol = "FBP";
        params.creatorFeeRecipient = CREATOR;
        params.creatorTaxBps = 0;
        params.buybackEnabled = false;
        params.expectedEconomics = factory.previewLaunchEconomics(0, address(0));
        params.salt = keccak256("funding-bands-mainnet-fork-probe");

        uint256 launchFee = factory.launchFee();
        vm.prank(CREATOR);
        address curve;
        (token, curve) =
            factory.launchToken{ value: launchFee }(params, 0, address(0), new address[](0));
        vm.warp(block.timestamp + IPonsV2SnipeTaxViewsFork(PONS_FACTORY).snipeTaxSeconds() + 1);

        address whale = address(0xDECAF);
        vm.prank(CREATOR);
        IPonsV2BondingCurveFork(curve).buy{ value: 1 ether }(1 ether, 1, CREATOR);
        vm.deal(whale, 20 ether);
        vm.prank(whale);
        IPonsV2BondingCurveFork(curve).buy{ value: 10 ether }(10 ether, 1, whale);
        assertTrue(IPonsV2BondingCurveFork(curve).graduated());
        IPonsV2FactoryGraduationFork(PONS_FACTORY).createGraduatedPool(token);
    }

    function _launchWithEscrow(
        SinjohPonsV2AdapterFactory adapterFactory,
        SinjohFundingBandsLaunchEscrow escrow,
        SinjohFundingBands.BandConfig[] memory managerConfigs,
        FundingBandsForkRouter router,
        bytes32 userSalt
    ) private returns (address token, address curve, uint256 escrowedInventory) {
        address predicted = adapterFactory.predictAddress(CREATOR, userSalt);
        assertEq(predicted, address(router.launchpadAdapter()));
        vm.prank(CREATOR);
        SinjohPonsV2Adapter adapter = SinjohPonsV2Adapter(
            payable(adapterFactory.deploy(CREATOR, address(router), userSalt))
        );

        IPonsV2LaunchFactory factory = IPonsV2LaunchFactory(PONS_FACTORY);
        IPonsV2LaunchFactory.TokenParams memory params;
        params.name = "Funding Bands Escrow Fork";
        params.symbol = "FBE";
        params.creatorFeeRecipient = address(adapter);
        params.creatorTaxBps = 0;
        params.buybackEnabled = false;
        params.expectedEconomics = factory.previewLaunchEconomics(0, address(0));
        params.salt = keccak256("funding-bands-mainnet-fork-escrow");

        ISinjohFundingBandsLaunchEscrow.BandConfig[] memory configs =
            new ISinjohFundingBandsLaunchEscrow.BandConfig[](1);
        configs[0] = ISinjohFundingBandsLaunchEscrow.BandConfig({
            lowerMarketCapUsdE8: managerConfigs[0].lowerMarketCapUsdE8,
            upperMarketCapUsdE8: managerConfigs[0].upperMarketCapUsdE8,
            destination: ISinjohFundingBandsLaunchEscrow.Destination.FEE_ROUTER,
            feeRouter: address(router)
        });
        uint16[] memory allocations = new uint16[](1);
        allocations[0] = 10_000;
        SinjohPonsV2Adapter.FundingBandsPlan memory plan = SinjohPonsV2Adapter.FundingBandsPlan({
            escrow: address(escrow),
            profileId: 0,
            inventoryBps: 10_000,
            configs: configs,
            allocationBps: allocations
        });

        uint256 developerBuy = 1 ether;
        uint256 launchFee = factory.launchFee();
        vm.prank(CREATOR);
        (token, curve) = adapter.launchWithFundingBands{ value: launchFee + developerBuy }(
            params, 0, address(0), developerBuy, 1, new address[](0), plan
        );
        assertEq(router.subject(), token);
        SinjohFundingBandsLaunchEscrow.PreparedAccount memory prepared =
            escrow.getPreparedAccount(token);
        assertEq(prepared.creator, CREATOR);
        assertTrue(prepared.exists);
        assertTrue(!prepared.activated);
        escrowedInventory = prepared.escrowedInventory;
        assertTrue(escrowedInventory > 0);
    }

    function _graduateAfterDeveloperBuy(address token, address curve) private {
        vm.warp(block.timestamp + IPonsV2SnipeTaxViewsFork(PONS_FACTORY).snipeTaxSeconds() + 1);
        address whale = address(0xB16B00B5);
        vm.deal(whale, 20 ether);
        vm.prank(whale);
        IPonsV2BondingCurveFork(curve).buy{ value: 10 ether }(10 ether, 1, whale);
        assertTrue(IPonsV2BondingCurveFork(curve).graduated());
        IPonsV2FactoryGraduationFork(PONS_FACTORY).createGraduatedPool(token);
    }

    function _bandAboveSpot(
        uint256 supply,
        int24 spacing,
        int24 spotTick,
        uint256 ethUsdE8,
        bool subjectIsToken0
    )
        private
        pure
        returns (
            uint128 lowerMarketCap,
            uint128 upperMarketCap,
            int24 lowerBoundary,
            int24 upperBoundary
        )
    {
        uint128 low = 1e8;
        uint128 high = 10_000_000_000e8;
        while (low < high) {
            uint128 middle = low + (high - low) / 2;
            FundingBandMath.ConvertedRange memory candidate = FundingBandMath.convertRange(
                middle, middle + middle / 10 + 1, supply, ethUsdE8, spacing, subjectIsToken0
            );
            bool below =
                subjectIsToken0 ? spotTick < candidate.tickLower : spotTick > candidate.tickUpper;
            if (below) {
                high = middle;
            } else {
                low = middle + 1;
            }
        }
        lowerMarketCap = low + low / 10;
        upperMarketCap = lowerMarketCap + lowerMarketCap / 5;
        FundingBandMath.ConvertedRange memory range = FundingBandMath.convertRange(
            lowerMarketCap, upperMarketCap, supply, ethUsdE8, spacing, subjectIsToken0
        );
        lowerBoundary = subjectIsToken0 ? range.tickLower : range.tickUpper;
        upperBoundary = subjectIsToken0 ? range.tickUpper : range.tickLower;
    }
}
