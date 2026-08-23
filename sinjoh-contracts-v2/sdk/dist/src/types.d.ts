import type { ContractFunctionArgs, ContractFunctionReturnType } from "viem";
import { projectFundingBandsV2Abi, projectLauncherV2Abi, projectLiquidityManagerV2Abi, projectRegistryV2Abi } from "./abis.generated.js";
export type ProjectLaunchConfig = ContractFunctionArgs<typeof projectLauncherV2Abi, "view", "validateLaunchConfig">[0];
export type ProjectLaunchPreview = ContractFunctionReturnType<typeof projectLauncherV2Abi, "view", "validateLaunchConfig">;
export type ProjectRecord = ContractFunctionReturnType<typeof projectRegistryV2Abi, "view", "project">;
export type FundingBandConfig = ContractFunctionArgs<typeof projectFundingBandsV2Abi, "nonpayable", "createBand">[0];
export type LiquidityAccountConfig = ContractFunctionReturnType<typeof projectLiquidityManagerV2Abi, "view", "accountConfig">;
//# sourceMappingURL=types.d.ts.map