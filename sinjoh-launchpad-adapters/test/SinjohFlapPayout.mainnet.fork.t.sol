// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { TestBase } from "./TestBase.sol";
import { IFlapTradePortal, SinjohFlapBuybackAdapter } from "../src/SinjohFlapBuybackAdapter.sol";
import { SinjohFlapPayoutPriceGuard } from "../src/SinjohFlapPayoutPriceGuard.sol";

interface IFlapPayoutForkWeth {
    function deposit() external payable;
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IFlapPayoutForkToken {
    function balanceOf(address account) external view returns (uint256);
}

/// @notice Proves the generic payout path against a real Flap mainnet token.
/// Every state change occurs only inside the local fork.
contract SinjohFlapPayoutMainnetForkTest is TestBase {
    address private constant PORTAL = 0x26605f322f7fF986f381bB9A6e3f5DAb0bEaEb09;
    address private constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;
    address private constant NINEHOOD = 0x01397109534e47d3742e794D3a610fA1C3158888;
    bytes32 private constant PORTAL_CODEHASH =
        0xcecb292d9c022858199c9348abf0d5836f9ea4dab5cf03710e1dcf41fd9a4c35;
    bytes32 private constant WETH_CODEHASH =
        0x5706be52f64875fee65a2cec0d80e47a23d8793cbe85d214b48445e2d05f5353;
    uint256 private constant SIGNER_KEY = uint256(keccak256("sinjoh-flap-payout-fork"));
    uint256 private constant AMOUNT = 0.0001 ether;
    string private constant DEFAULT_RPC = "https://rpc.mainnet.chain.robinhood.com";

    function setUp() public {
        vm.createSelectFork(vm.envOr("ROBINHOOD_MAINNET_RPC_URL", DEFAULT_RPC));
    }

    function test_routesWethIntoExistingFlapToken() public {
        SinjohFlapBuybackAdapter adapter =
            new SinjohFlapBuybackAdapter(PORTAL, WETH, PORTAL_CODEHASH, WETH_CODEHASH);
        SinjohFlapPayoutPriceGuard guard = new SinjohFlapPayoutPriceGuard(
            PORTAL, WETH, PORTAL_CODEHASH, WETH_CODEHASH, vm.addr(SIGNER_KEY), 500
        );

        uint256 quoted = _quote(AMOUNT);
        uint256 signedMinimum = quoted * 95 / 100;
        uint48 validAfter = uint48(block.timestamp);
        uint48 validUntil = uint48(block.timestamp + 60);
        bytes32 digest = guard.floorDigest(
            address(this),
            address(0x7777),
            WETH,
            NINEHOOD,
            AMOUNT,
            keccak256(""),
            signedMinimum,
            validAfter,
            validUntil
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_KEY, _personalDigest(digest));
        bytes memory guardData =
            abi.encode(signedMinimum, validAfter, validUntil, abi.encodePacked(r, s, v));
        (uint256 minimum,) =
            guard.minimumOutput(address(0x7777), WETH, NINEHOOD, AMOUNT, keccak256(""), guardData);

        vm.deal(address(this), AMOUNT);
        IFlapPayoutForkWeth(WETH).deposit{ value: AMOUNT }();
        IFlapPayoutForkWeth(WETH).approve(address(adapter), AMOUNT);
        uint256 beforeBalance = IFlapPayoutForkToken(NINEHOOD).balanceOf(address(this));
        adapter.swap(WETH, NINEHOOD, AMOUNT, minimum, "");
        assertTrue(IFlapPayoutForkToken(NINEHOOD).balanceOf(address(this)) > beforeBalance);
    }

    function _quote(uint256 amount) private view returns (uint256 output) {
        (bool ok, bytes memory result) = PORTAL.staticcall(
            abi.encodeCall(
                IFlapTradePortal.quoteExactInput,
                (IFlapTradePortal.QuoteExactInputParams({
                        inputToken: address(0), outputToken: NINEHOOD, inputAmount: amount
                    }))
            )
        );
        assertTrue(ok && result.length == 32);
        output = abi.decode(result, (uint256));
        assertTrue(output > 0);
    }

    function _personalDigest(bytes32 digest) private pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", digest));
    }
}
