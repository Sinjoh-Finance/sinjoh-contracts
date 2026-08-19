// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { TestBase } from "./TestBase.sol";
import {
    IFundingBandsSubjectFloor,
    SinjohPonsV2FundingBandsSubjectPriceGuard
} from "../src/SinjohPonsV2FundingBandsSubjectPriceGuard.sol";
import { SinjohPonsV2SubjectSellAdapter } from "../src/SinjohPonsV2SubjectSellAdapter.sol";
import {
    MockBondingCurve,
    MockERC20,
    MockFeeEscrow,
    MockLaunchFactory,
    MockPoolManager,
    MockWETH
} from "./mocks/PonsV2Mocks.sol";

contract SubjectSellMockMemeHook { }

contract MockFundingBandsSubjectFloor is IFundingBandsSubjectFloor {
    Account private _account;
    mapping(uint8 => Band) private _bands;

    function setAccount(address creator, address subject, uint8 bandCount) external {
        _account = Account({
            creator: creator,
            profileId: 0,
            bandCount: bandCount,
            subjectDecimals: 18,
            ethUsdE8: 4_000e8,
            oracleUpdatedAt: uint48(block.timestamp),
            exists: true,
            launch: VerifiedLaunch({
                creatorAtLaunch: creator,
                subject: subject,
                venue: 1,
                quoteAsset: address(0),
                pool: address(0),
                poolFee: 0,
                tickSpacing: 200,
                hooks: address(0),
                poolId: bytes32(0),
                launchSupply: 1_000_000_000 ether
            })
        });
    }

    function setBand(uint8 bandId, uint256 lowerWethPerSubjectX128, uint8 status) external {
        _bands[bandId].lowerWethPerSubjectX128 = lowerWethPerSubjectX128;
        _bands[bandId].status = status;
    }

    function getAccount(address) external view returns (Account memory) {
        return _account;
    }

    function getBand(address, uint8 bandId) external view returns (Band memory) {
        return _bands[bandId];
    }
}

