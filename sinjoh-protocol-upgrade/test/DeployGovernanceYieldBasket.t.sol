// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { SinjohJoint } from "@sinjoh-treasury/SinjohJoint.sol";
import { SinjohTreasuryVault } from "@sinjoh-treasury/SinjohTreasuryVault.sol";
import { IGovernanceController } from "../src/interfaces/IGovernanceController.sol";
import { ERC4626YieldAdapter } from "../src/adapters/ERC4626YieldAdapter.sol";
import { YieldBasket } from "../src/YieldBasket.sol";
import { DeployGovernanceYieldBasket } from "../script/DeployGovernanceYieldBasket.s.sol";
import { YieldDeploymentManifest } from "../script/YieldDeploymentManifest.sol";
import { YieldDeploymentTypes } from "../script/YieldDeploymentTypes.sol";
import { YieldDeploymentValidator } from "../script/YieldDeploymentValidator.sol";
import { TestBase } from "./TestBase.sol";
import { MockERC20, MockERC4626, MockFundable, MockYieldAdapter } from "./mocks/Mocks.sol";

contract DeployGovernanceYieldBasketHarness is DeployGovernanceYieldBasket {
    function parseForTest(string memory json)
        external
        pure
        returns (YieldDeploymentTypes.Parameters memory)
    {
        return YieldDeploymentManifest.parse(json);
    }

    function deployForTest(
        YieldDeploymentTypes.Parameters memory parameters,
        bytes32 manifestHash,
        address deployer
    ) external returns (Deployment memory deployment) {
        YieldDeploymentValidator.validate(parameters, deployer);
        deployment = _deploy(parameters, manifestHash);
        _verify(parameters, deployment);
    }
}

