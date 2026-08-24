#!/usr/bin/env bash
set -euo pipefail

package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
baseline_manifest="${BASELINE_RELEASE_MANIFEST:-$package_dir/deployments/project-launcher-v2-4663-e7bed3c-canonical.json}"

fail() {
  echo "mainnet successor preflight failed: $*" >&2
  exit 1
}

command -v jq >/dev/null 2>&1 || fail "jq is required"
[[ -f "$baseline_manifest" ]] || fail "baseline release manifest not found: $baseline_manifest"

manifest_value() {
  local key="$1"
  local value
  value="$(jq -er --arg key "$key" '.[$key]' "$baseline_manifest")" \
    || fail "baseline manifest is missing $key"
  [[ "$value" != "null" && -n "$value" ]] || fail "baseline manifest has no value for $key"
  printf '%s' "$value"
}

export RPC_URL="${RPC_URL:-https://rpc.mainnet.chain.robinhood.com}"
export EXPECTED_CHAIN_ID=4663
expected_deployer=0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49
requested_deployer="${DEPLOYER_ADDRESS:-$expected_deployer}"
requested_deployer_lower="$(printf '%s' "$requested_deployer" | tr '[:upper:]' '[:lower:]')"
expected_deployer_lower="$(printf '%s' "$expected_deployer" | tr '[:upper:]' '[:lower:]')"
[[ "$requested_deployer_lower" == "$expected_deployer_lower" ]] \
  || fail "DEPLOYER_ADDRESS must be the reviewed production owner $expected_deployer"
export DEPLOYER_ADDRESS="$expected_deployer"
export FOUNDRY_ACCOUNT="${FOUNDRY_ACCOUNT:-sinjoh-v2-production-owner}"
export PROTOCOL_FEE_RECIPIENT="$(manifest_value protocolFeeRecipient)"
export RANDOMNESS_ADAPTER="$(manifest_value randomnessAdapter)"
export RANDOMNESS_ADAPTER_RUNTIME_HASH="$(manifest_value randomnessAdapterRuntimeHash)"
export PROJECT_SWAP_ADAPTER="$(manifest_value projectSwapAdapter)"
export PROJECT_SWAP_ADAPTER_RUNTIME_HASH="$(manifest_value projectSwapAdapterRuntimeHash)"
export FUNDING_BAND_QUOTE_ASSET="$(manifest_value fundingBandQuoteAsset)"
export FUNDING_BAND_QUOTE_ASSET_RUNTIME_HASH="$(manifest_value fundingBandQuoteAssetRuntimeHash)"
export FUNDING_BAND_QUOTE_USD_AGGREGATOR="$(manifest_value fundingBandQuoteUsdAggregator)"
export FUNDING_BAND_QUOTE_USD_AGGREGATOR_RUNTIME_HASH="$(manifest_value fundingBandQuoteUsdAggregatorRuntimeHash)"
export V3_FACTORY="$(manifest_value v3Factory)"
export V3_FACTORY_RUNTIME_HASH="$(manifest_value v3FactoryRuntimeHash)"
export V3_POSITION_MANAGER="$(manifest_value v3PositionManager)"
export V3_POSITION_MANAGER_RUNTIME_HASH="$(manifest_value v3PositionManagerRuntimeHash)"
export V4_POSITION_MANAGER="$(manifest_value v4PositionManager)"
export V4_POSITION_MANAGER_RUNTIME_HASH="$(manifest_value v4PositionManagerRuntimeHash)"
export V4_STATE_VIEW="$(manifest_value v4StateView)"
export V4_STATE_VIEW_RUNTIME_HASH="$(manifest_value v4StateViewRuntimeHash)"
export PERMIT2="$(manifest_value permit2)"
export PERMIT2_RUNTIME_HASH="$(manifest_value permit2RuntimeHash)"
export PONS_LAUNCH_FACTORY="$(manifest_value ponsLaunchFactory)"
export PONS_LAUNCH_FACTORY_RUNTIME_HASH="$(manifest_value ponsLaunchFactoryRuntimeHash)"
export PONS_FEE_ESCROW=0xd3AFEB2a57f70eF218Aa82451c51B2fb0416Ac9e
export PONS_FEE_ESCROW_RUNTIME_HASH=0xf25f75cfbc1637ba068dc34f69098fa4e8a80f8ee8fe7bf7820594e0b3fed2f1
export DEPLOY_FRESH_LAUNCHPAD_FACTORIES=1
export UNLOCKED_DEPLOYMENT=0
export SIMULATE_ONLY=0
export DEPLOYMENT_MANIFEST_PATH="${DEPLOYMENT_MANIFEST_PATH:-deployments/project-launcher-v2-4663.json}"

exec "$package_dir/script/deploy-release.sh"