contract SinjohPonsV2SubjectSellAdapterTest is TestBase {
    uint256 private constant AMOUNT = 0.001 ether;

    MockWETH private weth;
    MockFeeEscrow private escrow;
    MockLaunchFactory private factory;
    SubjectSellMockMemeHook private hook;
    MockPoolManager private poolManager;
    MockERC20 private token;
    MockBondingCurve private curve;
    MockFundingBandsSubjectFloor private bands;
    SinjohPonsV2SubjectSellAdapter private adapter;
    SinjohPonsV2FundingBandsSubjectPriceGuard private guard;

    function setUp() public {
        vm.warp(1_000);
        weth = new MockWETH();
        escrow = new MockFeeEscrow();
        factory = new MockLaunchFactory(address(escrow));
        hook = new SubjectSellMockMemeHook();
        poolManager = new MockPoolManager();
        factory.setGraduationInfrastructure(address(hook), address(poolManager));

        token = new MockERC20("Launch", "LNCH", 18);
        curve = new MockBondingCurve(address(0), address(this), address(this), escrow);
        curve.initialize(address(token));
        factory.registerLaunch(address(token), address(curve), address(0), 0, 200, 2);

        bands = new MockFundingBandsSubjectFloor();
        bands.setAccount(address(this), address(token), 2);
        bands.setBand(0, 1 << 127, 2);
        bands.setBand(1, 1 << 128, 2);

        adapter = new SinjohPonsV2SubjectSellAdapter(
            address(factory),
            address(poolManager),
            address(weth),
            address(factory).codehash,
            address(poolManager).codehash,
            address(weth).codehash
        );
        guard = new SinjohPonsV2FundingBandsSubjectPriceGuard(
            address(factory),
            address(bands),
            address(weth),
            address(factory).codehash,
            address(bands).codehash,
            address(weth).codehash
        );

        token.mint(address(this), 10 ether);
        token.approve(address(adapter), type(uint256).max);
        vm.deal(address(poolManager), 100 ether);
    }

    function test_sellsSubjectThroughTheCanonicalGraduatedPool() public {
        uint256 tokenBefore = token.balanceOf(address(this));
        adapter.swap(address(token), address(weth), AMOUNT, 1, "");

        assertEq(token.balanceOf(address(this)), tokenBefore - AMOUNT);
        assertEq(weth.balanceOf(address(this)), AMOUNT * poolManager.rate());
        assertEq(token.balanceOf(address(adapter)), 0);
        assertEq(weth.balanceOf(address(adapter)), 0);
        assertEq(address(adapter).balance, 0);

        (address currency0, address currency1, uint24 fee, int24 tickSpacing, address hooks) =
            poolManager.lastKey();
        assertEq(currency0, address(0));
        assertEq(currency1, address(token));
        assertEq(uint256(fee), 0);
        assertEq(uint256(int256(tickSpacing)), 200);
        assertEq(hooks, address(hook));
        assertTrue(!poolManager.lastZeroForOne());
        assertEq(uint256(-poolManager.lastAmountSpecified()), AMOUNT);
    }

    function test_partialFillAndInsufficientOutputFailAtomically() public {
        poolManager.setSpendOverride(AMOUNT / 2);
        vm.expectRevert(SinjohPonsV2SubjectSellAdapter.InvalidSwapDelta.selector);
        adapter.swap(address(token), address(weth), AMOUNT, 1, "");

        poolManager.setSpendOverride(0);
        poolManager.setOutputOverride(5);
        vm.expectRevert(
            abi.encodeWithSelector(
                SinjohPonsV2SubjectSellAdapter.InsufficientOutput.selector, uint256(6), uint256(5)
            )
        );
        adapter.swap(address(token), address(weth), AMOUNT, 6, "");
    }

    function test_rejectsWrongPhasePairAndMalformedRoute() public {
        factory.setPhase(address(token), 0);
        vm.expectRevert(abi.encodeWithSelector(SinjohPonsV2SubjectSellAdapter.NoMarket.selector, 0));
        adapter.swap(address(token), address(weth), AMOUNT, 1, "");

        factory.setPhase(address(token), 2);
        vm.expectRevert(SinjohPonsV2SubjectSellAdapter.InvalidRoute.selector);
        adapter.swap(address(token), address(weth), AMOUNT, 1, hex"01");

        MockERC20 pair = new MockERC20("Pair", "PAIR", 18);
        MockERC20 paired = new MockERC20("Paired", "PAIRED", 18);
        factory.registerLaunch(address(paired), address(curve), address(pair), 0, 200, 2);
        paired.mint(address(this), AMOUNT);
        paired.approve(address(adapter), AMOUNT);
        vm.expectRevert(
            abi.encodeWithSelector(
                SinjohPonsV2SubjectSellAdapter.UnsupportedPair.selector, address(pair)
            )
        );
        adapter.swap(address(paired), address(weth), AMOUNT, 1, "");
    }

    function test_guardUsesHighestSettledBandLowerBoundaryWithFivePercentMargin() public view {
        (uint256 minimum, uint48 validUntil) = guard.minimumOutput(
            address(token), address(token), address(weth), 1 ether, keccak256(""), ""
        );
        assertEq(minimum, 0.95 ether);
        assertEq(uint256(validUntil), uint256(type(uint48).max));
    }

    function test_guardRequiresASettledBandAndExactFundingBandsAccount() public {
        bands.setBand(0, 1 << 127, 1);
        bands.setBand(1, 1 << 128, 1);
        vm.expectRevert(SinjohPonsV2FundingBandsSubjectPriceGuard.NoSettledBand.selector);
        guard.minimumOutput(
            address(token), address(token), address(weth), 1 ether, keccak256(""), ""
        );

        MockERC20 other = new MockERC20("Other", "OTHER", 18);
        vm.expectRevert(
            SinjohPonsV2FundingBandsSubjectPriceGuard.InvalidFundingBandsAccount.selector
        );
        guard.minimumOutput(
            address(other), address(other), address(weth), 1 ether, keccak256(""), ""
        );
    }
}
