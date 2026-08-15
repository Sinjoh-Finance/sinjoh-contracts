#!/usr/bin/env bash
set -euo pipefail

: "${ROBINHOOD_RPC_URL:?set ROBINHOOD_RPC_URL}"
: "${DEPLOYER_PRIVATE_KEY:?set DEPLOYER_PRIVATE_KEY}"
: "${GOVERNANCE:?set the two-step governance owner}"
: "${KEEPER_OPERATOR:?set the dedicated Funding Bands observer address}"

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
ORACLE_POOL="${ORACLE_POOL:-0x52e65B17fB6E5BA00Ed806f37Afcd2DaA50271Ca}"
FEE_ROUTER_FACTORY="${FEE_ROUTER_FACTORY:-0xA1F721a697Dd03a45f264F53bCBFd121212318eD}"
FEE_ROUTER_IMPLEMENTATION="${FEE_ROUTER_IMPLEMENTATION:-0x06274b69d4Cd4D98Ed7Cf4f45Fd50137e8A184a6}"
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

assert_equal() {
  local label="$1"
  local actual="$2"
  local expected="$3"
  [[ "$(lower "$actual")" == "$(lower "$expected")" ]] || {
    echo "$label mismatch: expected $expected, got $actual" >&2
    exit 1
  }
}

runtime_codehash() {
  local address="$1"
  local code
  code="$(cast code "$address" "${RPC_ARGS[@]}")"
  [[ "$code" != "0x" ]] || {
    echo "missing bytecode at $address" >&2
    exit 1
  }
  printf '%s' "$code" | cast keccak
}

assert_codehash() {
  local label="$1"
  local address="$2"
  local expected="$3"
  [[ "$expected" =~ ^0x[0-9a-fA-F]{64}$ ]] || {
    echo "$label expected code hash is not bytes32" >&2
    exit 1
  }
  assert_equal "$label code hash" "$(runtime_codehash "$address")" "$expected"
}

if [[ "$(cast chain-id "${RPC_ARGS[@]}")" != "4663" ]]; then
  echo "refusing to deploy outside Robinhood mainnet" >&2
  exit 1
fi
deployer="$(cast wallet address --private-key "$DEPLOYER_PRIVATE_KEY")"
for address in "$WETH" "$USDG" "$V3_FACTORY" "$V3_POSITION_MANAGER" "$V4_POSITION_MANAGER" \
  "$V4_STATE_VIEW" "$V4_POOL_MANAGER" "$PERMIT2" "$PONS_V2_FACTORY" "$PONS_V2_HOOK" \
  "$FEE_ROUTER_FACTORY" "$FEE_ROUTER_IMPLEMENTATION" "$ORACLE_POOL"; do
  [[ "$(cast code "$address" "${RPC_ARGS[@]}")" != "0x" ]] || {
    echo "missing bytecode at $address" >&2
    exit 1
  }
done

