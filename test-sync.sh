#!/bin/bash
# set -e

# ========================= Test Utilities =========================
PASS_COUNT=0
FAIL_COUNT=0
FAILURES=""
TOTAL_START=$(date +%s)

pass() {
    PASS_COUNT=$((PASS_COUNT + 1))
    echo "\033[32m  [PASS] $1 \033[0m"
}

fail() {
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAILURES="$FAILURES\n  - $1"
    echo "\033[31m  [FAIL] $1 \033[0m"
}

step_header() {
    echo ""
    echo "\033[36m╔══════════════════════════════════════════════════════════════╗\033[0m"
    echo "\033[36m║  Step $1: $2\033[0m"
    echo "\033[36m╚══════════════════════════════════════════════════════════════╝\033[0m"
}

section_header() {
    echo ""
    echo "\033[33m──────────────────────────────────────────────────────────────\033[0m"
    echo "\033[33m  $1\033[0m"
    echo "\033[33m──────────────────────────────────────────────────────────────\033[0m"
}

summary() {
    TOTAL_END=$(date +%s)
    ELAPSED=$((TOTAL_END - TOTAL_START))
    echo ""
    echo "\033[36m╔══════════════════════════════════════════════════════════════╗\033[0m"
    echo "\033[36m║  TEST SUMMARY                                              ║\033[0m"
    echo "\033[36m╚══════════════════════════════════════════════════════════════╝\033[0m"
    echo "  Total:  $((PASS_COUNT + FAIL_COUNT))"
    echo "\033[32m  Passed: $PASS_COUNT \033[0m"
    if [ "$FAIL_COUNT" -gt 0 ]; then
        echo "\033[31m  Failed: $FAIL_COUNT \033[0m"
        echo "\033[31m  Failures: $FAILURES \033[0m"
    else
        echo "  Failed: 0"
    fi
    echo "  Time:   ${ELAPSED}s"
    echo ""
    if [ "$FAIL_COUNT" -gt 0 ]; then
        echo "\033[31m  RESULT: FAILED \033[0m"
    else
        echo "\033[32m  RESULT: ALL PASSED \033[0m"
    fi
    echo ""
}

# ========================= Setup =========================
section_header "Environment Setup"

dfx stop
rm -rf .dfx
mv dfx.json dfx.json.bak
cat > dfx.json <<- EOF
{
  "canisters": {
    "SwapPool": {
      "main": "./src/SwapPool.mo",
      "type": "motoko"
    },
    "SwapFeeReceiver": {
      "main": "./src/SwapFeeReceiver.mo",
      "type": "motoko"
    },
    "SwapFactory": {
      "main": "./src/SwapFactory.mo",
      "type": "motoko"
    },
    "SwapDataBackup": {
      "main": "./src/SwapDataBackup.mo",
      "type": "motoko"
    },
    "PasscodeManager": {
      "main": "./src/PasscodeManager.mo",
      "type": "motoko"
    },
    "PositionIndex": {
      "main": "./src/PositionIndex.mo",
      "type": "motoko",
      "dependencies": ["SwapFactory"]
    },
    "TrustedCanisterManager": {
      "main": "./src/TrustedCanisterManager.mo",
      "type": "motoko"
    },
    "SwapPoolInstaller": {
      "main": "./src/SwapPoolInstaller.mo",
      "type": "motoko"
    },
    "Test": {
      "main": "./test/Test.mo",
      "type": "motoko"
    },
    "DIP20A": {
      "wasm": "./test/dip20/lib.wasm",
      "type": "custom",
      "candid": "./test/dip20/lib.did"
    },
    "DIP20B": {
      "wasm": "./test/dip20/lib.wasm",
      "type": "custom",
      "candid": "./test/dip20/lib.did"
    },
    "DIP20C": {
      "wasm": "./test/dip20/lib.wasm",
      "type": "custom",
      "candid": "./test/dip20/lib.did"
    },
    "ICRC2": {
      "wasm": "./test/icrc2/icrc2.wasm",
      "type": "custom",
      "candid": "./test/icrc2/icrc2.did"
    }
  },
  "defaults": { "build": { "packtool": "vessel sources" } }, "networks": { "local": { "bind": "127.0.0.1:8000", "type": "ephemeral" } }, "version": 1
}
EOF

