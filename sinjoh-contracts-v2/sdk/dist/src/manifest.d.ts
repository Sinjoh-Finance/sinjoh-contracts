import { type Address, type Hex } from "viem";
import type { ProjectLaunchConfig, ProjectLaunchPreview, ProjectRecord } from "./types.js";
type JsonPrimitive = boolean | null | number | string;
export type JsonValue = JsonPrimitive | readonly JsonValue[] | {
    readonly [key: string]: JsonValue;
};
export interface ProjectReleaseReference {
    gitCommit: string;
    buildHash: string;
    launcher: Address;
    registry: Address;
}
export interface ProjectLaunchManifestV1 {
    schemaVersion: "1.0";
    chainId: string;
    transactionHash: Hex;
    blockNumber: string;
    release: ProjectReleaseReference;
    launchConfigHash: Hex;
    projectId: Hex;
    subject: Address;
    creator: Address;
    controller: Address;
    enabledModules: string;
    configuration: JsonValue;
    predictedAddresses: JsonValue;
    registryRecord: JsonValue;
}
/**
 * Produces a JSON-safe project provenance artifact after launch. The caller supplies the exact
 * preflight result and Registry readback; any address, identity, mode, supply, or module mismatch
 * fails before an artifact can be published.
 */
export declare function buildProjectLaunchManifest(parameters: {
    chainId: bigint;
    transactionHash: Hex;
    blockNumber: bigint;
    release: ProjectReleaseReference;
    config: ProjectLaunchConfig;
    preview: ProjectLaunchPreview;
    record: ProjectRecord;
    registeredLaunchConfigHash: Hex;
}): ProjectLaunchManifestV1;
/** Stable serialization for storage, signing, or hashing. Object keys are sorted recursively. */
export declare function serializeProjectLaunchManifest(manifest: ProjectLaunchManifestV1): string;
export declare function projectLaunchManifestHash(manifest: ProjectLaunchManifestV1): Hex;
export {};
//# sourceMappingURL=manifest.d.ts.map