import { type Address, type Hex } from "viem";
import type { ProjectLaunchConfig } from "./types.js";
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