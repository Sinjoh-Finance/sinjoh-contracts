// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;
import { Test } from "forge-std/Test.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { AirdropVault } from "../../src/yield-banks/airdrop/AirdropVault.sol";
import { AirdropBankCustody } from "../../src/yield-banks/airdrop/AirdropBankCustody.sol";
import {
    AirdropAssetRegistry,
    IAirdropClaimAdapter
} from "../../src/yield-banks/airdrop/AirdropAssetRegistry.sol";
import {
    PonsAirdropClaimAdapter,
    IPonsAirdropDistributor
} from "../../src/yield-banks/airdrop/PonsAirdropClaimAdapter.sol";

contract AirdropTokenMock is ERC20 {
    address public blocked;
    constructor() ERC20("Airdrop fixture", "AIR") { }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function blockRecipient(address recipient) external {
        blocked = recipient;
    }

    function _update(address from, address to, uint256 amount) internal override {
        require(to != blocked || to == address(0), "blocked");
        super._update(from, to, amount);
    }
}

contract AirdropIdentityMock {
    mapping(uint256 => address) public ownerOf;
    mapping(uint256 => address) public accountOf;
    bool public closed;
    address public redemptionBeneficiary;

    function nft() external view returns (address) {
        return address(this);
    }

    function set(uint256 bank, address owner) external {
        ownerOf[bank] = owner;
        accountOf[bank] = address(this);
    }

    function close(address owner) external {
        closed = true;
        redemptionBeneficiary = owner;
    }
}

contract AirdropBeaconMock {
    address public implementation;

    constructor() {
        implementation = address(this);
    }

    function upgrade(address target) external {
        implementation = target;
    }
}

contract AirdropDistributorMock is IPonsAirdropDistributor {
    address public token;
    address public quoteToken;
    mapping(bytes32 => bool) public paid;
    mapping(bytes32 => bool) public valid;

    constructor(address subject, address reward) {
        token = subject;
        quoteToken = reward;
    }

    function authorize(uint256 epoch, address account, uint256 amount) external {
        valid[keccak256(abi.encode(epoch, account, amount))] = true;
    }

    function claimMany(Claim[] calldata claims) external {
        for (uint256 i; i < claims.length; ++i) {
            Claim calldata c = claims[i];
            bytes32 id = keccak256(abi.encode(c.epoch, c.account, c.quoteAmount));
            require(valid[id] && !paid[id] && c.nativeAmount == 0, "invalid claim");
            paid[id] = true;
            AirdropTokenMock(quoteToken).mint(c.account, c.quoteAmount);
        }
    }
}

contract AirdropReentrantBeneficiary {
    AirdropBankCustody public custody;
    bool public reentrySucceeded;

    function setCustody(AirdropBankCustody c) external {
        custody = c;
    }

    function claimNative() external {
        custody.claim(address(0));
    }

    receive() external payable {
        (reentrySucceeded,) = address(custody).call(abi.encodeCall(custody.claim, (address(0))));
    }
}

