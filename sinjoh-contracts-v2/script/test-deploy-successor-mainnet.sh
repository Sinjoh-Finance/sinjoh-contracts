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
    case "$*" in
      *"launchEnabled()(bool)"*)
        if [[ "${FAKE_LAUNCH_DISABLED:-0}" == "1" && "$*" == *"chainstack.com"* ]]; then
          echo false
        else
          echo true
        fi
        ;;
      *"launchFee()(uint256)"*) echo '["500000000000000"]' ;;
      *"getLaunchConfig(uint256)"*)
        echo '[["1000000000000000000000000000",100,1680000000000000000,4200000000000000000,0,200,true]]'
        ;;
      *"approvedPairTokens(address)(bool)"*)
        if [[ "${FAKE_PAIR_UNAPPROVED:-0}" == "1" && "$*" == *"quiknode.pro"* ]]; then
          echo false
        else
          echo true
        fi
        ;;
      *"launchFactory()(address)"*)
        if [[ "${FAKE_BINDING_MISMATCH:-0}" == "1" && "$*" == *"quiknode.pro"* ]]; then
          echo 0x7DCeEaB0A53684b001A4900768a52eAcDb27294e
        else
          echo 0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e
        fi
        ;;
      *) exit 64 ;;
    esac
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
disabled_output="$({
  PATH="$fake_bin:$PATH" \
  FAKE_LAUNCH_DISABLED=1 \
  RPC_URL=https://robinhood-mainnet.core.chainstack.com/primary-secret \
  RPC_VERIFICATION_URL=https://verified.robinhood-mainnet.quiknode.pro/secondary-secret \
  FOUNDRY_ACCOUNT=test-account \
    "$package_dir/script/deploy-successor-mainnet.sh"
} 2>&1)"
disabled_status=$?
set -e

[[ "$disabled_status" -ne 0 ]] || {
  echo "expected the successor wrapper to reject disabled public Pons launches" >&2
  exit 1
}
[[ "$disabled_output" == *"public Pons launches disabled"* ]] || {
  echo "disabled public Pons launch state was not reported" >&2
  exit 1
}
[[ "$disabled_output" == *"no transaction was sent"* ]] || {
  echo "pre-broadcast failure guarantee was not reported" >&2
  exit 1
}

set +e
pair_output="$({
  PATH="$fake_bin:$PATH" \
  FAKE_PAIR_UNAPPROVED=1 \
  RPC_URL=https://robinhood-mainnet.core.chainstack.com/primary-secret \
  RPC_VERIFICATION_URL=https://verified.robinhood-mainnet.quiknode.pro/secondary-secret \
  FOUNDRY_ACCOUNT=test-account \
    "$package_dir/script/deploy-successor-mainnet.sh"
} 2>&1)"
pair_status=$?
set -e

[[ "$pair_status" -ne 0 ]] || {
  echo "expected the successor wrapper to reject an unapproved UI pair" >&2
  exit 1
}
[[ "$pair_output" == *"reports UI pair"*"is not approved by public Pons"* ]] || {
  echo "QuickNode pair mismatch was not reported" >&2
  exit 1
}

set +e
binding_output="$({
  PATH="$fake_bin:$PATH" \
  FAKE_BINDING_MISMATCH=1 \
  RPC_URL=https://robinhood-mainnet.core.chainstack.com/primary-secret \
  RPC_VERIFICATION_URL=https://verified.robinhood-mainnet.quiknode.pro/secondary-secret \
  FOUNDRY_ACCOUNT=test-account \
    "$package_dir/script/deploy-successor-mainnet.sh"
} 2>&1)"
binding_status=$?
set -e

[[ "$binding_status" -ne 0 ]] || {
  echo "expected the successor wrapper to reject a crossed Pons generation" >&2
  exit 1
}
[[ "$binding_output" == *"Pons buyback adapter"*"not 0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e"* ]] || {
  echo "crossed Pons generation was not reported" >&2
  exit 1
}

echo "Successor RPC, public-factory, pair, and generation preflight tests passed"