assert_codehash "WETH" "$WETH" "0x5706be52f64875fee65a2cec0d80e47a23d8793cbe85d214b48445e2d05f5353"
assert_codehash "USDG" "$USDG" "0x864cc9ad53b338b82da1f7cab85ab0b3d5c8861acb422b6fec63cf36234f36a6"
assert_codehash "WETH/USDG oracle pool" "$ORACLE_POOL" "0x3298b5dd4e6f115074c526a55ad05a36fd73a0034ac22ec6cbaab32cc9c1e8d2"
assert_codehash "v3 factory" "$V3_FACTORY" "0xec72b1abd1f2faee020cfea9c646bd8994f9fb389054f6e574f103a895091739"
assert_codehash "v3 PositionManager" "$V3_POSITION_MANAGER" "0x0a493d1af3d0f25fed8efa205244ebee14114267a08647fc38c515c7cd6ead4f"
assert_codehash "v4 PositionManager" "$V4_POSITION_MANAGER" "0xc873e135dc9aaec88489cfbad146b4cb49d6a32e0d80326377784b7ba17670b2"
assert_codehash "v4 StateView" "$V4_STATE_VIEW" "0x7d9c591e0956fd89d98feb4ffcfe8bf1f7a62bd485edd979fa21d104b49878a6"
assert_codehash "v4 PoolManager" "$V4_POOL_MANAGER" "0xbd3881180b547f5fe817545743cfb4343e96b1bc6640dcd70c106b0066e95626"
assert_codehash "Permit2" "$PERMIT2" "0x5208783f52488f7d3493e5e38311ab707c1d75457fe472a19b0b4d57d66a7fca"
assert_codehash "Pons v2 factory" "$PONS_V2_FACTORY" "0x89a27da6f703e0a7cdd4f233e7cb57604ff75b164530962d3ff7cf8483a67d84"
assert_codehash "Pons v2 hook" "$PONS_V2_HOOK" "0xc21b1e6c1b45403e81a581f22ed6d9c747997af1cfdac1b1dc9f4b1d346a10db"
assert_codehash "fee router factory" "$FEE_ROUTER_FACTORY" \
  "0x9c409cacd26cd9e6acdf403ce14afa94c263a666886b2fec1a9e2af2063b4ca9"
assert_codehash "fee router implementation" "$FEE_ROUTER_IMPLEMENTATION" \
  "0x00eecc775b2dff40c52bdd038cdccc19b5812a527aa811b359a55249c6987276"
assert_equal "fee router factory implementation" \
  "$(cast call "$FEE_ROUTER_FACTORY" 'implementation()(address)' "${RPC_ARGS[@]}")" \
  "$FEE_ROUTER_IMPLEMENTATION"
fee_router_implementation_hex="${FEE_ROUTER_IMPLEMENTATION#0x}"
FEE_ROUTER_CODEHASH="$(cast keccak \
  "0x363d3d373d3d3d363d73${fee_router_implementation_hex}5af43d82803e903d91602b57fd5bf3")"

resolved_oracle_pool="$(cast call "$V3_FACTORY" 'getPool(address,address,uint24)(address)' \
  "$WETH" "$USDG" "$ORACLE_POOL_FEE" "${RPC_ARGS[@]}")"
assert_equal "WETH/USDG oracle pool" "$resolved_oracle_pool" "$ORACLE_POOL"
assert_equal "Pons v2 launch gate" \
  "$(cast call "$PONS_V2_FACTORY" 'launchEnabled()(bool)' "${RPC_ARGS[@]}")" "true"

pons_fee_escrow="$(cast call "$PONS_V2_FACTORY" 'feeEscrow()(address)' "${RPC_ARGS[@]}")"
for address in "$pons_fee_escrow"; do
  [[ "$(cast code "$address" "${RPC_ARGS[@]}")" != "0x" ]] || {
    echo "missing bytecode at $address" >&2
    exit 1
  }
done
assert_codehash "Pons v2 fee escrow" "$pons_fee_escrow" \
  "0xf25f75cfbc1637ba068dc34f69098fa4e8a80f8ee8fe7bf7820594e0b3fed2f1"

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

read -r adapter_factory adapter_factory_tx <<< "$(deploy \
  src/SinjohPonsV2AdapterFactory.sol:SinjohPonsV2AdapterFactory \
  --root ../sinjoh-launchpad-adapters \
  --constructor-args "$PONS_V2_FACTORY" "$pons_fee_escrow" "$WETH" 4663)"
adapter_implementation="$(cast call "$adapter_factory" 'implementation()(address)' "${RPC_ARGS[@]}")"
actual_adapter_codehash="$(cast call "$adapter_factory" \
  'adapterRuntimeCodehash()(bytes32)' "${RPC_ARGS[@]}")"
for address in "$adapter_factory" "$adapter_implementation"; do
  [[ "$(cast code "$address" "${RPC_ARGS[@]}")" != "0x" ]] || {
    echo "missing deployed adapter bytecode at $address" >&2
    exit 1
  }
