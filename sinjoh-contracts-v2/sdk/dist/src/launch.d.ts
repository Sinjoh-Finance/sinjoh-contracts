import { type Address, type Hex } from "viem";
import type { ProjectLaunchConfig } from "./types.js";
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
    tokenAllocations?: readonly {
        recipient: Address;
        amount: bigint;
    }[];
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
export declare function buildProjectLaunchConfig(policy: ProjectLaunchPolicy, choices: ProjectLaunchChoices): ProjectLaunchConfig;
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
export declare function buildLaunchFromPreset(preset: ProjectLaunchPreset, choices: CreatorLaunchChoices): ProjectLaunchConfig;
/** Corrective, user-facing copy for the Launcher's stable custom error names. */
export declare function launchErrorMessage(errorName: string): string;
//# sourceMappingURL=launch.d.ts.map