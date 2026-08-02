// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { TestBase } from "./TestBase.sol";
import { IFlapTradePortal, SinjohFlapBuybackPriceGuard } from "../src/SinjohFlapBuybackAdapter.sol";
import { SinjohSignedFloor } from "../src/libraries/SinjohSignedFloor.sol";

contract MockFlapQuotePortal {
    uint256 public quote = 1_000;

    function setQuote(uint256 value) external {
        quote = value;
    }

    function quoteExactInput(IFlapTradePortal.QuoteExactInputParams calldata)
        external
        view
        returns (uint256)
    {
        return quote;
    }
}

contract MockFlapExecutionWeth { }

contract SinjohFlapExecutionSecurityTest is TestBase {
    uint256 private constant SIGNER_KEY = uint256(keccak256("sinjoh-flap-security-signer"));
    address private constant SUBJECT = address(0x7777);
    uint256 private constant AMOUNT = 1 ether;

    MockFlapQuotePortal private portal;
    MockFlapExecutionWeth private weth;
    SinjohFlapBuybackPriceGuard private guard;

    function setUp() public {
        vm.warp(1_000);
        portal = new MockFlapQuotePortal();
        weth = new MockFlapExecutionWeth();
        guard = new SinjohFlapBuybackPriceGuard(
            address(portal),
            address(weth),
            address(portal).codehash,
            address(weth).codehash,
            vm.addr(SIGNER_KEY),
            500
        );
    }

    function test_signedFloorWinsOverWeakerPortalSpotFloor() public {
        bytes memory data =
            _guardData(AMOUNT, 975, uint48(block.timestamp), uint48(block.timestamp + 60));
        (uint256 minimum, uint48 validUntil) =
            guard.minimumOutput(SUBJECT, address(weth), SUBJECT, AMOUNT, keccak256(""), data);
        assertEq(minimum, 975);
        assertEq(validUntil, block.timestamp + 60);
    }

    function test_portalSpotFloorWinsOverWeakerSignedFloor() public {
        bytes memory data =
            _guardData(AMOUNT, 1, uint48(block.timestamp), uint48(block.timestamp + 60));
        (uint256 minimum,) =
            guard.minimumOutput(SUBJECT, address(weth), SUBJECT, AMOUNT, keccak256(""), data);
        assertEq(minimum, 950);
    }

    function test_signatureBindsExactAmountAndRouter() public {
        bytes memory data =
            _guardData(AMOUNT + 1, 975, uint48(block.timestamp), uint48(block.timestamp + 60));
        vm.expectRevert(SinjohSignedFloor.InvalidSignature.selector);
        guard.minimumOutput(SUBJECT, address(weth), SUBJECT, AMOUNT, keccak256(""), data);

        data = _guardData(AMOUNT, 975, uint48(block.timestamp), uint48(block.timestamp + 60));
        vm.startPrank(address(0xBAD));
        vm.expectRevert(SinjohSignedFloor.InvalidSignature.selector);
        guard.minimumOutput(SUBJECT, address(weth), SUBJECT, AMOUNT, keccak256(""), data);
        vm.stopPrank();
    }

    function test_rejectsExpiredFutureAndOverlongValidity() public {
        bytes memory data =
            _guardData(AMOUNT, 975, uint48(block.timestamp - 2), uint48(block.timestamp - 1));
        vm.expectRevert(SinjohSignedFloor.InvalidValidity.selector);
        guard.minimumOutput(SUBJECT, address(weth), SUBJECT, AMOUNT, keccak256(""), data);

        data = _guardData(AMOUNT, 975, uint48(block.timestamp + 1), uint48(block.timestamp + 60));
        vm.expectRevert(SinjohSignedFloor.InvalidValidity.selector);
        guard.minimumOutput(SUBJECT, address(weth), SUBJECT, AMOUNT, keccak256(""), data);

        data = _guardData(
            AMOUNT,
            975,
            uint48(block.timestamp),
            uint48(block.timestamp + guard.MAXIMUM_VALIDITY() + 1)
        );
        vm.expectRevert(SinjohSignedFloor.InvalidValidity.selector);
        guard.minimumOutput(SUBJECT, address(weth), SUBJECT, AMOUNT, keccak256(""), data);
    }

    function test_rejectsMalleableAndMalformedSignatures() public {
        uint48 validAfter = uint48(block.timestamp);
        uint48 validUntil = uint48(block.timestamp + 60);
        bytes32 digest = guard.floorDigest(
            address(this),
            SUBJECT,
            address(weth),
            SUBJECT,
            AMOUNT,
            keccak256(""),
            975,
            validAfter,
            validUntil
        );
        bytes32 personalDigest = _personalDigest(digest);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_KEY, personalDigest);
        uint256 curveOrder = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;
        bytes memory malleable =
            abi.encodePacked(r, bytes32(curveOrder - uint256(s)), v == 27 ? uint8(28) : uint8(27));
        bytes memory data = abi.encode(975, validAfter, validUntil, malleable);
        vm.expectRevert(SinjohSignedFloor.InvalidSignature.selector);
        guard.minimumOutput(SUBJECT, address(weth), SUBJECT, AMOUNT, keccak256(""), data);

        data = abi.encode(975, validAfter, validUntil, hex"01");
        vm.expectRevert(SinjohSignedFloor.InvalidSignature.selector);
        guard.minimumOutput(SUBJECT, address(weth), SUBJECT, AMOUNT, keccak256(""), data);
    }

    function test_dependencyCodeChangeFailsClosed() public {
        bytes memory data =
            _guardData(AMOUNT, 975, uint48(block.timestamp), uint48(block.timestamp + 60));
        vm.etch(address(portal), hex"60006000fd");
        vm.expectRevert(SinjohFlapBuybackPriceGuard.DependencyChanged.selector);
        guard.minimumOutput(SUBJECT, address(weth), SUBJECT, AMOUNT, keccak256(""), data);
    }

    function _guardData(uint256 amount, uint256 minimum, uint48 validAfter, uint48 validUntil)
        private
        returns (bytes memory)
    {
        bytes32 digest = guard.floorDigest(
            address(this),
            SUBJECT,
            address(weth),
            SUBJECT,
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
