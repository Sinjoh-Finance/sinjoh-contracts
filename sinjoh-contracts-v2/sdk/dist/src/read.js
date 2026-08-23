import { basketManagerV2Abi, basketVaultV2Abi, erc4626BasketYieldAdapterAbi, projectAirdropV2Abi, projectFundingBandsV2Abi, projectLauncherV2Abi, projectLiquidityManagerV2Abi, projectMultisigAccountV2Abi, projectRaffleV2Abi, projectRegistryV2Abi, projectRouterV2Abi, projectStakingPoolV2Abi, projectTreasuryVaultV2Abi, } from "./abis.generated.js";
export function predictLaunch(client, launcher, config) {
    return client.readContract({
        address: launcher,
        abi: projectLauncherV2Abi,
        functionName: "predictLaunch",
        args: [config],
    });
}
export function validateLaunchConfig(client, launcher, config) {
    return client.readContract({
        address: launcher,
        abi: projectLauncherV2Abi,
        functionName: "validateLaunchConfig",
        args: [config],
    });
}
export function projectRecord(client, registry, projectId) {
    return client.readContract({
        address: registry,
        abi: projectRegistryV2Abi,
        functionName: "project",
        args: [projectId],
    });
}
export const pendingWork = {
    treasuryBasketRoute(client, treasury, asset) {
        return client.readContract({
            address: treasury,
            abi: projectTreasuryVaultV2Abi,
            functionName: "basketRouteStatus",
            args: [asset],
        });
    },
    router(client, router, asset) {
        return client.readContract({
            address: router,
            abi: projectRouterV2Abi,
            functionName: "workStatus",
            args: [asset],
        });
    },
    airdropAccount(client, airdrop, accountId) {
        return client.readContract({
            address: airdrop,
            abi: projectAirdropV2Abi,
            functionName: "accountStatus",
            args: [accountId],
        });
    },
    airdropEpoch(client, airdrop, accountId, epochId) {
        return client.readContract({
            address: airdrop,
            abi: projectAirdropV2Abi,
            functionName: "epochStatus",
            args: [accountId, epochId],
        });
    },
    airdropCredit(client, airdrop, recipient, asset) {
        return client.readContract({
            address: airdrop,
            abi: projectAirdropV2Abi,
            functionName: "retryableCredit",
            args: [recipient, asset],
        });
    },
    basket(client, manager, basketId) {
        return client.readContract({
            address: manager,
            abi: basketManagerV2Abi,
            functionName: "basketMetadata",
            args: [basketId],
        });
    },
    basketTarget(client, vault, targetIndex) {
        return client.readContract({
            address: vault,
            abi: basketVaultV2Abi,
            functionName: "targetStatus",
            args: [targetIndex],
        });
    },
    erc4626BasketAdapter(client, adapter) {
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
    fundingBand(client, bands, bandId) {
        return client.readContract({
            address: bands,
            abi: projectFundingBandsV2Abi,
            functionName: "bandStatus",
            args: [bandId],
        });
    },
    raffleRound(client, raffle, roundId) {
        return client.readContract({
            address: raffle,
            abi: projectRaffleV2Abi,
            functionName: "roundStatus",
            args: [roundId],
        });
    },
    liquidityAccount(client, liquidityManager, accountId) {
        return client.readContract({
            address: liquidityManager,
            abi: projectLiquidityManagerV2Abi,
            functionName: "accountStatus",
            args: [accountId],
        });
    },
    stakingPosition(client, stakingPool, tokenId) {
        return client.readContract({
            address: stakingPool,
            abi: projectStakingPoolV2Abi,
            functionName: "positionData",
            args: [tokenId],
        });
    },
    multisigTransaction(client, multisig, transactionId) {
        return client.readContract({
            address: multisig,
            abi: projectMultisigAccountV2Abi,
            functionName: "transactionDetails",
            args: [transactionId],
        });
    },
};
//# sourceMappingURL=read.js.map