done
assert_equal "Pons v2 adapter factory launchFactory" \
  "$(cast call "$adapter_factory" 'launchFactory()(address)' "${RPC_ARGS[@]}")" "$PONS_V2_FACTORY"
assert_equal "Pons v2 adapter factory feeEscrow" \
  "$(cast call "$adapter_factory" 'feeEscrow()(address)' "${RPC_ARGS[@]}")" "$pons_fee_escrow"
assert_equal "Pons v2 adapter factory WETH" \
  "$(cast call "$adapter_factory" 'weth()(address)' "${RPC_ARGS[@]}")" "$WETH"
assert_equal "Pons v2 adapter factory binder" \
  "$(cast call "$adapter_factory" 'binder()(address)' "${RPC_ARGS[@]}")" "$deployer"
assert_equal "Pons v2 adapter implementation factory" \
  "$(cast call "$adapter_implementation" 'adapterFactory()(address)' "${RPC_ARGS[@]}")" "$adapter_factory"
[[ "$(cast call "$adapter_factory" 'deploymentChainId()(uint256)' "${RPC_ARGS[@]}")" == "4663" ]]
[[ "$(cast call "$adapter_implementation" 'initialized()(bool)' "${RPC_ARGS[@]}")" == "true" ]]
[[ "$(lower "$(cast call "$adapter_factory" 'fundingBandsEscrow()(address)' "${RPC_ARGS[@]}")")" == \
  "0x0000000000000000000000000000000000000000" ]]

read -r oracle oracle_tx <<< "$(deploy src/oracles/SinjohV3EthUsdOracle.sol:SinjohV3EthUsdOracle \
  --constructor-args "$V3_FACTORY" "$WETH" "$USDG" "$ORACLE_POOL_FEE" \
  "$ORACLE_TWAP_WINDOW" "$ORACLE_MAX_DEVIATION_BPS" "$ORACLE_MINIMUM_LIQUIDITY")"
read -r verifier verifier_tx <<< "$(deploy src/profiles/SinjohPonsV2LaunchVerifier.sol:SinjohPonsV2LaunchVerifier \
  --constructor-args "$PONS_V2_FACTORY" "$PONS_V2_HOOK" "$WETH" \
  "$SINJOH_PONS_V2_ADAPTER_CODEHASH")"
read -r escrow escrow_tx <<< "$(deploy src/SinjohFundingBandsLaunchEscrow.sol:SinjohFundingBandsLaunchEscrow \
  --constructor-args "$verifier" "$deployer")"
state_view_hash="$(runtime_codehash "$V4_STATE_VIEW")"
pool_manager_hash="$(runtime_codehash "$V4_POOL_MANAGER")"
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
  "$FEE_ROUTER_CODEHASH" "$PROTOCOL_FEE_RECIPIENT" "$escrow" "$MAX_ORACLE_AGE" "$profiles")"
read -r subject_sell_adapter subject_sell_adapter_tx <<< "$(deploy \
  src/SinjohPonsV2SubjectSellAdapter.sol:SinjohPonsV2SubjectSellAdapter \
  --root ../sinjoh-launchpad-adapters \
  --constructor-args "$PONS_V2_FACTORY" "$V4_POOL_MANAGER" "$WETH" \
  "$(runtime_codehash "$PONS_V2_FACTORY")" "$(runtime_codehash "$V4_POOL_MANAGER")" \
  "$(runtime_codehash "$WETH")")"
read -r subject_price_guard subject_price_guard_tx <<< "$(deploy \
  src/SinjohPonsV2FundingBandsSubjectPriceGuard.sol:SinjohPonsV2FundingBandsSubjectPriceGuard \
  --root ../sinjoh-launchpad-adapters \
  --constructor-args "$PONS_V2_FACTORY" "$manager" "$WETH" \
  "$(runtime_codehash "$PONS_V2_FACTORY")" "$(runtime_codehash "$manager")" \
  "$(runtime_codehash "$WETH")")"

