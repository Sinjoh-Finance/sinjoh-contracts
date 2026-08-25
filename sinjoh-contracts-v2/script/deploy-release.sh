#!/usr/bin/env bash
set -euo pipefail

package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo_dir="$(git -C "$package_dir" rev-parse --show-toplevel)"
package_relative="${package_dir#"$repo_dir"/}"

fail() {
  echo "release preflight failed: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command '$1' is not installed"
}

require_environment() {
  local name="$1"
  [[ -n "${!name:-}" ]] || fail "required environment variable '$name' is missing"
}

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
  else
    fail "either sha256sum or shasum is required"
  fi
}

for command_name in git forge cast node npm awk tr; do
  require_command "$command_name"
done

if [[ "${SIMULATE_ONLY:-0}" == "0" ]]; then
  source_changes="$(
    git -C "$repo_dir" status --porcelain --untracked-files=normal -- \
      "$package_relative" \
      ":(exclude)$package_relative/deployments/project-launcher-v2-*.json"
  )"
  if [[ -n "$source_changes" ]]; then
    fail "the contracts-v2 source tree is not clean"
  fi
fi

required_environment=(
  RPC_URL EXPECTED_CHAIN_ID DEPLOYER_ADDRESS PROTOCOL_FEE_RECIPIENT
  RANDOMNESS_ADAPTER RANDOMNESS_ADAPTER_RUNTIME_HASH
  PROJECT_SWAP_ADAPTER PROJECT_SWAP_ADAPTER_RUNTIME_HASH
  WETH
  PONS_V2_PAIR_BUYBACK_ADAPTER PONS_V2_PAIR_BUYBACK_ADAPTER_RUNTIME_HASH
  PONS_V2_PAIR_BUYBACK_PRICE_GUARD PONS_V2_PAIR_BUYBACK_PRICE_GUARD_RUNTIME_HASH
  FLAP_BUYBACK_ADAPTER FLAP_BUYBACK_ADAPTER_RUNTIME_HASH
  FLAP_BUYBACK_PRICE_GUARD FLAP_BUYBACK_PRICE_GUARD_RUNTIME_HASH
  FLAP_PAYOUT_PRICE_GUARD FLAP_PAYOUT_PRICE_GUARD_RUNTIME_HASH
  FUNDING_BAND_QUOTE_ASSET FUNDING_BAND_QUOTE_ASSET_RUNTIME_HASH
  FUNDING_BAND_QUOTE_USD_AGGREGATOR FUNDING_BAND_QUOTE_USD_AGGREGATOR_RUNTIME_HASH
  V3_FACTORY V3_FACTORY_RUNTIME_HASH V3_POSITION_MANAGER V3_POSITION_MANAGER_RUNTIME_HASH
  V4_POSITION_MANAGER V4_POSITION_MANAGER_RUNTIME_HASH V4_STATE_VIEW V4_STATE_VIEW_RUNTIME_HASH
  PERMIT2 PERMIT2_RUNTIME_HASH
  PONS_LAUNCH_FACTORY PONS_LAUNCH_FACTORY_RUNTIME_HASH
)
fresh_launchpad_factories="${DEPLOY_FRESH_LAUNCHPAD_FACTORIES:-0}"
if [[ "$fresh_launchpad_factories" != "0" && "$fresh_launchpad_factories" != "1" ]]; then
  fail "DEPLOY_FRESH_LAUNCHPAD_FACTORIES must be 0 or 1"
fi
if [[ "$fresh_launchpad_factories" == "1" ]]; then
  required_environment+=(PONS_FEE_ESCROW PONS_FEE_ESCROW_RUNTIME_HASH)
else
  required_environment+=(
    PONS_PROJECT_ADAPTER_FACTORY PONS_PROJECT_ADAPTER_FACTORY_RUNTIME_HASH
    POOLS_INSTANT_PROJECT_ADAPTER_FACTORY POOLS_INSTANT_PROJECT_ADAPTER_FACTORY_RUNTIME_HASH
    POOLS_INSTANT_NO_FEE_PROJECT_ADAPTER_FACTORY POOLS_INSTANT_NO_FEE_PROJECT_ADAPTER_FACTORY_RUNTIME_HASH
    POOLS_LBP_PROJECT_ADAPTER_FACTORY POOLS_LBP_PROJECT_ADAPTER_FACTORY_RUNTIME_HASH
    PONS_PROJECT_ADAPTER_IMPLEMENTATION PONS_PROJECT_ADAPTER_IMPLEMENTATION_RUNTIME_HASH
    POOLS_PROJECT_REGISTRATION_HELPER POOLS_PROJECT_REGISTRATION_HELPER_RUNTIME_HASH
  )
