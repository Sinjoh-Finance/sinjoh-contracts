// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {
    SinjohFlapBuybackAdapter,
    SinjohFlapBuybackPriceGuard
} from "../src/SinjohFlapBuybackAdapter.sol";
import {
    IFlapV2Router,
    SinjohFlapV2LiquidityManager
} from "../src/SinjohFlapV2LiquidityManager.sol";

interface VmSinjohFlapExecutionInfrastructure {
    function envUint(string calldata name) external view returns (uint256);
    function addr(uint256 privateKey) external pure returns (address);
    function startBroadcast(uint256 privateKey) external;
    function stopBroadcast() external;
}

/// @notice Deploys only shared Flap routing dependencies. It cannot create a
/// router, adapter clone, liquidity position, or token.
contract DeploySinjohFlapExecutionInfrastructure {
    error WrongChain(uint256 actual);
    error WrongDeployer(address actual);
    error DependencyMismatch(address dependency, bytes32 expected, bytes32 actual);
    error PortalConfigurationMismatch(bytes32 expected, bytes32 actual);
    error DeploymentIncomplete();

    event SinjohFlapExecutionInfrastructureDeployed(
        address indexed buybackAdapter,
        address indexed buybackPriceGuard,
        address indexed liquidityManager,
        address quoteSigner,
        bytes32 buybackAdapterCodehash,
        bytes32 buybackPriceGuardCodehash,
        bytes32 liquidityManagerCodehash
    );

    uint256 private constant CHAIN_ID = 4_663;
    address private constant EXPECTED_DEPLOYER = 0x1A0925c9651836281FFe3EBD1D99d5D9739967EA;
    address private constant QUOTE_SIGNER = 0xd89fB916dD031Da9b0A32e820307c2d41a7dDe09;

    address private constant PORTAL = 0x26605f322f7fF986f381bB9A6e3f5DAb0bEaEb09;
    address private constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;
    address private constant V2_FACTORY = 0x8bcEaA40B9AcdfAedF85AdF4FF01F5Ad6517937f;
    address private constant V2_ROUTER = 0x89e5DB8B5aA49aA85AC63f691524311AEB649eba;

    bytes32 private constant PORTAL_CODEHASH =
        0xcecb292d9c022858199c9348abf0d5836f9ea4dab5cf03710e1dcf41fd9a4c35;
    bytes32 private constant WETH_CODEHASH =
        0x5706be52f64875fee65a2cec0d80e47a23d8793cbe85d214b48445e2d05f5353;
    bytes32 private constant V2_FACTORY_CODEHASH =
        0xbab145d02e7005f0d84c6c1639d39b799b0ea16df99ebbdaf5a14d9da820b4e0;
    bytes32 private constant V2_ROUTER_CODEHASH =
        0xbd55ea26b2f8d42a8ff151511cef92a326a9817686899fe96a8a8f81ee7fc55e;
    bytes32 private constant REVIEWED_PORTAL_CONFIG_HASH =
        0xb789978b5db7d4d20b60a96ac19d9b9f4a667f2182a2d833a3dfb02459fbb713;

    VmSinjohFlapExecutionInfrastructure private constant vm = VmSinjohFlapExecutionInfrastructure(
        address(uint160(uint256(keccak256("hevm cheat code"))))
    );

    struct Deployment {
        address buybackAdapter;
        address buybackPriceGuard;
        address liquidityManager;
    }

    function run() external returns (Deployment memory deployed) {
        if (block.chainid != CHAIN_ID) revert WrongChain(block.chainid);
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        if (deployer != EXPECTED_DEPLOYER) revert WrongDeployer(deployer);
        _assertDependencies();

        vm.startBroadcast(deployerKey);
        SinjohFlapBuybackAdapter buybackAdapter =
            new SinjohFlapBuybackAdapter(PORTAL, WETH, PORTAL_CODEHASH, WETH_CODEHASH);
        SinjohFlapBuybackPriceGuard buybackPriceGuard = new SinjohFlapBuybackPriceGuard(
            PORTAL, WETH, PORTAL_CODEHASH, WETH_CODEHASH, QUOTE_SIGNER, 500
        );
        SinjohFlapV2LiquidityManager liquidityManager = new SinjohFlapV2LiquidityManager(
            PORTAL,
            WETH,
            V2_FACTORY,
            V2_ROUTER,
            PORTAL_CODEHASH,
            WETH_CODEHASH,
            REVIEWED_PORTAL_CONFIG_HASH,
            V2_FACTORY_CODEHASH,
            V2_ROUTER_CODEHASH,
            QUOTE_SIGNER,
            5_000,
            500,
            1,
            10 ether
        );
        vm.stopBroadcast();

        deployed = Deployment(
            address(buybackAdapter), address(buybackPriceGuard), address(liquidityManager)
        );
        _assertDeployment(deployed);
        emit SinjohFlapExecutionInfrastructureDeployed(
            deployed.buybackAdapter,
            deployed.buybackPriceGuard,
            deployed.liquidityManager,
            QUOTE_SIGNER,
            deployed.buybackAdapter.codehash,
            deployed.buybackPriceGuard.codehash,
            deployed.liquidityManager.codehash
        );
    }

    function _assertDependencies() private view {
        _assertCodehash(PORTAL, PORTAL_CODEHASH);
        _assertCodehash(WETH, WETH_CODEHASH);
        _assertCodehash(V2_FACTORY, V2_FACTORY_CODEHASH);
        _assertCodehash(V2_ROUTER, V2_ROUTER_CODEHASH);
        bytes32 current = _currentPortalConfigHash();
        if (current != REVIEWED_PORTAL_CONFIG_HASH) {
            revert PortalConfigurationMismatch(REVIEWED_PORTAL_CONFIG_HASH, current);
        }
        if (
            IFlapV2Router(V2_ROUTER).factory() != V2_FACTORY
                || IFlapV2Router(V2_ROUTER).WETH() != WETH
        ) revert DeploymentIncomplete();
    }

    function _assertDeployment(Deployment memory deployed) private view {
        if (
            deployed.buybackAdapter.code.length == 0 || deployed.buybackPriceGuard.code.length == 0
                || deployed.liquidityManager.code.length == 0
        ) revert DeploymentIncomplete();
        SinjohFlapBuybackAdapter buyback =
            SinjohFlapBuybackAdapter(payable(deployed.buybackAdapter));
        SinjohFlapBuybackPriceGuard guard = SinjohFlapBuybackPriceGuard(deployed.buybackPriceGuard);
        SinjohFlapV2LiquidityManager manager =
            SinjohFlapV2LiquidityManager(payable(deployed.liquidityManager));
        if (
            buyback.portal() != PORTAL || buyback.weth() != WETH
                || buyback.portalCodehash() != PORTAL_CODEHASH
                || buyback.wethCodehash() != WETH_CODEHASH || guard.portal() != PORTAL
                || guard.weth() != WETH || guard.quoteSigner() != QUOTE_SIGNER
                || guard.maxSlippageBps() != 500 || manager.portal() != PORTAL
                || manager.weth() != WETH || manager.v2Factory() != V2_FACTORY
                || manager.v2Router() != V2_ROUTER || manager.quoteSigner() != QUOTE_SIGNER
                || manager.quoteSwapBps() != 5_000 || manager.maxSlippageBps() != 500
                || manager.minNotional() != 1 || manager.maxNotional() != 10 ether
        ) revert DeploymentIncomplete();
    }

    function _currentPortalConfigHash() private view returns (bytes32) {
        (bool versionSuccess, bytes memory versionData) =
            PORTAL.staticcall(abi.encodeWithSignature("version()"));
        (bool configSuccess, bytes memory configData) = PORTAL.staticcall(
            abi.encodeWithSignature("getQuoteTokenConfiguration(address)", address(0))
        );
        if (!versionSuccess || !configSuccess || versionData.length == 0 || configData.length == 0)
        {
            revert DeploymentIncomplete();
        }
        return keccak256(abi.encode(PORTAL.codehash, keccak256(versionData), keccak256(configData)));
    }

    function _assertCodehash(address target, bytes32 expected) private view {
        bytes32 actual = target.codehash;
        if (actual != expected) revert DependencyMismatch(target, expected, actual);
    }
}