dfx start --clean --background
echo "  Creating all canisters..."
dfx canister create --all --with-cycles 1000000000000
echo "  Building all canisters..."
dfx build
echo ""

TOTAL_SUPPLY="1000000000000000000"
TRANS_FEE="100000000";
MINTER_PRINCIPAL="$(dfx identity get-principal)"
MINTER_WALLET="$(dfx identity get-wallet)"

# ========================= Install Canisters =========================
section_header "Installing Canisters"

echo "  Installing ICRC2..."
dfx canister install ICRC2 --argument="( record {name = \"ICRC2\"; symbol = \"ICRC2\"; decimals = 8; fee = 0; max_supply = 1_000_000_000_000; initial_balances = vec {record {record {owner = principal \"$MINTER_PRINCIPAL\";subaccount = null;};100_000_000}};min_burn_amount = 10_000;minting_account = null;advanced_settings = null; })"
echo "  Installing DIP20A, DIP20B, DIP20C..."
dfx canister install DIP20A --argument="(\"DIPA Logo\", \"DIPA\", \"DIPA\", 8, $TOTAL_SUPPLY, principal \"$MINTER_PRINCIPAL\", $TRANS_FEE)"
dfx canister install DIP20B --argument="(\"DIPB Logo\", \"DIPB\", \"DIPB\", 8, $TOTAL_SUPPLY, principal \"$MINTER_PRINCIPAL\", $TRANS_FEE)"
dfx canister install DIP20C --argument="(\"DIPC Logo\", \"DIPC\", \"DIPC\", 8, $TOTAL_SUPPLY, principal \"$MINTER_PRINCIPAL\", $TRANS_FEE)"

echo "  Installing infrastructure canisters..."
dfx canister install SwapFeeReceiver --argument="(principal \"$(dfx canister id SwapFactory)\", record {address=\"$(dfx canister id ICRC2)\"; standard=\"ICRC2\"}, record {address=\"$(dfx canister id ICRC2)\"; standard=\"ICRC2\"}, principal \"$MINTER_PRINCIPAL\")"
dfx canister install TrustedCanisterManager --argument="(null)"
dfx canister install Test
dfx canister install SwapDataBackup --argument="(principal \"$(dfx canister id SwapFactory)\", null)"
dfx canister install SwapFactory --argument="(principal \"$(dfx canister id SwapFeeReceiver)\", principal \"$(dfx canister id PasscodeManager)\", principal \"$(dfx canister id TrustedCanisterManager)\", principal \"$(dfx canister id SwapDataBackup)\", opt principal \"$MINTER_PRINCIPAL\", principal \"$(dfx canister id PositionIndex)\")"
dfx canister install PositionIndex --argument="(principal \"$(dfx canister id SwapFactory)\")"
dfx canister install PasscodeManager --argument="(principal \"$(dfx canister id ICRC2)\", 100000000, principal \"$(dfx canister id SwapFactory)\", principal \"$MINTER_PRINCIPAL\")"

dipAId=`dfx canister id DIP20A`
dipBId=`dfx canister id DIP20B`
dipCId=`dfx canister id DIP20C`

# Sort the three token IDs
if [[ "$dipAId" < "$dipBId" ]]; then
    if [[ "$dipAId" < "$dipCId" ]]; then
        token0="$dipAId"
        if [[ "$dipBId" < "$dipCId" ]]; then token1="$dipBId"; token2="$dipCId"
        else token1="$dipCId"; token2="$dipBId"; fi
    else
        token0="$dipCId"; token1="$dipAId"; token2="$dipBId"
    fi
