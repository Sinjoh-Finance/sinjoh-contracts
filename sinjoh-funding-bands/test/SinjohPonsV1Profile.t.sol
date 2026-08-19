// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { ISinjohLaunchVerifier } from "../src/interfaces/ISinjohLaunchVerifier.sol";
import {
    IPonsV1LaunchFactory,
    SinjohPonsV1LaunchVerifier
} from "../src/profiles/SinjohPonsV1LaunchVerifier.sol";
import { SinjohV3TwapBandPriceGuard } from "../src/profiles/SinjohV3TwapBandPriceGuard.sol";
import { TestBase } from "./TestBase.sol";
import {
    MockERC20,
    MockPonsV1Factory,
    MockV3Factory,
    MockV3Pool,
    MockV3PositionManager,
    MockWETH
} from "./mocks/MockInfrastructure.sol";

contract SinjohPonsV1ProfileTest is TestBase {
    address internal constant CREATOR = address(0xC0FFEE);
    uint256 internal constant SUPPLY = 1_000_000_000e18;

    MockERC20 internal subject;
    MockWETH internal weth;
    MockV3Pool internal pool;
    MockV3Factory internal v3Factory;
    MockV3PositionManager internal positionManager;
    MockPonsV1Factory internal ponsFactory;
    SinjohPonsV1LaunchVerifier internal verifier;
    SinjohV3TwapBandPriceGuard internal guard;

    function setUp() public {
        subject = new MockERC20("Subject", "SUB", 18);
        subject.mint(CREATOR, SUPPLY);
        weth = new MockWETH();
        pool = new MockV3Pool();
        v3Factory = new MockV3Factory();
        v3Factory.setPool(address(pool));
        positionManager = new MockV3PositionManager();
        ponsFactory = new MockPonsV1Factory();
        verifier = new SinjohPonsV1LaunchVerifier(
            address(ponsFactory), address(v3Factory), address(positionManager), address(weth)
        );
        guard = new SinjohV3TwapBandPriceGuard(30 minutes, 200);
        _setRecord(true, CREATOR);
    }

    function testResolvesCanonicalPonsLaunch() public view {
        ISinjohLaunchVerifier.VerifiedLaunch memory launch = verifier.verify(address(subject), "");
        assertEq(launch.creatorAtLaunch, CREATOR);
        assertEq(launch.subject, address(subject));
        assertEq(launch.quoteAsset, address(weth));
        assertEq(launch.pool, address(pool));
        assertEq(launch.launchSupply, SUPPLY);
        assertEq(uint256(launch.poolFee), 3_000);
        assertEq(uint256(uint24(launch.tickSpacing)), 60);
    }

    function testRejectsCounterfeitOrMissingRecord() public {
        _setRecord(false, CREATOR);
        vm.expectRevert(SinjohPonsV1LaunchVerifier.InvalidLaunch.selector);
        verifier.verify(address(subject), "");

        _setRecord(true, address(0));
        vm.expectRevert(SinjohPonsV1LaunchVerifier.InvalidLaunch.selector);
        verifier.verify(address(subject), "");
    }

    function testTwapGuardRequiresBothPricesAndBoundedDeviation() public {
        ISinjohLaunchVerifier.VerifiedLaunch memory launch = verifier.verify(address(subject), "");
        pool.setTicks(-1_100, -1_000);
        guard.validateBelow(launch, -900, true, "");

        pool.setTicks(-800, -1_000);
        vm.expectRevert(SinjohV3TwapBandPriceGuard.BoundaryNotCrossed.selector);
        guard.validateAbove(launch, -900, true, "");

        pool.setTicks(-700, -1_000);
        vm.expectRevert(
            abi.encodeWithSelector(
                SinjohV3TwapBandPriceGuard.ExcessiveDeviation.selector, int24(-700), int24(-1_000)
            )
        );
        guard.validateAbove(launch, -900, true, "");

        pool.setTicks(-850, -850);
        guard.validateAbove(launch, -900, true, "");
    }

    function _setRecord(bool exists, address deployer) private {
        ponsFactory.setLaunch(
            address(subject),
            IPonsV1LaunchFactory.LaunchedToken({
                token: address(subject),
                deployer: deployer,
                pairedToken: address(weth),
                positionManager: address(positionManager),
                positionId: 1,
                dexId: 0,
                launchConfigId: 0,
                restrictionsEndBlock: 0,
                supply: SUPPLY,
                isToken0: address(subject) < address(weth),
                poolFee: 3_000,
                exists: exists,
                initialBuyAmount: 0
            })
        );
    }
}
