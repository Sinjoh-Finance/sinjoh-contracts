import { isAddress, type Address, type Hex } from "viem";
import type { ProjectLaunchConfig } from "./types.js";

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
const BURN_ADDRESS = "0x000000000000000000000000000000000000dead";
const BYTES32 = /^0x[0-9a-fA-F]{64}$/;
const textEncoder = new TextEncoder();

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
  InvalidRaffleConfiguration: "Review the selected Raffle settings.",
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
