// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { PoolId, PoolIdLibrary } from "@uniswap/v4-core/src/types/PoolId.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";

import { ISinjohLaunchVerifier } from "../interfaces/ISinjohLaunchVerifier.sol";
import { ISinjohPrelaunchVerifier } from "../interfaces/ISinjohPrelaunchVerifier.sol";

interface IPonsV2LaunchFactory {
    enum GraduationPhase {
        NotGraduated,
        Swept,
        PoolCreated,
        Rescued
    }

    struct LaunchedToken {
        address token;
        address curve;
        address deployer;
        address creatorFeeRecipient;
        address pairToken;
        uint256 graduationThreshold;
        uint24 poolFee;
        int24 tickSpacing;
        uint16 creatorTaxBps;
        bool buybackEnabled;
        GraduationPhase phase;
        uint256 sweptQuote;
        uint256 sweptTokens;
        uint256 sweptAt;
        bool exists;
    }

    function getLaunchedToken(address token) external view returns (LaunchedToken memory);
    function memeHook() external view returns (address);
    function poolManager() external view returns (address);
}

interface IPonsV2LauncherToken {
    function deployer() external view returns (address);
    function launchFactory() external view returns (address);
    function curve() external view returns (address);
}

interface ISinjohPonsV2AdapterView {
    function creator() external view returns (address);
    function subject() external view returns (address);
    function launchFactory() external view returns (address);
    function curve() external view returns (address);
}

