#!/bin/bash
# set -e
# clear

# Declare a parameter swap_pool_canister_id, passed through command line
swap_pool_canister_id=$1

if [ -z "$swap_pool_canister_id" ]; then
    echo "Error: swap_pool_canister_id is not provided"
    exit 1
fi

sh ./build.sh

# TODO: update with the correct values
info_cid=""
fee_receiver_cid=""
trusted_canister_manager_cid=""
position_index_cid=""

cat > canister_ids.json <<- EOF
{
    "SwapPool": {
      "ic": "$swap_pool_canister_id"
    }
}
EOF

echo "swap_pool_canister_id: $swap_pool_canister_id"


# Get metadata JSON result
metadata_result=$(dfx canister --network=ic call SwapPool metadata --candid .dfx/local/canisters/SwapPool/SwapPool.did | idl2json)

# Check if the command was successful
if [ $? -ne 0 ]; then
    echo "Error: Failed to fetch metadata from SwapPool."
    exit 1
fi

# Use jq to parse token0 and token1's address and standard
token0_address=$(echo "$metadata_result" | jq -r '.ok.token0.address')
token0_standard=$(echo "$metadata_result" | jq -r '.ok.token0.standard')

token1_address=$(echo "$metadata_result" | jq -r '.ok.token1.address')
token1_standard=$(echo "$metadata_result" | jq -r '.ok.token1.standard')

# Check if fields were successfully extracted
if [[ -z "$token0_address" || -z "$token0_standard" || -z "$token1_address" || -z "$token1_standard" ]]; then
    echo "Error: Failed to extract token data from metadata."
    exit 1
fi

echo "---->  stop"

dfx canister --network=ic stop $swap_pool_canister_id

sleep 3  # Pause for 3 seconds

echo "---->  deploy"

# Construct new dfx deploy command
deploy_command="dfx deploy --network=ic SwapPool --argument='(record {address=\"$token0_address\"; standard=\"$token0_standard\"}, record {address=\"$token1_address\"; standard=\"$token1_standard\"}, principal \"$info_cid\", principal \"$fee_receiver_cid\", principal \"$trusted_canister_manager_cid\", principal \"$position_index_cid\")'"

# Output the generated command
echo "Generated deploy command:"
echo "$deploy_command"

# Execute the generated deploy command
eval "$deploy_command"

echo "---->  start"

dfx canister --network=ic start $swap_pool_canister_id
