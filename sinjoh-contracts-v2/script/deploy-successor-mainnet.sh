#!/usr/bin/env bash
set -euo pipefail

package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
baseline_manifest="${BASELINE_RELEASE_MANIFEST:-$package_dir/deployments/project-launcher-v2-4663-e7bed3c-canonical.json}"
mainnet_deployments="${MAINNET_DEPLOYMENTS:-$package_dir/../mainnet-deployments.json}"

fail() {
  echo "mainnet successor preflight failed: $*" >&2
  exit 1
}

command -v jq >/dev/null 2>&1 || fail "jq is required"
command -v cast >/dev/null 2>&1 || fail "cast is required"
[[ -f "$baseline_manifest" ]] || fail "baseline release manifest not found: $baseline_manifest"
[[ -f "$mainnet_deployments" ]] || fail "mainnet deployments not found: $mainnet_deployments"

[[ -n "${RPC_URL:-}" ]] \
  || fail "RPC_URL must be the authenticated production Chainstack endpoint; public RPC fallbacks are forbidden"
[[ -n "${RPC_VERIFICATION_URL:-}" ]] \
  || fail "RPC_VERIFICATION_URL must be the authenticated production QuickNode endpoint"
[[ "$RPC_URL" == https://* ]] \
  || fail "RPC_URL must use HTTPS for the production Chainstack endpoint"
[[ "$RPC_VERIFICATION_URL" == https://* ]] \
  || fail "RPC_VERIFICATION_URL must use HTTPS for the production QuickNode endpoint"

rpc_host() {
  local without_scheme="${1#*://}"
  printf '%s' "${without_scheme%%/*}" | tr '[:upper:]' '[:lower:]'
}

primary_rpc_host="$(rpc_host "$RPC_URL")"
verification_rpc_host="$(rpc_host "$RPC_VERIFICATION_URL")"
case "$primary_rpc_host" in
  *.core.chainstack.com|*.p2pify.com) ;;
  *) fail "RPC_URL host must be the production Chainstack endpoint, got $primary_rpc_host" ;;
esac
case "$verification_rpc_host" in
  *.quiknode.pro) ;;
  *) fail "RPC_VERIFICATION_URL host must be the production QuickNode endpoint, got $verification_rpc_host" ;;
esac
[[ "$RPC_URL" != "$RPC_VERIFICATION_URL" ]] \
  || fail "RPC_URL and RPC_VERIFICATION_URL must be independent endpoints"

manifest_value() {
  local key="$1"
  local value
  value="$(jq -er --arg key "$key" '.[$key]' "$baseline_manifest")" \
    || fail "baseline manifest is missing $key"
  [[ "$value" != "null" && -n "$value" ]] || fail "baseline manifest has no value for $key"
  printf '%s' "$value"
}

deployment_value() {
  local deployment="$1"
  local field="$2"
  local value
  value="$(jq -er --arg deployment "$deployment" --arg field "$field" \
    '.currentInfrastructure[$deployment][$field]' "$mainnet_deployments")" \
    || fail "mainnet deployments is missing $deployment.$field"
  [[ "$value" != "null" && -n "$value" ]] \
    || fail "mainnet deployments has no value for $deployment.$field"
  printf '%s' "$value"
}

export EXPECTED_CHAIN_ID=4663
primary_chain_id="$(cast chain-id --rpc-url "$RPC_URL")" \
  || fail "could not read the Chainstack production chain ID"
verification_chain_id="$(cast chain-id --rpc-url "$RPC_VERIFICATION_URL")" \
  || fail "could not read the QuickNode production chain ID"
[[ "$primary_chain_id" == "$EXPECTED_CHAIN_ID" ]] \
  || fail "Chainstack RPC chain $primary_chain_id does not match $EXPECTED_CHAIN_ID"
