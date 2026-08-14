// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { SinjohSignedPrice } from "../src/libraries/SinjohSignedPrice.sol";
import { SinjohSignedEthUsdOracle } from "../src/oracles/SinjohSignedEthUsdOracle.sol";
import { TestBase } from "./TestBase.sol";

contract SinjohSignedEthUsdOracleTest is TestBase {
    uint256 internal constant SIGNER_KEY = uint256(keccak256("eth-usd-test-signer"));
    uint256 internal constant SECP256K1N =
        0xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141;
    bytes32 internal constant PRICE_TYPEHASH = keccak256(
        "SinjohEthUsdPrice(uint256 chainId,address oracle,uint256 answerE8,uint48 observedAt,uint48 validAfter,uint48 validUntil)"
    );

    SinjohSignedEthUsdOracle internal oracle;

    function setUp() public {
        vm.chainId(4663);
        vm.warp(1_000_000);
        oracle = new SinjohSignedEthUsdOracle(vm.addr(SIGNER_KEY));
    }

    function testPublishesAggregatorCompatibleCompleteRounds() public {
        _update(1_900e8, 999_990, 1_000_000, 1_000_060, SIGNER_KEY);
        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = oracle.latestRoundData();
        assertEq(roundId, 1);
        // The oracle only accepts positive answers.
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(uint256(answer), 1_900e8);
        assertEq(startedAt, 999_990);
        assertEq(updatedAt, 999_990);
        assertEq(answeredInRound, roundId);
        assertEq(oracle.decimals(), 8);
    }

    function testRejectsWrongSignerReplayFutureAndStaleObservations() public {
        vm.expectRevert(SinjohSignedPrice.InvalidSignature.selector);
        _update(1_900e8, 999_990, 1_000_000, 1_000_060, 123);

        _update(1_900e8, 999_990, 1_000_000, 1_000_060, SIGNER_KEY);
        vm.expectRevert(SinjohSignedEthUsdOracle.InvalidPrice.selector);
        _update(1_901e8, 999_990, 1_000_000, 1_000_060, SIGNER_KEY);

        vm.expectRevert(SinjohSignedEthUsdOracle.InvalidPrice.selector);
        _update(1_901e8, 1_000_001, 1_000_000, 1_000_060, SIGNER_KEY);

        vm.expectRevert(SinjohSignedEthUsdOracle.InvalidPrice.selector);
        _update(1_901e8, 999_699, 999_699, 1_000_000, SIGNER_KEY);
    }

    function testRejectsExpiredOrOverlongAuthorization() public {
        vm.expectRevert(SinjohSignedPrice.InvalidValidity.selector);
        _update(1_900e8, 999_990, 999_900, 999_999, SIGNER_KEY);

        vm.expectRevert(SinjohSignedPrice.InvalidValidity.selector);
        _update(1_900e8, 999_990, 1_000_000, 1_000_301, SIGNER_KEY);
    }

    function testNoDataAndWrongChainDeploymentsRevert() public {
        vm.expectRevert(SinjohSignedEthUsdOracle.NoData.selector);
        oracle.latestRoundData();

        vm.chainId(1);
        vm.expectRevert(abi.encodeWithSelector(SinjohSignedEthUsdOracle.WrongChain.selector, 1));
        new SinjohSignedEthUsdOracle(vm.addr(SIGNER_KEY));
    }

    function testRejectsMalleableMalformedAndInvalidVSignatures() public {
        uint48 observedAt = 999_990;
        uint48 validAfter = 1_000_000;
        uint48 validUntil = 1_000_060;
        bytes32 digest = oracle.priceDigest(1_900e8, observedAt, validAfter, validUntil);
        bytes32 ethDigest = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", digest));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_KEY, ethDigest);

        bytes32 highS = bytes32(SECP256K1N - uint256(s));
        uint8 flippedV = v == 27 ? 28 : 27;
        vm.expectRevert(SinjohSignedPrice.InvalidSignature.selector);
        oracle.update(
            1_900e8, observedAt, validAfter, validUntil, abi.encodePacked(r, highS, flippedV)
        );

        vm.expectRevert(SinjohSignedPrice.InvalidSignature.selector);
        oracle.update(1_900e8, observedAt, validAfter, validUntil, hex"1234");

        vm.expectRevert(SinjohSignedPrice.InvalidSignature.selector);
        oracle.update(1_900e8, observedAt, validAfter, validUntil, abi.encodePacked(r, s, uint8(1)));
    }

    function _update(
        uint256 answerE8,
        uint48 observedAt,
        uint48 validAfter,
        uint48 validUntil,
        uint256 signerKey
    ) private {
        bytes32 digest = keccak256(
            abi.encode(
                PRICE_TYPEHASH,
                block.chainid,
                address(oracle),
                answerE8,
                observedAt,
                validAfter,
                validUntil
            )
        );
        bytes32 ethDigest = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", digest));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, ethDigest);
        oracle.update(answerE8, observedAt, validAfter, validUntil, abi.encodePacked(r, s, v));
    }
}
