import type { ContractFunctionArgs, ContractFunctionReturnType } from "viem";
import { projectLauncherV2Abi, projectRegistryV2Abi } from "./abis.generated.js";
export type ProjectLaunchConfig = ContractFunctionArgs<typeof projectLauncherV2Abi, "view", "validateLaunchConfig">[0];
export type ProjectLaunchPreview = ContractFunctionReturnType<typeof projectLauncherV2Abi, "view", "validateLaunchConfig">;
export type ProjectRecord = ContractFunctionReturnType<typeof projectRegistryV2Abi, "view", "project">;
//# sourceMappingURL=types.d.ts.map