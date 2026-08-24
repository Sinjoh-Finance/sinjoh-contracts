import { isAddress, type Address, type Hex } from "viem";
import type { ProjectLaunchConfig } from "./types.js";

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
const BURN_ADDRESS = "0x000000000000000000000000000000000000dead";
const BYTES32 = /^0x[0-9a-fA-F]{64}$/;
const textEncoder = new TextEncoder();

/** Release-owned configuration. It contains no creator, signer, guardian, or attestor identity. */
export interface ProjectLaunchPolicy {
  id: string;
  protocolVersion: string;
  modules: ProjectLaunchConfig["modules"];
  treasury: ProjectLaunchConfig["treasury"];
  routerRoutes: ProjectLaunchConfig["routerRoutes"];
  basket: ProjectLaunchConfig["basket"];
  basketERC4626Vaults: ProjectLaunchConfig["basketERC4626Vaults"];
  bands: ProjectLaunchConfig["bands"];
  raffle: ProjectLaunchConfig["raffle"];
  launchProfile: ProjectLaunchConfig["launchProfile"];
}

export interface ProjectGovernanceChoices {
  mode: "multisig" | "token-holder";
  voteSource: 0 | 1;
  multisigSigners?: readonly [Address, Address, Address];
  tokenPolicy?: Omit<ProjectLaunchConfig["governance"]["tokenGovernance"], "referenceSupply">;
}

/** Every identity and project-specific value is supplied for this launch, never by a preset. */
export interface ProjectLaunchChoices {
  creator: Address;
  name: string;
  symbol: string;
  totalSupply: bigint;
  salt: Hex;
  distribution: "launcher" | "launchpad";
  tokenAllocations?: readonly { recipient: Address; amount: bigint }[];
  governance: ProjectGovernanceChoices;
  stakingGuardian?: Address;
  stakingLockDuration?: bigint;
  airdropAttestor?: Address;
  airdropEligibilityMode?: ProjectLaunchConfig["airdrop"]["eligibilityMode"];
  airdropAdditionalExclusions?: readonly Address[];
  metadataURI?: string;
}

/**
 * Builds a launch from release policy plus project-owned choices. Launchpad mode deliberately emits
 * no token allocations because Pons/Pools distribute the one canonical token themselves.
 */
export function buildProjectLaunchConfig(
  policy: ProjectLaunchPolicy,
  choices: ProjectLaunchChoices,
): ProjectLaunchConfig {
  if (policy.id.trim().length === 0) throw new RangeError("Launch policy ID cannot be empty");
  if (policy.protocolVersion.trim().length === 0) {
    throw new RangeError("Launch policy protocol version cannot be empty");
  }
  assertUsableAddress(choices.creator, "Creator");
  if (choices.name.trim().length === 0) throw new RangeError("Token name cannot be empty");
  if (choices.symbol.trim().length === 0) throw new RangeError("Token symbol cannot be empty");
  if (choices.totalSupply <= 0n) throw new RangeError("Total supply must be greater than zero");
  if (!BYTES32.test(choices.salt)) throw new RangeError("Launch salt must be exactly 32 bytes");
  const metadataURI = choices.metadataURI ?? "";
  if (textEncoder.encode(metadataURI).length > 512) {
    throw new RangeError("Metadata URI cannot exceed 512 UTF-8 bytes");
  }

  const tokenAllocations = buildTokenAllocations(choices);
  const multisigSigners = buildMultisigSigners(choices.governance, choices.creator);
  const zeroSigners = [ZERO_ADDRESS, ZERO_ADDRESS, ZERO_ADDRESS] as const;
  const tokenPolicy = choices.governance.tokenPolicy ?? {
    votingDelay: 3_600,
    votingPeriod: 259_200,
    proposalThresholdBps: 100,
    quorumBps: 1_000,
    timelockDelay: 86_400,
  };

  const stakingGuardian = choices.stakingGuardian ?? ZERO_ADDRESS;
  const stakingLockDuration = choices.stakingLockDuration ?? 0n;
  if (policy.modules.staking) {
    if (stakingGuardian.toLowerCase() === BURN_ADDRESS) {
      throw new RangeError("Staking guardian cannot be the burn address");
    }
    if (stakingLockDuration <= 0n) {
      throw new RangeError("Staking lock duration must be greater than zero");
    }
  }
  const airdropAttestor = choices.airdropAttestor ?? ZERO_ADDRESS;
  if (policy.modules.airdrop) {
    assertUsableAddress(airdropAttestor, "Airdrop attestor");
    if (airdropAttestor.toLowerCase() === choices.creator.toLowerCase()) {
      throw new RangeError("Airdrop attestor must be independent from the creator");
    }
  }

  return {
    creator: choices.creator,
    name: choices.name.trim(),
    symbol: choices.symbol.trim(),
    totalSupply: choices.totalSupply,
    salt: choices.salt,
    governanceMode: choices.governance.mode === "multisig" ? 0 : 1,
    voteSource: choices.governance.mode === "multisig" ? 0 : choices.governance.voteSource,
    modules: policy.modules,
    tokenAllocations,
    governance: {
      multisigSigners: choices.governance.mode === "multisig" ? multisigSigners : zeroSigners,
      tokenGovernance: { ...tokenPolicy, referenceSupply: choices.totalSupply },
    },
    staking: { guardian: stakingGuardian, lockDuration: stakingLockDuration },
    airdrop: {
      attestor: airdropAttestor,
      eligibilityMode: choices.airdropEligibilityMode ?? 0,
      additionalExclusions: choices.airdropAdditionalExclusions ?? [],
    },
    treasury: policy.treasury,
    routerRoutes: policy.routerRoutes,
    basket: policy.basket,
    basketERC4626Vaults: policy.basketERC4626Vaults,
    bands: policy.bands,
    raffle: policy.raffle,
    launchProfile: policy.launchProfile,
    metadataURI,
  };
}

