#!/usr/bin/env bash
set -euo pipefail

package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo_dir="$(git -C "$package_dir" rev-parse --show-toplevel)"

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

require_evidence() {
  local name="$1"
  local path="${!name}"
  [[ -f "$path" && -s "$path" ]] || fail "$name must reference a non-empty evidence file"
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

if [[ -n "$(git -C "$repo_dir" status --porcelain --untracked-files=normal)" ]]; then
  fail "the git worktree is not clean"
fi

required_environment=(
  RPC_URL EXPECTED_CHAIN_ID PRIVATE_KEY PROTOCOL_FEE_RECIPIENT INTEGRATION_APPROVAL_ROOT
  V3_FACTORY V3_FACTORY_RUNTIME_HASH V3_POSITION_MANAGER V3_POSITION_MANAGER_RUNTIME_HASH
  V4_POSITION_MANAGER V4_POSITION_MANAGER_RUNTIME_HASH V4_STATE_VIEW V4_STATE_VIEW_RUNTIME_HASH
  PERMIT2 PERMIT2_RUNTIME_HASH AUDIT_REPORT_VERSION AUDIT_EVIDENCE_PATH FORK_EVIDENCE_PATH
  TESTNET_EVIDENCE_PATH ROLE_EVIDENCE_PATH ASSET_FLOW_EVIDENCE_PATH VERIFIER VERIFIER_URL
  VERIFIER_API_KEY
)
for environment_name in "${required_environment[@]}"; do
  require_environment "$environment_name"
done

[[ "${AUDIT_GATE_STATUS:-}" == "passed" ]] || fail "AUDIT_GATE_STATUS must be exactly 'passed'"
require_evidence AUDIT_EVIDENCE_PATH
require_evidence FORK_EVIDENCE_PATH
require_evidence TESTNET_EVIDENCE_PATH
require_evidence ROLE_EVIDENCE_PATH
require_evidence ASSET_FLOW_EVIDENCE_PATH
export AUDIT_EVIDENCE_HASH="$(sha256 < "$AUDIT_EVIDENCE_PATH")"
export FORK_EVIDENCE_HASH="$(sha256 < "$FORK_EVIDENCE_PATH")"
export TESTNET_EVIDENCE_HASH="$(sha256 < "$TESTNET_EVIDENCE_PATH")"
export ROLE_EVIDENCE_HASH="$(sha256 < "$ROLE_EVIDENCE_PATH")"
export ASSET_FLOW_EVIDENCE_HASH="$(sha256 < "$ASSET_FLOW_EVIDENCE_PATH")"

actual_chain_id="$(cast chain-id --rpc-url "$RPC_URL")"
[[ "$actual_chain_id" == "$EXPECTED_CHAIN_ID" ]] \
  || fail "RPC chain $actual_chain_id does not match EXPECTED_CHAIN_ID $EXPECTED_CHAIN_ID"

runtime_pairs=(
  "V3_FACTORY:V3_FACTORY_RUNTIME_HASH"
  "V3_POSITION_MANAGER:V3_POSITION_MANAGER_RUNTIME_HASH"
  "V4_POSITION_MANAGER:V4_POSITION_MANAGER_RUNTIME_HASH"
  "V4_STATE_VIEW:V4_STATE_VIEW_RUNTIME_HASH"
  "PERMIT2:PERMIT2_RUNTIME_HASH"
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
forge build --sizes
forge test
npm test --prefix sdk

build_material="$(
  for contract in ProjectLauncherV2 ProjectLaunchDeployerV2 ProjectRegistryV2; do
    forge inspect "$contract" deployedBytecode
  done
)"
export RELEASE_BUILD_HASH="$(printf '%s' "$build_material" | sha256)"

forge script script/DeployProjectLauncherV2.s.sol:DeployProjectLauncherV2 \
  --rpc-url "$RPC_URL" \
  --broadcast \
  --verify \
  --verifier "$VERIFIER" \
  --verifier-url "$VERIFIER_URL" \
  --etherscan-api-key "$VERIFIER_API_KEY"

manifest_path="${DEPLOYMENT_MANIFEST_PATH:-deployments/project-launcher-v2-${EXPECTED_CHAIN_ID}.json}"
node script/verify-release-manifest.mjs "$manifest_path"

echo "release deployment completed from $RELEASE_GIT_COMMIT on chain $EXPECTED_CHAIN_ID"
