#!/usr/bin/env bash
set -euo pipefail

: "${ROBINHOOD_RPC_URL:?set ROBINHOOD_RPC_URL}"
: "${DEPLOYER_PRIVATE_KEY:?set DEPLOYER_PRIVATE_KEY}"
: "${GOVERNANCE:?set the two-step governance owner}"
: "${KEEPER_OPERATOR:?set the existing Sinjoh keeper/observer address}"

WETH="${WETH:-0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73}"
USDG="${USDG:-0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168}"
V3_FACTORY="${V3_FACTORY:-0x1f7d7550B1b028f7571E69A784071F0205FD2EfA}"
V3_POSITION_MANAGER="${V3_POSITION_MANAGER:-0x73991a25C818Bf1f1128dEAaB1492D45638DE0D3}"
V4_POSITION_MANAGER="${V4_POSITION_MANAGER:-0x58daec3116aae6D93017bAAea7749052E8a04fA7}"
V4_STATE_VIEW="${V4_STATE_VIEW:-0xF3334192D15450CdD385c8B70e03f9A6bD9E673b}"
V4_POOL_MANAGER="${V4_POOL_MANAGER:-0x8366a39CC670B4001A1121B8F6A443A643e40951}"
PERMIT2="${PERMIT2:-0x000000000022D473030F116dDEE9F6B43aC78BA3}"
PONS_V2_FACTORY="${PONS_V2_FACTORY:-0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e}"
PONS_V2_HOOK="${PONS_V2_HOOK:-0xE5e702641Ea86F4ae6cC3cDaeD2B886f976Be044}"
SINJOH_PONS_V2_ADAPTER_CODEHASH="${SINJOH_PONS_V2_ADAPTER_CODEHASH:-0xc68d29cb840cd761142664c1a2a348ddccfa4f957df86d54898b981c549b28c7}"
FEE_ROUTER_CODEHASH="${FEE_ROUTER_CODEHASH:-0xf9461aa7ef61b19963cdc3da6d2fe09022718bd753e8c6b7239dce49254ce8fe}"
PROTOCOL_FEE_RECIPIENT="${PROTOCOL_FEE_RECIPIENT:-0x5Bb7582557F5be30b62c335Ad3ccf4bA79E138c5}"
MAX_ORACLE_AGE="${MAX_ORACLE_AGE:-900}"
ORACLE_POOL_FEE="${ORACLE_POOL_FEE:-100}"
ORACLE_TWAP_WINDOW="${ORACLE_TWAP_WINDOW:-900}"
ORACLE_MAX_DEVIATION_BPS="${ORACLE_MAX_DEVIATION_BPS:-500}"
ORACLE_MINIMUM_LIQUIDITY="${ORACLE_MINIMUM_LIQUIDITY:-1000000000000000000}"

for tool in cast forge jq; do
  command -v "$tool" >/dev/null 2>&1 || { echo "missing $tool" >&2; exit 1; }
done

RPC_ARGS=(--rpc-url "$ROBINHOOD_RPC_URL")
if [[ -n "${ROBINHOOD_RPC_HEADERS:-}" ]]; then
  RPC_ARGS+=(--rpc-headers "$ROBINHOOD_RPC_HEADERS")
fi

lower() { tr '[:upper:]' '[:lower:]' <<< "$1"; }

if [[ "$(cast chain-id "${RPC_ARGS[@]}")" != "4663" ]]; then
  echo "refusing to deploy outside Robinhood mainnet" >&2
  exit 1
fi
for address in "$WETH" "$USDG" "$V3_FACTORY" "$V3_POSITION_MANAGER" "$V4_POSITION_MANAGER" \
  "$V4_STATE_VIEW" "$V4_POOL_MANAGER" "$PERMIT2" "$PONS_V2_FACTORY" "$PONS_V2_HOOK"; do
  [[ "$(cast code "$address" "${RPC_ARGS[@]}")" != "0x" ]] || {
    echo "missing bytecode at $address" >&2
    exit 1
  }
done

actual_pool_manager="$(cast call "$V4_STATE_VIEW" 'poolManager()(address)' "${RPC_ARGS[@]}")"
[[ "$(lower "$actual_pool_manager")" == "$(lower "$V4_POOL_MANAGER")" ]] || {
  echo "StateView PoolManager mismatch" >&2
  exit 1
}
position_pool_manager="$(cast call "$V4_POSITION_MANAGER" 'poolManager()(address)' "${RPC_ARGS[@]}")"
[[ "$(lower "$position_pool_manager")" == "$(lower "$V4_POOL_MANAGER")" ]] || {
  echo "PositionManager PoolManager mismatch" >&2
  exit 1
}

deploy() {
  local contract="$1"
  shift
  local result
  result="$(forge create "$contract" "${RPC_ARGS[@]}" \
    --private-key "$DEPLOYER_PRIVATE_KEY" --broadcast --json "$@")"
  local address transaction_hash
  address="$(jq -r '.deployedTo // empty' <<< "$result")"
  transaction_hash="$(jq -r '.transactionHash // empty' <<< "$result")"
  [[ -n "$address" ]] || { echo "deployment failed for $contract" >&2; exit 1; }
  [[ -n "$transaction_hash" ]] || { echo "missing deployment transaction for $contract" >&2; exit 1; }
  printf '%s\t%s\n' "$address" "$transaction_hash"
}

read -r oracle oracle_tx <<< "$(deploy src/oracles/SinjohV3EthUsdOracle.sol:SinjohV3EthUsdOracle \
  --constructor-args "$V3_FACTORY" "$WETH" "$USDG" "$ORACLE_POOL_FEE" \
  "$ORACLE_TWAP_WINDOW" "$ORACLE_MAX_DEVIATION_BPS" "$ORACLE_MINIMUM_LIQUIDITY")"
