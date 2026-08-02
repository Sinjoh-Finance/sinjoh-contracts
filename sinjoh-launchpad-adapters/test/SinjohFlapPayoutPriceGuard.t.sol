// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { TestBase } from "./TestBase.sol";
import { IFlapTradePortal } from "../src/SinjohFlapBuybackAdapter.sol";
import { SinjohFlapPayoutPriceGuard } from "../src/SinjohFlapPayoutPriceGuard.sol";
import { SinjohSignedFloor } from "../src/libraries/SinjohSignedFloor.sol";

contract MockFlapPayoutPortal {
    uint256 public quote = 1_000;

    function quoteExactInput(IFlapTradePortal.QuoteExactInputParams calldata)
        external
        view
        returns (uint256)
    {
        return quote;
    }
}

contract MockFlapPayoutWeth { }

contract SinjohFlapPayoutPriceGuardTest is TestBase {
    uint256 private constant SIGNER_KEY = uint256(keccak256("sinjoh-flap-payout-signer"));
    address private constant SUBJECT = address(0x7777);
    address private constant PAYOUT = address(0xBEEF);
    uint256 private constant AMOUNT = 1 ether;

    MockFlapPayoutPortal private portal;
    MockFlapPayoutWeth private weth;
    SinjohFlapPayoutPriceGuard private guard;

    function setUp() public {
        vm.warp(1_000);
        portal = new MockFlapPayoutPortal();
        weth = new MockFlapPayoutWeth();
        guard = new SinjohFlapPayoutPriceGuard(
            address(portal),
            address(weth),
            address(portal).codehash,
            address(weth).codehash,
            vm.addr(SIGNER_KEY),
            500
        );
    }

    function test_allowsPayoutDifferentFromSubject() public {
        bytes memory data = _guardData(PAYOUT, AMOUNT, 975);
        (uint256 minimum, uint48 validUntil) =
            guard.minimumOutput(SUBJECT, address(weth), PAYOUT, AMOUNT, keccak256(""), data);
        assertEq(minimum, 975);
        assertEq(validUntil, block.timestamp + 60);
    }

    function test_livePortalFloorWins() public {
        bytes memory data = _guardData(PAYOUT, AMOUNT, 1);
        (uint256 minimum,) =
            guard.minimumOutput(SUBJECT, address(weth), PAYOUT, AMOUNT, keccak256(""), data);
        assertEq(minimum, 950);
    }

    function test_signatureBindsOutputAsset() public {
        bytes memory data = _guardData(address(0xCAFE), AMOUNT, 975);
        vm.expectRevert(SinjohSignedFloor.InvalidSignature.selector);
        guard.minimumOutput(SUBJECT, address(weth), PAYOUT, AMOUNT, keccak256(""), data);
    }

    function test_signatureBindsRouterSubjectAndAmount() public {
        bytes memory data = _guardData(PAYOUT, AMOUNT + 1, 975);
        vm.expectRevert(SinjohSignedFloor.InvalidSignature.selector);
        guard.minimumOutput(SUBJECT, address(weth), PAYOUT, AMOUNT, keccak256(""), data);

        data = _guardData(PAYOUT, AMOUNT, 975);
        vm.prank(address(0xBAD));
        vm.expectRevert(SinjohSignedFloor.InvalidSignature.selector);
        guard.minimumOutput(SUBJECT, address(weth), PAYOUT, AMOUNT, keccak256(""), data);
    }

    function test_rejectsInvalidAssetsAndRoute() public {
        bytes memory data = _guardData(PAYOUT, AMOUNT, 975);
        vm.expectRevert(SinjohFlapPayoutPriceGuard.InvalidAmount.selector);
        guard.minimumOutput(SUBJECT, address(weth), address(weth), AMOUNT, keccak256(""), data);
        vm.expectRevert(SinjohFlapPayoutPriceGuard.InvalidRoute.selector);
        guard.minimumOutput(SUBJECT, address(weth), PAYOUT, AMOUNT, keccak256("route"), data);
    }

    function test_dependencyChangeFailsClosed() public {
        bytes memory data = _guardData(PAYOUT, AMOUNT, 975);
        vm.etch(address(portal), hex"60006000fd");
        vm.expectRevert(SinjohFlapPayoutPriceGuard.DependencyChanged.selector);
        guard.minimumOutput(SUBJECT, address(weth), PAYOUT, AMOUNT, keccak256(""), data);
    }

    function _guardData(address assetOut, uint256 amount, uint256 minimum)
        private
        returns (bytes memory)
    {
        uint48 validAfter = uint48(block.timestamp);
        uint48 validUntil = uint48(block.timestamp + 60);
        bytes32 digest = guard.floorDigest(
            address(this),
            SUBJECT,
            address(weth),
            assetOut,
            amount,
            keccak256(""),
            minimum,
            validAfter,
            validUntil
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_KEY, _personalDigest(digest));
        return abi.encode(minimum, validAfter, validUntil, abi.encodePacked(r, s, v));
    }

    function _personalDigest(bytes32 digest) private pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", digest));
    }
}
