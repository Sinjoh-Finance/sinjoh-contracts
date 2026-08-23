#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 <4663|46630> [rpc-url]" >&2
}

chain_id="${1:-}"
rpc_url="${2:-}"

case "$chain_id" in
  4663)
    rpc_url="${rpc_url:-${ROBINHOOD_MAINNET_RPC_URL:-${ROBINHOOD_RPC_URL:-}}}"
    ;;
  46630)
    rpc_url="${rpc_url:-${ROBINHOOD_TESTNET_RPC_URL:-${ROBINHOOD_RPC_URL:-}}}"
    ;;
  *)
    usage
    exit 2
    ;;
esac

if [[ -z "$rpc_url" ]]; then
  echo "an authenticated archive RPC URL is required" >&2
  exit 2
fi

actual_chain_id="$(cast chain-id --rpc-url "$rpc_url")"
if [[ "$actual_chain_id" != "$chain_id" ]]; then
  echo "RPC chain mismatch: expected $chain_id, received $actual_chain_id" >&2
  exit 1
fi

export ROBINHOOD_RPC_URL="$rpc_url"
if [[ "$chain_id" == "4663" ]]; then
  export ROBINHOOD_MAINNET_RPC_URL="$rpc_url"
  export RH_RPC_URL="$rpc_url"
else
  export ROBINHOOD_TESTNET_RPC_URL="$rpc_url"
fi

list="deployments/forks/${chain_id}.txt"
if [[ ! -f "$list" ]]; then
  echo "fork-test inventory is missing: $list" >&2
  exit 1
fi

while IFS= read -r test_path; do
  if [[ -z "$test_path" || "$test_path" == \#* ]]; then
    continue
  fi
  if [[ ! -f "$test_path" ]]; then
    echo "fork test does not exist: $test_path" >&2
    exit 1
  fi
  package="${test_path%%/*}"
  relative_path="${test_path#*/}"
  echo "[fork:$chain_id] $test_path"
  (cd "$package" && forge test --match-path "$relative_path" -vv)
done < "$list"

