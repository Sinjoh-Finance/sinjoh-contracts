#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
launchpad_dir="$repo_dir/sinjoh-launchpad-adapters"
contracts_dir="$repo_dir/sinjoh-contracts-v2"
account="${FOUNDRY_ACCOUNT:-sinjoh-deployer}"
password_args=()
if [[ -n "${FOUNDRY_PASSWORD_FILE:-}" ]]; then
  password_args+=(--password-file "$FOUNDRY_PASSWORD_FILE")
fi
expected_factory=0x7DCeEaB0A53684b001A4900768a52eAcDb27294e
expected_quote_signer=0xd89fB916dD031Da9b0A32e820307c2d41a7dDe09

fail() {
  echo "corrective Project V2 deployment failed: $*" >&2
  exit 1
}

for command_name in railway jq forge cast; do
  command -v "$command_name" >/dev/null 2>&1 || fail "$command_name is required"
done

variables_json="$(
  RAILWAY_CALLER=skill:use-railway@1.3.7 \
  RAILWAY_AGENT_SESSION=sinjoh-production-release-20260825 \
    railway variable list \
      --project 3e8e2a91-1b86-498e-887c-6cbd5d694dcb \
      --environment fbc453ac-828e-4727-8184-90c9ac588626 \
      --service 039acfe1-72a1-4d66-8470-af0366c7b626 \
      --json
)"
primary_rpc="$(jq -er '(.variables // .).SINJOH_RPC_PRIMARY' <<<"$variables_json")"
secondary_rpc="$(jq -er '(.variables // .).SINJOH_RPC_SECONDARY' <<<"$variables_json")"
unset variables_json

[[ "$(cast chain-id --rpc-url "$primary_rpc")" == "4663" ]] || fail "primary RPC is not chain 4663"
[[ "$(cast chain-id --rpc-url "$secondary_rpc")" == "4663" ]] || fail "secondary RPC is not chain 4663"

cd "$launchpad_dir"
FOUNDRY_ETH_RPC_URL="$primary_rpc" forge script \
  script/DeployPonsV2PairBuybackInfrastructure.s.sol:DeployPonsV2PairBuybackInfrastructure \
  --account "$account" \
  "${password_args[@]}" \
  --broadcast \
  --slow \
  -vv

broadcast="$launchpad_dir/broadcast/DeployPonsV2PairBuybackInfrastructure.s.sol/4663/run-latest.json"
[[ -f "$broadcast" ]] || fail "pair-buyback broadcast receipt was not written"
adapter="$(jq -er '[.transactions[] | select(.contractName == "SinjohPonsV2PairBuybackAdapter")][0].contractAddress' "$broadcast")"
guard="$(jq -er '[.transactions[] | select(.contractName == "SinjohPonsV2PairBuybackPriceGuard")][0].contractAddress' "$broadcast")"
[[ "$(jq -r '[.receipts[] | select(.status != "0x1" and .status != 1)] | length' "$broadcast")" == "0" ]] \
  || fail "a pair-buyback deployment transaction failed"

verify_binding() {
  local rpc="$1"
  local label="$2"
  local adapter_factory guard_factory guard_signer
  adapter_factory="$(cast call "$adapter" 'launchFactory()(address)' --rpc-url "$rpc")"
  guard_factory="$(cast call "$guard" 'launchFactory()(address)' --rpc-url "$rpc")"
  guard_signer="$(cast call "$guard" 'quoteSigner()(address)' --rpc-url "$rpc")"
  [[ "$(printf '%s' "$adapter_factory" | tr '[:upper:]' '[:lower:]')" == "$(printf '%s' "$expected_factory" | tr '[:upper:]' '[:lower:]')" ]] \
    || fail "$label reports adapter factory $adapter_factory"
  [[ "$(printf '%s' "$guard_factory" | tr '[:upper:]' '[:lower:]')" == "$(printf '%s' "$expected_factory" | tr '[:upper:]' '[:lower:]')" ]] \
    || fail "$label reports guard factory $guard_factory"
  [[ "$(printf '%s' "$guard_signer" | tr '[:upper:]' '[:lower:]')" == "$(printf '%s' "$expected_quote_signer" | tr '[:upper:]' '[:lower:]')" ]] \
    || fail "$label reports guard signer $guard_signer"
}

verify_binding "$primary_rpc" primary
verify_binding "$secondary_rpc" secondary

adapter_hash="$(cast keccak "$(cast code "$adapter" --rpc-url "$primary_rpc")")"
guard_hash="$(cast keccak "$(cast code "$guard" --rpc-url "$primary_rpc")")"
[[ "$(printf '%s' "$adapter_hash" | tr '[:upper:]' '[:lower:]')" == "$(cast keccak "$(cast code "$adapter" --rpc-url "$secondary_rpc")" | tr '[:upper:]' '[:lower:]')" ]] \
  || fail "adapter runtime hash differs across providers"
[[ "$(printf '%s' "$guard_hash" | tr '[:upper:]' '[:lower:]')" == "$(cast keccak "$(cast code "$guard" --rpc-url "$secondary_rpc")" | tr '[:upper:]' '[:lower:]')" ]] \
  || fail "guard runtime hash differs across providers"

export PONS_V2_PAIR_BUYBACK_ADAPTER="$adapter"
export PONS_V2_PAIR_BUYBACK_ADAPTER_RUNTIME_HASH="$adapter_hash"
export PONS_V2_PAIR_BUYBACK_PRICE_GUARD="$guard"
export PONS_V2_PAIR_BUYBACK_PRICE_GUARD_RUNTIME_HASH="$guard_hash"

cd "$contracts_dir"
RPC_URL="$primary_rpc" \
RPC_VERIFICATION_URL="$secondary_rpc" \
FOUNDRY_ACCOUNT="$account" \
SIMULATE_ONLY=0 \
DEPLOYMENT_MANIFEST_PATH=deployments/project-launcher-v2-4663-corrected.json \
  ./script/deploy-successor-mainnet.sh

echo "corrected pair adapter: $adapter"
echo "corrected pair guard: $guard"