/// @notice Resolves only graduated Pons v2 launches whose quote is native ETH.
/// The launch-time deployer remains the Funding Bands controller even
/// if Pons later rotates the mutable creator-fee recipient.
contract SinjohPonsV2LaunchVerifier is ISinjohLaunchVerifier, ISinjohPrelaunchVerifier {
    using PoolIdLibrary for PoolKey;

    error InvalidAddress();
    error InvalidLaunch();

    IPonsV2LaunchFactory public immutable ponsFactory;
    address public immutable memeHook;
    address public immutable poolManager;
    address public immutable weth;
    bytes32 public immutable sinjohAdapterCodehash;
    bytes32 public immutable sinjohProjectAdapterCodehash;

    constructor(
        address ponsFactory_,
        address memeHook_,
        address weth_,
        bytes32 sinjohAdapterCodehash_,
        bytes32 sinjohProjectAdapterCodehash_
    ) {
        if (
            ponsFactory_.code.length == 0 || memeHook_.code.length == 0 || weth_.code.length == 0
                || sinjohAdapterCodehash_ == bytes32(0)
                || sinjohProjectAdapterCodehash_ == bytes32(0)
        ) {
            revert InvalidAddress();
        }
        IPonsV2LaunchFactory factory = IPonsV2LaunchFactory(ponsFactory_);
        address poolManager_ = factory.poolManager();
        if (factory.memeHook() != memeHook_ || poolManager_.code.length == 0) {
            revert InvalidAddress();
        }
        ponsFactory = factory;
        memeHook = memeHook_;
        poolManager = poolManager_;
        weth = weth_;
        sinjohAdapterCodehash = sinjohAdapterCodehash_;
        sinjohProjectAdapterCodehash = sinjohProjectAdapterCodehash_;
    }

    function verify(address subject, bytes calldata launchData)
        external
        view
        returns (VerifiedLaunch memory launch)
    {
        if (launchData.length != 0 && launchData.length != 32) revert InvalidLaunch();
        if (ponsFactory.memeHook() != memeHook || ponsFactory.poolManager() != poolManager) {
            revert InvalidLaunch();
        }
        IPonsV2LaunchFactory.LaunchedToken memory record = ponsFactory.getLaunchedToken(subject);
        if (
            !record.exists || record.token != subject || record.curve.code.length == 0
                || record.deployer == address(0)
                || record.phase != IPonsV2LaunchFactory.GraduationPhase.PoolCreated
                || record.pairToken != address(0) || record.tickSpacing <= 0
        ) revert InvalidLaunch();

        address creator = record.deployer;
        if (record.deployer.code.length != 0) {
            if (!_isApprovedAdapterCodehash(record.deployer.codehash)) revert InvalidLaunch();
            ISinjohPonsV2AdapterView adapter = ISinjohPonsV2AdapterView(record.deployer);
            creator = adapter.creator();
            if (
                creator == address(0) || adapter.subject() != subject
                    || adapter.launchFactory() != address(ponsFactory)
                    || adapter.curve() != record.curve
            ) revert InvalidLaunch();
        }

        IPonsV2LauncherToken token = IPonsV2LauncherToken(subject);
        if (
            token.deployer() != record.deployer || token.launchFactory() != address(ponsFactory)
                || token.curve() != record.curve
        ) revert InvalidLaunch();
        uint256 currentSupply = IERC20(subject).totalSupply();
        uint256 launchSupply =
            launchData.length == 0 ? currentSupply : abi.decode(launchData, (uint256));
        if (currentSupply == 0 || launchSupply == 0 || currentSupply > launchSupply) {
            revert InvalidLaunch();
        }

        address token0 = subject < record.pairToken ? subject : record.pairToken;
        address token1 = subject < record.pairToken ? record.pairToken : subject;
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: record.poolFee,
            tickSpacing: record.tickSpacing,
            hooks: IHooks(memeHook)
        });
        PoolId poolId = key.toId();

        launch = VerifiedLaunch({
            creatorAtLaunch: creator,
            subject: subject,
            venue: Venue.UNISWAP_V4,
            quoteAsset: record.pairToken,
            pool: address(0),
            poolFee: record.poolFee,
            tickSpacing: record.tickSpacing,
            hooks: memeHook,
            poolId: PoolId.unwrap(poolId),
            launchSupply: launchSupply
        });
    }

    /// @notice Verifies the adapter-originated launch while the Pons curve is
    /// still live. This binds escrowed inventory to the actual subject,
    /// immutable launch deployer, human creator, curve, and launch supply.
    function verifyPreparation(address subject, address adapter_, bytes calldata launchData)
        external
        view
        returns (VerifiedPreparation memory preparation)
    {
        if (launchData.length != 0 || adapter_ == address(0)) revert InvalidLaunch();
        if (ponsFactory.memeHook() != memeHook || ponsFactory.poolManager() != poolManager) {
            revert InvalidLaunch();
        }
        IPonsV2LaunchFactory.LaunchedToken memory record = ponsFactory.getLaunchedToken(subject);
        if (
            !record.exists || record.token != subject || record.curve.code.length == 0
                || record.deployer != adapter_ || record.pairToken != address(0)
                || record.phase != IPonsV2LaunchFactory.GraduationPhase.NotGraduated
                || !_isApprovedAdapterCodehash(adapter_.codehash)
        ) revert InvalidLaunch();

        ISinjohPonsV2AdapterView adapter = ISinjohPonsV2AdapterView(adapter_);
        address creator = adapter.creator();
        if (
            creator == address(0) || adapter.subject() != subject
                || adapter.launchFactory() != address(ponsFactory)
                || adapter.curve() != record.curve
        ) revert InvalidLaunch();

        IPonsV2LauncherToken token = IPonsV2LauncherToken(subject);
        if (
            token.deployer() != adapter_ || token.launchFactory() != address(ponsFactory)
                || token.curve() != record.curve
        ) revert InvalidLaunch();
        uint256 launchSupply = IERC20(subject).totalSupply();
        if (launchSupply == 0) revert InvalidLaunch();
        preparation = VerifiedPreparation({
            creatorAtLaunch: creator, subject: subject, launchSupply: launchSupply
        });
    }

    function _isApprovedAdapterCodehash(bytes32 codehash) private view returns (bool) {
        return codehash == sinjohAdapterCodehash || codehash == sinjohProjectAdapterCodehash;
    }
}