[[ "$(lower "$(cast call "$oracle" 'weth()(address)' "${RPC_ARGS[@]}")")" == "$(lower "$WETH")" ]]
[[ "$(lower "$(cast call "$oracle" 'usdStable()(address)' "${RPC_ARGS[@]}")")" == "$(lower "$USDG")" ]]
[[ "$(lower "$(cast call "$oracle" 'pool()(address)' "${RPC_ARGS[@]}")")" == "$(lower "$ORACLE_POOL")" ]]
[[ "$(cast call "$oracle" 'twapWindow()(uint32)' "${RPC_ARGS[@]}")" == "$ORACLE_TWAP_WINDOW" ]]
cast call "$oracle" 'latestRoundData()(uint80,int256,uint256,uint256,uint80)' "${RPC_ARGS[@]}" >/dev/null
[[ "$(lower "$(cast call "$guard" 'owner()(address)' "${RPC_ARGS[@]}")")" == "$(lower "$GOVERNANCE")" ]]
[[ "$(lower "$(cast call "$guard" 'quoteSigner()(address)' "${RPC_ARGS[@]}")")" == "$(lower "$KEEPER_OPERATOR")" ]]
[[ "$(cast call "$guard" 'CONFIRMATION_PERIOD()(uint48)' "${RPC_ARGS[@]}")" == "15" ]]
[[ "$(lower "$(cast call "$verifier" 'ponsFactory()(address)' "${RPC_ARGS[@]}")")" == "$(lower "$PONS_V2_FACTORY")" ]]
[[ "$(lower "$(cast call "$verifier" 'memeHook()(address)' "${RPC_ARGS[@]}")")" == "$(lower "$PONS_V2_HOOK")" ]]
[[ "$(lower "$(cast call "$verifier" 'weth()(address)' "${RPC_ARGS[@]}")")" == "$(lower "$WETH")" ]]
[[ "$(lower "$(cast call "$verifier" 'sinjohAdapterCodehash()(bytes32)' "${RPC_ARGS[@]}")")" == "$(lower "$actual_adapter_codehash")" ]]
profile="$(cast call "$manager" 'getProfile(uint8)(address,address,bytes32)' 0 "${RPC_ARGS[@]}")"
[[ "$(lower "$(sed -n '1p' <<< "$profile")")" == "$(lower "$verifier")" ]]
[[ "$(lower "$(sed -n '2p' <<< "$profile")")" == "$(lower "$guard")" ]]
[[ "$(lower "$(sed -n '3p' <<< "$profile")")" == "$(lower "$(cast keccak 0x)")" ]]
[[ "$(cast call "$manager" 'V4_SETTLEMENT_DELAY()(uint48)' "${RPC_ARGS[@]}")" == "15" ]]
[[ "$(lower "$(cast call "$manager" 'weth()(address)' "${RPC_ARGS[@]}")")" == "$(lower "$WETH")" ]]
[[ "$(lower "$(cast call "$manager" 'v3Factory()(address)' "${RPC_ARGS[@]}")")" == "$(lower "$V3_FACTORY")" ]]
[[ "$(lower "$(cast call "$manager" 'v3PositionManager()(address)' "${RPC_ARGS[@]}")")" == "$(lower "$V3_POSITION_MANAGER")" ]]
[[ "$(lower "$(cast call "$manager" 'v4PositionManager()(address)' "${RPC_ARGS[@]}")")" == "$(lower "$V4_POSITION_MANAGER")" ]]
[[ "$(lower "$(cast call "$manager" 'v4StateView()(address)' "${RPC_ARGS[@]}")")" == "$(lower "$V4_STATE_VIEW")" ]]
[[ "$(lower "$(cast call "$manager" 'v4PoolManager()(address)' "${RPC_ARGS[@]}")")" == "$(lower "$V4_POOL_MANAGER")" ]]
[[ "$(lower "$(cast call "$manager" 'permit2()(address)' "${RPC_ARGS[@]}")")" == "$(lower "$PERMIT2")" ]]
[[ "$(lower "$(cast call "$manager" 'ethUsdOracle()(address)' "${RPC_ARGS[@]}")")" == "$(lower "$oracle")" ]]
[[ "$(lower "$(cast call "$manager" 'protocolFeeRecipient()(address)' "${RPC_ARGS[@]}")")" == "$(lower "$PROTOCOL_FEE_RECIPIENT")" ]]
[[ "$(lower "$(cast call "$manager" 'feeRouterCodehash()(bytes32)' "${RPC_ARGS[@]}")")" == "$(lower "$FEE_ROUTER_CODEHASH")" ]]
[[ "$(cast call "$manager" 'maxOracleAge()(uint48)' "${RPC_ARGS[@]}")" == "$MAX_ORACLE_AGE" ]]
[[ "$(lower "$(cast call "$manager" 'launchEscrow()(address)' "${RPC_ARGS[@]}")")" == "$(lower "$escrow")" ]]
assert_equal "subject sell adapter factory" \
  "$(cast call "$subject_sell_adapter" 'launchFactory()(address)' "${RPC_ARGS[@]}")" "$PONS_V2_FACTORY"
