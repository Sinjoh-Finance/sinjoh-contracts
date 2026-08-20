#!/usr/bin/env bash
set -euo pipefail

packages=(
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

for package in "${packages[@]}"; do
  echo "==> ${package}: format"
  (cd "$package" && forge fmt --check)

  echo "==> ${package}: test"
  if [[ "${SINJOH_RUN_FORK_TESTS:-0}" == "1" ]]; then
    (cd "$package" && forge test)
  else
    (cd "$package" && forge test --no-match-path 'test/*.fork.t.sol')
  fi
done
