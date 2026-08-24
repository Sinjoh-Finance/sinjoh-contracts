// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { ProjectVotesToken } from "../../src/token/ProjectVotesToken.sol";
import { PonsProjectVotesToken } from "../../src/token/PonsProjectVotesToken.sol";
import { ProjectVotesTokenFactoryV2 } from "../../src/token/ProjectVotesTokenFactoryV2.sol";
import { MockRegistry } from "../mocks/MockRegistry.sol";
import { TestBase } from "../TestBase.sol";

contract ProjectVotesTokenFactoryV2Test is TestBase {
    address private constant CREATOR = address(0xC0FFEE);
    address private constant CURVE = address(0xC01234);
    address private constant BUYER = address(0xB0B);
    address private constant LATE_CUSTODY = address(0xD00000);
    uint256 private constant SUPPLY = 1_000_000e18;

    MockRegistry private registry;
    ProjectVotesTokenFactoryV2 private factory;

    function setUp() public {
        vm.warp(1_000);
        registry = new MockRegistry();
        factory = new ProjectVotesTokenFactoryV2();
    }

    function testDeploysPredictedPonsCompatibleCanonicalVotingToken() public {
        ProjectVotesTokenFactoryV2.PonsTokenDeployment memory deployment = _ponsDeployment();
        address predicted = factory.predictPons(deployment, address(this));
        PonsProjectVotesToken token = PonsProjectVotesToken(factory.deployPons(deployment));

        assertEq(address(token), predicted);
        assertEq(token.registry(), address(registry));
        assertEq(token.creator(), CREATOR);
        assertEq(token.deployer(), CREATOR);
        assertEq(token.launchFactory(), address(0xFAc7));
        assertEq(token.curve(), CURVE);
        assertEq(token.initialSupply(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(CURVE), SUPPLY);
        assertEq(token.eligibleVotingSupply(), 0);
        assertTrue(token.isVotingExcluded(CURVE));

        vm.warp(1_100);
        vm.prank(CURVE);
        token.transfer(BUYER, 25_000e18);
        assertEq(token.getVotes(BUYER), 25_000e18);
        assertEq(token.eligibleVotingSupply(), 25_000e18);
    }

    function testPonsPredictionIsNamespacedByCallingLaunchpad() public view {
        ProjectVotesTokenFactoryV2.PonsTokenDeployment memory deployment = _ponsDeployment();
        assertNotEq(
            factory.predictPons(deployment, address(this)),
            factory.predictPons(deployment, address(0xBEEF))
        );
    }

    function testPinnedLauncherFinalizesLateCustodyExactlyOnceAndCorrectsVotes() public {
        PonsProjectVotesToken token = PonsProjectVotesToken(factory.deployPons(_ponsDeployment()));
        vm.prank(CURVE);
        token.transfer(LATE_CUSTODY, 10_000e18);
        assertEq(token.getVotes(LATE_CUSTODY), 10_000e18);
        assertEq(token.eligibleVotingSupply(), 10_000e18);

        address[] memory finalExclusions = new address[](2);
        finalExclusions[0] = CURVE;
        finalExclusions[1] = LATE_CUSTODY;
        token.finalizeVotingExclusions(finalExclusions);

        assertTrue(token.votingExclusionsFinalized());
        assertTrue(token.isVotingExcluded(LATE_CUSTODY));
        assertEq(token.getVotes(LATE_CUSTODY), 0);
        assertEq(token.eligibleVotingSupply(), 0);

        vm.expectRevert(PonsProjectVotesToken.VotingExclusionsAlreadyFinalized.selector);
        token.finalizeVotingExclusions(finalExclusions);
    }

    function testDeploysGenericCanonicalTokenForExistingTokenLaunchpads() public {
        ProjectVotesToken.TokenAllocation[] memory allocations =
            new ProjectVotesToken.TokenAllocation[](1);
        allocations[0] = ProjectVotesToken.TokenAllocation({ recipient: CURVE, amount: SUPPLY });
        address[] memory exclusions = new address[](1);
        exclusions[0] = CURVE;
        ProjectVotesTokenFactoryV2.TokenDeployment memory deployment =
            ProjectVotesTokenFactoryV2.TokenDeployment({
                name: "Pools Project",
                symbol: "POOL",
                registry: address(registry),
                creator: CREATOR,
                allocations: allocations,
                votingExclusions: exclusions,
                salt: keccak256("POOLS")
            });

        address predicted = factory.predict(deployment, address(this));
        ProjectVotesToken token = ProjectVotesToken(factory.deploy(deployment));
        assertEq(address(token), predicted);
        assertEq(token.balanceOf(CURVE), SUPPLY);
        assertEq(token.eligibleVotingSupply(), 0);
    }

    function _ponsDeployment()
        private
        view
        returns (ProjectVotesTokenFactoryV2.PonsTokenDeployment memory deployment)
    {
        address[] memory exclusions = new address[](1);
        exclusions[0] = CURVE;
        deployment = ProjectVotesTokenFactoryV2.PonsTokenDeployment({
            token: PonsProjectVotesToken.TokenConfig({
                name: "Pons Project",
                symbol: "PONS",
                logo: "ipfs://logo",
                description: "",
                socials: PonsProjectVotesToken.Socials({
                    twitter: "", telegram: "", discord: "", website: "", farcaster: ""
                }),
                registry: address(registry),
                creator: CREATOR,
                curve: CURVE,
                launchFactory: address(0xFAc7),
                votingExclusionConfigurator: address(this),
                supply: SUPPLY,
                votingExclusions: exclusions
            }),
            salt: keccak256("PONS")
        });
    }
}
