dfx deploy --network=ic --wallet=$(dfx identity --network=ic get-wallet) SwapPool --argument="(
        record { address = \"ryjl3-tyaaa-aaaaa-aaaba-cai\"; standard = \"ICRC-1\" }, 
        record { address = \"ryjl3-tyaaa-aaaaa-aaaba-cai\"; standard = \"ICRC-1\" },
        principal \"jjdg3-6qaaa-aaaah-adsoq-cai\",
        principal \"jjdg3-6qaaa-aaaah-adsoq-cai\")"

dfx canister --network=ic --wallet=$(dfx identity --network=ic get-wallet) update-settings --add-controller ry2wr-pqaaa-aaaah-adxla-cai aq22q-5aaaa-aaaah-adyna-cai

dfx deploy --network ic --wallet=$(dfx identity --network=ic get-wallet) SwapFactoryTest

gzip SwapPoolTest.wasm

cp SwapPoolTest.wasm.gz swap_pool.wasm.gz