assert_equal "subject sell adapter pool manager" \
  "$(cast call "$subject_sell_adapter" 'poolManager()(address)' "${RPC_ARGS[@]}")" "$V4_POOL_MANAGER"
assert_equal "subject sell adapter WETH" \
  "$(cast call "$subject_sell_adapter" 'weth()(address)' "${RPC_ARGS[@]}")" "$WETH"
assert_equal "subject price guard factory" \
  "$(cast call "$subject_price_guard" 'launchFactory()(address)' "${RPC_ARGS[@]}")" "$PONS_V2_FACTORY"
assert_equal "subject price guard manager" \
  "$(cast call "$subject_price_guard" 'fundingBandsManager()(address)' "${RPC_ARGS[@]}")" "$manager"
assert_equal "subject price guard WETH" \
  "$(cast call "$subject_price_guard" 'weth()(address)' "${RPC_ARGS[@]}")" "$WETH"
[[ "$(lower "$(cast call "$escrow" 'verifier()(address)' "${RPC_ARGS[@]}")")" == "$(lower "$verifier")" ]]
[[ "$(lower "$(cast call "$escrow" 'manager()(address)' "${RPC_ARGS[@]}")")" == "0x0000000000000000000000000000000000000000" ]]

# Binding is deliberately the final write. Every independently checkable
# dependency, immutable, profile, and timing invariant has passed above.
bind_result="$(cast send "$escrow" 'bindManager(address)' "$manager" \
  "${RPC_ARGS[@]}" --private-key "$DEPLOYER_PRIVATE_KEY" --json)"
bind_tx="$(jq -r '.transactionHash // empty' <<< "$bind_result")"
[[ -n "$bind_tx" ]] || { echo "missing escrow binding transaction" >&2; exit 1; }
[[ "$(lower "$(cast call "$escrow" 'manager()(address)' "${RPC_ARGS[@]}")")" == "$(lower "$manager")" ]]

adapter_bind_result="$(cast send "$adapter_factory" \
  'bindFundingBandsEscrow(address)' "$escrow" \
  "${RPC_ARGS[@]}" --private-key "$DEPLOYER_PRIVATE_KEY" --json)"
adapter_bind_tx="$(jq -r '.transactionHash // empty' <<< "$adapter_bind_result")"
[[ -n "$adapter_bind_tx" ]] || { echo "missing adapter escrow binding transaction" >&2; exit 1; }
[[ "$(lower "$(cast call "$adapter_factory" 'fundingBandsEscrow()(address)' "${RPC_ARGS[@]}")")" == "$(lower "$escrow")" ]]

manager_block_raw="$(cast receipt "$manager_tx" --json "${RPC_ARGS[@]}" | jq -r '.blockNumber')"
manager_block="$(cast to-dec "$manager_block_raw")"