function buildMultisigSigners(
  governance: ProjectGovernanceChoices,
  creator: Address,
): readonly [Address, Address, Address] {
  if (governance.mode !== "multisig") return [creator, creator, creator];
  if (!governance.multisigSigners) {
    throw new RangeError("Multisig governance requires exactly three signers");
  }
  const signers = governance.multisigSigners.map((signer, index) => {
    assertUsableAddress(signer, `Multisig signer ${index + 1}`);
    return signer;
  }).sort((left, right) => left.toLowerCase().localeCompare(right.toLowerCase()));
  if (new Set(signers.map((signer) => signer.toLowerCase())).size !== 3) {
    throw new RangeError("Multisig signers must be distinct");
  }
  return signers as [Address, Address, Address];
}

function buildTokenAllocations(
  choices: ProjectLaunchChoices,
): readonly { recipient: Address; amount: bigint }[] {
  const allocations = choices.tokenAllocations ?? [];
  if (choices.distribution === "launchpad") {
    if (allocations.length !== 0) {
      throw new RangeError("Launchpad projects cannot submit a second token allocation");
    }
    return [];
  }
  if (allocations.length === 0 || allocations.length > 16) {
    throw new RangeError("Token allocations must contain between 1 and 16 recipients");
  }
  const seen = new Set<string>();
  let total = 0n;
  return allocations.map((allocation, index) => {
    assertUsableAddress(allocation.recipient, `Allocation ${index + 1} recipient`);
    if (allocation.amount <= 0n) {
      throw new RangeError(`Allocation ${index + 1} amount must be greater than zero`);
    }
    const normalized = allocation.recipient.toLowerCase();
    if (seen.has(normalized)) {
      throw new RangeError(`Allocation ${index + 1} duplicates an earlier recipient`);
    }
    seen.add(normalized);
    total += allocation.amount;
    if (index === allocations.length - 1 && total !== choices.totalSupply) {
      throw new RangeError("Token allocations must add up to the total supply exactly");
    }
    return allocation;
  });
}

/**
 * A complete platform-reviewed configuration. Infrastructure addresses, proofs, routes, module
 * dependencies, and protocol defaults belong here—not in a creator form.
 */
export interface ProjectLaunchPreset {
  id: string;
  protocolVersion: string;
  config: ProjectLaunchConfig;
}

/** Fields the creator actually owns in the normal launch journey. */
export interface CreatorLaunchChoices {
  creator: Address;
  name: string;
  symbol: string;
  totalSupply: bigint;
  salt: Hex;
  tokenAllocations: readonly {
    recipient: Address;
    amount: bigint;
  }[];
  metadataURI?: string;
}

/**
 * Hydrates one reviewed launch preset without exposing protocol plumbing to the creator.
 * The returned tuple can be passed directly to `validateLaunchConfig`, then `launch`.
 */
