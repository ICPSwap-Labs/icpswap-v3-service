MODULE_HASH=$(dfx canister --network=ic call vbgd2-jaaaa-aaaam-adwia-cai getCanisterStatus | sed -n 's/.*moduleHash = opt blob "\(.*\)".*/\1/p' | sed 's/\\/\\\\/g')
echo "$MODULE_HASH"