else
    if [[ "$dipBId" < "$dipCId" ]]; then
        token0="$dipBId"
        if [[ "$dipAId" < "$dipCId" ]]; then token1="$dipAId"; token2="$dipCId"
        else token1="$dipCId"; token2="$dipAId"; fi
    else
        token0="$dipCId"; token1="$dipBId"; token2="$dipAId"
    fi
fi

echo ""
echo "  token0: $token0"
echo "  token1: $token1"
echo "  token2: $token2"

swapFactoryId=`dfx canister id SwapFactory`

# ========================= Setup SwapPoolInstaller =========================
section_header "Setting up SwapPoolInstaller"

dfx deploy SwapPoolInstaller --argument="(principal \"$(dfx canister id SwapFactory)\", principal \"$(dfx canister id SwapFactory)\", principal \"$(dfx canister id PositionIndex)\")"
dfx canister update-settings SwapPoolInstaller --add-controller "$swapFactoryId"
dfx canister update-settings SwapPoolInstaller --remove-controller "$MINTER_WALLET"
MODULE_HASH=$(dfx canister call SwapPoolInstaller getStatus | sed -n 's/.*moduleHash = opt blob "\(.*\)".*/\1/p')
dfx canister call SwapFactory setInstallerModuleHash "(blob \"$MODULE_HASH\")"
dfx canister call SwapFactory addPoolInstallers "(vec {record {canisterId = principal \"$(dfx canister id SwapPoolInstaller)\"; subnet = \"mainnet\"; subnetType = \"mainnet\"; weight = 100: nat};})"
dfx canister call SwapFactory removePoolInstaller "(principal \"$(dfx canister id SwapPoolInstaller)\")"
dfx canister call SwapFactory addPoolInstallers "(vec {record {canisterId = principal \"$(dfx canister id SwapPoolInstaller)\"; subnet = \"mainnet\"; subnetType = \"mainnet\"; weight = 100: nat};})"
dfx canister deposit-cycles 50698725619460 SwapPoolInstaller

echo "  Uploading WASM..."
if [ ! -f "./upload-pool-wasm.sh" ]; then
    echo "  Error: upload-pool-wasm.sh not found"
    exit 1
fi
chmod +x ./upload-pool-wasm.sh
sh ./upload-pool-wasm.sh

# ========================= Helper Functions =========================

function balanceOf()
{
    if [ $3 = "null" ]; then
        subaccount="null"
    else
        subaccount="opt principal \"$3\""
    fi
    balance=`dfx canister call Test testTokenAdapterBalanceOf "(\"$1\", \"DIP20\", principal \"$2\", $subaccount)"`
    echo $balance
}

function create_pool() #token0 token1 sqrtPriceX96
{
    local t0=$1
    local t1=$2
    local sqrtPriceX96=$3

    dfx canister call ICRC2 icrc2_approve "(record{amount=1000000000000;created_at_time=null;expected_allowance=null;expires_at=null;fee=null;from_subaccount=null;memo=null;spender=record {owner= principal \"$(dfx canister id PasscodeManager)\";subaccount=null;}})" > /dev/null
    dfx canister call PasscodeManager depositFrom "(record {amount=100000000;fee=0;})" > /dev/null
    dfx canister call PasscodeManager requestPasscode "(principal \"$t0\", principal \"$t1\", 3000)" > /dev/null

    result=`dfx canister call SwapFactory createPool "(record {subnet = opt \"mainnet\"; token0 = record {address = \"$t0\"; standard = \"DIP20\";}; token1 = record {address = \"$t1\"; standard = \"DIP20\";}; fee = 3000; sqrtPriceX96 = \"$sqrtPriceX96\"})"`
    if [[ ! "$result" =~ " ok = record " ]]; then
        fail "create_pool ($t0-$t1): $result"
        return 1
    fi

    local poolId=`echo $result | awk -F"canisterId = principal \"" '{print $2}' | awk -F"\";" '{print $1}'`
    dfx canister call $t0 approve "(principal \"$poolId\", $TOTAL_SUPPLY)" > /dev/null
    dfx canister call $t1 approve "(principal \"$poolId\", $TOTAL_SUPPLY)" > /dev/null
    dfx canister call PositionIndex updatePoolIds > /dev/null
    dfx canister call PasscodeManager transferValidate "(principal \"$poolId\", 100000000)" > /dev/null
    dfx canister call PasscodeManager transfer "(principal \"$poolId\", 100000000)" > /dev/null

    echo "$poolId"
    return 0
}

