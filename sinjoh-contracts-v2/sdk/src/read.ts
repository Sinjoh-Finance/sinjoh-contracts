import type { Address, Hex, PublicClient } from "viem";
import {
  basketManagerV2Abi,
  basketVaultV2Abi,
  erc4626BasketYieldAdapterAbi,
  projectAirdropV2Abi,
  projectFundingBandsV2Abi,
  projectLauncherV2Abi,
  projectLiquidityManagerV2Abi,
  projectMultisigAccountV2Abi,
  projectRaffleV2Abi,
  projectRegistryV2Abi,
  projectRouterV2Abi,
  projectStakingPoolV2Abi,
  projectTreasuryVaultV2Abi,
} from "./abis.generated.js";
import type { ProjectLaunchConfig } from "./types.js";

export function predictLaunch(
  client: PublicClient,
  launcher: Address,
  config: ProjectLaunchConfig,
) {
  return client.readContract({
    address: launcher,
    abi: projectLauncherV2Abi,
    functionName: "predictLaunch",
    args: [config],
  });
}

export function validateLaunchConfig(
  client: PublicClient,
  launcher: Address,
  config: ProjectLaunchConfig,
) {
  return client.readContract({
    address: launcher,
    abi: projectLauncherV2Abi,
    functionName: "validateLaunchConfig",
    args: [config],
  });
}

export function projectRecord(client: PublicClient, registry: Address, projectId: Hex) {
  return client.readContract({
    address: registry,
    abi: projectRegistryV2Abi,
    functionName: "project",
    args: [projectId],
  });
}

export const pendingWork = {
  treasuryBasketRoute(client: PublicClient, treasury: Address, asset: Address) {
    return client.readContract({
      address: treasury,
      abi: projectTreasuryVaultV2Abi,
      functionName: "basketRouteStatus",
      args: [asset],
    });
  },
  router(client: PublicClient, router: Address, asset: Address) {
    return client.readContract({
      address: router,
      abi: projectRouterV2Abi,
      functionName: "workStatus",
      args: [asset],
    });
  },
  airdropAccount(client: PublicClient, airdrop: Address, accountId: Hex) {
    return client.readContract({
      address: airdrop,
      abi: projectAirdropV2Abi,
      functionName: "accountStatus",
      args: [accountId],
    });
  },
  airdropEpoch(client: PublicClient, airdrop: Address, accountId: Hex, epochId: bigint) {
    return client.readContract({
      address: airdrop,
      abi: projectAirdropV2Abi,
      functionName: "epochStatus",
      args: [accountId, epochId],
    });
  },
  basket(client: PublicClient, manager: Address, basketId: bigint) {
    return client.readContract({
      address: manager,
      abi: basketManagerV2Abi,
      functionName: "basketMetadata",
      args: [basketId],
    });
  },
  basketTarget(client: PublicClient, vault: Address, targetIndex: bigint) {
    return client.readContract({
      address: vault,
      abi: basketVaultV2Abi,
      functionName: "targetStatus",
      args: [targetIndex],
    });
  },
  erc4626BasketAdapter(client: PublicClient, adapter: Address) {
    return Promise.all([
      client.readContract({
        address: adapter,
        abi: erc4626BasketYieldAdapterAbi,
        functionName: "basketVault",
      }),
      client.readContract({
        address: adapter,
        abi: erc4626BasketYieldAdapterAbi,
        functionName: "vault",
      }),
      client.readContract({
        address: adapter,
        abi: erc4626BasketYieldAdapterAbi,
        functionName: "depositAsset",
      }),
      client.readContract({
        address: adapter,
        abi: erc4626BasketYieldAdapterAbi,
        functionName: "managedPrincipal",
      }),
      client.readContract({
        address: adapter,
        abi: erc4626BasketYieldAdapterAbi,
        functionName: "totalAssets",
      }),
    ]);
  },
  fundingBand(client: PublicClient, bands: Address, bandId: bigint) {
    return client.readContract({
      address: bands,
      abi: projectFundingBandsV2Abi,
      functionName: "bandStatus",
      args: [bandId],
    });
  },
  raffleRound(client: PublicClient, raffle: Address, roundId: bigint) {
    return client.readContract({
      address: raffle,
      abi: projectRaffleV2Abi,
      functionName: "roundStatus",
      args: [roundId],
    });
  },
  liquidityAccount(client: PublicClient, liquidityManager: Address, accountId: Hex) {
    return client.readContract({
      address: liquidityManager,
      abi: projectLiquidityManagerV2Abi,
      functionName: "accountStatus",
      args: [accountId],
    });
  },
  stakingPosition(client: PublicClient, stakingPool: Address, tokenId: bigint) {
    return client.readContract({
      address: stakingPool,
      abi: projectStakingPoolV2Abi,
      functionName: "positionData",
      args: [tokenId],
    });
  },
  multisigTransaction(client: PublicClient, multisig: Address, transactionId: Hex) {
    return client.readContract({
      address: multisig,
      abi: projectMultisigAccountV2Abi,
      functionName: "transactionDetails",
      args: [transactionId],
    });
  },
} as const;