jq -n \
  --arg chainId "4663" \
  --arg governance "$GOVERNANCE" \
  --arg adapterFactory "$adapter_factory" \
  --arg adapterImplementation "$adapter_implementation" \
  --arg adapterRuntimeCodehash "$actual_adapter_codehash" \
  --arg adapterFactoryCodehash "$(runtime_codehash "$SINJOH_PONS_V2_ADAPTER_FACTORY")" \
  --arg adapterImplementationCodehash "$(runtime_codehash "$adapter_implementation")" \
  --arg fundingBandMath "$math" \
  --arg fundingBandV4 "$v4_library" \
  --arg oracle "$oracle" \
  --arg verifier "$verifier" \
  --arg guard "$guard" \
  --arg escrow "$escrow" \
  --arg manager "$manager" \
  --arg subjectSellAdapter "$subject_sell_adapter" \
  --arg subjectPriceGuard "$subject_price_guard" \
  --arg managerDeploymentBlock "$manager_block" \
  --arg confirmationPeriod "15" \
  --arg oracleCodehash "$(runtime_codehash "$oracle")" \
  --arg verifierCodehash "$(runtime_codehash "$verifier")" \
  --arg guardCodehash "$(runtime_codehash "$guard")" \
  --arg escrowCodehash "$(runtime_codehash "$escrow")" \
  --arg managerCodehash "$(runtime_codehash "$manager")" \
  --arg subjectSellAdapterCodehash "$(runtime_codehash "$subject_sell_adapter")" \
  --arg subjectPriceGuardCodehash "$(runtime_codehash "$subject_price_guard")" \
  --arg oracleTx "$oracle_tx" --arg verifierTx "$verifier_tx" --arg guardTx "$guard_tx" \
  --arg fundingBandMathTx "$math_tx" --arg fundingBandV4Tx "$v4_library_tx" \
  --arg escrowTx "$escrow_tx" --arg managerTx "$manager_tx" --arg bindTx "$bind_tx" \
  --arg adapterFactoryTx "$adapter_factory_tx" --arg adapterBindTx "$adapter_bind_tx" \
  --arg subjectSellAdapterTx "$subject_sell_adapter_tx" \
  --arg subjectPriceGuardTx "$subject_price_guard_tx" \
  '{chainId:($chainId|tonumber),governance:$governance,
    ponsV2AdapterFactory:$adapterFactory,ponsV2AdapterImplementation:$adapterImplementation,
    ponsV2AdapterRuntimeCodehash:$adapterRuntimeCodehash,fundingBandMath:$fundingBandMath,
    fundingBandV4:$fundingBandV4,oracle:$oracle,verifier:$verifier,guard:$guard,escrow:$escrow,manager:$manager,
    subjectSellAdapter:$subjectSellAdapter,subjectPriceGuard:$subjectPriceGuard,
    managerDeploymentBlock:($managerDeploymentBlock|tonumber),
    confirmationPeriodSeconds:($confirmationPeriod|tonumber),
    transactions:{fundingBandMath:$fundingBandMathTx,fundingBandV4:$fundingBandV4Tx,
      oracle:$oracleTx,verifier:$verifierTx,guard:$guardTx,escrow:$escrowTx,
      adapterFactory:$adapterFactoryTx,manager:$managerTx,subjectSellAdapter:$subjectSellAdapterTx,
      subjectPriceGuard:$subjectPriceGuardTx,bindEscrow:$bindTx,bindAdapterEscrow:$adapterBindTx},
    codehashes:{ponsV2AdapterFactory:$adapterFactoryCodehash,
      ponsV2AdapterImplementation:$adapterImplementationCodehash,
      oracle:$oracleCodehash,verifier:$verifierCodehash,guard:$guardCodehash,
      escrow:$escrowCodehash,manager:$managerCodehash,subjectSellAdapter:$subjectSellAdapterCodehash,
      subjectPriceGuard:$subjectPriceGuardCodehash}}'
