import {
  encodeFunctionData,
  type Abi,
  type Address,
  type ContractFunctionArgs,
  type ContractFunctionName,
  type EncodeFunctionDataParameters,
  type Hex,
} from "viem";

export interface GovernanceAction {
  target: Address;
  value: bigint;
  data: Hex;
}

/** Encodes one typed module mutation for either Multisig or Token Governance workflows. */
export function encodeGovernanceAction<
  const TAbi extends Abi,
  TFunctionName extends ContractFunctionName<TAbi, "payable" | "nonpayable">,
>(parameters: {
  target: Address;
  abi: TAbi;
  functionName: TFunctionName;
  args: ContractFunctionArgs<TAbi, "payable" | "nonpayable", TFunctionName>;
  value?: bigint;
}): GovernanceAction {
  const { target, abi, functionName, args, value = 0n } = parameters;
  const data = encodeFunctionData(
    { abi, functionName, args } as unknown as EncodeFunctionDataParameters,
  );
  return { target, value, data };
}