[[ "$verification_chain_id" == "$EXPECTED_CHAIN_ID" ]] \
  || fail "QuickNode RPC chain $verification_chain_id does not match $EXPECTED_CHAIN_ID"

primary_block="$(cast block-number --rpc-url "$RPC_URL")" \
  || fail "could not read the Chainstack production head"
verification_block="$(cast block-number --rpc-url "$RPC_VERIFICATION_URL")" \
  || fail "could not read the QuickNode production head"
block_delta=$((primary_block - verification_block))
(( block_delta < 0 )) && block_delta=$((-block_delta))
(( block_delta <= 20 )) \
  || fail "production RPC heads disagree by $block_delta blocks (Chainstack $primary_block, QuickNode $verification_block)"

expected_deployer=0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49
requested_deployer="${DEPLOYER_ADDRESS:-$expected_deployer}"
requested_deployer_lower="$(printf '%s' "$requested_deployer" | tr '[:upper:]' '[:lower:]')"
expected_deployer_lower="$(printf '%s' "$expected_deployer" | tr '[:upper:]' '[:lower:]')"
[[ "$requested_deployer_lower" == "$expected_deployer_lower" ]] \
  || fail "DEPLOYER_ADDRESS must be the authorized deployer $expected_deployer"
export DEPLOYER_ADDRESS="$expected_deployer"
primary_nonce="$(cast nonce "$DEPLOYER_ADDRESS" --rpc-url "$RPC_URL")" \
  || fail "could not read the authorized deployer nonce through Chainstack"
verification_nonce="$(cast nonce "$DEPLOYER_ADDRESS" --rpc-url "$RPC_VERIFICATION_URL")" \
  || fail "could not read the authorized deployer nonce through QuickNode"
[[ "$primary_nonce" == "$verification_nonce" ]] \
  || fail "production RPC deployer nonces disagree (Chainstack $primary_nonce, QuickNode $verification_nonce)"
simulate_only="${SIMULATE_ONLY:-0}"
[[ "$simulate_only" == "0" || "$simulate_only" == "1" ]] \
  || fail "SIMULATE_ONLY must be 0 or 1"
stateful_fork_rpc_url="${STATEFUL_FORK_RPC_URL:-}"
if [[ -n "$stateful_fork_rpc_url" ]]; then
  [[ "$simulate_only" == "0" ]] \
    || fail "STATEFUL_FORK_RPC_URL requires SIMULATE_ONLY=0"
  fork_chain_id="$(cast chain-id --rpc-url "$stateful_fork_rpc_url")" \
    || fail "could not read the stateful fork chain ID"
  [[ "$fork_chain_id" == "$EXPECTED_CHAIN_ID" ]] \
    || fail "stateful fork chain $fork_chain_id does not match $EXPECTED_CHAIN_ID"
  fork_nonce="$(cast nonce "$DEPLOYER_ADDRESS" --rpc-url "$stateful_fork_rpc_url")" \
    || fail "could not read the authorized deployer nonce from the stateful fork"
  [[ "$fork_nonce" == "$primary_nonce" ]] \
    || fail "stateful fork deployer nonce $fork_nonce does not match production nonce $primary_nonce"
elif [[ "$simulate_only" == "0" ]]; then
  [[ -n "${FOUNDRY_ACCOUNT:-}" ]] \
    || fail "FOUNDRY_ACCOUNT must name the local Foundry keystore for $expected_deployer"
  export FOUNDRY_ACCOUNT
