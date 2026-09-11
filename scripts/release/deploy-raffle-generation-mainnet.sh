#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
expected_tree=f156c25714132f081968755308a67936c38d6880
expected_signer=0x3d58E42d3a920dE4C1F71EE041c7eBb82ee23f49
mode="${1:---simulate}"
[[ "$mode" == --simulate || "$mode" == --broadcast ]] || { echo 'Use --simulate or --broadcast' >&2; exit 1; }

cd "$repo_dir"
[[ "$(git rev-parse HEAD:sinjoh-raffle-rewards)" == "$expected_tree" ]] \
  || { echo 'Raffle package differs from the rehearsed release.' >&2; exit 1; }
git diff --exit-code HEAD -- sinjoh-raffle-rewards >/dev/null

# Obtain only managed RPCs. No automation signer is used for protocol deployment.
variables_json="$(
  RAILWAY_CALLER=skill:use-railway@1.4.0 \
  RAILWAY_AGENT_SESSION=sinjoh-raffle-release-20260911 \
  railway variable list --project 3e8e2a91-1b86-498e-887c-6cbd5d694dcb \
    --environment fbc453ac-828e-4727-8184-90c9ac588626 \
    --service 039acfe1-72a1-4d66-8470-af0366c7b626 --json
)"
primary_rpc="$(jq -er '(.variables // .).SINJOH_RPC_PRIMARY' <<<"$variables_json")"
secondary_rpc="$(jq -er '(.variables // .).SINJOH_RPC_SECONDARY' <<<"$variables_json")"
unset variables_json
[[ "$(ETH_RPC_URL="$primary_rpc" cast chain-id)" == 4663 ]]
[[ "$(ETH_RPC_URL="$secondary_rpc" cast chain-id)" == 4663 ]]

if [[ "$mode" == --broadcast ]]; then
  # Deployment signing is distinct from approving/merging the source change.
  state="$(gh pr view 39 --repo Sinjoh-Finance/sinjoh-contracts --json state --jq .state)"
  [[ "$state" == MERGED ]] || { echo 'Contracts PR #39 must be reviewed and merged before broadcasting.' >&2; exit 1; }
fi

cd "$repo_dir/sinjoh-raffle-rewards"
export RANDOMNESS_ADAPTER=0xD16BCD59ca33C1e85578Aa5d60a02C4E2231c491
export ETH_RPC_URL="$primary_rpc"
export FOUNDRY_ETH_RPC_URL="$primary_rpc"
unset primary_rpc secondary_rpc

if [[ "$mode" == --simulate ]]; then
  forge script script/DeployRaffleRewardsFactory.s.sol:DeployRaffleRewardsFactory \
    --sender "$expected_signer"
  exit
fi

# Read the password locally without echoing it or passing it in process arguments.
password_file="$(mktemp "${TMPDIR:-/tmp}/sinjoh-raffle-password.XXXXXX")"
trap 'rm -f "$password_file"' EXIT
chmod 600 "$password_file"
read -r -s -p 'Unlock sinjoh-deployer locally (password is not echoed): ' password
printf '\n'
printf '%s' "$password" > "$password_file"
unset password
actual_signer="$(cast wallet address --account sinjoh-deployer --password-file "$password_file")"
[[ "$(tr '[:upper:]' '[:lower:]' <<<"$actual_signer")" == "$(tr '[:upper:]' '[:lower:]' <<<"$expected_signer")" ]] \
  || { echo 'Deployer does not match the reviewed protocol signer.' >&2; exit 1; }

forge script script/DeployRaffleRewardsFactory.s.sol:DeployRaffleRewardsFactory \
  --account sinjoh-deployer --password-file "$password_file" --broadcast

printf '\nDeployment submitted. Do not activate it until finalized and independently verified.\n'