contract AirdropCustodyTest is Test {
    AirdropIdentityMock identity;
    AirdropTokenMock token;
    AirdropTokenMock reward;
    AirdropVault vault;
    AirdropBankCustody c1;
    AirdropBankCustody c2;
    AirdropAssetRegistry registry;
    AirdropDistributorMock distributor;
    AirdropBeaconMock beacon;
    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    function setUp() public {
        identity = new AirdropIdentityMock();
        identity.set(1, alice);
        identity.set(2, bob);
        token = new AirdropTokenMock();
        reward = new AirdropTokenMock();
        registry = new AirdropAssetRegistry(address(this), keccak256("approved"));
        registry.register(address(token), keccak256("evidence"));
        distributor = new AirdropDistributorMock(address(token), address(reward));
        beacon = new AirdropBeaconMock();
        registry.addClaimRoute(
            address(token),
            address(new PonsAirdropClaimAdapter(address(distributor), address(beacon)))
        );
        registry.setEnabled(address(token), true);
        vault = new AirdropVault(address(this), address(identity), address(registry));
        token.mint(address(this), 1000 ether);
        token.approve(address(vault), type(uint256).max);
        vault.deposit(1, address(token), 100 ether);
        vault.deposit(2, address(token), 200 ether);
        c1 = vault.custodyOf(1, address(token));
        c2 = vault.custodyOf(2, address(token));
    }

    function custody(uint256 bank) internal view returns (AirdropBankCustody) {
        return bank == 1 ? c1 : c2;
    }

    function payload(uint256 amount) internal pure returns (bytes memory) {
        return abi.encode(uint256(1), amount, uint256(0), new bytes32[](0));
    }

    function testPrincipalAndRewardsNeverMixAcrossBanks() public {
        reward.mint(address(custody(1)), 17 ether);
        reward.mint(address(custody(2)), 23 ether);
        vm.prank(alice);
        custody(1).claim(address(reward));
        assertEq(reward.balanceOf(alice), 17 ether);
        assertEq(custody(2).available(address(reward)), 23 ether);
        vm.prank(alice);
        assertEq(custody(1).claim(address(token)), 0);
        assertEq(vault.totalPrincipal(address(token)), 300 ether);
    }

    function testMinimumHoldingBlocksIneligibleEntryWithoutLockingExits() public {
        registry.setEnabled(address(token), false);
        registry.setMinimumHoldingUnits(address(token), 1000 ether);
        registry.setEnabled(address(token), true);
        vm.expectRevert(AirdropVault.InvalidTransfer.selector);
        vault.deposit(1, address(token), 1 ether);
        assertEq(c1.principal(), 100 ether);
        vault.withdraw(1, address(token), 100 ether);
        assertEq(c1.principal(), 0);
    }

    function testSameTokenRewardOnlyPaysSurplus() public {
        token.mint(address(custody(1)), 7 ether);
        vm.prank(alice);
        custody(1).claim(address(token));
        assertEq(token.balanceOf(alice), 7 ether);
        assertEq(token.balanceOf(address(custody(1))), 100 ether);
    }

    function testOldOwnerCannotClaimAfterTransfer() public {
        reward.mint(address(custody(1)), 7 ether);
        identity.set(1, bob);
        vm.prank(alice);
        vm.expectRevert(AirdropBankCustody.Unauthorized.selector);
        custody(1).claim(address(reward));
        vm.prank(bob);
        custody(1).claim(address(reward));
        assertEq(reward.balanceOf(bob), 7 ether);
    }

    function testLateRewardsAndReentryKeepSameCustody() public {
        address holder = address(custody(1));
        vault.withdraw(1, address(token), 100 ether);
        reward.mint(holder, 7 ether);
        vm.prank(alice);
        custody(1).claim(address(reward));
        vault.deposit(1, address(token), 20 ether);
        assertEq(address(custody(1)), holder);
        assertEq(custody(1).principal(), 20 ether);
        assertEq(reward.balanceOf(alice), 7 ether);
    }

    function testClosedBankUsesRecordedRedemptionBeneficiary() public {
        vault.withdraw(1, address(token), 100 ether);
        identity.close(alice);
        identity.set(1, address(0));
        reward.mint(address(custody(1)), 7 ether);
        vm.prank(alice);
        custody(1).claim(address(reward));
        assertEq(reward.balanceOf(alice), 7 ether);
    }

    function testBlockedRewardCanRetryWithoutLosingBalance() public {
        reward.mint(address(custody(1)), 7 ether);
        reward.blockRecipient(alice);
        vm.prank(alice);
        vm.expectRevert();
        custody(1).claim(address(reward));
        assertEq(custody(1).totalPaid(address(reward)), 0);
        assertEq(custody(1).available(address(reward)), 7 ether);
        reward.blockRecipient(address(0));
        vm.prank(alice);
        custody(1).claim(address(reward));
        vm.prank(alice);
        assertEq(custody(1).claim(address(reward)), 0);
        assertEq(custody(1).totalPaid(address(reward)), 7 ether);
    }

    function testPermissionlessCollectionPinsRecipientAndRejectsReplay() public {
        distributor.authorize(1, address(custody(1)), 7 ether);
        vm.prank(bob);
        custody(1).collect(0, payload(7 ether));
        assertEq(custody(1).available(address(reward)), 7 ether);
        assertEq(reward.balanceOf(bob), 0);
        vm.expectRevert(AirdropBankCustody.ClaimFailed.selector);
        custody(1).collect(0, payload(7 ether));
    }

    function testInvalidProofDoesNotChangeBalances() public {
        vm.expectRevert(AirdropBankCustody.ClaimFailed.selector);
        custody(1).collect(0, payload(9 ether));
        assertEq(custody(1).available(address(reward)), 0);
        assertEq(custody(1).principal(), 100 ether);
    }

    function testUpstreamUpgradeStopsCollectionButNotPaidRewardRecovery() public {
        reward.mint(address(custody(1)), 7 ether);
        beacon.upgrade(address(reward));
        vm.expectRevert(PonsAirdropClaimAdapter.InvalidClaim.selector);
        custody(1).collect(0, payload(7 ether));
        vm.prank(alice);
        custody(1).claim(address(reward));
        assertEq(reward.balanceOf(alice), 7 ether);
        vault.withdraw(1, address(token), 100 ether);
    }

    function testDisabledEntryDoesNotLockExitOrRewards() public {
        registry.setEnabled(address(token), false);
        vm.expectRevert(AirdropAssetRegistry.InvalidAsset.selector);
        vault.deposit(1, address(token), 1 ether);
        vault.withdraw(1, address(token), 100 ether);
        assertEq(custody(1).principal(), 0);
    }

    function testOnlyControllerCanChangePrincipal() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.withdraw(1, address(token), 1 ether);
        vm.prank(alice);
        vm.expectRevert();
        custody(1).withdraw(1 ether);
    }

    function testFuzzPayoutNeverSpendsPrincipal(uint128 incoming) public {
        reward.mint(address(custody(1)), incoming);
        vm.prank(alice);
        custody(1).claim(address(reward));
        assertEq(custody(1).principal(), 100 ether);
        assertEq(token.balanceOf(address(custody(1))), 100 ether);
        assertEq(reward.balanceOf(alice), incoming);
        assertEq(custody(1).available(address(reward)), 0);
    }

    function testNativePayoutReentryCannotDoubleSpend() public {
        AirdropReentrantBeneficiary receiver = new AirdropReentrantBeneficiary();
        receiver.setCustody(c1);
        identity.set(1, address(receiver));
        vm.deal(address(c1), 1 ether);
        receiver.claimNative();
        assertEq(address(receiver).balance, 1 ether);
        assertFalse(receiver.reentrySucceeded());
        assertEq(c1.totalPaid(address(0)), 1 ether);
        assertEq(c1.principal(), 100 ether);
    }

    function testFuzzPrincipalWithdrawalConservesBankAggregate(uint128 raw) public {
        uint256 amount = bound(uint256(raw), 1, 100 ether);
        uint256 beforeBalance = token.balanceOf(address(this));
        vault.withdraw(1, address(token), amount);
        assertEq(c1.principal(), 100 ether - amount);
        assertEq(vault.totalPrincipal(address(token)), c1.principal() + c2.principal());
        assertEq(token.balanceOf(address(this)), beforeBalance + amount);
        assertEq(token.balanceOf(address(c2)), 200 ether);
    }
}
