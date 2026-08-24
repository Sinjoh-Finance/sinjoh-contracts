#!/usr/bin/env bash
set -euo pipefail

readonly INTENDED_OWNER="0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49"
readonly ZERO_ADDRESS="0x0000000000000000000000000000000000000000"
readonly FOUNDRY_ACCOUNT="sinjoh-deployer"
readonly RAILWAY_PROJECT="3e8e2a91-1b86-498e-887c-6cbd5d694dcb"
readonly RAILWAY_SERVICE="039acfe1-72a1-4d66-8470-af0366c7b626"
readonly RAILWAY_ENVIRONMENT="fbc453ac-828e-4727-8184-90c9ac588626"

readonly CONTRACT_NAMES=("hook" "locker" "vault")
readonly CONTRACT_ADDRESSES=(
  "0xE9Ec0Ffc7d5bEF33f815D7b0cDd15A7c5Dc1e044"
  "0x1006fA85294A9c38AA4214d52c86CC970Ddc5647"
  "0xA61f18568d3B817bbb95450D42F7403e871Ce0a1"
)

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

for binary in railway jq node cast; do
  command -v "$binary" >/dev/null 2>&1 || fail "Missing required executable: $binary"
done

variables_json="$(railway variable list \
  --project "$RAILWAY_PROJECT" \
  --service "$RAILWAY_SERVICE" \
  --environment "$RAILWAY_ENVIRONMENT" \
  --json)"

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

primary_chain_id="$(ETH_RPC_URL="$primary_rpc" cast chain-id)"
secondary_chain_id="$(ETH_RPC_URL="$secondary_rpc" cast chain-id)"
[[ "$primary_chain_id" == "4663" ]] || fail "Chainstack returned unexpected chain ID $primary_chain_id"
[[ "$secondary_chain_id" == "4663" ]] || fail "QuickNode returned unexpected chain ID $secondary_chain_id"

lowercase() {
  tr '[:upper:]' '[:lower:]' <<<"$1"
}

read_owner() {
  local rpc="$1"
  local address="$2"
  ETH_RPC_URL="$rpc" cast call "$address" 'owner()(address)'
}

read_pending_owner() {
  local rpc="$1"
  local address="$2"
  ETH_RPC_URL="$rpc" cast call "$address" 'pendingOwner()(address)'
}

verify_dual_state() {
  local name="$1"
  local address="$2"
  local expected_owner="$3"
  local expected_pending="$4"
  local owner_a owner_b pending_a pending_b

  owner_a="$(read_owner "$primary_rpc" "$address")"
  owner_b="$(read_owner "$secondary_rpc" "$address")"
  pending_a="$(read_pending_owner "$primary_rpc" "$address")"
  pending_b="$(read_pending_owner "$secondary_rpc" "$address")"

  [[ "$(lowercase "$owner_a")" == "$(lowercase "$owner_b")" ]] \
    || fail "Providers disagree on $name owner"
  [[ "$(lowercase "$pending_a")" == "$(lowercase "$pending_b")" ]] \
    || fail "Providers disagree on $name pending owner"
  [[ "$(lowercase "$owner_a")" == "$(lowercase "$expected_owner")" ]] \
    || fail "$name owner is $owner_a, expected $expected_owner"
  [[ "$(lowercase "$pending_a")" == "$(lowercase "$expected_pending")" ]] \
    || fail "$name pending owner is $pending_a, expected $expected_pending"
}

safe_nonce() {
  local pending_a pending_b latest_a latest_b
  pending_a="$(ETH_RPC_URL="$primary_rpc" cast nonce --block pending "$INTENDED_OWNER")"
  pending_b="$(ETH_RPC_URL="$secondary_rpc" cast nonce --block pending "$INTENDED_OWNER")"
  latest_a="$(ETH_RPC_URL="$primary_rpc" cast nonce --block latest "$INTENDED_OWNER")"
  latest_b="$(ETH_RPC_URL="$secondary_rpc" cast nonce --block latest "$INTENDED_OWNER")"
  [[ "$pending_a" == "$pending_b" ]] || fail "Providers disagree on pending nonce"
  [[ "$latest_a" == "$latest_b" ]] || fail "Providers disagree on latest nonce"
  [[ "$pending_a" == "$latest_a" ]] || fail "The intended owner already has an in-flight transaction"
  printf '%s\n' "$pending_a"
}

password_file="$(mktemp /tmp/sinjoh-ownership-password.XXXXXX)"
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

