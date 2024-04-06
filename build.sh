#!/bin/bash

rm -rf .dfx

dfx identity use icpswap-v2

cp -R ./dfx.json ./dfx_temp.json

echo "==> build SwapPool..."

cat <<< $(jq '.canisters={
  SwapPool: {
    "main": "./src/SwapPool.mo",
    "type": "motoko"
  },
  "SwapFeeReceiver": {
    "main": "./src/SwapFeeReceiver.mo",
    "type": "motoko"
  },
  SwapFactory: {
    "main": "./src/SwapFactory.mo",
    "type": "motoko"
  },
  TrustedCanisterManager: {
    "main": "./src/TrustedCanisterManager.mo",
    "type": "motoko"
  },
  PasscodeManager: {
    "main": "./src/TrustedCanisterManager.mo",
    "type": "motoko"
  },
  "PositionIndex": {
    "main": "./src/PositionIndex.mo",
    "type": "motoko",
    "dependencies": ["SwapFactory"]
  }
}' dfx.json) > dfx.json
dfx start --background

dfx canister create --all
dfx build --all
dfx stop
rm ./dfx.json
cp -R ./dfx_temp.json ./dfx.json
rm ./dfx_temp.json