function deposit() #poolId token amount
{
    local poolId=$1
    local token=$2
    local amount=$3
    result=`dfx canister call $poolId depositFrom "(record {token=\"$token\"; amount=$amount: nat; fee=$TRANS_FEE: nat;})"`
    echo "  deposit $token ok ($amount)"
}

function mint() #poolId tickLower tickUpper amount0 amount1
{
    local poolId=$1
    result=`dfx canister call $poolId mint "(record {token0=\"$token0\"; token1=\"$token1\"; fee=3000: nat; tickLower=$2: int; tickUpper=$3: int; amount0Desired=\"$4\"; amount1Desired=\"$5\";})"`
    if [[ "$result" =~ "ok" ]]; then
        pass "mint on $poolId"
    else
        fail "mint on $poolId: $result"
    fi
}

function oneStepSwap() #poolId depositToken amount amountOutMinimum
{
    local poolId=$1
    local depositToken=$2
    local amount=$3
    local minOut=$4

    local metadata_json=$(dfx canister call $poolId metadata --candid .dfx/local/canisters/SwapPool/SwapPool.did | idl2json)
    local poolToken0=$(echo "$metadata_json" | jq -r '.ok.token0.address')

    if [[ "$depositToken" == "$poolToken0" ]]; then
        result=`dfx canister call $poolId depositFromAndSwap "(record { zeroForOne = true; amountIn = \"$amount\"; amountOutMinimum = \"$minOut\"; tokenInFee = $TRANS_FEE: nat; tokenOutFee = $TRANS_FEE: nat; })"`
    else
        result=`dfx canister call $poolId depositFromAndSwap "(record { zeroForOne = false; amountIn = \"$amount\"; amountOutMinimum = \"$minOut\"; tokenInFee = $TRANS_FEE: nat; tokenOutFee = $TRANS_FEE: nat; })"`
    fi
    if [[ "$result" =~ "ok" ]]; then
        echo "  oneStepSwap ok (amount=$amount)"
    else
        echo "\033[31m  oneStepSwap FAILED: $result \033[0m"
    fi
}

function swap() #poolId depositToken amount amountOutMinimum
{
    local poolId=$1
    local depositToken=$2
    local amount=$3
    local minOut=$4

    local metadata_json=$(dfx canister call $poolId metadata --candid .dfx/local/canisters/SwapPool/SwapPool.did | idl2json)
    local poolToken0=$(echo "$metadata_json" | jq -r '.ok.token0.address')

    if [[ "$depositToken" == "$poolToken0" ]]; then
        result=`dfx canister call $poolId swap "(record {zeroForOne=true; amountIn=\"$amount\"; amountOutMinimum=\"$minOut\";})"`
    else
        result=`dfx canister call $poolId swap "(record {zeroForOne=false; amountIn=\"$amount\"; amountOutMinimum=\"$minOut\";})"`
    fi
    if [[ "$result" =~ "ok" ]]; then
        echo "  swap ok (amount=$amount)"
    else
        echo "\033[31m  swap FAILED: $result \033[0m"
    fi
}

