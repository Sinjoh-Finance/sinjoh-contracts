// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { PoolId } from "@uniswap/v4-core/src/types/PoolId.sol";

import { FundingBandMath } from "../src/FundingBandMath.sol";
import { IV4StateView, SinjohFundingBands } from "../src/SinjohFundingBands.sol";
import { ISinjohLaunchVerifier } from "../src/interfaces/ISinjohLaunchVerifier.sol";
import { SinjohV3EthUsdOracle } from "../src/oracles/SinjohV3EthUsdOracle.sol";
import { SinjohPonsV2LaunchVerifier } from "../src/profiles/SinjohPonsV2LaunchVerifier.sol";
import {
    SinjohV4ConfirmedBandPriceGuard
} from "../src/profiles/SinjohV4ConfirmedBandPriceGuard.sol";
import { TestBase } from "./TestBase.sol";

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

interface IPonsV2LaunchFactoryAdminFork {
    function setLaunchEnabled(bool enabled) external;
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
    bytes32 internal constant SINJOH_ADAPTER_CODEHASH =
        0xc68d29cb840cd761142664c1a2a348ddccfa4f957df86d54898b981c549b28c7;
    address internal constant PONS_OWNER = 0xFdDE5a1E3cDF791Da71E49F817D70C7ceD72CC36;
    address internal constant CREATOR = address(0xC4EA704);

    receive() external payable { }

    function testPonsV2RealHookMintIncreaseCrossAndNativeSettlement() public {
        _exerciseLifecycle();
    }

    function _exerciseLifecycle() private {
        vm.createSelectFork(vm.envOr("ROBINHOOD_RPC_URL", DEFAULT_RPC));
        if (!IPonsV2LaunchFactoryFork(PONS_FACTORY).launchEnabled()) {
            vm.prank(PONS_OWNER);
            IPonsV2LaunchFactoryAdminFork(PONS_FACTORY).setLaunchEnabled(true);
        }
        vm.deal(CREATOR, 100 ether);
        (address subject,) = _launchAndGraduate();

        SinjohPonsV2LaunchVerifier verifier =
            new SinjohPonsV2LaunchVerifier(PONS_FACTORY, PONS_HOOK, WETH, SINJOH_ADAPTER_CODEHASH);
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
            keccak256("fee-router-codehash"),
            address(0xFEE),
            1 hours,
            profiles
        );

        ISinjohLaunchVerifier.VerifiedLaunch memory launch = verifier.verify(subject, "");
        assertEq(launch.creatorAtLaunch, CREATOR);
        assertEq(launch.quoteAsset, address(0));
        assertTrue(launch.poolId != bytes32(0));
        (uint160 sqrtPriceX96, int24 spotTick,,) =
            IV4StateView(V4_STATE_VIEW).getSlot0(PoolId.wrap(launch.poolId));
        assertTrue(sqrtPriceX96 != 0);

        (
            uint128 lowerMarketCap,
            uint128 upperMarketCap,
            int24 lowerBoundary,
            int24 upperBoundary
        ) = _bandAboveSpot(
            launch.launchSupply,
            launch.tickSpacing,
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
            destination: SinjohFundingBands.Destination.CREATOR,
            feeRouter: address(0)
        });

        vm.prank(CREATOR);
        manager.create(subject, 0, configs, "", "");

        uint128 firstDeposit = 5e23;
        uint128 secondDeposit = 5e23;
        assertTrue(IERC20(subject).balanceOf(CREATOR) >= uint256(firstDeposit) + secondDeposit);
        vm.prank(CREATOR);
        IERC20(subject).approve(address(manager), uint256(firstDeposit) + secondDeposit);
        SinjohFundingBands.BandFunding[] memory funding = new SinjohFundingBands.BandFunding[](1);
        funding[0] = SinjohFundingBands.BandFunding({ bandId: 0, amount: firstDeposit });
        vm.prank(CREATOR);
        manager.fund(subject, funding, "");
        funding[0].amount = secondDeposit;
        vm.prank(CREATOR);
        manager.fund(subject, funding, "");
        SinjohFundingBands.Band memory active = manager.getBand(subject, 0);
        assertTrue(active.positionId != 0 && active.liquidity != 0);

        vm.deal(address(this), 3 ether);
        IWETHFork(WETH).deposit{ value: 3 ether }();
        IERC20(WETH).approve(PONS_BUYBACK_ADAPTER, 3 ether);
        ISwapAdapterFork(PONS_BUYBACK_ADAPTER).swap(WETH, subject, 3 ether, 1, "");

        (, int24 crossedTick,,) = IV4StateView(V4_STATE_VIEW).getSlot0(PoolId.wrap(launch.poolId));
        assertTrue(crossedTick <= upperBoundary);
        manager.armSettlement(subject, 0, "");
        SinjohV4ConfirmedBandPriceGuard.Observation[] memory observations =
            new SinjohV4ConfirmedBandPriceGuard.Observation[](1);
        observations[0] = SinjohV4ConfirmedBandPriceGuard.Observation({
            manager: address(manager),
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
    }

    function _launchAndGraduate() private returns (address token, address curve) {
        IPonsV2LaunchFactoryFork factory = IPonsV2LaunchFactoryFork(PONS_FACTORY);
        IPonsV2LaunchFactoryFork.TokenParams memory params;
        params.name = "Funding Bands Fork";
        params.symbol = "FBF";
        params.creatorFeeRecipient = CREATOR;
        params.creatorTaxBps = 0;
        params.buybackEnabled = false;
        params.expectedEconomics = factory.previewLaunchEconomics(0, address(0));
        params.salt = keccak256("funding-bands-mainnet-fork");

        uint256 launchFee = factory.launchFee();
        vm.prank(CREATOR);
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
