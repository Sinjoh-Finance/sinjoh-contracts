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
  FUNDING_BAND_QUOTE_ASSET FUNDING_BAND_QUOTE_ASSET_RUNTIME_HASH
  FUNDING_BAND_QUOTE_USD_AGGREGATOR FUNDING_BAND_QUOTE_USD_AGGREGATOR_RUNTIME_HASH
  V3_FACTORY V3_FACTORY_RUNTIME_HASH V3_POSITION_MANAGER V3_POSITION_MANAGER_RUNTIME_HASH
  V4_POSITION_MANAGER V4_POSITION_MANAGER_RUNTIME_HASH V4_STATE_VIEW V4_STATE_VIEW_RUNTIME_HASH
  PERMIT2 PERMIT2_RUNTIME_HASH
  PONS_PROJECT_ADAPTER_FACTORY PONS_PROJECT_ADAPTER_FACTORY_RUNTIME_HASH
  POOLS_INSTANT_PROJECT_ADAPTER_FACTORY POOLS_INSTANT_PROJECT_ADAPTER_FACTORY_RUNTIME_HASH
  POOLS_INSTANT_NO_FEE_PROJECT_ADAPTER_FACTORY POOLS_INSTANT_NO_FEE_PROJECT_ADAPTER_FACTORY_RUNTIME_HASH
  POOLS_LBP_PROJECT_ADAPTER_FACTORY POOLS_LBP_PROJECT_ADAPTER_FACTORY_RUNTIME_HASH
  PONS_PROJECT_ADAPTER_IMPLEMENTATION PONS_PROJECT_ADAPTER_IMPLEMENTATION_RUNTIME_HASH
  POOLS_PROJECT_REGISTRATION_HELPER POOLS_PROJECT_REGISTRATION_HELPER_RUNTIME_HASH
  PONS_LAUNCH_FACTORY PONS_LAUNCH_FACTORY_RUNTIME_HASH
)
for environment_name in "${required_environment[@]}"; do
  require_environment "$environment_name"
done

simulate_only="${SIMULATE_ONLY:-0}"
if [[ "$simulate_only" != "0" && "$simulate_only" != "1" ]]; then
  fail "SIMULATE_ONLY must be 0 or 1"
fi
if [[ "$simulate_only" == "0" ]]; then
  for environment_name in FOUNDRY_ACCOUNT; do
    require_environment "$environment_name"
  done
fi

actual_chain_id="$(cast chain-id --rpc-url "$RPC_URL")"
[[ "$actual_chain_id" == "$EXPECTED_CHAIN_ID" ]] \
  || fail "RPC chain $actual_chain_id does not match EXPECTED_CHAIN_ID $EXPECTED_CHAIN_ID"

runtime_pairs=(
  "RANDOMNESS_ADAPTER:RANDOMNESS_ADAPTER_RUNTIME_HASH"
  "PROJECT_SWAP_ADAPTER:PROJECT_SWAP_ADAPTER_RUNTIME_HASH"
  "FUNDING_BAND_QUOTE_ASSET:FUNDING_BAND_QUOTE_ASSET_RUNTIME_HASH"
  "FUNDING_BAND_QUOTE_USD_AGGREGATOR:FUNDING_BAND_QUOTE_USD_AGGREGATOR_RUNTIME_HASH"
  "V3_FACTORY:V3_FACTORY_RUNTIME_HASH"
  "V3_POSITION_MANAGER:V3_POSITION_MANAGER_RUNTIME_HASH"
  "V4_POSITION_MANAGER:V4_POSITION_MANAGER_RUNTIME_HASH"
  "V4_STATE_VIEW:V4_STATE_VIEW_RUNTIME_HASH"
  "PERMIT2:PERMIT2_RUNTIME_HASH"
  "PONS_PROJECT_ADAPTER_FACTORY:PONS_PROJECT_ADAPTER_FACTORY_RUNTIME_HASH"
  "POOLS_INSTANT_PROJECT_ADAPTER_FACTORY:POOLS_INSTANT_PROJECT_ADAPTER_FACTORY_RUNTIME_HASH"
  "POOLS_INSTANT_NO_FEE_PROJECT_ADAPTER_FACTORY:POOLS_INSTANT_NO_FEE_PROJECT_ADAPTER_FACTORY_RUNTIME_HASH"
  "POOLS_LBP_PROJECT_ADAPTER_FACTORY:POOLS_LBP_PROJECT_ADAPTER_FACTORY_RUNTIME_HASH"
  "PONS_PROJECT_ADAPTER_IMPLEMENTATION:PONS_PROJECT_ADAPTER_IMPLEMENTATION_RUNTIME_HASH"
  "POOLS_PROJECT_REGISTRATION_HELPER:POOLS_PROJECT_REGISTRATION_HELPER_RUNTIME_HASH"
  "PONS_LAUNCH_FACTORY:PONS_LAUNCH_FACTORY_RUNTIME_HASH"
)
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

forge_args=(
  script script/DeployProjectLauncherV2.s.sol:DeployProjectLauncherV2
  --rpc-url "$RPC_URL"
  --sender "$DEPLOYER_ADDRESS"
)
if [[ "$simulate_only" == "0" ]]; then
  forge_args+=(
    --account "$FOUNDRY_ACCOUNT"
    --broadcast
  )
fi
forge "${forge_args[@]}"

manifest_path="${DEPLOYMENT_MANIFEST_PATH:-deployments/project-launcher-v2-${EXPECTED_CHAIN_ID}.json}"
node script/verify-release-manifest.mjs "$manifest_path"

if [[ "$simulate_only" == "1" ]]; then
  echo "release deployment simulation completed from $RELEASE_GIT_COMMIT on chain $EXPECTED_CHAIN_ID"
else
  node script/verify-deployed-release.mjs "$manifest_path"
  echo "release deployment completed from $RELEASE_GIT_COMMIT on chain $EXPECTED_CHAIN_ID"
  echo "source verification is separate: ./script/verify-release-sources.sh '$manifest_path'"
fi