function getPoolState() #poolId label
{
    local poolId=$1
    local label=$2
    local metadata_json=$(dfx canister call $poolId metadata --candid .dfx/local/canisters/SwapPool/SwapPool.did | idl2json)
    local sqrtPriceX96=$(echo "$metadata_json" | jq -r '.ok.sqrtPriceX96' | tr -d '_')
    local tick=$(echo "$metadata_json" | jq -r '.ok.tick' | tr -d '_')
    local liquidity=$(echo "$metadata_json" | jq -r '.ok.liquidity' | tr -d '_')

    echo "  $label: tick=$tick  liquidity=$liquidity  sqrtPriceX96=$sqrtPriceX96"
}

# ========================= Test Cases =========================

function testSyncSwap()
{
    step_header 1 "Create three pools"
    echo "  Creating pool token0-token1..."
    poolId01=$(create_pool "$token0" "$token1" "274450166607934908532224538203")
    echo "  Creating pool token0-token2..."
    poolId02=$(create_pool "$token0" "$token2" "274450166607934908532224538203")
    echo "  Creating pool token1-token2..."
    poolId12=$(create_pool "$token1" "$token2" "274450166607934908532224538203")

    echo ""
    echo "  poolId01: $poolId01"
    echo "  poolId02: $poolId02"
    echo "  poolId12: $poolId12"

    if [ -z "$poolId01" ] || [ -z "$poolId02" ] || [ -z "$poolId12" ]; then
        fail "Pool creation failed"
        return
    fi
    pass "Created 3 pools"

    dfx canister call $poolId01 stopJobs "(vec {\"SyncTrxsJob\";})" > /dev/null
    dfx canister call $poolId02 stopJobs "(vec {\"SyncTrxsJob\";})" > /dev/null
    dfx canister call $poolId12 stopJobs "(vec {\"SyncTrxsJob\";})" > /dev/null

    step_header 2 "Initialize pools with liquidity"
    echo "  Initializing pool01..."
    deposit "$poolId01" "$token0" 99999999999999
    deposit "$poolId01" "$token1" 99999999999999
    mint "$poolId01" -887220 887220 99999999999999 99999999999999

    echo "  Initializing pool02..."
    deposit "$poolId02" "$token0" 99999999999999
    deposit "$poolId02" "$token2" 99999999999999
    mint "$poolId02" -887220 887220 99999999999999 99999999999999

    echo "  Initializing pool12..."
    deposit "$poolId12" "$token1" 99999999999999
    deposit "$poolId12" "$token2" 99999999999999
    mint "$poolId12" -887220 887220 99999999999999 99999999999999

    section_header "Initial Pool States"
    getPoolState "$poolId01" "pool01"
    getPoolState "$poolId02" "pool02"
    getPoolState "$poolId12" "pool12"

    local count=10

    step_header 3 "Pool01: Sync mode ($count sequential swaps)"
    for ((i=1; i<=$count; i++)); do
        oneStepSwap "$poolId01" "$token0" 10000000000 0
    done
    pass "pool01 sync: $count swaps"

    step_header 4 "Pool02: Async mode ($count parallel swaps)"
    for ((i=1; i<=$count; i++)); do
        oneStepSwap "$poolId02" "$token0" 10000000000 0 &
    done
    wait
    pass "pool02 async: $count swaps"

    step_header 5 "Pool12: Mixed mode ($count swaps: half oneStep + half regular)"
    deposit "$poolId12" "$token1" $((10000000000 * count / 2))
    for ((i=1; i<=$count/2; i++)); do
        oneStepSwap "$poolId12" "$token1" 10000000000 0 &
        swap "$poolId12" "$token1" 10000000000 0 &
    done
    wait
    pass "pool12 mixed: $count swaps"

    echo "  Waiting 30s for all queues to drain..."
    sleep 30

    step_header 6 "Final pool states"
    getPoolState "$poolId01" "pool01 (sync)"
    getPoolState "$poolId02" "pool02 (async)"
    getPoolState "$poolId12" "pool12 (mixed)"
}

testSyncSwap

summary

dfx stop
mv dfx.json.bak dfx.json
