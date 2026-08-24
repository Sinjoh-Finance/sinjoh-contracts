#!/usr/bin/env bash
set -euo pipefail

package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
baseline_manifest="${BASELINE_RELEASE_MANIFEST:-$package_dir/deployments/project-launcher-v2-4663-e7bed3c-canonical.json}"

fail() {
  echo "mainnet successor preflight failed: $*" >&2
  exit 1
}

command -v jq >/dev/null 2>&1 || fail "jq is required"
command -v cast >/dev/null 2>&1 || fail "cast is required"
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
  || fail "DEPLOYER_ADDRESS must be the authorized deployer $expected_deployer"
export DEPLOYER_ADDRESS="$expected_deployer"
[[ -n "${FOUNDRY_ACCOUNT:-}" ]] \
  || fail "FOUNDRY_ACCOUNT must name the local Foundry keystore for $expected_deployer"
export FOUNDRY_ACCOUNT
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
pons_owner="$(cast call "$PONS_LAUNCH_FACTORY" 'owner()(address)' --rpc-url "$RPC_URL")" \
  || fail "could not read the Pons launch factory owner"
pons_owner_lower="$(printf '%s' "$pons_owner" | tr '[:upper:]' '[:lower:]')"
[[ "$pons_owner_lower" == "$expected_deployer_lower" ]] \
  || fail "Pons launch factory $PONS_LAUNCH_FACTORY is controlled by $pons_owner, not $expected_deployer; complete the explicit ownership handoff before release (no transaction was sent)"

# These successor factories were successfully deployed from the authorized deployer on
# 2026-08-24. Reuse them so a resumed release cannot redeploy the same generation or spend gas
# twice. deploy-release.sh verifies every runtime hash before the core broadcast.
export PONS_PROJECT_ADAPTER_FACTORY=0xAc299024C0f4E561D6e99CEFABB9b7212de729b6
export PONS_PROJECT_ADAPTER_FACTORY_RUNTIME_HASH=0x964762b1cdb587f7dc7d27f796e0ed403e0066e00a7ed0d015c90b1df32c5ec5
export PONS_PROJECT_ADAPTER_IMPLEMENTATION=0x3943b7f46b201CFe5033367Ae2E102555e0ea50F
export PONS_PROJECT_ADAPTER_IMPLEMENTATION_RUNTIME_HASH=0xd61178a140dc8f8df8a0ae4987dc93b7063334496591c10e81aee660d1d916e6
export POOLS_INSTANT_PROJECT_ADAPTER_FACTORY=0xc13238cdF673eE82704255C14C6224fC7AfA9C36
export POOLS_INSTANT_PROJECT_ADAPTER_FACTORY_RUNTIME_HASH=0xccaf8d43bf0d0da6d4a7dd2e539c7d0f2d71c470546c0dc8b1df6e3f96e25428
export POOLS_INSTANT_NO_FEE_PROJECT_ADAPTER_FACTORY=0x990A008705c115eF1cb779B73D20F2BcA865f03A
export POOLS_INSTANT_NO_FEE_PROJECT_ADAPTER_FACTORY_RUNTIME_HASH=0x81e78639a3c06cb115f800feceba601a5eb06e756ef2fec48abfb2376251579c
export POOLS_LBP_PROJECT_ADAPTER_FACTORY=0x00ed429B6810281784372B6Bf610541670815A60
export POOLS_LBP_PROJECT_ADAPTER_FACTORY_RUNTIME_HASH=0x33329edabc21310bac6d6b90c462ba63c139f9937ad9cec6f8bdacda0d86b30b
export POOLS_PROJECT_REGISTRATION_HELPER=0x570CFbE42720d96bcEaa592D2D110EF7211E7FA9
export POOLS_PROJECT_REGISTRATION_HELPER_RUNTIME_HASH=0xde1b2a2c36ea4734ffca677dbb588ede4fc96b1e243b07632e9f1efbb56e7f49
export DEPLOY_FRESH_LAUNCHPAD_FACTORIES=0
export UNLOCKED_DEPLOYMENT=0
export SIMULATE_ONLY=0
export DEPLOYMENT_MANIFEST_PATH="${DEPLOYMENT_MANIFEST_PATH:-deployments/project-launcher-v2-4663.json}"

exec "$package_dir/script/deploy-release.sh"