fi
export PROTOCOL_FEE_RECIPIENT="$(manifest_value protocolFeeRecipient)"
export RANDOMNESS_ADAPTER="$(manifest_value randomnessAdapter)"
export RANDOMNESS_ADAPTER_RUNTIME_HASH="$(manifest_value randomnessAdapterRuntimeHash)"
export PROJECT_SWAP_ADAPTER="$(manifest_value projectSwapAdapter)"
export PROJECT_SWAP_ADAPTER_RUNTIME_HASH="$(manifest_value projectSwapAdapterRuntimeHash)"
export WETH="$(jq -er '.letscashDependencies.weth.address' "$mainnet_deployments")"
export PONS_V2_PAIR_BUYBACK_ADAPTER="$(deployment_value ponsV2PairBuybackAdapter address)"
export PONS_V2_PAIR_BUYBACK_ADAPTER_RUNTIME_HASH="$(deployment_value ponsV2PairBuybackAdapter runtimeCodeHash)"
export PONS_V2_PAIR_BUYBACK_PRICE_GUARD="$(deployment_value ponsV2PairBuybackPriceGuard address)"
export PONS_V2_PAIR_BUYBACK_PRICE_GUARD_RUNTIME_HASH="$(deployment_value ponsV2PairBuybackPriceGuard runtimeCodeHash)"
export FLAP_BUYBACK_ADAPTER="$(deployment_value flapBuybackAdapter address)"
export FLAP_BUYBACK_ADAPTER_RUNTIME_HASH="$(deployment_value flapBuybackAdapter runtimeCodeHash)"
export FLAP_BUYBACK_PRICE_GUARD="$(deployment_value flapBuybackPriceGuard address)"
export FLAP_BUYBACK_PRICE_GUARD_RUNTIME_HASH="$(deployment_value flapBuybackPriceGuard runtimeCodeHash)"
export FLAP_PAYOUT_PRICE_GUARD="$(deployment_value flapPayoutPriceGuard address)"
export FLAP_PAYOUT_PRICE_GUARD_RUNTIME_HASH="$(deployment_value flapPayoutPriceGuard runtimeCodeHash)"
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
  || fail "could not read the Pons launch factory owner through Chainstack"
pons_owner_verification="$(cast call "$PONS_LAUNCH_FACTORY" 'owner()(address)' --rpc-url "$RPC_VERIFICATION_URL")" \
  || fail "could not read the Pons launch factory owner through QuickNode"
pons_owner_lower="$(printf '%s' "$pons_owner" | tr '[:upper:]' '[:lower:]')"
pons_owner_verification_lower="$(printf '%s' "$pons_owner_verification" | tr '[:upper:]' '[:lower:]')"
[[ "$pons_owner_lower" == "$expected_deployer_lower" ]] \
  || fail "Pons launch factory $PONS_LAUNCH_FACTORY is controlled by $pons_owner, not $expected_deployer; complete the explicit ownership handoff before release (no transaction was sent)"
[[ "$pons_owner_verification_lower" == "$expected_deployer_lower" ]] \
  || fail "QuickNode reports Pons launch factory owner $pons_owner_verification, not $expected_deployer (no transaction was sent)"

# Project adapter factories bind to one immutable Project V2 launcher generation and reject any
# later rebind. A successor release therefore requires fresh factories; reusing the prior release's
# addresses would only fail after the core deployment had already consumed gas.
export PONS_FEE_ESCROW="$(jq -er '.dependencies.ponsV2FeeEscrow.address' "$mainnet_deployments")"
export PONS_FEE_ESCROW_RUNTIME_HASH="$(
  jq -er '.dependencies.ponsV2FeeEscrow.runtimeCodeHash' "$mainnet_deployments"
)"
export DEPLOY_FRESH_LAUNCHPAD_FACTORIES=1
if [[ -n "$stateful_fork_rpc_url" ]]; then
  export RPC_URL="$stateful_fork_rpc_url"
  export RPC_VERIFICATION_URL="$stateful_fork_rpc_url"
  export UNLOCKED_DEPLOYMENT=1
else
  export UNLOCKED_DEPLOYMENT=0
fi
export SIMULATE_ONLY="$simulate_only"
export DEPLOYMENT_MANIFEST_PATH="${DEPLOYMENT_MANIFEST_PATH:-deployments/project-launcher-v2-4663.json}"

exec "$package_dir/script/deploy-release.sh"
