// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IChainlinkAggregatorV3 } from "../interfaces/IChainlinkAggregatorV3.sol";
import { SinjohRotatableQuoteSigner } from "../access/SinjohRotatableQuoteSigner.sol";
import { SinjohSignedPrice } from "../libraries/SinjohSignedPrice.sol";

/// @notice AggregatorV3-compatible ETH/USD snapshot source for Robinhood Chain,
/// with a dedicated signer and a governance-controlled recovery path.
contract SinjohSignedEthUsdOracle is IChainlinkAggregatorV3, SinjohRotatableQuoteSigner {
    uint256 private constant ROBINHOOD_CHAIN_ID = 4663;
    uint48 public constant MAXIMUM_VALIDITY = 5 minutes;
    uint48 public constant MAXIMUM_OBSERVATION_DELAY = 5 minutes;
    bytes32 public constant PRICE_TYPEHASH = keccak256(
        "SinjohEthUsdPrice(uint256 chainId,address oracle,uint256 answerE8,uint48 observedAt,uint48 validAfter,uint48 validUntil)"
    );

    error WrongChain(uint256 actual);
    error InvalidPrice();
    error NoData();

    event AnswerUpdated(uint256 indexed answerE8, uint256 indexed roundId, uint256 observedAt);

    uint8 public constant decimals = 8;
    uint80 private _roundId;
    int256 private _answer;
    uint48 private _updatedAt;

    constructor(address initialGovernance, address initialQuoteSigner)
        SinjohRotatableQuoteSigner(initialGovernance, initialQuoteSigner)
    {
        if (block.chainid != ROBINHOOD_CHAIN_ID) revert WrongChain(block.chainid);
    }

    function priceDigest(uint256 answerE8, uint48 observedAt, uint48 validAfter, uint48 validUntil)
        public
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                PRICE_TYPEHASH,
                block.chainid,
                address(this),
                answerE8,
                observedAt,
                validAfter,
                validUntil
            )
        );
    }

    function update(
        uint256 answerE8,
        uint48 observedAt,
        uint48 validAfter,
        uint48 validUntil,
        bytes calldata signature
    ) external {
        if (
            answerE8 == 0 || answerE8 > uint256(type(int256).max) || observedAt <= _updatedAt
                // Timestamp comparisons reject future or stale signed observations.
                // forge-lint: disable-next-line(block-timestamp)
                || observedAt > block.timestamp
                // forge-lint: disable-next-line(block-timestamp)
                || block.timestamp - observedAt > MAXIMUM_OBSERVATION_DELAY
                || observedAt > validUntil
        ) revert InvalidPrice();
        SinjohSignedPrice.validate(
            priceDigest(answerE8, observedAt, validAfter, validUntil),
            quoteSigner,
            validAfter,
            validUntil,
            MAXIMUM_VALIDITY,
            signature
        );

        unchecked {
            _roundId++;
        }
        // `answerE8` was bounded to int256.max above.
        // forge-lint: disable-next-line(unsafe-typecast)
        _answer = int256(answerE8);
        _updatedAt = observedAt;
        emit AnswerUpdated(answerE8, _roundId, observedAt);
    }

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        roundId = _roundId;
        if (roundId == 0) revert NoData();
        answer = _answer;
        startedAt = _updatedAt;
        updatedAt = _updatedAt;
        answeredInRound = roundId;
    }
}
