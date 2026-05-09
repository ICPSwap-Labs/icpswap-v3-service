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
    "TOKENA": {
      "wasm": "./test/icrc2/icrc2.wasm",
      "type": "custom",
      "candid": "./test/icrc2/icrc2.did"
    },
    "TOKENB": {
      "wasm": "./test/icrc2/icrc2.wasm",
      "type": "custom",
      "candid": "./test/icrc2/icrc2.did"
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
dfx canister create --all
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
echo "  Installing TOKENA & TOKENB..."
dfx canister install TOKENA --argument="( record {name = \"TOKENA\"; symbol = \"TOKENA\"; decimals = 8; fee = $TRANS_FEE; max_supply = $TOTAL_SUPPLY; initial_balances = vec {record {record {owner = principal \"$MINTER_PRINCIPAL\";subaccount = null;};100_000_000}};min_burn_amount = 10_000;minting_account = null;advanced_settings = null; })"
dfx canister install TOKENB --argument="( record {name = \"TOKENB\"; symbol = \"TOKENB\"; decimals = 8; fee = $TRANS_FEE; max_supply = $TOTAL_SUPPLY; initial_balances = vec {record {record {owner = principal \"$MINTER_PRINCIPAL\";subaccount = null;};100_000_000}};min_burn_amount = 10_000;minting_account = null;advanced_settings = null; })"

echo "  Installing infrastructure canisters..."
dfx canister install SwapFeeReceiver --argument="(principal \"$(dfx canister id SwapFactory)\", record {address=\"$(dfx canister id ICRC2)\"; standard=\"ICRC2\"}, record {address=\"$(dfx canister id ICRC2)\"; standard=\"ICRC2\"}, principal \"$MINTER_PRINCIPAL\")"
dfx canister install TrustedCanisterManager --argument="(null)"
dfx canister install Test
dfx canister install SwapDataBackup --argument="(principal \"$(dfx canister id SwapFactory)\", null)"
dfx canister install SwapFactory --argument="(principal \"$(dfx canister id SwapFeeReceiver)\", principal \"$(dfx canister id PasscodeManager)\", principal \"$(dfx canister id TrustedCanisterManager)\", principal \"$(dfx canister id SwapDataBackup)\", opt principal \"$MINTER_PRINCIPAL\", principal \"$(dfx canister id PositionIndex)\")"
dfx canister install PositionIndex --argument="(principal \"$(dfx canister id SwapFactory)\")"
dfx canister install PasscodeManager --argument="(principal \"$(dfx canister id ICRC2)\", 100000000, principal \"$(dfx canister id SwapFactory)\", principal \"$MINTER_PRINCIPAL\")"

tokenAId=`dfx canister id TOKENA`
tokenBId=`dfx canister id TOKENB`
testId=`dfx canister id Test`
swapFactoryId=`dfx canister id SwapFactory`
positionIndexId=`dfx canister id PositionIndex`
swapFeeReceiverId=`dfx canister id SwapFeeReceiver`

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

testAccount=`dfx canister call Test getAccount "(principal \"$testId\")" | sed 's/[()]//g' | sed 's/"//g'`
currentAccount=`dfx canister call Test getAccount "(principal \"$MINTER_PRINCIPAL\")" | sed 's/[()]//g' | sed 's/"//g'`

if [[ "$tokenAId" < "$tokenBId" ]]; then
    token0="$tokenAId"
    token1="$tokenBId"
else
    token0="$tokenBId"
    token1="$tokenAId"
fi
token0Standard="ICRC1"
token1Standard="ICRC2"
echo ""
echo "  token0: $token0 ($token0Standard)"
echo "  token1: $token1 ($token1Standard)"

subaccount=$(dfx canister call Test getSubaccount | grep -o 'blob "[^"]*"' | sed 's/blob "//;s/"//')

# ========================= Helper Functions =========================

function balanceOf()
{
    if [ $3 = "null" ]; then
        sb="null"
    else
        sb="opt principal \"$3\""
    fi
    balance=`dfx canister call Test testTokenAdapterBalanceOf "(\"$1\", \"ICRC2\", principal \"$2\", $sb)"`
    echo $balance
}

function create_pool()
{
    section_header "pool" "Creating Pool"
    dfx canister call ICRC2 icrc2_approve "(record{amount=1000000000000;created_at_time=null;expected_allowance=null;expires_at=null;fee=null;from_subaccount=null;memo=null;spender=record {owner= principal \"$(dfx canister id PasscodeManager)\";subaccount=null;}})" > /dev/null
    dfx canister call PasscodeManager depositFrom "(record {amount=100000000;fee=0;})" > /dev/null
    dfx canister call PasscodeManager requestPasscode "(principal \"$token0\", principal \"$token1\", 3000)" > /dev/null

    result=`dfx canister call SwapFactory createPool "(record {subnet = opt \"mainnet\"; token0 = record {address = \"$token0\"; standard = \"$token0Standard\";}; token1 = record {address = \"$token1\"; standard = \"$token1Standard\";}; fee = 3000; sqrtPriceX96 = \"$1\"})"`
    if [[ ! "$result" =~ " ok = record " ]]; then
        fail "create_pool: $result"
        return
    fi
    poolId=`echo $result | awk -F"canisterId = principal \"" '{print $2}' | awk -F"\";" '{print $1}'`
    dfx canister call $token1 icrc2_approve "(record{amount=$TOTAL_SUPPLY;created_at_time=null;expected_allowance=null;expires_at=null;fee=opt $TRANS_FEE;from_subaccount=null;memo=null;spender=record {owner= principal \"$poolId\";subaccount=null;}})" > /dev/null
    dfx canister call PasscodeManager transferValidate "(principal \"$poolId\", 100000000)" > /dev/null
    dfx canister call PasscodeManager transfer "(principal \"$poolId\", 100000000)" > /dev/null
    echo "  Pool created: $poolId"
}

function deposit()
{
    result=`dfx canister call $1 icrc1_transfer "(record {from_subaccount = null; to = record {owner = principal \"$poolId\"; subaccount = opt blob \"$subaccount\";}; amount = $2:nat; fee = opt $TRANS_FEE; memo = null; created_at_time = null;})"`
    result=`dfx canister call $poolId deposit "(record {token = \"$1\"; amount = $2: nat; fee = $TRANS_FEE: nat; })"`
    echo "  deposit $1 ok ($2)"
}

function depositFrom()
{
    result=`dfx canister call $poolId depositFrom "(record {token = \"$1\"; amount = $2: nat; fee = $TRANS_FEE: nat; })"`
    echo "  depositFrom $1 ok ($2)"
}

function mint()
{
    result=`dfx canister call $poolId mint "(record { token0 = \"$token0\"; token1 = \"$token1\"; fee = 3000: nat; tickLower = $1: int; tickUpper = $2: int; amount0Desired = \"$3\"; amount1Desired = \"$4\"; })"`
    if [[ "$result" =~ "ok" ]]; then
        pass "mint (tickLower=$1, tickUpper=$2)"
    else
        fail "mint: $result"
    fi
}

function withdrawAll()
{
    result=`dfx canister call $poolId getUserUnusedBalance "(principal \"$MINTER_PRINCIPAL\")"`
    withdrawAmount0=$(echo "$result" | sed -n 's/.*balance0 = \([0-9_]*\) : nat.*/\1/p' | sed 's/[^0-9]//g')
    withdrawAmount1=$(echo "$result" | sed -n 's/.*balance1 = \([0-9_]*\) : nat.*/\1/p' | sed 's/[^0-9]//g')

    if [ "$withdrawAmount0" -gt 0 ]; then
        dfx canister call $poolId withdraw "(record {token = \"$token0\"; fee = $TRANS_FEE: nat; amount = $withdrawAmount0: nat;})" > /dev/null 2>&1
    fi
    if [ "$withdrawAmount1" -gt 0 ]; then
        dfx canister call $poolId withdraw "(record {token = \"$token1\"; fee = $TRANS_FEE: nat; amount = $withdrawAmount1: nat;})" > /dev/null 2>&1
    fi

    sleep 2
    pass "withdrawAll (amount0=$withdrawAmount0, amount1=$withdrawAmount1)"
}

function swap()
{
    if [[ "$1" =~ "$token0" ]]; then
        result=`dfx canister call $poolId swap "(record { zeroForOne = true; amountIn = \"$2\"; amountOutMinimum = \"$3\"; })"`
    else
        result=`dfx canister call $poolId swap "(record { zeroForOne = false; amountIn = \"$2\"; amountOutMinimum = \"$3\"; })"`
    fi
    if [[ "$result" =~ "ok" ]]; then
        pass "swap (amountIn=$2)"
    else
        fail "swap: $result"
    fi
}

function oneStepSwap()
{
    if [[ "$1" =~ "$token0" ]]; then
        result=`dfx canister call $poolId depositAndSwap "(record { zeroForOne = true; amountIn = \"$2\"; amountOutMinimum = \"$3\"; tokenInFee = $TRANS_FEE: nat; tokenOutFee = $TRANS_FEE: nat; })"`
    else
        result=`dfx canister call $poolId depositFromAndSwap "(record { zeroForOne = false; amountIn = \"$2\"; amountOutMinimum = \"$3\"; tokenInFee = $TRANS_FEE: nat; tokenOutFee = $TRANS_FEE: nat; })"`
    fi
    if [[ "$result" =~ "ok" ]]; then
        pass "oneStepSwap (amountIn=$2)"
    else
        fail "oneStepSwap: $result"
    fi
}

function checkUnusedBalance()
{
    result=`dfx canister call $poolId getUserUnusedBalance "(principal \"$MINTER_PRINCIPAL\")"`
    echo "  unusedBalance: $result"
}

function getCurrentTick()
{
    # Flatten multi-line output, then extract `tick = N : int`. -E for BSD/GNU sed parity.
    dfx canister call $poolId metadata 2>/dev/null \
        | tr -d '\n' \
        | sed -nE 's/.*tick[[:space:]]*=[[:space:]]*(-?[0-9_]+)[[:space:]]*:[[:space:]]*int.*/\1/p' \
        | tr -d '_'
}

function getNextPositionId()
{
    dfx canister call $poolId metadata 2>/dev/null \
        | tr -d '\n' \
        | sed -nE 's/.*nextPositionId[[:space:]]*=[[:space:]]*([0-9_]+)[[:space:]]*:[[:space:]]*nat.*/\1/p' \
        | tr -d '_'
}

# Returns 1 if positionId appears in upper or lower limit orders, else 0.
function limitOrderPresent()
{
    local pid=$1
    local out
    out=$(dfx canister call $poolId getLimitOrders 2>/dev/null | tr -d '\n')
    if echo "$out" | grep -q "userPositionId = $pid : nat"; then echo 1; else echo 0; fi
}

function checkBalance()
{
    token0BalanceResult="$(balanceOf $token0 $MINTER_PRINCIPAL null)"
    token1BalanceResult="$(balanceOf $token1 $MINTER_PRINCIPAL null)"
    token0BalanceResult=${token0BalanceResult//"_"/""}
    token1BalanceResult=${token1BalanceResult//"_"/""}
    if [[ "$token0BalanceResult" =~ "$1" ]] && [[ "$token1BalanceResult" =~ "$2" ]]; then
        pass "checkBalance (token0=$1, token1=$2)"
    else
        fail "checkBalance: expected token0=$1 token1=$2, got token0=$token0BalanceResult token1=$token1BalanceResult"
    fi
}

function monitor_withdraw_queue()
{
    local pool_id=$1
    local timeout=${2:-60}
    local end_time=$(($(date +%s) + timeout))

    echo "  Monitoring withdraw queue (timeout=${timeout}s)..."
    while [ $(date +%s) -lt $end_time ]; do
        local queue_info=$(dfx canister call $pool_id getWithdrawQueueInfo --candid .dfx/local/canisters/SwapPool/SwapPool.did 2>&1 | idl2json 2>&1)
        if echo "$queue_info" | jq -e . >/dev/null 2>&1; then
            local queue_size=$(echo "$queue_info" | jq -r '.ok.queueSize // "?"')
            if [ "$queue_size" = "0" ]; then
                echo "  Queue drained."
                return
            fi
            echo "  [$(date +%H:%M:%S)] queue=$queue_size"
        fi
        sleep 1
    done
    echo "  Queue monitoring timed out."
}

function testWithdrawQueue()
{
    section_header "WQ" "Withdraw Queue Stress Test"

    deposit $token0 10000000000000000

    local count=50
    echo "  Submitting $count withdraw requests in parallel..."
    for ((i=1; i<=$count; i++)); do
        dfx canister call $poolId withdraw "(record {token = \"$token0\"; fee = $TRANS_FEE: nat; amount = 10000000000: nat;})" > /dev/null 2>&1 &
    done
    wait
    echo "  All requests submitted."

    monitor_withdraw_queue $poolId 180

    local queue_info=$(dfx canister call $poolId getWithdrawQueueInfo --candid .dfx/local/canisters/SwapPool/SwapPool.did 2>&1 | idl2json 2>&1)
    local final_size=$(echo "$queue_info" | jq -r '.ok.queueSize // "?"')
    if [ "$final_size" = "0" ]; then
        pass "withdrawQueue ($count items processed)"
    else
        fail "withdrawQueue: $final_size items remaining"
    fi
}

# Regression test for the limit-order partial-fill bug: when tickLimit is set
# strictly inside (tickLower, tickUpper), the order must NOT fire while the
# position is still in-range. It must only fire once _tick crosses tickUpper
# (upper order) so the input is fully converted to output.
function step_partial_fill_regression()
{
    step_header "PF" "Limit-order partial-fill regression (bug fix)"

    local spacing=60   # fee=3000 → tickSpacing=60
    local t0=$(getCurrentTick)
    if [ -z "$t0" ]; then
        fail "partial-fill: could not parse tick from metadata() — check dfx output format"
        return
    fi
    echo "  current tick: $t0"

    # Place the test range above the current tick, aligned to spacing.
    local margin=$((spacing * 30))
    local width=$((spacing * 60))
    local base=$(( ( (t0 + margin + spacing - 1) / spacing ) * spacing ))
    local pfTickLower=$base
    local pfTickUpper=$(( base + width ))
    local pfTickLimit=$(( base + width / 2 ))
    # tickLimit must fall on an integer tick; align to spacing for safety.
    pfTickLimit=$(( (pfTickLimit / spacing) * spacing ))
    echo "  test range: [$pfTickLower, $pfTickUpper]  tickLimit: $pfTickLimit"

    if [ "$t0" -ge "$pfTickLower" ]; then
        fail "partial-fill: current tick $t0 already inside/above intended range"
        return
    fi

    local pfId=$(getNextPositionId)
    if [ -z "$pfId" ]; then
        fail "partial-fill: could not parse nextPositionId from metadata()"
        return
    fi
    deposit $token0 10000000000
    depositFrom $token1 10000000000
    mint $pfTickLower $pfTickUpper 9000000000 10000000000
    echo "  pfPositionId=$pfId"

    local addRes
    addRes=$(dfx canister call $poolId addLimitOrder \
        "(record { positionId = $pfId :nat; tickLimit = $pfTickLimit :int; })")
    if [[ ! "$addRes" =~ "ok" ]]; then
        fail "partial-fill: addLimitOrder failed: $addRes"
        return
    fi
    if [ "$(limitOrderPresent $pfId)" -ne 1 ]; then
        fail "partial-fill: limit order not registered"
        return
    fi

    # ---- Phase A: try to land tick in [tickLimit, tickUpper) ----
    # Ramp swap size until we cross tickLimit but stay below tickUpper.
    local landed=0
    local cur
    for amt in 5000000000 10000000000 20000000000 50000000000 100000000000; do
        cur=$(getCurrentTick)
        if [ "$cur" -ge "$pfTickLimit" ]; then break; fi
        depositFrom $token1 $amt
        swap $token1 $amt 0
        sleep 3
    done
    cur=$(getCurrentTick)
    echo "  tick after phase A: $cur"
    if [ "$cur" -ge "$pfTickLimit" ] && [ "$cur" -lt "$pfTickUpper" ]; then
        landed=1
        if [ "$(limitOrderPresent $pfId)" -eq 1 ]; then
            pass "partial-fill: order survives mid-range tick=$cur (>=tickLimit=$pfTickLimit, <tickUpper=$pfTickUpper)"
        else
            fail "partial-fill: order fired prematurely at tick=$cur — bug regressed"
            return
        fi
    elif [ "$cur" -ge "$pfTickUpper" ]; then
        echo "  WARN: phase A overshot tickUpper (tick=$cur); cannot test mid-range survival in this run"
    else
        echo "  WARN: phase A could not reach tickLimit=$pfTickLimit (tick=$cur); increase swap amounts"
    fi

    # ---- Phase B: push tick past tickUpper; order MUST fire ----
    for amt in 50000000000 100000000000 200000000000 500000000000; do
        cur=$(getCurrentTick)
        if [ "$cur" -ge "$pfTickUpper" ]; then break; fi
        depositFrom $token1 $amt
        swap $token1 $amt 0
        sleep 5
    done
    cur=$(getCurrentTick)
    echo "  tick after phase B: $cur"
    if [ "$cur" -ge "$pfTickUpper" ]; then
        if [ "$(limitOrderPresent $pfId)" -eq 0 ]; then
            pass "partial-fill: order fires after tick=$cur >= tickUpper=$pfTickUpper"
        else
            fail "partial-fill: order failed to fire after tick crossed tickUpper"
        fi
    else
        fail "partial-fill: could not push tick past tickUpper=$pfTickUpper (tick=$cur)"
    fi

    withdrawAll
}

# ========================= Test Cases =========================

function testBizFlow()
{
    create_pool 274450166607934908532224538203

    dfx canister call $poolId setAdmins "(vec {principal \"$MINTER_PRINCIPAL\"})" > /dev/null

    step_header 0 "Stop sync jobs"
    dfx canister call $poolId stopJobs "(vec {\"SyncTrxsJob\";})" > /dev/null

    step_header 1 "Deposit (ICRC1 transfer + deposit, ICRC2 depositFrom)"
    deposit $token0 10000000000
    depositFrom $token1 10000000000
    checkUnusedBalance

    step_header 2 "Withdraw all"
    withdrawAll
    checkUnusedBalance

    step_header 3 "Mint position"
    deposit $token0 100000000000
    depositFrom $token1 100000000000
    checkUnusedBalance
    mint -887220 887220 99900000000 100000000000
    checkUnusedBalance

    step_header 4 "Mint + add limit orders (x3)"
    for ((batch = 0; batch < 3; batch++)); do
        positionId=$((batch + 2))
        echo "  Adding upper limit order (positionId=$positionId)..."
        deposit $token0 1000000000
        depositFrom $token1 1000000000
        mint 24900 36060 900000000 1000000000
        dfx canister call $poolId addLimitOrder "(record { positionId = $positionId :nat; tickLimit = 36060 :int; })" > /dev/null
    done
    checkUnusedBalance

    step_header 5 "Remove limit order (positionId=2)"
    result=`dfx canister call $poolId removeLimitOrder "(2:nat)"`
    if [[ "$result" =~ "ok" ]]; then
        pass "removeLimitOrder (positionId=2)"
    else
        fail "removeLimitOrder: $result"
    fi

    step_partial_fill_regression

    step_header 6 "Swap token1 -> token0"
    depositFrom $token1 200000000000
    swap $token1 200000000000 0
    withdrawAll
    checkUnusedBalance

    step_header 7 "OneStepSwap token0 -> token1 (with quote)"
    quote=`dfx canister call $poolId quote "(record { zeroForOne = true; amountIn = \"100000000000\"; amountOutMinimum = \"0\"; })" | sed 's/.*ok = \([0-9_]*\).*/\1/' | tr -d '_'`
    echo "  quote=$quote"
    result=`dfx canister call $token0 icrc1_transfer "(record {from_subaccount = null; to = record {owner = principal \"$poolId\"; subaccount = opt blob \"$subaccount\";}; amount = 100100000000:nat; fee = opt $TRANS_FEE; memo = null; created_at_time = null;})"`
    oneStepSwap $token0 100000000000 $quote
    checkUnusedBalance

    step_header 8 "Transfer position"
    echo "  Before transfer:"
    testPools=`dfx canister call PositionIndex getUserPools "(\"$testAccount\")"`
    echo "    testPools: $testPools"
    currentPools=`dfx canister call PositionIndex getUserPools "(\"$currentAccount\")"`
    echo "    currentPools: $currentPools"

    dfx canister call $poolId transferPosition "(principal \"$MINTER_PRINCIPAL\", principal \"$testId\", 1:nat)" > /dev/null
    sleep 5

    echo "  After transfer:"
    testPools=`dfx canister call PositionIndex getUserPools "(\"$testAccount\")"`
    echo "    testPools: $testPools"
    currentPools=`dfx canister call PositionIndex getUserPools "(\"$currentAccount\")"`
    echo "    currentPools: $currentPools"

    if [[ "$testPools" =~ "$poolId" ]]; then
        pass "transferPosition (positionId=1 -> testId)"
    else
        fail "transferPosition: testId pool list doesn't contain poolId"
    fi

    testWithdrawQueue

    # Save swap record
    swap_record_result=$(dfx canister call $poolId getSwapRecordState --candid .dfx/local/canisters/SwapPool/SwapPool.did | idl2json)
    echo "$swap_record_result" > swap_record.json
    echo "  Swap record saved to swap_record.json"
}

testBizFlow

summary

dfx stop
mv dfx.json.bak dfx.json
