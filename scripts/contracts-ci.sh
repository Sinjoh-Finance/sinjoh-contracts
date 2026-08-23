#!/usr/bin/env bash
set -euo pipefail

readonly PACKAGES=(
  sinjoh-fee-router
  sinjoh-revenue-collector
  sinjoh-airdrop-distributor
  sinjoh-liquidity-manager
  sinjoh-funding-bands
  sinjoh-raffle-rewards
  sinjoh-randomness
  sinjoh-treasury-vault
  sinjoh-pons-v1-adapter
  sinjoh-launchpad-adapters
  sinjoh-protocol-upgrade
  sinjoh-integration
)

usage() {
  echo "usage: $0 <ci|fmt|build|test|list> [package|all]" >&2
}

contains_package() {
  local candidate="$1"
  local package
  for package in "${PACKAGES[@]}"; do
    if [[ "$package" == "$candidate" ]]; then
      return 0
    fi
  done
  return 1
}

run_package() {
  local operation="$1"
  local package="$2"

  echo "[$operation] $package"
  case "$operation" in
    fmt)
      (cd "$package" && forge fmt --check)
      ;;
    build)
      (cd "$package" && forge build)
      ;;
    test)
      (cd "$package" && forge test --no-match-path 'test/*.fork.t.sol')
      ;;
    ci)
      (cd "$package" && forge fmt --check)
      (cd "$package" && forge build)
      (cd "$package" && forge test --no-match-path 'test/*.fork.t.sol')
      ;;
    *)
      usage
      exit 2
      ;;
  esac
}

operation="${1:-}"
target="${2:-all}"

if [[ "$operation" == "list" ]]; then
  printf '%s\n' "${PACKAGES[@]}"
  exit 0
fi

if [[ -z "$operation" ]]; then
  usage
  exit 2
fi

if [[ "$target" == "all" ]]; then
  for package in "${PACKAGES[@]}"; do
    run_package "$operation" "$package"
  done
  exit 0
fi

if ! contains_package "$target"; then
  echo "unknown Foundry package: $target" >&2
  usage
  exit 2
fi

run_package "$operation" "$target"