fi
for environment_name in "${required_environment[@]}"; do
  require_environment "$environment_name"
done

simulate_only="${SIMULATE_ONLY:-0}"
if [[ "$simulate_only" != "0" && "$simulate_only" != "1" ]]; then
  fail "SIMULATE_ONLY must be 0 or 1"
fi
unlocked_deployment="${UNLOCKED_DEPLOYMENT:-0}"
if [[ "$unlocked_deployment" != "0" && "$unlocked_deployment" != "1" ]]; then
  fail "UNLOCKED_DEPLOYMENT must be 0 or 1"
fi
if [[ "$fresh_launchpad_factories" == "1" && "$simulate_only" == "1" ]]; then
  fail "fresh launchpad factories require a stateful fork rehearsal or broadcast"
fi
if [[ "$simulate_only" == "0" ]]; then
  if [[ "$unlocked_deployment" == "0" ]]; then
    require_environment FOUNDRY_ACCOUNT
  fi
fi

actual_chain_id="$(cast chain-id --rpc-url "$RPC_URL")"
[[ "$actual_chain_id" == "$EXPECTED_CHAIN_ID" ]] \
  || fail "RPC chain $actual_chain_id does not match EXPECTED_CHAIN_ID $EXPECTED_CHAIN_ID"
if [[ "$EXPECTED_CHAIN_ID" == "4663" ]]; then
  require_environment RPC_VERIFICATION_URL
  verification_chain_id="$(cast chain-id --rpc-url "$RPC_VERIFICATION_URL")"
  [[ "$verification_chain_id" == "$EXPECTED_CHAIN_ID" ]] \
    || fail "verification RPC chain $verification_chain_id does not match EXPECTED_CHAIN_ID $EXPECTED_CHAIN_ID"
fi

runtime_pairs=(
  "RANDOMNESS_ADAPTER:RANDOMNESS_ADAPTER_RUNTIME_HASH"
  "PROJECT_SWAP_ADAPTER:PROJECT_SWAP_ADAPTER_RUNTIME_HASH"
  "PONS_V2_PAIR_BUYBACK_ADAPTER:PONS_V2_PAIR_BUYBACK_ADAPTER_RUNTIME_HASH"
  "PONS_V2_PAIR_BUYBACK_PRICE_GUARD:PONS_V2_PAIR_BUYBACK_PRICE_GUARD_RUNTIME_HASH"
  "FLAP_BUYBACK_ADAPTER:FLAP_BUYBACK_ADAPTER_RUNTIME_HASH"
  "FLAP_BUYBACK_PRICE_GUARD:FLAP_BUYBACK_PRICE_GUARD_RUNTIME_HASH"
  "FLAP_PAYOUT_PRICE_GUARD:FLAP_PAYOUT_PRICE_GUARD_RUNTIME_HASH"
  "FUNDING_BAND_QUOTE_ASSET:FUNDING_BAND_QUOTE_ASSET_RUNTIME_HASH"
  "FUNDING_BAND_QUOTE_USD_AGGREGATOR:FUNDING_BAND_QUOTE_USD_AGGREGATOR_RUNTIME_HASH"
  "V3_FACTORY:V3_FACTORY_RUNTIME_HASH"
  "V3_POSITION_MANAGER:V3_POSITION_MANAGER_RUNTIME_HASH"
  "V4_POSITION_MANAGER:V4_POSITION_MANAGER_RUNTIME_HASH"
  "V4_STATE_VIEW:V4_STATE_VIEW_RUNTIME_HASH"
  "PERMIT2:PERMIT2_RUNTIME_HASH"
  "PONS_LAUNCH_FACTORY:PONS_LAUNCH_FACTORY_RUNTIME_HASH"
)
if [[ "$fresh_launchpad_factories" == "1" ]]; then
  runtime_pairs+=("PONS_FEE_ESCROW:PONS_FEE_ESCROW_RUNTIME_HASH")
