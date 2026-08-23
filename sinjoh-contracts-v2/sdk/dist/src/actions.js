import { encodeFunctionData, } from "viem";
/** Encodes one typed module mutation for either Multisig or Token Governance workflows. */
export function encodeGovernanceAction(parameters) {
    const { target, abi, functionName, args, value = 0n } = parameters;
    const data = encodeFunctionData({ abi, functionName, args });
    return { target, value, data };
}
//# sourceMappingURL=actions.js.map