read -r verifier verifier_tx <<< "$(deploy src/profiles/SinjohPonsV2LaunchVerifier.sol:SinjohPonsV2LaunchVerifier \
  --constructor-args "$PONS_V2_FACTORY" "$PONS_V2_HOOK" "$WETH" \
  "$SINJOH_PONS_V2_ADAPTER_CODEHASH")"
state_view_hash="$(cast codehash "$V4_STATE_VIEW" "${RPC_ARGS[@]}")"
pool_manager_hash="$(cast codehash "$V4_POOL_MANAGER" "${RPC_ARGS[@]}")"
read -r guard guard_tx <<< "$(deploy src/profiles/SinjohV4ConfirmedBandPriceGuard.sol:SinjohV4ConfirmedBandPriceGuard \
  --constructor-args "$V4_STATE_VIEW" "$state_view_hash" "$pool_manager_hash" \
  "$GOVERNANCE" "$KEEPER_OPERATOR")"
read -r math math_tx <<< "$(deploy src/FundingBandMath.sol:FundingBandMath)"
read -r v4_library v4_library_tx <<< "$(deploy src/FundingBandV4.sol:FundingBandV4)"

profiles="[($verifier,$guard,0x)]"
read -r manager manager_tx <<< "$(deploy src/SinjohFundingBands.sol:SinjohFundingBands \
  --libraries "src/FundingBandMath.sol:FundingBandMath:$math" \
  --libraries "src/FundingBandV4.sol:FundingBandV4:$v4_library" \
  --constructor-args "$WETH" "$V3_FACTORY" "$V3_POSITION_MANAGER" \
  "$V4_POSITION_MANAGER" "$V4_STATE_VIEW" "$PERMIT2" "$oracle" \
  "$FEE_ROUTER_CODEHASH" "$PROTOCOL_FEE_RECIPIENT" "$MAX_ORACLE_AGE" "$profiles")"

[[ "$(lower "$(cast call "$oracle" 'weth()(address)' "${RPC_ARGS[@]}")")" == "$(lower "$WETH")" ]]
[[ "$(lower "$(cast call "$oracle" 'usdStable()(address)' "${RPC_ARGS[@]}")")" == "$(lower "$USDG")" ]]
[[ "$(cast call "$oracle" 'twapWindow()(uint32)' "${RPC_ARGS[@]}")" == "$ORACLE_TWAP_WINDOW" ]]
cast call "$oracle" 'latestRoundData()(uint80,int256,uint256,uint256,uint80)' "${RPC_ARGS[@]}" >/dev/null
[[ "$(lower "$(cast call "$guard" 'owner()(address)' "${RPC_ARGS[@]}")")" == "$(lower "$GOVERNANCE")" ]]
[[ "$(lower "$(cast call "$guard" 'quoteSigner()(address)' "${RPC_ARGS[@]}")")" == "$(lower "$KEEPER_OPERATOR")" ]]
[[ "$(cast call "$guard" 'CONFIRMATION_PERIOD()(uint48)' "${RPC_ARGS[@]}")" == "30" ]]
profile="$(cast call "$manager" 'getProfile(uint8)(address,address,bytes32)' 0 "${RPC_ARGS[@]}")"
[[ "$(lower "$(sed -n '1p' <<< "$profile")")" == "$(lower "$verifier")" ]]
[[ "$(lower "$(sed -n '2p' <<< "$profile")")" == "$(lower "$guard")" ]]

manager_block_raw="$(cast receipt "$manager_tx" --json "${RPC_ARGS[@]}" | jq -r '.blockNumber')"
manager_block="$(cast to-dec "$manager_block_raw")"

jq -n \
  --arg chainId "4663" \
  --arg governance "$GOVERNANCE" \
  --arg fundingBandMath "$math" \
  --arg fundingBandV4 "$v4_library" \
  --arg oracle "$oracle" \
  --arg verifier "$verifier" \
  --arg guard "$guard" \
  --arg manager "$manager" \
  --arg managerDeploymentBlock "$manager_block" \
  --arg confirmationPeriod "30" \
  --arg oracleCodehash "$(cast codehash "$oracle" "${RPC_ARGS[@]}")" \
  --arg verifierCodehash "$(cast codehash "$verifier" "${RPC_ARGS[@]}")" \
  --arg guardCodehash "$(cast codehash "$guard" "${RPC_ARGS[@]}")" \
  --arg managerCodehash "$(cast codehash "$manager" "${RPC_ARGS[@]}")" \
  --arg oracleTx "$oracle_tx" --arg verifierTx "$verifier_tx" --arg guardTx "$guard_tx" \
  --arg fundingBandMathTx "$math_tx" --arg fundingBandV4Tx "$v4_library_tx" \
  --arg managerTx "$manager_tx" \
  '{chainId:($chainId|tonumber),governance:$governance,fundingBandMath:$fundingBandMath,
    fundingBandV4:$fundingBandV4,oracle:$oracle,verifier:$verifier,guard:$guard,manager:$manager,
    managerDeploymentBlock:($managerDeploymentBlock|tonumber),
    confirmationPeriodSeconds:($confirmationPeriod|tonumber),
    transactions:{fundingBandMath:$fundingBandMathTx,fundingBandV4:$fundingBandV4Tx,
      oracle:$oracleTx,verifier:$verifierTx,guard:$guardTx,manager:$managerTx},
    codehashes:{oracle:$oracleCodehash,verifier:$verifierCodehash,guard:$guardCodehash,
      manager:$managerCodehash}}'
