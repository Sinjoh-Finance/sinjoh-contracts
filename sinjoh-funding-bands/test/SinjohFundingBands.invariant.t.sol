// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { SinjohFundingBands } from "../src/SinjohFundingBands.sol";
import { ISinjohLaunchVerifier } from "../src/interfaces/ISinjohLaunchVerifier.sol";
import { InvariantTestBase } from "./TestBase.sol";
import {
    MockBandPriceGuard,
    MockERC20,
    MockFundingBandsEscrowState,
    MockLaunchVerifier,
    MockOracle,
    MockPermit2,
    MockV3Factory,
    MockV3Pool,
    MockV3PositionManager,
    MockV4PoolManager,
    MockV4PositionManager,
    MockV4StateView,
    MockWETH
} from "./mocks/MockInfrastructure.sol";

contract FundingBandsHandler {
    SinjohFundingBands public immutable manager;
    MockWETH public immutable weth;
    MockERC20 public immutable subject;

    constructor(SinjohFundingBands manager_, MockWETH weth_, MockERC20 subject_) {
        manager = manager_;
        weth = weth_;
        subject = subject_;
    }

    function sendWeth(uint96 rawAmount) external {
        uint256 owed = manager.proceedsOwed(address(subject), 0, address(weth));
        if (owed == 0) return;
        manager.sendProceeds(address(subject), 0, address(weth), uint256(rawAmount) % owed + 1);
    }

    function sendSubject(uint96 rawAmount) external {
        uint256 owed = manager.proceedsOwed(address(subject), 0, address(subject));
        if (owed == 0) return;
        manager.sendProceeds(address(subject), 0, address(subject), uint256(rawAmount) % owed + 1);
    }

    function sendProtocol(uint96 rawAmount) external {
        uint256 owed = manager.protocolOwed();
        if (owed == 0) return;
        manager.sendProtocolFee(uint256(rawAmount) % owed + 1);
    }

    function donateWeth(uint96 rawAmount) external {
        weth.mint(address(manager), uint256(rawAmount) % 1e24 + 1);
    }
}

contract SinjohFundingBandsInvariantTest is InvariantTestBase {
    address internal constant PROTOCOL = address(0xFEE);
    uint256 internal constant SUPPLY = 1_000_000_000e18;
    uint256 internal constant GROSS_WETH = 100e18;

    MockERC20 internal subject;
    MockWETH internal weth;
    SinjohFundingBands internal manager;
    FundingBandsHandler internal handler;

    function setUp() public {
        vm.chainId(4663);
        vm.warp(1_000_000);
        subject = new MockERC20("Subject", "SUB", 18);
        subject.mint(address(this), SUPPLY);
        weth = new MockWETH();
        MockOracle oracle = new MockOracle(8);
        MockLaunchVerifier verifier = new MockLaunchVerifier();
        MockBandPriceGuard guard = new MockBandPriceGuard();
        MockV3Pool pool = new MockV3Pool();
        MockV3Factory factory = new MockV3Factory();
        factory.setPool(address(pool));
        MockV3PositionManager v3PositionManager = new MockV3PositionManager();
        MockPermit2 permit2 = new MockPermit2();
        MockV4PoolManager v4PoolManager = new MockV4PoolManager();
        MockV4PositionManager v4PositionManager = new MockV4PositionManager(permit2, v4PoolManager);
        MockV4StateView stateView = new MockV4StateView(address(v4PoolManager));
        SinjohFundingBands.ProfileInput[] memory profiles = new SinjohFundingBands.ProfileInput[](1);
        profiles[0] = SinjohFundingBands.ProfileInput({
            verifier: address(verifier), priceGuard: address(guard), hookData: ""
        });
        MockFundingBandsEscrowState launchEscrowState = new MockFundingBandsEscrowState();
        manager = new SinjohFundingBands(
            address(weth),
            address(factory),
            address(v3PositionManager),
            address(v4PositionManager),
            address(stateView),
            address(permit2),
            address(oracle),
            keccak256("fee-router-codehash"),
            PROTOCOL,
            address(launchEscrowState),
            1 hours,
            profiles
        );
        verifier.setLaunch(
            ISinjohLaunchVerifier.VerifiedLaunch({
                creatorAtLaunch: address(this),
                subject: address(subject),
                venue: ISinjohLaunchVerifier.Venue.UNISWAP_V3,
                quoteAsset: address(weth),
                pool: address(pool),
                poolFee: 3_000,
                tickSpacing: 60,
                hooks: address(0),
                poolId: bytes32(0),
                launchSupply: SUPPLY
            })
        );
        bool subjectIsToken0 = address(subject) < address(weth);
        guard.setTicks(
            subjectIsToken0 ? int24(-800_000) : int24(800_000),
            subjectIsToken0 ? int24(-800_000) : int24(800_000)
        );
        SinjohFundingBands.BandConfig[] memory configs = new SinjohFundingBands.BandConfig[](1);
        configs[0] = SinjohFundingBands.BandConfig({
            lowerMarketCapUsdE8: 100_000e8,
            upperMarketCapUsdE8: 200_000e8,
            destination: SinjohFundingBands.Destination.CREATOR,
            feeRouter: address(0)
        });
        manager.create(address(subject), 0, configs, "", "");
        subject.approve(address(manager), 100e18);
        SinjohFundingBands.BandFunding[] memory funding = new SinjohFundingBands.BandFunding[](1);
        funding[0] = SinjohFundingBands.BandFunding({ bandId: 0, amount: 100e18 });
        manager.fund(address(subject), funding, "");
        uint256 tokenId = manager.getBand(address(subject), 0).positionId;
        weth.mint(address(v3PositionManager), GROSS_WETH);
        if (subjectIsToken0) {
            v3PositionManager.setSettlement(tokenId, 1e18, GROSS_WETH);
        } else {
            v3PositionManager.setSettlement(tokenId, GROSS_WETH, 1e18);
        }
        guard.setTicks(
            subjectIsToken0 ? int24(800_000) : int24(-800_000),
            subjectIsToken0 ? int24(800_000) : int24(-800_000)
        );
        manager.settle(address(subject), 0, "");

        handler = new FundingBandsHandler(manager, weth, subject);
        _targetedContracts.push(address(handler));
    }

    function invariantLiabilitiesNeverExceedBalances() public view {
        assertTrue(manager.totalLiability(address(weth)) <= weth.balanceOf(address(manager)));
        assertTrue(manager.totalLiability(address(subject)) <= subject.balanceOf(address(manager)));
    }

    function invariantAggregateLiabilitiesEqualDetailedLedgers() public view {
        assertEq(
            manager.totalLiability(address(weth)),
            manager.protocolOwed() + manager.proceedsOwed(address(subject), 0, address(weth))
        );
        assertEq(
            manager.totalLiability(address(subject)),
            manager.proceedsOwed(address(subject), 0, address(subject))
        );
    }

    function invariantProtocolFeeIsExactlyOnePercentOfGross() public view {
        assertEq(manager.protocolOwed() + weth.balanceOf(PROTOCOL), GROSS_WETH / 100);
    }
}