export function buildLaunchFromPreset(
  preset: ProjectLaunchPreset,
  choices: CreatorLaunchChoices,
): ProjectLaunchConfig {
  if (preset.id.trim().length === 0) throw new RangeError("Launch preset ID cannot be empty");
  if (preset.protocolVersion.trim().length === 0) {
    throw new RangeError("Launch preset protocol version cannot be empty");
  }
  if (preset.config.modules?.raffle && (
    preset.config.raffle.creator.toLowerCase() !== ZERO_ADDRESS
      || preset.config.raffle.randomness.toLowerCase() !== ZERO_ADDRESS
      || preset.config.raffle.protocolFeeRecipient.toLowerCase() !== ZERO_ADDRESS
  )) {
    throw new RangeError(
      "The selected Raffle preset is not compatible with this release. Refresh the launch profile",
    );
  }
  assertUsableAddress(choices.creator, "Creator");
  if (choices.name.trim().length === 0) throw new RangeError("Token name cannot be empty");
  if (choices.symbol.trim().length === 0) throw new RangeError("Token symbol cannot be empty");
  if (choices.totalSupply <= 0n) throw new RangeError("Total supply must be greater than zero");
  if (!BYTES32.test(choices.salt)) throw new RangeError("Launch salt must be exactly 32 bytes");
  if (choices.tokenAllocations.length === 0 || choices.tokenAllocations.length > 16) {
    throw new RangeError("Token allocations must contain between 1 and 16 recipients");
  }

  const seen = new Set<string>();
  let allocated = 0n;
  const tokenAllocations = choices.tokenAllocations.map((allocation, index) => {
    assertUsableAddress(allocation.recipient, `Allocation ${index + 1} recipient`);
    if (allocation.amount <= 0n) {
      throw new RangeError(`Allocation ${index + 1} amount must be greater than zero`);
    }
    const normalized = allocation.recipient.toLowerCase();
    if (seen.has(normalized)) {
      throw new RangeError(`Allocation ${index + 1} duplicates an earlier recipient`);
    }
    seen.add(normalized);
    allocated += allocation.amount;
    return { recipient: allocation.recipient, amount: allocation.amount };
  });
  if (allocated !== choices.totalSupply) {
    throw new RangeError("Token allocations must add up to the total supply exactly");
  }

  const metadataURI = choices.metadataURI ?? "";
  if (textEncoder.encode(metadataURI).length > 512) {
    throw new RangeError("Metadata URI cannot exceed 512 UTF-8 bytes");
  }

  return {
    ...preset.config,
    creator: choices.creator,
    name: choices.name.trim(),
    symbol: choices.symbol.trim(),
    totalSupply: choices.totalSupply,
    salt: choices.salt,
    tokenAllocations,
    metadataURI,
  };
}

/** Corrective, user-facing copy for the Launcher's stable custom error names. */
export function launchErrorMessage(errorName: string): string {
  return launchErrorMessages[errorName] ?? "This launch configuration is no longer valid. Review it and try again.";
}

const launchErrorMessages: Readonly<Record<string, string>> = {
  InvalidCreator: "Choose a valid creator wallet.",
  CreatorMustLaunch: "Connect the creator wallet selected for this project.",
  InvalidTokenMetadata: "Enter both a token name and symbol.",
  InvalidMetadataURI: "Shorten the metadata link to 512 bytes or fewer.",
  InvalidTotalSupply: "Make the token allocations add up to the total supply exactly.",
  InvalidTokenAllocations: "Add between 1 and 16 token allocation recipients.",
  InvalidTokenAllocation: "Every token allocation needs a valid recipient and a positive amount.",
  DuplicateTokenAllocation: "Combine duplicate token recipients into one allocation.",
  AllocationToCustody: "A launch custody contract cannot receive the initial token allocation.",
  InvalidModuleDependencies: "One selected feature requires another feature that is currently disabled.",
  InvalidGovernanceConfiguration: "Review the selected governance settings and signers.",
  InvalidStakingConfiguration: "Choose a valid staking lock and optional guardian.",
  InvalidAirdropConfiguration: "Review the Airdrop mode and attestor settings.",
  InvalidTreasuryConfiguration: "Review the Treasury Basket allocation settings.",
  InvalidBasketConfiguration: "The selected Basket preset or asset set is not available.",
  InvalidBandsConfiguration: "The selected Funding Bands profile is not available.",
  InvalidRaffleConfiguration: "The selected Raffle profile is unavailable. Refresh and try again.",
  InvalidRouterPlaceholder: "A Router destination requires a module that is not enabled.",
  CreatorExcluded: "The creator wallet cannot be excluded from this project's holder benefits.",
  ModuleDeploymentMismatch: "Address verification failed. Do not submit this launch; refresh the release profile.",
};

function assertUsableAddress(address: Address, label: string): void {
  const normalized = address.toLowerCase();
  if (!isAddress(address) || normalized === ZERO_ADDRESS || normalized === BURN_ADDRESS) {
    throw new RangeError(`${label} must be a valid non-burn address`);
  }
}
