import { encodeFunctionData, parseUnits, } from "viem";
import { projectFundingBandsV2Abi, projectGovernorV2Abi, projectMultisigAccountV2Abi, projectTreasuryVaultV2Abi, } from "./abis.generated.js";
export function governanceBatch(actions) {
    if (actions.length === 0)
        throw new RangeError("Governance batch cannot be empty");
    return {
        targets: actions.map((action) => action.target),
        values: actions.map((action) => action.value),
        calldatas: actions.map((action) => action.data),
    };
}
/** Encodes a wallet transaction that submits the same typed batch to a Multisig Account. */
export function encodeMultisigSubmission(actions) {
    const batch = governanceBatch(actions);
    return encodeFunctionData({
        abi: projectMultisigAccountV2Abi,
        functionName: "submit",
        args: [batch.targets, batch.values, batch.calldatas],
    });
}
/** Encodes a wallet transaction that proposes the same typed batch to Token Governance. */
export function encodeTokenGovernanceProposal(actions, description) {
    if (description.trim().length === 0)
        throw new RangeError("Proposal description cannot be empty");
    const batch = governanceBatch(actions);
    return encodeFunctionData({
        abi: projectGovernorV2Abi,
        functionName: "propose",
        args: [batch.targets, batch.values, batch.calldatas, description],
    });
}
/** Encodes one typed module mutation for either Multisig or Token Governance workflows. */
export function encodeGovernanceAction(parameters) {
    const { target, abi, functionName, args, value = 0n } = parameters;
    const data = encodeFunctionData({ abi, functionName, args });
    return { target, value, data };
}
export const fundingBandDestination = {
    creator: 0,
    treasury: 1,
    buybackBurn: 2,
    buybackAirdrop: 3,
    router: 4,
    raffle: 5,
    basketViaTreasury: 6,
};
/** Converts a human-readable USD market cap into the protocol's fixed 8-decimal representation. */
export function marketCapUsdE8(value) {
    const result = parseUnits(value, 8);
    if (result <= 0n)
        throw new RangeError("Market cap must be greater than zero");
    return result;
}
/** Builds a no-route destination config for destinations that need no adapter calldata. */
export function simpleFundingBandConfig(parameters) {
    const lowerMarketCapUsdE8 = marketCapUsdE8(parameters.lowerMarketCapUsd);
    const upperMarketCapUsdE8 = marketCapUsdE8(parameters.upperMarketCapUsd);
    if (lowerMarketCapUsdE8 >= upperMarketCapUsdE8) {
        throw new RangeError("Upper market cap must be greater than lower market cap");
    }
    if (parameters.subjectAmount <= 0n) {
        throw new RangeError("Subject amount must be greater than zero");
    }
    return {
        lowerMarketCapUsdE8,
        upperMarketCapUsdE8,
        subjectAmount: parameters.subjectAmount,
        destination: parameters.destination,
        destinationConfig: "0x",
    };
}
/** Builds the exact Treasury-prefund + band-create governance batch. */
export function buildFundingBandCreationActions(parameters) {
    const { treasury, fundingBands, subject, config, observationData = "0x" } = parameters;
    return [
        encodeGovernanceAction({
            target: treasury,
            abi: projectTreasuryVaultV2Abi,
            functionName: "send",
            args: [subject, config.subjectAmount, fundingBands],
        }),
        encodeGovernanceAction({
            target: fundingBands,
            abi: projectFundingBandsV2Abi,
            functionName: "createBand",
            args: [config, observationData],
        }),
    ];
}
//# sourceMappingURL=actions.js.map