#!/usr/bin/env bash
set -euo pipefail

package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
manifest_path="${1:-}"

if [[ -z "$manifest_path" ]]; then
  echo "usage: RPC_URL=<url> ./script/verify-release-sources.sh <manifest.json>" >&2
  exit 1
fi
if [[ "$manifest_path" != /* ]]; then
  manifest_path="$package_dir/$manifest_path"
fi
[[ -f "$manifest_path" ]] || { echo "manifest not found: $manifest_path" >&2; exit 1; }
[[ -n "${RPC_URL:-}" ]] || { echo "RPC_URL is required" >&2; exit 1; }

chain_id="$(jq -r '.chainId' "$manifest_path")"
actual_chain_id="$(cast chain-id --rpc-url "$RPC_URL")"
[[ "$actual_chain_id" == "$chain_id" ]] \
  || { echo "RPC chain $actual_chain_id does not match manifest chain $chain_id" >&2; exit 1; }

verifier="${SOURCE_VERIFIER:-sourcify}"
# Foundry otherwise lets unrelated ambient verifier settings override the provider selected here.
unset VERIFIER_URL VERIFIER_API_KEY ETHERSCAN_API_KEY
verification_args=(
  --chain-id "$chain_id"
  --rpc-url "$RPC_URL"
  --verifier "$verifier"
  --guess-constructor-args
  --watch
  --retries 8
  --delay 5
)
if [[ -n "${SOURCE_VERIFIER_URL:-}" ]]; then
  verification_args+=(--verifier-url "$SOURCE_VERIFIER_URL")
fi
if [[ -n "${SOURCE_VERIFIER_API_KEY:-}" ]]; then
  verification_args+=(--verifier-api-key "$SOURCE_VERIFIER_API_KEY")
fi

verify() {
  local manifest_key="$1"
  local contract="$2"
  local address
  address="$(jq -r --arg key "$manifest_key" '.[$key]' "$manifest_path")"
  verify_address "$address" "$contract"
}

verify_address() {
  local address="$1"
  local contract="$2"
  if [[ "$verifier" == "sourcify" ]] && command -v curl >/dev/null 2>&1; then
    local status
    status="$(curl -fsS --max-time 20 \
      "https://sourcify.dev/server/v2/contract/$chain_id/$address" \
      | jq -r '.match // empty' 2>/dev/null || true)"
    if [[ "$status" == "match" || "$status" == "exact_match" ]]; then
      echo "source already verified: $address ($contract)"
      return
    fi
  fi
  forge verify-contract "$address" "$contract" "${verification_args[@]}"
}

cd "$package_dir"
verify raffleImplementation src/raffle/ProjectRaffleV2.sol:ProjectRaffleV2
verify fundingBandV3IntegrationFactory \
  src/bands/FundingBandV3IntegrationFactory.sol:FundingBandV3IntegrationFactory
verify fundingBandQuoteUsdOracle \
  src/bands/FundingBandQuoteUsdOracleAdapter.sol:FundingBandQuoteUsdOracleAdapter
verify projectV3PriceGuard500 \
  src/integrations/ProjectV3TwapPriceGuard.sol:ProjectV3TwapPriceGuard
verify projectV3PriceGuard3000 \
  src/integrations/ProjectV3TwapPriceGuard.sol:ProjectV3TwapPriceGuard
verify projectV3PriceGuard10000 \
  src/integrations/ProjectV3TwapPriceGuard.sol:ProjectV3TwapPriceGuard

deployment_engine="$(jq -r '.deploymentEngine' "$manifest_path")"
for module in TOKEN MULTISIG TIMELOCK STAKING TREASURY AIRDROP ROUTER BANDS LIQUIDITY; do
  module_key="$(cast keccak "$module")"
  store="$(cast call "$deployment_engine" 'creationCodeStore(bytes32)(address)' \
    "$module_key" --rpc-url "$RPC_URL")"
  verify_address "$store" src/core/CreationCodeStoreV2.sol:CreationCodeStoreV2
done

verify registry src/core/ProjectRegistryV2.sol:ProjectRegistryV2
verify deploymentEngine src/core/ProjectLaunchDeployerV2.sol:ProjectLaunchDeployerV2
verify launcher src/core/ProjectLauncherV2.sol:ProjectLauncherV2

echo "verified all release sources from $manifest_path"
