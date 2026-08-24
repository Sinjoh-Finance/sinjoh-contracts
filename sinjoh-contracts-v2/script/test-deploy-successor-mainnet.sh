#!/usr/bin/env bash
set -euo pipefail

package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fake_bin="$(mktemp -d)"
trap 'rm -rf "$fake_bin"' EXIT

cat > "$fake_bin/cast" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  chain-id) echo 4663 ;;
  block-number) echo 45000000 ;;
  nonce)
    if [[ "${FAKE_NONCE_MISMATCH:-0}" == "1" && "$*" == *"quiknode.pro"* ]]; then
      echo 7806
    else
      echo 7805
    fi
    ;;
  call)
    if [[ "${FAKE_PRIMARY_OWNER_MATCH:-0}" == "1" && "$*" == *"chainstack.com"* ]]; then
      echo 0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49
    else
      echo 0xe4605138e185FBeE40ff6193A044aa0BE2909216
    fi
    ;;
  *) exit 64 ;;
esac
EOF
chmod +x "$fake_bin/cast"

set +e
missing_rpc_output="$({
  PATH="$fake_bin:$PATH" \
  FOUNDRY_ACCOUNT=test-account \
    "$package_dir/script/deploy-successor-mainnet.sh"
} 2>&1)"
missing_rpc_status=$?
set -e

[[ "$missing_rpc_status" -ne 0 ]] || {
  echo "expected the successor wrapper to require authenticated RPC endpoints" >&2
  exit 1
}
[[ "$missing_rpc_output" == *"public RPC fallbacks are forbidden"* ]] || {
  echo "missing RPC failure did not explain the production requirement" >&2
  exit 1
}

set +e
public_rpc_output="$({
  PATH="$fake_bin:$PATH" \
  RPC_URL=https://rpc.mainnet.chain.robinhood.com \
  RPC_VERIFICATION_URL=https://robinhood-mainnet.g.alchemy.com/v2/not-a-real-key \
  FOUNDRY_ACCOUNT=test-account \
    "$package_dir/script/deploy-successor-mainnet.sh"
} 2>&1)"
public_rpc_status=$?
set -e

[[ "$public_rpc_status" -ne 0 ]] || {
  echo "expected the successor wrapper to reject public and Alchemy RPC endpoints" >&2
  exit 1
}
[[ "$public_rpc_output" == *"production Chainstack endpoint"* ]] || {
  echo "public RPC rejection did not name the required provider" >&2
  exit 1
}

set +e
insecure_rpc_output="$({
  PATH="$fake_bin:$PATH" \
  RPC_URL=http://robinhood-mainnet.core.chainstack.com/primary-secret \
  RPC_VERIFICATION_URL=https://verified.robinhood-mainnet.quiknode.pro/secondary-secret \
  FOUNDRY_ACCOUNT=test-account \
    "$package_dir/script/deploy-successor-mainnet.sh"
} 2>&1)"
insecure_rpc_status=$?
set -e

[[ "$insecure_rpc_status" -ne 0 ]] || {
  echo "expected the successor wrapper to reject an insecure Chainstack endpoint" >&2
  exit 1
}
[[ "$insecure_rpc_output" == *"must use HTTPS"* ]] || {
  echo "insecure Chainstack endpoint rejection was not explicit" >&2
  exit 1
}

set +e
nonce_mismatch_output="$({
  PATH="$fake_bin:$PATH" \
  FAKE_NONCE_MISMATCH=1 \
  RPC_URL=https://robinhood-mainnet.core.chainstack.com/primary-secret \
  RPC_VERIFICATION_URL=https://verified.robinhood-mainnet.quiknode.pro/secondary-secret \
  FOUNDRY_ACCOUNT=test-account \
    "$package_dir/script/deploy-successor-mainnet.sh"
} 2>&1)"
nonce_mismatch_status=$?
set -e

[[ "$nonce_mismatch_status" -ne 0 ]] || {
  echo "expected the successor wrapper to reject provider nonce disagreement" >&2
  exit 1
}
[[ "$nonce_mismatch_output" == *"deployer nonces disagree"* ]] || {
  echo "provider nonce disagreement was not reported" >&2
  exit 1
}

set +e
output="$({
  PATH="$fake_bin:$PATH" \
  RPC_URL=https://robinhood-mainnet.core.chainstack.com/primary-secret \
  RPC_VERIFICATION_URL=https://verified.robinhood-mainnet.quiknode.pro/secondary-secret \
  FOUNDRY_ACCOUNT=test-account \
    "$package_dir/script/deploy-successor-mainnet.sh"
} 2>&1)"
status=$?
set -e

[[ "$status" -ne 0 ]] || {
  echo "expected the successor wrapper to reject a mismatched Pons owner" >&2
  exit 1
}
[[ "$output" == *"0xe4605138e185FBeE40ff6193A044aa0BE2909216"* ]] || {
  echo "mismatched Pons owner was not reported" >&2
  exit 1
}
[[ "$output" == *"0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49"* ]] || {
  echo "authorized deployer was not reported" >&2
  exit 1
}
[[ "$output" == *"no transaction was sent"* ]] || {
  echo "pre-broadcast failure guarantee was not reported" >&2
  exit 1
}

set +e
secondary_owner_output="$({
  PATH="$fake_bin:$PATH" \
  FAKE_PRIMARY_OWNER_MATCH=1 \
  RPC_URL=https://robinhood-mainnet.core.chainstack.com/primary-secret \
  RPC_VERIFICATION_URL=https://verified.robinhood-mainnet.quiknode.pro/secondary-secret \
  FOUNDRY_ACCOUNT=test-account \
    "$package_dir/script/deploy-successor-mainnet.sh"
} 2>&1)"
secondary_owner_status=$?
set -e

[[ "$secondary_owner_status" -ne 0 ]] || {
  echo "expected the successor wrapper to reject a QuickNode owner mismatch" >&2
  exit 1
}
[[ "$secondary_owner_output" == *"QuickNode reports Pons launch factory owner"* ]] || {
  echo "QuickNode owner mismatch was not reported" >&2
  exit 1
}

echo "Successor RPC and owner preflight tests passed"
