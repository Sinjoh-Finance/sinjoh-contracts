#!/usr/bin/env bash
set -euo pipefail

package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fake_bin="$(mktemp -d)"
trap 'rm -rf "$fake_bin"' EXIT

cat > "$fake_bin/cast" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "call" ]]; then
  echo 0xe4605138e185FBeE40ff6193A044aa0BE2909216
  exit 0
fi
exit 64
EOF
chmod +x "$fake_bin/cast"

set +e
output="$({
  PATH="$fake_bin:$PATH" \
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

echo "Successor owner preflight test passed"
