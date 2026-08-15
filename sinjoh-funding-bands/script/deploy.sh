#!/usr/bin/env bash
set -euo pipefail

: "${ROBINHOOD_RPC_URL:?set ROBINHOOD_RPC_URL}"
: "${DEPLOYER_PRIVATE_KEY:?set DEPLOYER_PRIVATE_KEY}"
: "${DEPENDENCIES:?set seven comma-separated dependency addresses}"
: "${DEPENDENCY_HASHES:?set seven comma-separated dependency code hashes}"
: "${PROFILE_ADDRESSES:?set alternating verifier,guard addresses}"
: "${PROFILE_HASHES:?set matching verifier,guard code hashes}"
: "${PROFILE_HOOK_DATA_HASHES:?set one hook-data hash per profile}"
: "${PROFILES:?set ABI tuple array, for example [(0xVerifier,0xGuard,0x)]}"
: "${FEE_ROUTER_CODEHASH:?set the independently approved Fee Router clone runtime hash}"
: "${PROTOCOL_FEE_RECIPIENT:?set PROTOCOL_FEE_RECIPIENT}"
: "${MAX_ORACLE_AGE:?set MAX_ORACLE_AGE}"

for required_tool in cast forge jq; do
  if ! command -v "$required_tool" >/dev/null 2>&1; then
    echo "required deployment tool is missing: $required_tool" >&2
    exit 1
  fi
done

lowercase() {
  tr '[:upper:]' '[:lower:]' <<< "$1"
}

assert_equal() {
  local label="$1"
  local actual
  local expected
  actual="$(lowercase "$2")"
  expected="$(lowercase "$3")"
  if [[ "$actual" != "$expected" ]]; then
    echo "$label mismatch: expected $3, got $2" >&2
    exit 1
  fi
}