contract DeployGovernanceYieldBasketTest is TestBase {
    uint256 private constant MAINNET_CHAIN_ID = 4_663;
    address private constant GUARDIAN = address(0xBEEF);
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant CAROL = address(0xCA401);

    DeployGovernanceYieldBasketHarness private script;
    MockERC20 private asset;
    MockERC20 private reward;
    MockFundable private sink;
    MockYieldAdapter private adapter;
    SinjohJoint private joint;
    SinjohTreasuryVault private treasury;

    function setUp() public {
        vm.chainId(MAINNET_CHAIN_ID);
        script = new DeployGovernanceYieldBasketHarness();
        asset = new MockERC20();
        reward = new MockERC20();
        sink = new MockFundable();
        adapter = new MockYieldAdapter(address(asset), reward);
        adapter.setBasket(vm.computeCreateAddress(address(script), 2));
        address[3] memory signers = [ALICE, BOB, CAROL];
        joint = new SinjohJoint(signers, 30 days);
        treasury = new SinjohTreasuryVault(address(joint), 3 days, address(0), 0);
    }

    function testDeploysAndGeneratesJointConfigurationCalls() public {
        DeployGovernanceYieldBasket.Deployment memory deployment = script.deployForTest(
            _jointParameters(), keccak256("reviewed-yield-manifest"), address(this)
        );

        assertEq(deployment.controller.authority(), address(joint));
        assertEq(
            uint256(deployment.controller.mode()), uint256(IGovernanceController.Mode.MULTISIG)
        );
        assertEq(deployment.basket.treasury(), address(treasury));
        assertEq(deployment.basket.emergencyGuardian(), GUARDIAN);
        assertEq(address(deployment.basket.depositAsset()), address(asset));
        assertEq(deployment.configurationTargets.length, 2);
        assertEq(deployment.configurationCalldatas.length, 2);

        adapter.setBasket(address(deployment.basket));
        _jointExecute(deployment.configurationTargets[0], deployment.configurationCalldatas[0]);
        _jointExecute(deployment.configurationTargets[1], deployment.configurationCalldatas[1]);
        YieldBasket.AdapterConfig memory config =
            deployment.basket.getAdapterConfig(address(adapter));
        assertEq(config.allocationLimitBps, 5_000);
        assertEq(config.distributionInterval, 30 minutes);
        assertEq(
            deployment.basket.getAdapterRewardRoute(address(adapter), address(reward)).distributor,
            address(sink)
        );
    }

    function testPredeployedERC4626AdapterBindsToManifestBasketAddress() public {
        MockERC4626 erc4626Vault = new MockERC4626(IERC20(address(asset)));
        address expectedBasket = vm.computeCreateAddress(address(script), 2);
        ERC4626YieldAdapter erc4626Adapter = new ERC4626YieldAdapter(expectedBasket, erc4626Vault);
        YieldDeploymentTypes.Parameters memory parameters = _jointParameters();
        parameters.adapters[0].adapter = address(erc4626Adapter);
        parameters.adapters[0].runtimeCodeHash = address(erc4626Adapter).codehash;
        parameters.rewardRoutes = new YieldDeploymentTypes.RewardRoutePlan[](0);

        DeployGovernanceYieldBasket.Deployment memory deployment =
            script.deployForTest(parameters, keccak256("erc4626-manifest"), address(this));
        assertEq(address(deployment.basket), expectedBasket);
        assertEq(erc4626Adapter.basket(), expectedBasket);
        _jointExecute(deployment.configurationTargets[0], deployment.configurationCalldatas[0]);
        assertTrue(deployment.basket.approvedAdapter(address(erc4626Adapter)));
    }

    function testRejectsWrongChainBeforeDeployment() public {
        vm.chainId(MAINNET_CHAIN_ID + 1);
        vm.expectPartialRevert(YieldDeploymentValidator.WrongChain.selector);
        script.deployForTest(_jointParameters(), bytes32(0), address(this));
    }

    function testParsesAdapterAndRewardRouteManifest() public view {
        string memory json = string.concat(
            '{"schemaVersion":1,"chainId":4663,',
            '"expectedDeployer":"0x0000000000000000000000000000000000000001",',
            '"governanceMode":"MULTISIG",',
            '"authority":"0x0000000000000000000000000000000000000002",',
            '"authorityRuntimeCodeHash":"0x0000000000000000000000000000000000000000000000000000000000000003",',
            '"tokenGovernor":"0x0000000000000000000000000000000000000000",',
            '"emergencyGuardian":"0x0000000000000000000000000000000000000004",',
            '"treasury":"0x0000000000000000000000000000000000000005",',
            '"treasuryRuntimeCodeHash":"0x0000000000000000000000000000000000000000000000000000000000000006",',
            '"treasuryGovernorHandoffDelay":259200,',
            '"treasuryRecoveryAddress":"0x0000000000000000000000000000000000000000",',
            '"treasuryRecoveryInactivityPeriod":0,',
            '"depositAsset":"0x0000000000000000000000000000000000000007",',
            '"depositAssetRuntimeCodeHash":"0x0000000000000000000000000000000000000000000000000000000000000008",',
            '"expectedBasket":"0x000000000000000000000000000000000000000f",',
            '"adapterCount":1,"adapters":[{',
            '"adapter":"0x0000000000000000000000000000000000000009",',
            '"runtimeCodeHash":"0x000000000000000000000000000000000000000000000000000000000000000a",',
            '"allocationLimitBps":5000,"distributionInterval":1800}],',
            '"rewardRouteCount":1,"rewardRoutes":[{',
            '"adapter":"0x0000000000000000000000000000000000000009",',
            '"rewardToken":"0x000000000000000000000000000000000000000b",',
            '"rewardTokenRuntimeCodeHash":"0x000000000000000000000000000000000000000000000000000000000000000c",',
            '"distributor":"0x000000000000000000000000000000000000000d",',
            '"distributorRuntimeCodeHash":"0x000000000000000000000000000000000000000000000000000000000000000e",',
            '"distributionConfig":"0x1234"}]}'
        );
        YieldDeploymentTypes.Parameters memory parameters = script.parseForTest(json);
        assertEq(parameters.chainId, MAINNET_CHAIN_ID);
        assertEq(parameters.adapters.length, 1);
        assertEq(parameters.adapters[0].allocationLimitBps, 5_000);
        assertEq(parameters.rewardRoutes.length, 1);
        assertTrue(keccak256(parameters.rewardRoutes[0].distributionConfig) == keccak256(hex"1234"));
    }

    function testRejectsUnexpectedDeployer() public {
        vm.expectPartialRevert(YieldDeploymentValidator.WrongDeployer.selector);
        script.deployForTest(_jointParameters(), bytes32(0), address(0xBAD));
    }

    function testRejectsWrongAdapterRuntimeHash() public {
        YieldDeploymentTypes.Parameters memory parameters = _jointParameters();
        parameters.adapters[0].runtimeCodeHash = bytes32(uint256(1));
        vm.expectPartialRevert(YieldDeploymentValidator.RuntimeCodeHashMismatch.selector);
        script.deployForTest(parameters, bytes32(0), address(this));
    }

    function testRejectsAllocationCapOutsideBasketBounds() public {
        YieldDeploymentTypes.Parameters memory parameters = _jointParameters();
        parameters.adapters[0].allocationLimitBps = 0;
        vm.expectPartialRevert(YieldDeploymentValidator.InvalidAdapterPlan.selector);
        script.deployForTest(parameters, bytes32(0), address(this));
    }

    function testTokenGovernorModeRequiresAdminRemovalAndFinalRoles() public {
        address[] memory noProposers = new address[](0);
        address[] memory executors = new address[](1);
        executors[0] = address(0);
        TimelockController timelock =
            new TimelockController(1 days, noProposers, executors, address(this));
        MockFundable governor = new MockFundable();
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));
        SinjohTreasuryVault governedTreasury =
            new SinjohTreasuryVault(address(timelock), 3 days, address(0), 0);

        YieldDeploymentTypes.Parameters memory parameters =
            _parameters(address(timelock), governedTreasury);
        parameters.governanceMode = IGovernanceController.Mode.TOKEN_GOVERNOR;
        parameters.tokenGovernor = address(governor);
        vm.expectRevert(YieldDeploymentValidator.TimelockRoleMismatch.selector);
        script.deployForTest(parameters, bytes32(0), address(this));

        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), address(this));
        DeployGovernanceYieldBasket.Deployment memory deployment =
            script.deployForTest(parameters, bytes32(0), address(this));
        assertEq(deployment.controller.authority(), address(timelock));
        assertTrue(!timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), address(this)));
    }

    function _jointParameters() private view returns (YieldDeploymentTypes.Parameters memory) {
        return _parameters(address(joint), treasury);
    }

    function _parameters(address authority, SinjohTreasuryVault treasury_)
        private
        view
        returns (YieldDeploymentTypes.Parameters memory parameters)
    {
        YieldDeploymentTypes.AdapterPlan[] memory adapters =
            new YieldDeploymentTypes.AdapterPlan[](1);
        adapters[0] = YieldDeploymentTypes.AdapterPlan({
            adapter: address(adapter),
            runtimeCodeHash: address(adapter).codehash,
            allocationLimitBps: 5_000,
            distributionInterval: 30 minutes
        });
        YieldDeploymentTypes.RewardRoutePlan[] memory routes =
            new YieldDeploymentTypes.RewardRoutePlan[](1);
        routes[0] = YieldDeploymentTypes.RewardRoutePlan({
            adapter: address(adapter),
            rewardToken: address(reward),
            rewardTokenRuntimeCodeHash: address(reward).codehash,
            distributor: address(sink),
            distributorRuntimeCodeHash: address(sink).codehash,
            distributionConfig: hex"1234"
        });
        parameters = YieldDeploymentTypes.Parameters({
            schemaVersion: 1,
            chainId: MAINNET_CHAIN_ID,
            expectedDeployer: address(this),
            governanceMode: IGovernanceController.Mode.MULTISIG,
            authority: authority,
            authorityRuntimeCodeHash: authority.codehash,
            tokenGovernor: address(0),
            emergencyGuardian: GUARDIAN,
            treasury: address(treasury_),
            treasuryRuntimeCodeHash: address(treasury_).codehash,
            treasuryGovernorHandoffDelay: 3 days,
            treasuryRecoveryAddress: address(0),
            treasuryRecoveryInactivityPeriod: 0,
            depositAsset: address(asset),
            depositAssetRuntimeCodeHash: address(asset).codehash,
            expectedBasket: vm.computeCreateAddress(address(script), 2),
            adapters: adapters,
            rewardRoutes: routes
        });
    }

    function _jointExecute(address target, bytes memory data) private {
        vm.prank(ALICE);
        uint256 proposalId = joint.propose(target, 0, data);
        vm.prank(BOB);
        joint.confirm(proposalId);
        vm.prank(ALICE);
        joint.execute(proposalId);
    }
}
