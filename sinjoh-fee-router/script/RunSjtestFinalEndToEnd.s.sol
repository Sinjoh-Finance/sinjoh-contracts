// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface VmSjtestFinalEndToEnd {
    function addr(uint256 privateKey) external returns (address);
    function envAddress(string calldata name) external returns (address);
    function envUint(string calldata name) external returns (uint256);
    function startBroadcast(uint256 privateKey) external;
    function stopBroadcast() external;
}

interface IERC20Final {
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface ISwapAdapterFinal {
    function swap(
        address assetIn,
        address assetOut,
        uint256 amountIn,
        uint256 minimumAmountOut,
        bytes calldata routeData
    ) external payable;
}

interface IPriceGuardFinal {
    function minimumOutput(
        address subject,
        address assetIn,
        address assetOut,
        uint256 amountIn,
        bytes32 routeHash,
        bytes calldata guardData
    ) external view returns (uint256 minOut, uint48 validUntil);
}

interface IPonsLockerFinal {
    function setFeeRedirect(address subject, address redirect) external;
    function collectFees(address subject) external;
    function feeRedirects(address subject) external view returns (address);
}

interface IPonsAdapterFinal {
    function forward(address asset) external returns (uint256 amount);
}

interface IFeeRouterFinal {
    function sync(address asset) external returns (uint256 gross, uint256 fee);
    function processBucket(
        uint8 bucketId,
        address inputAsset,
        uint256 amountIn,
        uint256 callerMinOut,
        bytes calldata guardData
    ) external returns (uint256 amountOut);
    function sendProtocolFee(address asset, uint256 amount) external;
    function sendWallet(address recipient, address asset, uint256 amount) external;
    function fundSink(uint8 bucketId, uint8 allocationId, uint256 amount) external;
    function protocolOwed(address asset) external view returns (uint256);
    function bucketInputOwed(uint8 bucketId, address asset) external view returns (uint256);
    function walletOwed(address recipient, address asset) external view returns (uint256);
    function sinkOwed(uint16 allocationKey, address asset) external view returns (uint256);
    function totalLiability(address asset) external view returns (uint256);
}

interface ILiquidityManagerFinal {
    function accountId(address funder, address subject) external pure returns (bytes32);
    function accountFinancials(bytes32 id)
        external
        view
        returns (
            uint256 pendingQuote,
            uint256 pendingSubject,
            uint256 positionId,
            uint48 lastMintAt,
            bool configured
        );
    function mint(
        address funder,
        address subject,
        uint256 notional,
        uint256 callerMinOut,
        bytes calldata guardData
    ) external returns (uint256 tokenId, uint128 liquidity);
    function collect(address funder, address subject) external;
    function protocolOwed(address asset) external view returns (uint256);
    function sendProtocolFee(address asset, uint256 amount) external;
}

interface IAirdropFinal {
    function accountId(address funder, address subject, address asset)
        external
        pure
        returns (bytes32);
    function accountFinancials(bytes32 id)
        external
        view
        returns (
            uint256 totalFunded,
            uint256 totalPaid,
            uint256 latestRootSum,
            uint64 latestEpochId,
            uint64 latestSnapshotBlock
        );
    function protocolOwed(address asset) external view returns (uint256);
    function sendProtocolFee(address asset, uint256 amount) external;
}

interface IRevenueCollectorFinal {
    function processor() external view returns (address);
    function forwardAll(address asset) external;
}

contract RunSjtestFinalEndToEnd {
    address internal constant EXPECTED_DEPLOYER = 0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49;
    address internal constant SJTEST = 0x690caA9c7FF95e01d470Ec60Ed6aD57d794a38F5;
    address internal constant PONS_WETH = 0x37E402B8081eFcE1D82A09a066512278006e4691;
    address internal constant PONS_LOCKER = 0x9E18AFba6eADDC1A00Edd35FB7AB6C5CD1E1dEE0;
    address internal constant GOVERNANCE = 0x39E2f5eFdFd808F26B98979a06BA11ea82E1C85f;

    uint256 internal constant WETH_SWAP_AMOUNT = 1_000_000_000_000;
    uint256 internal constant SUBJECT_SWAP_AMOUNT = 1_000 ether;
    uint256 internal constant POST_MINT_WETH_SWAP_AMOUNT = 10_000_000_000;
    uint256 internal constant POST_MINT_SUBJECT_SWAP_AMOUNT = 10 ether;

    VmSjtestFinalEndToEnd internal constant vm =
        VmSjtestFinalEndToEnd(address(uint160(uint256(keccak256("hevm cheat code")))));

    error WrongEnvironment();
    error MissingFees();
    error InvariantViolation();

    function run()
        external
        returns (
            uint256 positionId,
            uint128 liquidity,
            bytes32 airdropAccount,
            uint256 airdropAmount
        )
    {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address forwardAdapter = vm.envAddress("FORWARD_ADAPTER");
        address reverseAdapter = vm.envAddress("REVERSE_ADAPTER");
        address bidirectionalGuard = vm.envAddress("BIDIRECTIONAL_GUARD");
        address routerAddress = vm.envAddress("ROUTER");
        address ponsAdapter = vm.envAddress("PONS_ADAPTER");
        address airdropDistributor = vm.envAddress("AIRDROP_DISTRIBUTOR");
        address v3Manager = vm.envAddress("V3_MANAGER");
        address revenueCollector = vm.envAddress("REVENUE_COLLECTOR");
        if (block.chainid != 46_630 || vm.addr(deployerKey) != EXPECTED_DEPLOYER) {
            revert WrongEnvironment();
        }
        if (
            forwardAdapter.code.length == 0 || reverseAdapter.code.length == 0
                || bidirectionalGuard.code.length == 0 || routerAddress.code.length == 0
                || ponsAdapter.code.length == 0 || airdropDistributor.code.length == 0
                || v3Manager.code.length == 0 || revenueCollector.code.length == 0
        ) revert WrongEnvironment();
        if (IRevenueCollectorFinal(revenueCollector).processor() != GOVERNANCE) {
            revert WrongEnvironment();
        }

        bytes memory routeData = abi.encode(uint160(0));
        (uint256 reverseMinimum,) = IPriceGuardFinal(bidirectionalGuard)
            .minimumOutput(SJTEST, SJTEST, PONS_WETH, SUBJECT_SWAP_AMOUNT, keccak256(routeData), "");
        (uint256 postMintReverseMinimum,) = IPriceGuardFinal(bidirectionalGuard)
            .minimumOutput(
                SJTEST, SJTEST, PONS_WETH, POST_MINT_SUBJECT_SWAP_AMOUNT, keccak256(routeData), ""
            );

        vm.startBroadcast(deployerKey);
        IPonsLockerFinal(PONS_LOCKER).setFeeRedirect(SJTEST, ponsAdapter);
        if (IPonsLockerFinal(PONS_LOCKER).feeRedirects(SJTEST) != ponsAdapter) {
            revert InvariantViolation();
        }

        IERC20Final(PONS_WETH).approve(forwardAdapter, WETH_SWAP_AMOUNT);
        ISwapAdapterFinal(forwardAdapter).swap(PONS_WETH, SJTEST, WETH_SWAP_AMOUNT, 1, routeData);
        IERC20Final(SJTEST).approve(reverseAdapter, SUBJECT_SWAP_AMOUNT);
        ISwapAdapterFinal(reverseAdapter)
            .swap(SJTEST, PONS_WETH, SUBJECT_SWAP_AMOUNT, reverseMinimum, routeData);

        IPonsLockerFinal(PONS_LOCKER).collectFees(SJTEST);
        uint256 forwardedSubject = IPonsAdapterFinal(ponsAdapter).forward(SJTEST);
        uint256 forwardedWeth = IPonsAdapterFinal(ponsAdapter).forward(PONS_WETH);
        if (forwardedSubject == 0 || forwardedWeth == 0) revert MissingFees();

        IFeeRouterFinal router = IFeeRouterFinal(routerAddress);
        router.sync(SJTEST);
        router.sync(PONS_WETH);
        uint256 pendingSubject = router.bucketInputOwed(0, SJTEST);
        uint256 pendingWeth = router.bucketInputOwed(0, PONS_WETH);
        if (pendingSubject == 0 || pendingWeth == 0) revert MissingFees();

        router.processBucket(0, SJTEST, pendingSubject, 1, "");
        router.processBucket(0, PONS_WETH, pendingWeth, 1, "");

        uint256 subjectProtocol = router.protocolOwed(SJTEST);
        uint256 wethProtocol = router.protocolOwed(PONS_WETH);
        if (subjectProtocol != 0) router.sendProtocolFee(SJTEST, subjectProtocol);
        if (wethProtocol != 0) router.sendProtocolFee(PONS_WETH, wethProtocol);

        uint256 treasury = router.walletOwed(EXPECTED_DEPLOYER, PONS_WETH);
        airdropAmount = router.sinkOwed(1, PONS_WETH);
        uint256 liquidityAmount = router.sinkOwed(2, PONS_WETH);
        if (treasury == 0 || airdropAmount == 0 || liquidityAmount == 0) revert MissingFees();

        router.sendWallet(EXPECTED_DEPLOYER, PONS_WETH, treasury);
        router.fundSink(0, 1, airdropAmount);
        router.fundSink(0, 2, liquidityAmount);

        ILiquidityManagerFinal manager = ILiquidityManagerFinal(v3Manager);
        bytes32 liquidityAccount = manager.accountId(routerAddress, SJTEST);
        (uint256 pendingQuote,,,, bool configured) = manager.accountFinancials(liquidityAccount);
        if (!configured || pendingQuote != liquidityAmount) revert InvariantViolation();
        (positionId, liquidity) = manager.mint(routerAddress, SJTEST, pendingQuote, 1, "");

        IAirdropFinal distributor = IAirdropFinal(airdropDistributor);
        airdropAccount = distributor.accountId(routerAddress, SJTEST, PONS_WETH);
        (uint256 totalFunded,,,,) = distributor.accountFinancials(airdropAccount);
        uint256 airdropProtocol = distributor.protocolOwed(PONS_WETH);
        uint256 expectedAirdropProtocol = airdropAmount / 100;
        if (
            totalFunded != airdropAmount - expectedAirdropProtocol
                || airdropProtocol != expectedAirdropProtocol
        ) revert InvariantViolation();
        distributor.sendProtocolFee(PONS_WETH, airdropProtocol);

        IERC20Final(PONS_WETH).approve(forwardAdapter, POST_MINT_WETH_SWAP_AMOUNT);
        ISwapAdapterFinal(forwardAdapter)
            .swap(PONS_WETH, SJTEST, POST_MINT_WETH_SWAP_AMOUNT, 1, routeData);
        IERC20Final(SJTEST).approve(reverseAdapter, POST_MINT_SUBJECT_SWAP_AMOUNT);
        ISwapAdapterFinal(reverseAdapter)
            .swap(
                SJTEST, PONS_WETH, POST_MINT_SUBJECT_SWAP_AMOUNT, postMintReverseMinimum, routeData
            );
        manager.collect(routerAddress, SJTEST);
        uint256 managerWethProtocol = manager.protocolOwed(PONS_WETH);
        uint256 managerSubjectProtocol = manager.protocolOwed(SJTEST);
        if (managerWethProtocol == 0 && managerSubjectProtocol == 0) revert MissingFees();
        if (managerWethProtocol != 0) {
            manager.sendProtocolFee(PONS_WETH, managerWethProtocol);
        }
        if (managerSubjectProtocol != 0) {
            manager.sendProtocolFee(SJTEST, managerSubjectProtocol);
        }

        uint256 collectorWeth = IERC20Final(PONS_WETH).balanceOf(revenueCollector);
        uint256 collectorSubject = IERC20Final(SJTEST).balanceOf(revenueCollector);
        if (collectorWeth == 0 || collectorSubject == 0) revert MissingFees();
        uint256 governanceWethBefore = IERC20Final(PONS_WETH).balanceOf(GOVERNANCE);
        uint256 governanceSubjectBefore = IERC20Final(SJTEST).balanceOf(GOVERNANCE);
        IRevenueCollectorFinal(revenueCollector).forwardAll(PONS_WETH);
        IRevenueCollectorFinal(revenueCollector).forwardAll(SJTEST);
        if (
            IERC20Final(PONS_WETH).balanceOf(GOVERNANCE) - governanceWethBefore != collectorWeth
                || IERC20Final(SJTEST).balanceOf(GOVERNANCE) - governanceSubjectBefore
                    != collectorSubject
        ) revert InvariantViolation();
        vm.stopBroadcast();

        if (
            positionId == 0 || liquidity == 0 || router.totalLiability(SJTEST) != 0
                || router.totalLiability(PONS_WETH) != 0
        ) revert InvariantViolation();
    }
}
