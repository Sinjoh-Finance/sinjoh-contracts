#!/usr/bin/env bash
set -euo pipefail

readonly REPO_ROOT="/Users/dsb/sinjoh-contracts-unified-governance"
readonly INTENDED_OWNER="0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49"
readonly FOUNDRY_ACCOUNT_NAME="sinjoh-deployer"
readonly FOUNDRY_KEYSTORE_PATH="/Users/dsb/.foundry/keystores/sinjoh-deployer"
readonly RECOVERY_CONFIRMATION="I_UNDERSTAND_THIS_BROADCASTS_MAINNET"
readonly RAILWAY_PROJECT="3e8e2a91-1b86-498e-887c-6cbd5d694dcb"
readonly RAILWAY_SERVICE="039acfe1-72a1-4d66-8470-af0366c7b626"
readonly RAILWAY_ENVIRONMENT="fbc453ac-828e-4727-8184-90c9ac588626"
readonly RAILWAY_CALLER_VALUE="skill:use-railway@1.3.7"
readonly RAILWAY_SESSION_VALUE="sinjoh-project-v2-production-20260824"

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

for binary in railway jq node cast git; do
  command -v "$binary" >/dev/null 2>&1 || fail "Missing required executable: $binary"
done

cd "$REPO_ROOT"
[[ "$(git branch --show-current)" == "codex/project-v2-production-promotion" ]] \
  || fail "Unexpected contracts branch"
[[ -z "$(git status --porcelain --untracked-files=no)" ]] \
  || fail "Tracked contracts worktree must be clean before recovery"

variables_json="$(
  RAILWAY_CALLER="$RAILWAY_CALLER_VALUE" RAILWAY_AGENT_SESSION="$RAILWAY_SESSION_VALUE" \
    railway variable list \
      --project "$RAILWAY_PROJECT" \
      --service "$RAILWAY_SERVICE" \
      --environment "$RAILWAY_ENVIRONMENT" \
      --json
)"
primary_rpc="$(jq -er '(.variables // .).SINJOH_RPC_PRIMARY' <<<"$variables_json")"
secondary_rpc="$(jq -er '(.variables // .).SINJOH_RPC_SECONDARY' <<<"$variables_json")"
unset variables_json

PRIMARY_RPC="$primary_rpc" SECONDARY_RPC="$secondary_rpc" node <<'NODE'
const primary = new URL(process.env.PRIMARY_RPC);
const secondary = new URL(process.env.SECONDARY_RPC);
const primaryHost = primary.hostname.toLowerCase();
const secondaryHost = secondary.hostname.toLowerCase();
if (primary.protocol !== "https:" || !(primaryHost.includes("p2pify.com") || primaryHost.includes("chainstack"))) {
  throw new Error("SINJOH_RPC_PRIMARY is not an HTTPS Chainstack endpoint");
}
if (secondary.protocol !== "https:" || !(secondaryHost.includes("quiknode.pro") || secondaryHost.includes("quicknode"))) {
  throw new Error("SINJOH_RPC_SECONDARY is not an HTTPS QuickNode endpoint");
}
NODE

[[ "$(ETH_RPC_URL="$primary_rpc" cast chain-id)" == "4663" ]] \
  || fail "Chainstack returned the wrong chain ID"
[[ "$(ETH_RPC_URL="$secondary_rpc" cast chain-id)" == "4663" ]] \
  || fail "QuickNode returned the wrong chain ID"

password_file="$(mktemp /tmp/sinjoh-recovery-password.XXXXXX)"
cleanup() {
  if [[ -f "$password_file" ]]; then
    chmod 600 "$password_file" 2>/dev/null || true
    rm -f "$password_file"
  fi
}
trap cleanup EXIT INT TERM
chmod 600 "$password_file"

printf 'Enter sinjoh-deployer keystore password: '
IFS= read -r -s keystore_password
printf '\n'
printf '%s\n' "$keystore_password" >"$password_file"
unset keystore_password

account_address="$(cast wallet address \
  --account "$FOUNDRY_ACCOUNT_NAME" \
  --password-file "$password_file")"
account_address_lower="$(tr '[:upper:]' '[:lower:]' <<<"$account_address")"
intended_owner_lower="$(tr '[:upper:]' '[:lower:]' <<<"$INTENDED_OWNER")"
[[ "$account_address_lower" == "$intended_owner_lower" ]] \
  || fail "$FOUNDRY_ACCOUNT_NAME resolves to $account_address, not $INTENDED_OWNER"

RPC_URL="$primary_rpc" \
RPC_VERIFICATION_URL="$secondary_rpc" \
FOUNDRY_ACCOUNT="$FOUNDRY_ACCOUNT_NAME" \
FOUNDRY_KEYSTORE_PATH="$FOUNDRY_KEYSTORE_PATH" \
FOUNDRY_PASSWORD_FILE="$password_file" \
EXECUTE_PROJECT_V2_RECOVERY="$RECOVERY_CONFIRMATION" \
node sinjoh-contracts-v2/script/recover-project-v2-mainnet.mjs
