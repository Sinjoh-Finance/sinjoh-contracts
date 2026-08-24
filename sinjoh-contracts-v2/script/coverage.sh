#!/usr/bin/env bash
set -euo pipefail

package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
link_dir="$package_dir/lib"

fail() {
  echo "coverage failed: $*" >&2
  exit 1
}

cleanup() {
  for link in openzeppelin-contracts v3-core v4-periphery; do
    if [[ -L "$link_dir/$link" ]]; then
      unlink "$link_dir/$link"
    fi
  done
  rmdir "$link_dir" 2>/dev/null || true
}
trap cleanup EXIT

mkdir -p "$link_dir"
for link in openzeppelin-contracts v3-core v4-periphery; do
  [[ ! -e "$link_dir/$link" && ! -L "$link_dir/$link" ]] \
    || fail "$link_dir/$link already exists"
done
ln -s ../../sinjoh-treasury-vault/lib/openzeppelin-contracts \
  "$link_dir/openzeppelin-contracts"
ln -s ../../sinjoh-liquidity-manager/lib/v3-core "$link_dir/v3-core"
ln -s ../../sinjoh-liquidity-manager/lib/v4-periphery "$link_dir/v4-periphery"

cd "$package_dir"

# Coverage instrumentation expands the Launcher's stored module creation code beyond EIP-3860.
# Preserve its real production-mode result separately, then cover every other suite.
forge test --match-contract ProjectLauncherV2Test -q
forge coverage \
  --ir-minimum \
  --report lcov \
  --report-file security/coverage.lcov \
  --exclude-tests \
  --no-match-contract ProjectLauncherV2Test \
  -R '@openzeppelin/contracts/=lib/openzeppelin-contracts/contracts/' \
  -R '@uniswap/v3-core/=lib/v3-core/' \
  -R '@uniswap/v4-core/=lib/v4-periphery/lib/v4-core/' \
  -R '@uniswap/v4-periphery/=lib/v4-periphery/' \
  -R 'permit2/=lib/v4-periphery/lib/permit2/'
