// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;
import {
    SinjohAirdropClaimAdapter,
    ISinjohHolderAirdrop
} from "../../src/yield-banks/airdrop/SinjohAirdropClaimAdapter.sol";
import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { PonsAirdropClaimAdapter } from "../../src/yield-banks/airdrop/PonsAirdropClaimAdapter.sol";
import {
    ReflectionAirdropClaimAdapter
} from "../../src/yield-banks/airdrop/ReflectionAirdropClaimAdapter.sol";
import { AirdropBankCustody } from "../../src/yield-banks/airdrop/AirdropBankCustody.sol";
import { AirdropAssetRegistry } from "../../src/yield-banks/airdrop/AirdropAssetRegistry.sol";
import { AirdropIdentityMock } from "../unit/AirdropCustody.t.sol";

/// @dev Historical proof belongs to a previously eligible holder. Etching custody at that
/// address verifies contract-recipient collection/payout, NOT future publisher eligibility
/// for a newly deployed Piggy Bank holder. No mainnet state or transactions are changed.
interface ISinjohClaimPaid {
    function paid(bytes32, address) external view returns (uint256);
}

interface IReflectionState {
    function shareholders(uint256) external view returns (address);
    function rewardThreshold() external view returns (uint256);
    function shares(address) external view returns (uint256, uint256, uint256);
}

interface IWETHAirdropFixture {
    function deposit() external payable;
}