else
  runtime_pairs+=(
    "PONS_PROJECT_ADAPTER_FACTORY:PONS_PROJECT_ADAPTER_FACTORY_RUNTIME_HASH"
    "POOLS_INSTANT_PROJECT_ADAPTER_FACTORY:POOLS_INSTANT_PROJECT_ADAPTER_FACTORY_RUNTIME_HASH"
    "POOLS_INSTANT_NO_FEE_PROJECT_ADAPTER_FACTORY:POOLS_INSTANT_NO_FEE_PROJECT_ADAPTER_FACTORY_RUNTIME_HASH"
    "POOLS_LBP_PROJECT_ADAPTER_FACTORY:POOLS_LBP_PROJECT_ADAPTER_FACTORY_RUNTIME_HASH"
    "PONS_PROJECT_ADAPTER_IMPLEMENTATION:PONS_PROJECT_ADAPTER_IMPLEMENTATION_RUNTIME_HASH"
    "POOLS_PROJECT_REGISTRATION_HELPER:POOLS_PROJECT_REGISTRATION_HELPER_RUNTIME_HASH"
  )
fi
for pair in "${runtime_pairs[@]}"; do
  address_name="${pair%%:*}"
  hash_name="${pair##*:}"
  code="$(cast code "${!address_name}" --rpc-url "$RPC_URL")"
  [[ "$code" != "0x" ]] || fail "$address_name has no code on the target chain"
  actual_hash="$(cast keccak "$code")"
  expected_hash="${!hash_name}"
  actual_hash_lower="$(printf '%s' "$actual_hash" | tr '[:upper:]' '[:lower:]')"
  expected_hash_lower="$(printf '%s' "$expected_hash" | tr '[:upper:]' '[:lower:]')"
  [[ "$actual_hash_lower" == "$expected_hash_lower" ]] \
    || fail "$address_name runtime hash is $actual_hash, expected $expected_hash"
done

export RELEASE_GIT_COMMIT="$(git -C "$repo_dir" rev-parse HEAD)"
export RELEASE_SOURCE_TREE_HASH="$(git -C "$repo_dir" rev-parse HEAD:sinjoh-contracts-v2)"

cd "$package_dir"
forge fmt --check
forge build
forge test
npm test --prefix sdk

release_contracts=(
  ProjectVotesToken ProjectMultisigAccountV2 ProjectTimelockV2 ProjectStakingPoolV2
  ProjectTreasuryVaultV2 ProjectAirdropV2 ProjectRouterV2 ProjectFundingBandsV2
  ProjectRaffleV2 ProjectLiquidityManagerV2
  UniswapV3FundingBandMarketCapGuard UniswapV3FundingBandPositionAdapter
  FundingBandV3IntegrationFactory FundingBandQuoteUsdOracleAdapter ProjectV3TwapPriceGuard
  ProjectWethUnwrapPriceGuard
  CreationCodeStoreV2 ProjectRegistryV2
  ProjectLaunchDeployerV2 ProjectLaunchValidatorV2 ProjectLauncherV2
  ProjectVotesTokenFactoryV2 LaunchpadProjectVotesTokenFactoryV2
)

