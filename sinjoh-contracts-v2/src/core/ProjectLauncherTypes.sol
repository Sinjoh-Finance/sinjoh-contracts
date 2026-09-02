// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import { AirdropEligibilityMode } from "../airdrop/AirdropTypes.sol";
import { BasketConfig } from "../basket/BasketTypes.sol";
import { TokenGovernanceConfig } from "../governance/TokenGovernanceConfig.sol";
import { RaffleTypes } from "../raffle/RaffleTypes.sol";
import { RouterRouteInput } from "../router/RouterTypes.sol";

enum LaunchGovernanceMode {
    MULTISIG,
    TOKEN_HOLDER
}

enum LaunchVoteSource {
    LIQUID,
    STAKED
}

struct ModuleSelection {
    bool treasury;
    bool router;
    bool staking;
    bool airdrop;
    bool basket;
    bool fundingBands;
    bool raffle;
    bool liquidity;
}

struct LaunchTokenAllocation {
    address recipient;
    uint256 amount;
}

struct GovernanceLaunchConfig {
    address[3] multisigSigners;
    TokenGovernanceConfig tokenGovernance;
}

struct StakingLaunchConfig {
    address guardian;
    uint64 lockDuration;
}

struct AirdropLaunchConfig {
    address attestor;
    AirdropEligibilityMode eligibilityMode;
    address[] additionalExclusions;
}

struct TreasuryLaunchConfig {
    uint16 basketAllocationBps;
    address[] basketRouteAssets;
}

struct BandsLaunchConfig {
    address quoteAsset;
    address marketCapGuard;
    address positionAdapter;
    uint32 twapWindow;
    address quoteUsdOracle;
    uint48 confirmationPeriod;
    uint48 maximumObservationAge;
    bytes32[] integrationApprovalProof;
}

struct LaunchProfileConfig {
    address canonicalPool;
    address[] additionalCustodyExclusions;
}

struct ProjectLaunchConfig {
    address creator;
    string name;
    string symbol;
    uint256 totalSupply;
    bytes32 salt;
    LaunchGovernanceMode governanceMode;
    LaunchVoteSource voteSource;
    ModuleSelection modules;
    LaunchTokenAllocation[] tokenAllocations;
    GovernanceLaunchConfig governance;
    StakingLaunchConfig staking;
    AirdropLaunchConfig airdrop;
    TreasuryLaunchConfig treasury;
    RouterRouteInput[] routerRoutes;
    BasketConfig basket;
    address[] basketERC4626Vaults;
    BandsLaunchConfig bands;
    RaffleTypes.Config raffle;
    LaunchProfileConfig launchProfile;
    string metadataURI;
}

struct ProjectLaunchAddresses {
    address subject;
    address controller;
    address multisigAccount;
    address tokenGovernor;
    address tokenTimelock;
    address voteSource;
    address liquidVotes;
    address treasury;
    address router;
    address stakingPool;
    address posNft;
    address airdrop;
    address raffle;
    address liquidityManager;
    address fundingBands;
    address fundingBandMarketCapGuard;
    address fundingBandPositionAdapter;
    address basketManager;
    address primaryBasketVault;
    address[] basketYieldAdapters;
    uint256 primaryBasketId;
}

struct ProjectLaunchPreview {
    bytes32 launchConfigHash;
    bytes32 projectId;
    uint256 enabledModules;
    ProjectLaunchAddresses addresses;
}

struct LauncherReleaseConfig {
    address protocolFeeRecipient;
    bytes32 integrationApprovalRoot;
    bool basketEnabled;
    address raffleImplementation;
    address randomnessAdapter;
    address basketVaultImplementation;
    address erc4626YieldAdapterFactory;
    address fundingBandV3IntegrationFactory;
    address v3Factory;
    address v3PositionManager;
    address v4PositionManager;
    address v4StateView;
    address permit2;
}

struct CreationCodeBinding {
    bytes32 moduleKey;
    address store;
}