contract AirdropClaimsForkTest is Test {
    address constant SUBJECT = 0xD5f1afEA47b1A9eab414D2ee740cF1d6d039E725;
    address constant REWARD = 0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC;
    address constant DISTRIBUTOR = 0xe25E9Bc31d24BB652Fb6E2E466d7c9c89701173e;
    address constant BEACON = 0xa125492aca28449D2291f5415A818697345cfA09;
    address constant HOLDER = 0xF38C98d633aD4B75ca70C3d667EE99A32A3224fE;

    function _proof() private pure returns (bytes memory) {
        bytes32[] memory proof = new bytes32[](10);
        proof[0] = 0x6c6a18eb57b99cc5e2a70c0623057d4ba59c459cf65d0d44b4fa755cf3e6a1dc;
        proof[1] = 0x73107fe5bbb5b0c44b88b8979f52de8358632415f420f75f78b079df4f6ceb11;
        proof[2] = 0x32bd208f897cecf6765c79ae81cc883903ac3219989049a28bd407fd9386a127;
        proof[3] = 0x561add950b88d9a3812f43be9d795647141098cde54e75500f340c9e9c6377fb;
        proof[4] = 0x9ff0999b52b47244b071cb37223dd67a68f9d96685160aa706e32c83b4e0b0f4;
        proof[5] = 0x4cc3392a543ff83a8efca649a1a6dc7c9609432f4d9925505c5cdacce5645f58;
        proof[6] = 0xd01140d43f837f868094761f6c60c036d9025b11e6eb93018d948c927c4efc5c;
        proof[7] = 0xd4d1f69b0cd582a7befa3c705e59be8107661eac79b26443d3f2f68508f9a168;
        proof[8] = 0xcfd5f370818d5333a4dd87950874909a03ca2a8599a4e43ada08e695e624c8ad;
        proof[9] = 0xa46ab50ad3faf245b0eb18e91b3df9ace631d3cc80e8ea6f7eef53d93bae4f5e;
        return abi.encode(uint256(1060), uint256(743824186919858), uint256(0), proof);
    }

    function testHistoricalPonsProofCollectsToContractAndPaysCurrentNFTOwner() public {
        vm.createSelectFork(vm.envString("ROBINHOOD_MAINNET_RPC_URL"), 62925211);
        PonsAirdropClaimAdapter adapter = new PonsAirdropClaimAdapter(DISTRIBUTOR, BEACON);
        AirdropIdentityMock identity = new AirdropIdentityMock();
        address alice = address(0xA11CE);
        identity.set(1, alice);
        AirdropAssetRegistry registry = new AirdropAssetRegistry(address(this), keccak256("fork"));
        registry.register(SUBJECT, keccak256("evidence"));
        registry.addClaimRoute(SUBJECT, address(adapter));
        AirdropBankCustody template =
            new AirdropBankCustody(address(this), address(identity), address(registry), 1);
        vm.etch(HOLDER, address(template).code);
        AirdropBankCustody custody = AirdropBankCustody(payable(HOLDER));
        uint256 beforeBalance = IERC20(REWARD).balanceOf(HOLDER);
        custody.collect(SUBJECT, 0, _proof());
        assertEq(IERC20(REWARD).balanceOf(HOLDER) - beforeBalance, 743824186919858);
        vm.expectRevert();
        custody.collect(SUBJECT, 0, _proof());
        uint256 owed = custody.available(REWARD);
        vm.prank(alice);
        custody.claim(REWARD);
        assertEq(IERC20(REWARD).balanceOf(alice), owed);
        assertEq(custody.available(REWARD), 0);
    }

    function testHistoricalPonsProofCannotRedirectRecipient() public {
        vm.createSelectFork(vm.envString("ROBINHOOD_MAINNET_RPC_URL"), 62925211);
        PonsAirdropClaimAdapter adapter = new PonsAirdropClaimAdapter(DISTRIBUTOR, BEACON);
        (address target, bytes memory callData) = adapter.prepare(address(0xBAD), _proof());
        uint256 beforeBalance = IERC20(REWARD).balanceOf(address(0xBAD));
        target.call(callData);
        assertEq(IERC20(REWARD).balanceOf(address(0xBAD)), beforeBalance);
    }

    function testExpiredPonsProofRejected() public {
        vm.createSelectFork(vm.envString("ROBINHOOD_MAINNET_RPC_URL"), 62925211);
        PonsAirdropClaimAdapter adapter = new PonsAirdropClaimAdapter(DISTRIBUTOR, BEACON);
        vm.warp(block.timestamp + 365 days);
        (address target, bytes memory callData) = adapter.prepare(HOLDER, _proof());
        uint256 beforeBalance = IERC20(REWARD).balanceOf(HOLDER);
        target.call(callData);
        assertEq(IERC20(REWARD).balanceOf(HOLDER), beforeBalance);
    }

    function testHistoricalSinjohMerkleSumProofPaysCustodyAndRejectsReplay() public {
        vm.createSelectFork(vm.envString("ROBINHOOD_MAINNET_RPC_URL"), 61849170);
        address distributor = 0xA1d65242D367501D9A261389a69005e584F4786a;
        address subject = 0xB40921cb9e3EDE2B3F0EdFb26F652f2739FDb51c;
        address reward = 0x2cC0FAC44B8252f6B10208B091aFf2c94B4da77D;
        address holder = 0x00000000Cf1cD5867BE5D90B99A6EBd683BC031c;
        SinjohAirdropClaimAdapter adapter = new SinjohAirdropClaimAdapter(
            distributor, 0xea0E0125D49CD48DD8E59C6e36898fBa02645bA1, subject, reward
        );
        AirdropIdentityMock identity = new AirdropIdentityMock();
        address alice = address(0xA11CE);
        identity.set(1, alice);
        AirdropAssetRegistry registry = new AirdropAssetRegistry(address(this), keccak256("fork"));
        registry.register(subject, keccak256("evidence"));
        registry.addClaimRoute(subject, address(adapter));
        AirdropBankCustody template =
            new AirdropBankCustody(address(this), address(identity), address(registry), 1);
        vm.etch(holder, address(template).code);
        AirdropBankCustody custody = AirdropBankCustody(payable(holder));
        ISinjohHolderAirdrop.ProofElement[] memory proof =
            new ISinjohHolderAirdrop.ProofElement[](7);
        proof[0] = ISinjohHolderAirdrop.ProofElement(
            0xa12a3afcc1bb40197a4360029fd4ec342d750c6ef36c3f3633a99105d29794b5,
            113371450993481467598,
            false
        );
        proof[1] = ISinjohHolderAirdrop.ProofElement(
            0x0d0a7cdbb56ad99fce1a3d1a113baf77f2d2f8126b25e004fd7d0db90f0eff92,
            103442459624207765259,
            false
        );
        proof[2] = ISinjohHolderAirdrop.ProofElement(
            0x72fc345d27d0ec66c00f2db13d314daf6edf50a542cf4a27b9ac0032ec45121d,
            210372154652900116482,
            false
        );
        proof[3] = ISinjohHolderAirdrop.ProofElement(
            0xcd03b19123f027a6565d2f617c69a6fafb3b5d4e339b490a0058c6f2d607b8c4,
            27969730246789056703015,
            false
        );
        proof[4] = ISinjohHolderAirdrop.ProofElement(
            0x43db2adc4f1d79b0d412ef20e9cc1c14cf66643c5930aece4a95ec6e7f17351a,
            104946043741008098811042,
            false
        );
        proof[5] = ISinjohHolderAirdrop.ProofElement(
            0xe8320aef5441bea5aab90ffa9d04db6b430b91ed197881c7b01724a2b1a4afed,
            87171693247972120000062,
            false
        );
        proof[6] = ISinjohHolderAirdrop.ProofElement(
            0x47c2dd5b5f613c07c86810129775bec79cbf9b92907466b1b920075b8ddcda9e,
            14557054766909533285140,
            false
        );
        bytes memory payload = abi.encode(uint64(2), uint256(11205987), proof);
        uint256 alreadyPaid = ISinjohClaimPaid(distributor).paid(adapter.accountId(), holder);
        uint256 beforeBalance = IERC20(reward).balanceOf(holder);
        custody.collect(subject, 0, payload);
        assertEq(IERC20(reward).balanceOf(holder) - beforeBalance, 11205987 - alreadyPaid);
        vm.expectRevert(AirdropBankCustody.NoRewardsReceived.selector);
        custody.collect(subject, 0, payload);
        uint256 owed = custody.available(reward);
        vm.prank(alice);
        custody.claim(reward);
        assertEq(IERC20(reward).balanceOf(alice), owed);
    }

    function testReflectionTrackerRegistersContractHolderOnActualTokenTransfer() public {
        vm.createSelectFork(vm.envString("ROBINHOOD_MAINNET_RPC_URL"), 62925369);
        address dist = 0x8d4c92C67baBA4D38f57F65211a7AF8dB92e8ABB;
        ReflectionAirdropClaimAdapter adapter = new ReflectionAirdropClaimAdapter(dist);
        AirdropIdentityMock identity = new AirdropIdentityMock();
        identity.set(1, address(0xA11CE));
        AirdropAssetRegistry registry =
            new AirdropAssetRegistry(address(this), keccak256("reflection"));
        registry.register(adapter.subject(), keccak256("evidence"));
        registry.addClaimRoute(adapter.subject(), address(adapter));
        AirdropBankCustody holder = new AirdropBankCustody(
            address(this), address(identity), address(registry), 1
        );
        IReflectionState tracker = IReflectionState(dist);
        address donor = tracker.shareholders(0);
        uint256 threshold = tracker.rewardThreshold();
        require(IERC20(adapter.subject()).balanceOf(donor) >= threshold, "donor insufficient");
        address subject = adapter.subject();
        vm.prank(donor);
        IERC20(subject).transfer(address(holder), threshold);
        (uint256 share,,) = tracker.shares(address(holder));
        assertEq(share, threshold);
        // First verify no-op protection, then fund the real tracker through an actual WETH
        // transfer on this fork. This tests claim mechanics, not future trading-fee income.
        vm.expectRevert();
        holder.collect(subject, 0, "");
        address reward = adapter.rewardAsset();
        vm.deal(address(this), 1 ether);
        IWETHAirdropFixture(reward).deposit{ value: 1 ether }();
        IERC20(reward).transfer(dist, 1 ether);
        holder.collect(subject, 0, "");
        uint256 received = holder.available(reward);
        assertGt(received, 0);
        uint256 before = IERC20(reward).balanceOf(address(0xA11CE));
        vm.prank(address(0xA11CE));
        holder.claim(reward);
        assertEq(IERC20(reward).balanceOf(address(0xA11CE)), before + received);
        assertEq(IERC20(subject).balanceOf(address(holder)), threshold);
        vm.expectRevert();
        holder.collect(subject, 0, "");
    }
}