verify_hashes() {
  local addresses_csv="$1"
  local hashes_csv="$2"
  local addresses
  local hashes
  local index
  local runtime
  local actual_hash
  IFS=',' read -r -a addresses <<< "$addresses_csv"
  IFS=',' read -r -a hashes <<< "$hashes_csv"
  if [[ ${#addresses[@]} -eq 0 || ${#addresses[@]} -ne ${#hashes[@]} ]]; then
    echo "address and code-hash lists must be non-empty and equal length" >&2
    exit 1
  fi
  for index in "${!addresses[@]}"; do
    if [[ ! "${hashes[$index]}" =~ ^0x[0-9a-fA-F]{64}$ ]]; then
      echo "invalid bytes32 code hash for ${addresses[$index]}" >&2
      exit 1
    fi
    runtime="$(cast code "${addresses[$index]}" --rpc-url "$ROBINHOOD_RPC_URL")"
    if [[ "$runtime" == "0x" ]]; then
      echo "no runtime bytecode at ${addresses[$index]}" >&2
      exit 1
    fi
    actual_hash="$(cast codehash "${addresses[$index]}" --rpc-url "$ROBINHOOD_RPC_URL")"
    assert_equal "code hash for ${addresses[$index]}" "$actual_hash" "${hashes[$index]}"
  done
}

verify_address_getter() {
  local deployment="$1"
  local signature="$2"
  local expected="$3"
  local actual
  actual="$(cast call "$deployment" "$signature" --rpc-url "$ROBINHOOD_RPC_URL")"
  assert_equal "$signature" "$actual" "$expected"
}

if [[ "$(cast chain-id --rpc-url "$ROBINHOOD_RPC_URL")" != "4663" ]]; then
  echo "refusing to deploy outside Robinhood mainnet (chain ID 4663)" >&2
  exit 1
fi

IFS=',' read -r -a dependency_addresses <<< "$DEPENDENCIES"
IFS=',' read -r -a dependency_hashes <<< "$DEPENDENCY_HASHES"
IFS=',' read -r -a profile_addresses <<< "$PROFILE_ADDRESSES"
IFS=',' read -r -a profile_hashes <<< "$PROFILE_HASHES"
IFS=',' read -r -a profile_hook_data_hashes <<< "$PROFILE_HOOK_DATA_HASHES"

if [[ ${#dependency_addresses[@]} -ne 7 || ${#dependency_hashes[@]} -ne 7 ]]; then
  echo "DEPENDENCIES and DEPENDENCY_HASHES must each contain seven values" >&2
  exit 1
fi
if [[ ${#profile_addresses[@]} -eq 0 || $((${#profile_addresses[@]} % 2)) -ne 0 ]]; then
  echo "PROFILE_ADDRESSES must contain verifier,guard pairs" >&2
  exit 1
fi
if [[ ${#profile_addresses[@]} -ne ${#profile_hashes[@]} ]]; then
  echo "PROFILE_ADDRESSES and PROFILE_HASHES must contain the same number of values" >&2
  exit 1
fi
profile_count=$((${#profile_addresses[@]} / 2))
if [[ $profile_count -gt 255 ]]; then
  echo "at most 255 immutable profiles are supported" >&2
  exit 1
fi
if [[ ${#profile_hook_data_hashes[@]} -ne $profile_count ]]; then
  echo "PROFILE_HOOK_DATA_HASHES must contain one value per profile" >&2
  exit 1
fi
if [[ ! "$FEE_ROUTER_CODEHASH" =~ ^0x[0-9a-fA-F]{64}$ ]] \
  || [[ "$FEE_ROUTER_CODEHASH" == "0x0000000000000000000000000000000000000000000000000000000000000000" ]]; then
  echo "FEE_ROUTER_CODEHASH must be a nonzero bytes32 value" >&2
  exit 1
fi
if [[ ! "$MAX_ORACLE_AGE" =~ ^[0-9]+$ ]] || [[ "$MAX_ORACLE_AGE" -eq 0 ]]; then
  echo "MAX_ORACLE_AGE must be a positive integer" >&2
  exit 1
fi
for hook_hash in "${profile_hook_data_hashes[@]}"; do
  if [[ ! "$hook_hash" =~ ^0x[0-9a-fA-F]{64}$ ]]; then
    echo "every PROFILE_HOOK_DATA_HASHES value must be bytes32" >&2
    exit 1
  fi
done

verify_hashes "$DEPENDENCIES" "$DEPENDENCY_HASHES"
verify_hashes "$PROFILE_ADDRESSES" "$PROFILE_HASHES"

deployer_address="$(cast wallet address --private-key "$DEPLOYER_PRIVATE_KEY")"
escrow_json="$(forge create src/SinjohFundingBandsLaunchEscrow.sol:SinjohFundingBandsLaunchEscrow \
  --constructor-args "${profile_addresses[0]}" "$deployer_address" \
  --rpc-url "$ROBINHOOD_RPC_URL" \
  --private-key "$DEPLOYER_PRIVATE_KEY" \
  --broadcast --json)"
escrow_address="$(jq -r '.deployedTo' <<< "$escrow_json")"
if [[ -z "$escrow_address" || "$escrow_address" == "null" ]]; then
  echo "SinjohFundingBandsLaunchEscrow deployment did not return an address" >&2
  exit 1
fi

math_json="$(forge create src/FundingBandMath.sol:FundingBandMath \
  --rpc-url "$ROBINHOOD_RPC_URL" \
  --private-key "$DEPLOYER_PRIVATE_KEY" \
  --broadcast --json)"
math_address="$(jq -r '.deployedTo' <<< "$math_json")"
if [[ -z "$math_address" || "$math_address" == "null" ]]; then
  echo "FundingBandMath deployment did not return an address" >&2
  exit 1
fi

v4_json="$(forge create src/FundingBandV4.sol:FundingBandV4 \
  --rpc-url "$ROBINHOOD_RPC_URL" \
  --private-key "$DEPLOYER_PRIVATE_KEY" \
  --broadcast --json)"
v4_library_address="$(jq -r '.deployedTo' <<< "$v4_json")"
if [[ -z "$v4_library_address" || "$v4_library_address" == "null" ]]; then
  echo "FundingBandV4 deployment did not return an address" >&2
  exit 1
fi

manager_json="$(forge create src/SinjohFundingBands.sol:SinjohFundingBands \
  --libraries "src/FundingBandMath.sol:FundingBandMath:$math_address" \
  --libraries "src/FundingBandV4.sol:FundingBandV4:$v4_library_address" \
  --constructor-args \
    "${dependency_addresses[0]}" \
    "${dependency_addresses[1]}" \
    "${dependency_addresses[2]}" \
    "${dependency_addresses[3]}" \
    "${dependency_addresses[4]}" \
    "${dependency_addresses[5]}" \
    "${dependency_addresses[6]}" \
    "$FEE_ROUTER_CODEHASH" \
    "$PROTOCOL_FEE_RECIPIENT" \
    "$escrow_address" \
    "$MAX_ORACLE_AGE" \
    "$PROFILES" \
  --rpc-url "$ROBINHOOD_RPC_URL" \
  --private-key "$DEPLOYER_PRIVATE_KEY" \
  --broadcast --json)"
manager_address="$(jq -r '.deployedTo' <<< "$manager_json")"
if [[ -z "$manager_address" || "$manager_address" == "null" ]]; then
  echo "SinjohFundingBands deployment did not return an address" >&2
  exit 1
fi

verify_address_getter "$manager_address" "weth()(address)" "${dependency_addresses[0]}"
verify_address_getter "$manager_address" "v3Factory()(address)" "${dependency_addresses[1]}"
verify_address_getter "$manager_address" "v3PositionManager()(address)" "${dependency_addresses[2]}"
verify_address_getter "$manager_address" "v4PositionManager()(address)" "${dependency_addresses[3]}"
verify_address_getter "$manager_address" "v4StateView()(address)" "${dependency_addresses[4]}"
verify_address_getter "$manager_address" "permit2()(address)" "${dependency_addresses[5]}"
verify_address_getter "$manager_address" "ethUsdOracle()(address)" "${dependency_addresses[6]}"
verify_address_getter "$manager_address" "protocolFeeRecipient()(address)" "$PROTOCOL_FEE_RECIPIENT"
verify_address_getter "$manager_address" "launchEscrow()(address)" "$escrow_address"
verify_address_getter "$escrow_address" "verifier()(address)" "${profile_addresses[0]}"
verify_address_getter "$escrow_address" "manager()(address)" "0x0000000000000000000000000000000000000000"

actual_fee_router_codehash="$(cast call "$manager_address" 'feeRouterCodehash()(bytes32)' \
  --rpc-url "$ROBINHOOD_RPC_URL")"
assert_equal "feeRouterCodehash" "$actual_fee_router_codehash" "$FEE_ROUTER_CODEHASH"

v4_pool_manager="$(cast call "${dependency_addresses[3]}" 'poolManager()(address)' \
  --rpc-url "$ROBINHOOD_RPC_URL")"
verify_address_getter "$manager_address" "v4PoolManager()(address)" "$v4_pool_manager"

actual_max_oracle_age="$(cast call "$manager_address" 'maxOracleAge()(uint48)' \
  --rpc-url "$ROBINHOOD_RPC_URL")"
assert_equal "maxOracleAge" "$actual_max_oracle_age" "$MAX_ORACLE_AGE"
actual_profile_count="$(cast call "$manager_address" 'profileCount()(uint8)' \
  --rpc-url "$ROBINHOOD_RPC_URL")"
assert_equal "profileCount" "$actual_profile_count" "$profile_count"

for ((profile_index = 0; profile_index < profile_count; profile_index++)); do
  profile_result="$(cast call "$manager_address" \
    'getProfile(uint8)(address,address,bytes32)' "$profile_index" \
    --rpc-url "$ROBINHOOD_RPC_URL")"
  actual_verifier="$(sed -n '1p' <<< "$profile_result")"
  actual_guard="$(sed -n '2p' <<< "$profile_result")"
  actual_hook_hash="$(sed -n '3p' <<< "$profile_result")"
  address_index=$((profile_index * 2))
  assert_equal "profile $profile_index verifier" \
    "$actual_verifier" "${profile_addresses[$address_index]}"
  assert_equal "profile $profile_index guard" \
    "$actual_guard" "${profile_addresses[$((address_index + 1))]}"
  assert_equal "profile $profile_index hook-data hash" \
    "$actual_hook_hash" "${profile_hook_data_hashes[$profile_index]}"
done

# The one-time escrow binding is the final deployment write, after every
# independently verifiable dependency, immutable, profile, and timing check.
cast send "$escrow_address" 'bindManager(address)' "$manager_address" \
  --rpc-url "$ROBINHOOD_RPC_URL" \
  --private-key "$DEPLOYER_PRIVATE_KEY" --json >/dev/null
verify_address_getter "$escrow_address" "manager()(address)" "$manager_address"

echo "FundingBandMath: $math_address"
echo "FundingBandV4: $v4_library_address"
echo "SinjohFundingBandsLaunchEscrow: $escrow_address"
echo "SinjohFundingBands: $manager_address"
echo "SinjohFundingBands code hash: $(cast codehash "$manager_address" --rpc-url "$ROBINHOOD_RPC_URL")"