# Foundry's global --sizes gate also includes deliberately oversized test harnesses. Enforce the
# EIP-170 limit against the production release set itself instead.
for contract in "${release_contracts[@]}"; do
  runtime_hex="$(forge inspect "$contract" deployedBytecode)"
  runtime_bytes=$(( (${#runtime_hex} - 2) / 2 ))
  (( runtime_bytes <= 24576 )) \
    || fail "$contract runtime is $runtime_bytes bytes, above the EIP-170 limit of 24576"
done

build_material="$(
  for contract in "${release_contracts[@]}"; do
    forge inspect "$contract" bytecode
    forge inspect "$contract" deployedBytecode
  done
)"
export RELEASE_BUILD_HASH="$(printf '%s' "$build_material" | sha256)"

signer_args=()
if [[ "$simulate_only" == "0" ]]; then
  if [[ "$unlocked_deployment" == "1" ]]; then
    signer_args+=(--unlocked)
  else
    signer_args+=(--account "$FOUNDRY_ACCOUNT")
  fi
fi

compute_create_address() {
  local nonce="$1"
  cast compute-address --nonce "$nonce" "$DEPLOYER_ADDRESS" | awk '{print $NF}'
}

if [[ "$fresh_launchpad_factories" == "1" ]]; then
  launchpad_dir="$repo_dir/sinjoh-launchpad-adapters"
  initial_nonce="$(cast nonce "$DEPLOYER_ADDRESS" --rpc-url "$RPC_URL")"
  export PONS_PROJECT_ADAPTER_FACTORY="$(compute_create_address "$initial_nonce")"
  export PONS_PROJECT_ADAPTER_IMPLEMENTATION="$(compute_create_address "$((initial_nonce + 1))")"
  export POOLS_INSTANT_PROJECT_ADAPTER_FACTORY="$(compute_create_address "$((initial_nonce + 2))")"
  export POOLS_INSTANT_NO_FEE_PROJECT_ADAPTER_FACTORY="$(compute_create_address "$((initial_nonce + 3))")"
  export POOLS_LBP_PROJECT_ADAPTER_FACTORY="$(compute_create_address "$((initial_nonce + 4))")"
  export POOLS_PROJECT_REGISTRATION_HELPER="$(compute_create_address "$((initial_nonce + 5))")"

  (
    cd "$launchpad_dir"
    forge script script/DeployPonsV2AdapterFactory.s.sol:DeployPonsV2AdapterFactory \
      --rpc-url "$RPC_URL" --sender "$DEPLOYER_ADDRESS" "${signer_args[@]}" --broadcast
  )
  nonce_after_pons="$(cast nonce "$DEPLOYER_ADDRESS" --rpc-url "$RPC_URL")"
  [[ "$nonce_after_pons" == "$((initial_nonce + 2))" ]] \
    || fail "Pons factory deployment advanced nonce to $nonce_after_pons, expected $((initial_nonce + 2))"

  (
    cd "$launchpad_dir"
    forge script script/DeployPoolsTradeAdapterFactories.s.sol:DeployPoolsTradeAdapterFactories \
      --rpc-url "$RPC_URL" --sender "$DEPLOYER_ADDRESS" "${signer_args[@]}" --broadcast
  )
  nonce_after_pools="$(cast nonce "$DEPLOYER_ADDRESS" --rpc-url "$RPC_URL")"
  [[ "$nonce_after_pools" == "$((initial_nonce + 6))" ]] \
    || fail "Pools factory deployment advanced nonce to $nonce_after_pools, expected $((initial_nonce + 6))"

  export PONS_PROJECT_ADAPTER_FACTORY_RUNTIME_HASH="$(cast keccak "$(cast code "$PONS_PROJECT_ADAPTER_FACTORY" --rpc-url "$RPC_URL")")"
  export PONS_PROJECT_ADAPTER_IMPLEMENTATION_RUNTIME_HASH="$(cast keccak "$(cast code "$PONS_PROJECT_ADAPTER_IMPLEMENTATION" --rpc-url "$RPC_URL")")"
  export POOLS_INSTANT_PROJECT_ADAPTER_FACTORY_RUNTIME_HASH="$(cast keccak "$(cast code "$POOLS_INSTANT_PROJECT_ADAPTER_FACTORY" --rpc-url "$RPC_URL")")"
  export POOLS_INSTANT_NO_FEE_PROJECT_ADAPTER_FACTORY_RUNTIME_HASH="$(cast keccak "$(cast code "$POOLS_INSTANT_NO_FEE_PROJECT_ADAPTER_FACTORY" --rpc-url "$RPC_URL")")"
  export POOLS_LBP_PROJECT_ADAPTER_FACTORY_RUNTIME_HASH="$(cast keccak "$(cast code "$POOLS_LBP_PROJECT_ADAPTER_FACTORY" --rpc-url "$RPC_URL")")"
  export POOLS_PROJECT_REGISTRATION_HELPER_RUNTIME_HASH="$(cast keccak "$(cast code "$POOLS_PROJECT_REGISTRATION_HELPER" --rpc-url "$RPC_URL")")"
fi

forge_args=(
  script script/DeployProjectLauncherV2.s.sol:DeployProjectLauncherV2
  --rpc-url "$RPC_URL"
  --sender "$DEPLOYER_ADDRESS"
)
if [[ "$simulate_only" == "0" ]]; then
  forge_args+=("${signer_args[@]}" --broadcast)
fi
forge "${forge_args[@]}"

manifest_path="${DEPLOYMENT_MANIFEST_PATH:-deployments/project-launcher-v2-${EXPECTED_CHAIN_ID}.json}"
node script/verify-release-manifest.mjs "$manifest_path"

if [[ "$simulate_only" == "1" ]]; then
  echo "release deployment simulation completed from $RELEASE_GIT_COMMIT on chain $EXPECTED_CHAIN_ID"
else
  node script/verify-deployed-release.mjs "$manifest_path"
  if [[ -n "${RPC_VERIFICATION_URL:-}" ]]; then
    RPC_URL="$RPC_VERIFICATION_URL" node script/verify-deployed-release.mjs "$manifest_path"
  fi
  echo "release deployment completed from $RELEASE_GIT_COMMIT on chain $EXPECTED_CHAIN_ID"
  echo "source verification is separate: ./script/verify-release-sources.sh '$manifest_path'"
fi
