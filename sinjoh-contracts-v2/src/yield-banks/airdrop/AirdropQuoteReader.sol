// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { AirdropObservationPublisher } from "./AirdropObservationPublisher.sol";

/// @notice RPC simulation helper: apply signed prices, then perform read-only calls.
/// Use through eth_call; no transaction or gas payment is needed to display a portfolio.
/// This contract has no bank permissions, delegatecalls, approvals or asset custody.
contract AirdropQuoteReader {
    using Address for address;
    struct Read { address target; bytes data; }
    AirdropObservationPublisher public immutable publisher;
    bytes32 public immutable publisherCodeHash;
    error InvalidConfiguration();

    constructor(address publisher_) {
        if(publisher_.code.length == 0) revert InvalidConfiguration();
        publisher = AirdropObservationPublisher(publisher_);
        publisherCodeHash = publisher_.codehash;
    }

    function read(
        AirdropObservationPublisher.Observation[] calldata observations,
        uint48 validUntil,
        bytes calldata signature,
        Read[] calldata calls
    ) external returns (bytes[] memory results) {
        if(address(publisher).codehash != publisherCodeHash || calls.length == 0 || calls.length > 100) {
            revert InvalidConfiguration();
        }
        publisher.publishSigned(observations, validUntil, signature);
        results = new bytes[](calls.length);
        for(uint256 i; i < calls.length; ++i) {
            results[i] = calls[i].target.functionStaticCall(calls[i].data);
        }
    }
}