account_address="$(cast wallet address --account "$FOUNDRY_ACCOUNT" --password-file "$password_file")"
[[ "$(lowercase "$account_address")" == "$(lowercase "$INTENDED_OWNER")" ]] \
  || fail "$FOUNDRY_ACCOUNT resolves to $account_address, not $INTENDED_OWNER"

for index in "${!CONTRACT_ADDRESSES[@]}"; do
  name="${CONTRACT_NAMES[$index]}"
  address="${CONTRACT_ADDRESSES[$index]}"
  owner="$(read_owner "$primary_rpc" "$address")"
  pending_owner="$(read_pending_owner "$primary_rpc" "$address")"

  if [[ "$(lowercase "$owner")" == "$(lowercase "$INTENDED_OWNER")" ]] && \
     [[ "$(lowercase "$pending_owner")" == "$(lowercase "$ZERO_ADDRESS")" ]]; then
    verify_dual_state "$name" "$address" "$INTENDED_OWNER" "$ZERO_ADDRESS"
    printf '%s %s is already owned by %s; skipping.\n' "$name" "$address" "$INTENDED_OWNER"
    continue
  fi

  [[ "$(lowercase "$pending_owner")" == "$(lowercase "$INTENDED_OWNER")" ]] \
    || fail "$name $address is not pending acceptance by $INTENDED_OWNER"

  verify_dual_state "$name" "$address" "$owner" "$INTENDED_OWNER"

  ETH_RPC_URL="$primary_rpc" cast call \
    --block pending \
    --from "$INTENDED_OWNER" \
    "$address" 'acceptOwnership()' >/dev/null
  ETH_RPC_URL="$secondary_rpc" cast call \
    --block pending \
    --from "$INTENDED_OWNER" \
    "$address" 'acceptOwnership()' >/dev/null

  estimate_a="$(ETH_RPC_URL="$primary_rpc" cast estimate --block pending --from "$INTENDED_OWNER" "$address" 'acceptOwnership()')"
  estimate_b="$(ETH_RPC_URL="$secondary_rpc" cast estimate --block pending --from "$INTENDED_OWNER" "$address" 'acceptOwnership()')"
  gas_a="$(ETH_RPC_URL="$primary_rpc" cast gas-price)"
  gas_b="$(ETH_RPC_URL="$secondary_rpc" cast gas-price)"
  nonce="$(safe_nonce)"

  if (( estimate_a > estimate_b )); then estimate="$estimate_a"; else estimate="$estimate_b"; fi
  if (( gas_a > gas_b )); then gas_price="$gas_a"; else gas_price="$gas_b"; fi
  gas_limit=$(( estimate * 2 ))
  gas_price=$(( gas_price * 2 ))

  transaction_hash="$(ETH_RPC_URL="$primary_rpc" cast send \
    --account "$FOUNDRY_ACCOUNT" \
    --password-file "$password_file" \
    --from "$INTENDED_OWNER" \
    --nonce "$nonce" \
    --gas-limit "$gas_limit" \
    --gas-price "$gas_price" \
    --legacy \
    --async \
    "$address" 'acceptOwnership()')"
  printf '%s %s submitted at nonce %s: %s\n' "$name" "$address" "$nonce" "$transaction_hash"

  receipt_a="$(ETH_RPC_URL="$primary_rpc" cast receipt --confirmations 1 --json "$transaction_hash")"
  receipt_b="$(ETH_RPC_URL="$secondary_rpc" cast receipt --confirmations 1 --json "$transaction_hash")"
  status_a="$(jq -r '.status' <<<"$receipt_a")"
  status_b="$(jq -r '.status' <<<"$receipt_b")"
  block_hash_a="$(jq -r '.blockHash' <<<"$receipt_a")"
  block_hash_b="$(jq -r '.blockHash' <<<"$receipt_b")"
  unset receipt_a receipt_b

  [[ "$status_a" == "0x1" || "$status_a" == "1" ]] || fail "$name acceptance reverted"
  [[ "$status_b" == "0x1" || "$status_b" == "1" ]] || fail "QuickNode reports that $name acceptance reverted"
  [[ "$block_hash_a" == "$block_hash_b" ]] || fail "Providers disagree on $name receipt block"

  verify_dual_state "$name" "$address" "$INTENDED_OWNER" "$ZERO_ADDRESS"
  printf '%s %s ownership accepted and dual-provider verified.\n' "$name" "$address"
done

printf 'All Pons V2 ownership handoffs are complete.\n'
