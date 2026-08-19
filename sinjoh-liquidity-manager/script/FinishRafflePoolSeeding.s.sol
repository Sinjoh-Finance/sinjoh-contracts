// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

interface VmSeed {
    function startBroadcast() external;
    function stopBroadcast() external;
}

interface ISeedGuard {
    function prime(address tokenA, address tokenB, uint16 cardinality) external returns (address);
    function poolFor(address tokenA, address tokenB) external view returns (address);
}

interface ISeedPool {
    function slot0() external view returns (uint160, int24, uint16, uint16, uint16, uint8, bool);
}

interface ISeedWeth {
    function deposit() external payable;
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface ISeedAdapter {
    function swap(
        address assetIn,
        address assetOut,
        uint256 amountIn,
        uint256 minAmountOut,
        bytes calldata routeData
    ) external payable;
}

/// @notice Finishes what the interrupted guards broadcast did not: primes and
/// seeds the three deficient pools, using the ALREADY-DEPLOYED guards. Deploys
/// nothing.
contract FinishRafflePoolSeeding {
    VmSeed internal constant vm = VmSeed(address(uint160(uint256(keccak256("hevm cheat code")))));
    address internal constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;
    address internal constant ADAPTER = 0xc9F600ebaf9EE1F4a24568D2e4Af9E8df1e07D7B;
    address internal constant GUARD_500 = 0xDad51edC925D4CCd46c1229763F40d1F32c7480C;
    address internal constant GUARD_10000 = 0xf81d21e0b51A7DD815f44682B63b7e732E0b4803;
    /// @dev 500 observation slots: ample 300-second retention at these pools'
    /// trade rates, a third of the fleet-standard capacity cost. Priming is
    /// monotonic and permissionless, so anyone can raise it later.
    uint16 internal constant CARDINALITY = 500;

    function run() external {
        vm.startBroadcast();
        // Priming alone is enough for actively traded pools: capacity is the
        // only thing they lack, and their own organic swaps write the history
        // once it exists. Only rarely-traded RDDT gets a seed swap to write
        // its first observation.
        _finish(GUARD_10000, 0x05b37Fb53A299a1b874A619e1c4C404D52C36F4C, 10_000, 0.0005 ether); // RDDT
        _finish(GUARD_500, 0x2e0847E8910a9732eB3fb1bb4b70a580ADAD4FE3, 500, 0); // GOOGL: prime only
        _finish(GUARD_500, 0xaF3D76f1834A1d425780943C99Ea8A608f8a93f9, 500, 0); // AAPL: prime only
        vm.stopBroadcast();
    }

    function _finish(address guard, address asset, uint24 fee, uint256 startAmount) private {
        // Deliberately no mid-flight verification: a local simulation shares
        // one timestamp across every transaction, and an actively trading
        // pool skips same-timestamp oracle writes, so a self-checking loop
        // reads its own seed as failed and escalates into money that is not
        // there. On chain each transaction lands in a later block and the
        // write happens. The measured single seed per pool is emitted, and
        // `PreflightStockRoutes` is the gate that verifies the outcome.
        address pool = ISeedGuard(guard).poolFor(WETH, asset);
        (,,, uint16 card, uint16 next,,) = ISeedPool(pool).slot0();
        if (next < CARDINALITY) ISeedGuard(guard).prime(WETH, asset, CARDINALITY);
        if (card >= 2 || startAmount == 0) return;
        ISeedWeth(WETH).deposit{ value: startAmount }();
        ISeedWeth(WETH).approve(ADAPTER, startAmount);
        ISeedAdapter(ADAPTER).swap(WETH, asset, startAmount, 0, abi.encode(fee));
    }
}
