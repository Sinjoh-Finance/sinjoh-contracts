// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { SinjohV3EthUsdOracle } from "../src/oracles/SinjohV3EthUsdOracle.sol";
import { TestBase } from "./TestBase.sol";

contract OracleToken {
    uint8 public immutable decimals;

    constructor(uint8 decimals_) {
        decimals = decimals_;
    }
}

contract OracleV3Factory {
    address public pool;
    int24 public tickSpacing = 1;

    function setPool(address value) external {
        pool = value;
    }

    function getPool(address, address, uint24) external view returns (address) {
        return pool;
    }

    function feeAmountTickSpacing(uint24) external view returns (int24) {
        return tickSpacing;
    }
}

contract OracleV3Pool {
    address public immutable factory;
    address public immutable token0;
    address public immutable token1;
    uint24 public immutable fee;
    uint128 public liquidity = 1e18;
    uint160 public sqrtPriceX96 = 1 << 96;
    int24 public spotTick;
    int24 public twapTick;
    uint16 public cardinality = 2;
    bool public unlocked = true;
    bool public failObserve;

    constructor(address factory_, address tokenA, address tokenB, uint24 fee_) {
        factory = factory_;
        token0 = tokenA < tokenB ? tokenA : tokenB;
        token1 = tokenA < tokenB ? tokenB : tokenA;
        fee = fee_;
    }

    function setState(
        int24 spotTick_,
        int24 twapTick_,
        uint128 liquidity_,
        uint16 cardinality_,
        bool unlocked_,
        bool failObserve_
    ) external {
        spotTick = spotTick_;
        twapTick = twapTick_;
        liquidity = liquidity_;
        cardinality = cardinality_;
        unlocked = unlocked_;
        failObserve = failObserve_;
    }

    function setSqrtPriceX96(uint160 value) external {
        sqrtPriceX96 = value;
    }

    function slot0() external view returns (uint160, int24, uint16, uint16, uint16, uint8, bool) {
        return (sqrtPriceX96, spotTick, 0, cardinality, cardinality, 0, unlocked);
    }

    function observe(uint32[] calldata secondsAgos)
        external
        view
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidity)
    {
        require(!failObserve && secondsAgos.length == 2, "OBSERVE");
        tickCumulatives = new int56[](2);
        secondsPerLiquidity = new uint160[](2);
        tickCumulatives[0] = -int56(twapTick) * int56(uint56(secondsAgos[0]));
    }
}

contract SinjohV3EthUsdOracleTest is TestBase {
    uint24 internal constant FEE = 100;
    uint32 internal constant WINDOW = 15 minutes;
    uint128 internal constant MINIMUM_LIQUIDITY = 1e12;

    OracleToken internal weth;
    OracleToken internal usd;
    OracleV3Factory internal factory;
    OracleV3Pool internal pool;
    SinjohV3EthUsdOracle internal oracle;

    function setUp() public {
        vm.chainId(4663);
        vm.warp(1_000_000);
        weth = new OracleToken(18);
        usd = new OracleToken(6);
        factory = new OracleV3Factory();
        pool = new OracleV3Pool(address(factory), address(weth), address(usd), FEE);
        factory.setPool(address(pool));
        oracle = new SinjohV3EthUsdOracle(
            address(factory), address(weth), address(usd), FEE, WINDOW, 100, MINIMUM_LIQUIDITY
        );
    }

    function testReturnsFullWindowTwapAsFreshE8Round() public view {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answered) =
            oracle.latestRoundData();
        assertEq(roundId, block.number);
        assertTrue(answer > 0);
        // Positivity is asserted immediately above.
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(uint256(answer), 1e20);
        assertEq(startedAt, block.timestamp - WINDOW);
        assertEq(updatedAt, block.timestamp);
        assertEq(answered, roundId);
    }

    function testRevertsOnSpotManipulation() public {
        pool.setState(1_000, 0, 1e18, 2, true, false);
        vm.expectRevert(
            abi.encodeWithSelector(
                SinjohV3EthUsdOracle.ExcessivePriceDeviation.selector, uint256(100), uint256(951)
            )
        );
        oracle.latestRoundData();
    }

    function testRevertsWithoutLiquidityHistoryOrUnlockedPool() public {
        pool.setState(0, 0, MINIMUM_LIQUIDITY - 1, 2, true, false);
        vm.expectRevert(SinjohV3EthUsdOracle.OracleNotReady.selector);
        oracle.latestRoundData();

        pool.setState(0, 0, 1e18, 1, true, false);
        vm.expectRevert(SinjohV3EthUsdOracle.OracleNotReady.selector);
        oracle.latestRoundData();

        pool.setState(0, 0, 1e18, 2, false, false);
        vm.expectRevert(SinjohV3EthUsdOracle.OracleNotReady.selector);
        oracle.latestRoundData();

        pool.setState(0, 0, 1e18, 2, true, true);
        vm.expectRevert(SinjohV3EthUsdOracle.OracleNotReady.selector);
        oracle.latestRoundData();

        pool.setState(0, 0, 1e18, 2, true, false);
        pool.setSqrtPriceX96(0);
        vm.expectRevert(SinjohV3EthUsdOracle.OracleNotReady.selector);
        oracle.latestRoundData();
    }

    function testRevertsIfFactoryStopsResolvingPinnedPool() public {
        factory.setPool(address(0));
        vm.expectRevert(SinjohV3EthUsdOracle.DependencyChanged.selector);
        oracle.latestRoundData();
    }

    function testRejectsWrongChainAndUnsafeConfiguration() public {
        vm.chainId(1);
        vm.expectRevert(abi.encodeWithSelector(SinjohV3EthUsdOracle.WrongChain.selector, 1));
        new SinjohV3EthUsdOracle(
            address(factory), address(weth), address(usd), FEE, WINDOW, 100, MINIMUM_LIQUIDITY
        );

        vm.chainId(4663);
        vm.expectRevert(SinjohV3EthUsdOracle.InvalidConfiguration.selector);
        new SinjohV3EthUsdOracle(
            address(factory), address(weth), address(usd), FEE, 0, 100, MINIMUM_LIQUIDITY
        );
    }
}
