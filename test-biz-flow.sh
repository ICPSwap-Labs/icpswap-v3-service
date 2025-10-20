#!/bin/bash
# set -e
# clear
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
    },
    "base_index": {
      "wasm": "./test/base_index/base_index.wasm",
      "type": "custom",
      "candid": "./test/base_index/base_index.did"
    },
    "node_index": {
      "wasm": "./test/node_index/node_index.wasm",
      "type": "custom",
      "candid": "./test/node_index/node_index.did"
    },
    "price": {
      "wasm": "./test/price/price.wasm",
      "type": "custom",
      "candid": "./test/price/price.did"
    }
  },
  "defaults": { "build": { "packtool": "vessel sources" } }, "networks": { "local": { "bind": "127.0.0.1:8000", "type": "ephemeral" } }, "version": 1
}
EOF

dfx start --clean --background
echo "-=========== create all"
dfx canister create --all
echo "-=========== build all"
dfx build
echo

TOTAL_SUPPLY="1000000000000000000"
TRANS_FEE="100000000";
# TRANS_FEE="0";
MINTER_PRINCIPAL="$(dfx identity get-principal)"
MINTER_WALLET="$(dfx identity get-wallet)"

echo "==> Install canisters"
echo
echo "==> install ICRC2"
dfx canister install ICRC2 --argument="( record {name = \"ICRC2\"; symbol = \"ICRC2\"; decimals = 8; fee = 0; max_supply = 1_000_000_000_000; initial_balances = vec {record {record {owner = principal \"$MINTER_PRINCIPAL\";subaccount = null;};100_000_000}};min_burn_amount = 10_000;minting_account = null;advanced_settings = null; })"
echo "==>install TOKENA"
dfx canister install TOKENA --argument="( record {name = \"TOKENA\"; symbol = \"TOKENA\"; decimals = 8; fee = $TRANS_FEE; max_supply = $TOTAL_SUPPLY; initial_balances = vec {record {record {owner = principal \"$MINTER_PRINCIPAL\";subaccount = null;};100_000_000}};min_burn_amount = 10_000;minting_account = null;advanced_settings = null; })"
echo "==>install TOKENB"
dfx canister install TOKENB --argument="( record {name = \"TOKENB\"; symbol = \"TOKENB\"; decimals = 8; fee = $TRANS_FEE; max_supply = $TOTAL_SUPPLY; initial_balances = vec {record {record {owner = principal \"$MINTER_PRINCIPAL\";subaccount = null;};100_000_000}};min_burn_amount = 10_000;minting_account = null;advanced_settings = null; })"

echo "==> install SwapFeeReceiver"
dfx canister install SwapFeeReceiver --argument="(principal \"$(dfx canister id SwapFactory)\", record {address=\"$(dfx canister id ICRC2)\"; standard=\"ICRC2\"}, record {address=\"$(dfx canister id ICRC2)\"; standard=\"ICRC2\"}, principal \"$MINTER_PRINCIPAL\")"
echo "==> install TrustedCanisterManager"
dfx canister install TrustedCanisterManager --argument="(null)"
echo "==> install Test"
dfx canister install Test
echo "==> install price"
dfx deploy price
echo "==> install base_index"
dfx deploy base_index --argument="(principal \"$(dfx canister id price)\", principal \"$(dfx canister id node_index)\")"
echo "==> install node_index"
dfx deploy node_index --argument="(\"$(dfx canister id base_index)\", \"$(dfx canister id price)\")"
echo "==> install SwapDataBackup"
dfx canister install SwapDataBackup --argument="(principal \"$(dfx canister id SwapFactory)\", null)"
echo "==> install SwapFactory"
dfx canister install SwapFactory --argument="(principal \"$(dfx canister id base_index)\", principal \"$(dfx canister id SwapFeeReceiver)\", principal \"$(dfx canister id PasscodeManager)\", principal \"$(dfx canister id TrustedCanisterManager)\", principal \"$(dfx canister id SwapDataBackup)\", opt principal \"$MINTER_PRINCIPAL\", principal \"$(dfx canister id PositionIndex)\")"
echo "==> install PositionIndex"
dfx canister install PositionIndex --argument="(principal \"$(dfx canister id SwapFactory)\")"
dfx canister install PasscodeManager --argument="(principal \"$(dfx canister id ICRC2)\", 100000000, principal \"$(dfx canister id SwapFactory)\", principal \"$MINTER_PRINCIPAL\")"

tokenAId=`dfx canister id TOKENA`
tokenBId=`dfx canister id TOKENB`
testId=`dfx canister id Test`
infoId=`dfx canister id base_index`
swapFactoryId=`dfx canister id SwapFactory`
positionIndexId=`dfx canister id PositionIndex`
swapFeeReceiverId=`dfx canister id SwapFeeReceiver`
zeroForOne="true"
echo "==> infoId (\"$infoId\")"
echo "==> positionIndexId (\"$positionIndexId\")"
echo "==> swapFeeReceiverId (\"$swapFeeReceiverId\")"

echo "==> install SwapPoolInstaller"
dfx deploy SwapPoolInstaller --argument="(principal \"$(dfx canister id SwapFactory)\", principal \"$(dfx canister id SwapFactory)\", principal \"$(dfx canister id PositionIndex)\")"
# dfx canister status SwapPoolInstaller
dfx canister update-settings SwapPoolInstaller --add-controller "$swapFactoryId"
dfx canister update-settings SwapPoolInstaller --remove-controller "$MINTER_WALLET"
# dfx canister status SwapPoolInstaller
MODULE_HASH=$(dfx canister call SwapPoolInstaller getStatus | sed -n 's/.*moduleHash = opt blob "\(.*\)".*/\1/p')
dfx canister call SwapFactory setInstallerModuleHash "(blob \"$MODULE_HASH\")"
dfx canister call SwapFactory getInstallerModuleHash
dfx canister call SwapFactory addPoolInstallers "(vec {record {canisterId = principal \"$(dfx canister id SwapPoolInstaller)\"; subnet = \"mainnet\"; subnetType = \"mainnet\"; weight = 100: nat};})" 
dfx canister call SwapFactory removePoolInstaller "(principal \"$(dfx canister id SwapPoolInstaller)\")" 
dfx canister call SwapFactory addPoolInstallers "(vec {record {canisterId = principal \"$(dfx canister id SwapPoolInstaller)\"; subnet = \"mainnet\"; subnetType = \"mainnet\"; weight = 100: nat};})" 

dfx canister deposit-cycles 50698725619460 SwapPoolInstaller

# Upload WASM to both SwapFactory and SwapPoolInstaller
echo "==> Uploading WASM to SwapFactory and SwapPoolInstaller..."

# Check if upload-pool-wasm.sh exists and has execute permission
if [ ! -f "./upload-pool-wasm.sh" ]; then
    echo "Error: upload-pool-wasm.sh not found in current directory"
    exit 1
fi

# Make sure the script has execute permission
chmod +x ./upload-pool-wasm.sh

# Execute the script
sh ./upload-pool-wasm.sh

testAccount=`dfx canister call Test getAccount "(principal \"$testId\")" | sed 's/[()]//g' | sed 's/"//g'`
echo "testAccount: $testAccount"
currentAccount=`dfx canister call Test getAccount "(principal \"$MINTER_PRINCIPAL\")" | sed 's/[()]//g' | sed 's/"//g'`
echo "currentAccount: $currentAccount"

dfx canister call base_index addClient "(principal \"$swapFactoryId\")"

if [[ "$tokenAId" < "$tokenBId" ]]; then
    token0="$tokenAId"
    token1="$tokenBId"
else
    token0="$tokenBId"
    token1="$tokenAId"
fi
token0Standard="ICRC1"
token1Standard="ICRC2"
echo "======================================="
echo "== token0: $token0"
echo "== token1: $token1"
echo "== token0Standard: $token0Standard"
echo "== token1Standard: $token1Standard"
echo "======================================="

subaccount=$(dfx canister call Test getSubaccount | grep -o 'blob "[^"]*"' | sed 's/blob "//;s/"//')

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

# create pool
function create_pool() #sqrtPriceX96
{
    dfx canister call ICRC2 icrc2_approve "(record{amount=1000000000000;created_at_time=null;expected_allowance=null;expires_at=null;fee=null;from_subaccount=null;memo=null;spender=record {owner= principal \"$(dfx canister id PasscodeManager)\";subaccount=null;}})"
    dfx canister call PasscodeManager depositFrom "(record {amount=100000000;fee=0;})"
    dfx canister call PasscodeManager requestPasscode "(principal \"$token0\", principal \"$token1\", 3000)"
    
    result=`dfx canister call SwapFactory createPool "(record {subnet = opt \"mainnet\"; token0 = record {address = \"$token0\"; standard = \"$token0Standard\";}; token1 = record {address = \"$token1\"; standard = \"$token1Standard\";}; fee = 3000; sqrtPriceX96 = \"$1\"})"`
    if [[ ! "$result" =~ " ok = record " ]]; then
        echo "\033[31mcreate pool fail. $result - \033[0m"
    fi
    echo "create_pool result: $result"
    poolId=`echo $result | awk -F"canisterId = principal \"" '{print $2}' | awk -F"\";" '{print $1}'`
    # dfx canister call $tokenAId approve "(principal \"$poolId\", $TOTAL_SUPPLY)"
    dfx canister call $token1 icrc2_approve "(record{amount=$TOTAL_SUPPLY;created_at_time=null;expected_allowance=null;expires_at=null;fee=opt $TRANS_FEE;from_subaccount=null;memo=null;spender=record {owner= principal \"$poolId\";subaccount=null;}})"

    # dfx canister call PositionIndex updatePoolIds 
    
    dfx canister call PasscodeManager transferValidate "(principal \"$poolId\", 100000000)"
    dfx canister call PasscodeManager transfer "(principal \"$poolId\", 100000000)"
}

function deposit() # token tokenAmount
{
    echo "==> deposit: transfer to subaccount"
    result=`dfx canister call $1 icrc1_transfer "(record {from_subaccount = null; to = record {owner = principal \"$poolId\"; subaccount = opt blob \"$subaccount\";}; amount = $2:nat; fee = opt $TRANS_FEE; memo = null; created_at_time = null;})"`
    subaccountBalance=`balanceOf $1 $poolId $MINTER_PRINCIPAL`
    echo "subaccount balance: $subaccountBalance"
    
    depositAmount=$2
    echo "deposit amount: $depositAmount"

    echo "==> pool deposit"
    result=`dfx canister call $poolId deposit "(record {token = \"$1\"; amount = $depositAmount: nat; fee = $TRANS_FEE: nat; })"`
    echo "deposit result: $result"

    echo "\033[32m deposit $1 success. \033[0m"
}

function depositFrom() # token tokenAmount
{   
    echo "==> pool deposit from"
    result=`dfx canister call $poolId depositFrom "(record {token = \"$1\"; amount = $2: nat; fee = $TRANS_FEE: nat; })"`
    echo "\033[32m depositFrom $1 success. \033[0m"
}

function mint(){ #tickLower tickUpper amount0Desired amount1Desired
    result=`dfx canister call $poolId mint "(record { token0 = \"$token0\"; token1 = \"$token1\"; fee = 3000: nat; tickLower = $1: int; tickUpper = $2: int; amount0Desired = \"$3\"; amount1Desired = \"$4\"; })"`
    echo "\033[32m mint success: $result \033[0m"

    # dfx canister call PositionIndex addPoolId "(\"$poolId\")"
}

function withdrawAll() #token amount
{
    result=`dfx canister call $poolId getUserUnusedBalance "(principal \"$MINTER_PRINCIPAL\")"`
    echo "unused balance result: $result"

    withdrawAmount0=$(echo "$result" | sed -n 's/.*balance0 = \([0-9_]*\) : nat.*/\1/p' | sed 's/[^0-9]//g')
    withdrawAmount1=$(echo "$result" | sed -n 's/.*balance1 = \([0-9_]*\) : nat.*/\1/p' | sed 's/[^0-9]//g')
    echo "withdraw amount0: $withdrawAmount0"
    echo "withdraw amount1: $withdrawAmount1"

    if [ "$withdrawAmount0" -gt 0 ]; then
        result=`dfx canister call $poolId withdraw "(record {token = \"$token0\"; fee = $TRANS_FEE: nat; amount = $withdrawAmount0: nat;})"`
        echo "token0 withdraw result: $result"
    fi

    if [ "$withdrawAmount1" -gt 0 ]; then
        result=`dfx canister call $poolId withdraw "(record {token = \"$token1\"; fee = $TRANS_FEE: nat; amount = $withdrawAmount1: nat;})"`
        echo "token1 withdraw result: $result"
    fi

    echo "\033[32m withdraw all success. \033[0m"
}

# Get withdraw queue information
function get_withdraw_queue_info() {
    local pool_id=$1
    echo "=== Withdraw Queue Information ==="
    local queue_info=$(dfx canister call $pool_id getWithdrawQueueInfo --candid .dfx/local/canisters/SwapPool/SwapPool.did | idl2json)
    
    # Check if the command was successful
    if [ $? -ne 0 ]; then
        echo "Error: Failed to fetch withdraw queue info"
        return 1
    fi
    
    # Debug: show raw JSON (uncomment to debug)
    # echo "Raw JSON: $queue_info"
    
    # Extract values from JSON response
    # Use 'tostring' to convert boolean to string, otherwise false becomes "unknown" with //
    local is_processing=$(echo "$queue_info" | jq -r '.ok.isProcessing | tostring')
    local queue_size=$(echo "$queue_info" | jq -r '.ok.queueSize // "unknown"')
    
    echo "Queue size: $queue_size"
    echo "Is processing: $is_processing"
}

# Optional monitoring function for withdraw queue (uncomment to use)
function monitor_withdraw_queue() {
    local pool_id=$1
    local timeout=${2:-60}  # Default 60 seconds timeout
    
    echo "=== Monitoring withdraw queue for $timeout seconds ==="
    local end_time=$(($(date +%s) + timeout))
    local last_print_time=0
    
    while [ $(date +%s) -lt $end_time ]; do
        local current_time=$(date +%s)
        
        # Only fetch and print every 1 second
        if [ $((current_time - last_print_time)) -ge 1 ]; then
            # Use getWithdrawQueueInfo and convert to JSON using idl2json
            local queue_info=$(dfx canister call $pool_id getWithdrawQueueInfo --candid .dfx/local/canisters/SwapPool/SwapPool.did 2>&1 | idl2json 2>&1)
            
            # Check if the call was successful and parse JSON
            if echo "$queue_info" | jq -e . >/dev/null 2>&1; then
                # Extract values from JSON response
                # Use 'tostring' to convert boolean to string, otherwise false becomes "?" with //
                local is_processing=$(echo "$queue_info" | jq -r '.ok.isProcessing | tostring')
                local queue_size=$(echo "$queue_info" | jq -r '.ok.queueSize // "?"')
                
                echo "[$(date +%H:%M:%S)] Queue: $queue_size items | Processing: $is_processing"
                
                # If queue is empty, we're done (regardless of processing status)
                if [ "$queue_size" = "0" ]; then
                    echo "=== Queue is empty! ==="
                    break
                fi
            else
                # Fallback: if JSON parsing fails, show raw output
                echo "[$(date +%H:%M:%S)] Queue: (parsing error) | Raw: $queue_info"
            fi
            
            last_print_time=$current_time
        fi
        
        sleep 1  # Check more frequently but only print every second
    done
}

function testWithdrawQueue() {
    echo
    echo "=== Testing Withdraw Queue Mechanism ==="
    echo "NOTE: Queue now processes ONE item at a time to minimize resource consumption"
    echo
    
    # Ensure we have a pool and some balance to withdraw
    echo "==> Preparing for withdraw queue test"
    deposit $token0 10000000000000000
    
    echo "==> Initial queue status (should be empty)"
    get_withdraw_queue_info $poolId
    
    echo "==> Starting withdraw queue test"
    local start_time=$(date +%s)
    echo "Test start time: $(date)"
    
    local count=50
    echo "Submitting $count withdraw requests..."
    echo "WARNING: This will take approximately $count seconds to process (1 item per async call)"
    for ((i=1; i<=$count; i++)); do
        echo "Operation $i of $count"
        dfx canister call $poolId withdraw "(record {token = \"$token0\"; fee = $TRANS_FEE: nat; amount = 10000000000: nat;})" >/dev/null 2>&1 &
    done

    echo "Waiting for all requests to be submitted..."
    wait
    
    local submit_end_time=$(date +%s)
    local submit_duration=$((submit_end_time - start_time))
    echo "All requests submitted in $submit_duration seconds at $(date)"
    
    echo "==> Monitoring queue processing (processing one item at a time)..."
    monitor_withdraw_queue $poolId 180
    
    echo "==> Final queue status"
    get_withdraw_queue_info $poolId
}

function swap() #depositToken depositAmount amountIn amountOutMinimum ### liquidity tickCurrent sqrtRatioX96  token0BalanceAmount token1BalanceAmount zeroForOne
{
    echo "== swap... =="
    if [[ "$1" =~ "$token0" ]]; then
        result=`dfx canister call $poolId swap "(record { zeroForOne = true; amountIn = \"$2\"; amountOutMinimum = \"$3\"; })"`
    else
        result=`dfx canister call $poolId swap "(record { zeroForOne = false; amountIn = \"$2\"; amountOutMinimum = \"$3\"; })"`
    fi
    echo "\033[32m swap success: $result \033[0m"
}

function oneStepSwap()
{
    echo "== oneStepSwap... =="
    if [[ "$1" =~ "$token0" ]]; then
        result=`dfx canister call $poolId depositAndSwap "(record { zeroForOne = true; amountIn = \"$2\"; amountOutMinimum = \"$3\"; tokenInFee = $TRANS_FEE: nat; tokenOutFee = $TRANS_FEE: nat; })"`
    else
        result=`dfx canister call $poolId depositFromAndSwap "(record { zeroForOne = false; amountIn = \"$2\"; amountOutMinimum = \"$3\"; tokenInFee = $TRANS_FEE: nat; tokenOutFee = $TRANS_FEE: nat; })"`
    fi
    echo "\033[32m oneStepSwap success: $result \033[0m"
}

function checkUnusedBalance(){
    result=`dfx canister call $poolId getUserUnusedBalance "(principal \"$MINTER_PRINCIPAL\")"`
    echo "unused balances: $result"
}

function checkBalance(){
    token0BalanceResult="$(balanceOf $token0 $MINTER_PRINCIPAL null)"
    echo "token0 $MINTER_PRINCIPAL balance: $token0BalanceResult"
    token1BalanceResult="$(balanceOf $token1 $MINTER_PRINCIPAL null)"
    echo "token1 $MINTER_PRINCIPAL balance: $token1BalanceResult"
    token0BalanceResult=${token0BalanceResult//"_"/""}
    token1BalanceResult=${token1BalanceResult//"_"/""}
    if [[ "$token0BalanceResult" =~ "$1" ]] && [[ "$token1BalanceResult" =~ "$2" ]]; then
      echo "\033[32m token balance success. \033[0m"
    else
      echo "\033[31m token balance fail. $info \n expected $1 $2\033[0m"
    fi
}

function testBizFlow()
{
    
    echo
    echo test whole biz flow
    echo
    #sqrtPriceX96
    create_pool 274450166607934908532224538203

    dfx canister call $poolId setAdmins "(vec {principal \"$MINTER_PRINCIPAL\"})"

    echo "==> step 0 stop jobs"
    dfx canister call $poolId stopJobs "(vec {\"SyncTrxsJob\";})"

    echo

    echo "==> step 1 deposit"
    deposit $token0 10000000000
    depositFrom $token1 10000000000

    echo "==> step 1.1 balanceOf subaccount"
    balanceOf $token0 $poolId $MINTER_PRINCIPAL

    echo "==> step 1.2 balanceOf pool"
    balanceOf $token0 $poolId "null"
    balanceOf $token1 $poolId "null"

    checkUnusedBalance

    echo "==> step 2 withdraw all"
    withdrawAll

    echo "==> step 2.1 balanceOf subaccount"
    balanceOf $token0 $poolId $MINTER_PRINCIPAL

    checkUnusedBalance

    echo "==> step 3 mint"
    deposit $token0 100000000000
    depositFrom $token1 100000000000
    
    echo "==> step 3.1 balanceOf subaccount"
    balanceOf $token0 $poolId $MINTER_PRINCIPAL

    checkUnusedBalance

    # tickLower tickUpper amount0Desired amount1Desired
    mint -887220 887220 99900000000 100000000000 

    checkUnusedBalance

    echo "==> step 4 mint and add limit order"
    for ((batch = 0; batch < 3; batch++)); do
      positionId=$((batch + 2))

      echo "==> add upper limit order $positionId"
      deposit $token0 1000000000
      depositFrom $token1 1000000000
      # current tick 24850
      mint 24900 36060 900000000 1000000000 

      dfx canister call $poolId addLimitOrder "(record { positionId = $positionId :nat; tickLimit = 36060 :int; })"
    done

    echo "==> step 4.1 balanceOf subaccount"
    balanceOf $token0 $poolId $MINTER_PRINCIPAL

    checkUnusedBalance

    echo "==> step 5 remove limit order"
    dfx canister call $poolId removeLimitOrder "(2:nat)"

    echo "==> step 6 swap 1->0"
    depositFrom $token1 200000000000
    swap $token1 200000000000 0
    withdrawAll

    checkUnusedBalance

    echo "==> step 7 swap 0->1"
    quote=`dfx canister call $poolId quote "(record { zeroForOne = true; amountIn = \"100000000000\"; amountOutMinimum = \"0\"; })" | sed 's/.*ok = \([0-9_]*\).*/\1/' | tr -d '_'`
    echo "quote result: $quote"

    result=`dfx canister call $token0 icrc1_transfer "(record {from_subaccount = null; to = record {owner = principal \"$poolId\"; subaccount = opt blob \"$subaccount\";}; amount = 100100000000:nat; fee = opt $TRANS_FEE; memo = null; created_at_time = null;})"`
    oneStepSwap $token0 100000000000 $quote

    echo "==> step 7.1 balanceOf subaccount"
    balanceOf $token0 $poolId $MINTER_PRINCIPAL

    checkUnusedBalance

    echo "==> step 8 transfer position"

    echo "==> step 8.1 position index data"
    testPools=`dfx canister call PositionIndex getUserPools "(\"$testAccount\")"`
    echo "testPools: $testPools"
    currentPools=`dfx canister call PositionIndex getUserPools "(\"$currentAccount\")"`
    echo "currentPools: $currentPools"

    echo "==> step 8.2 transfer position"
    dfx canister call $poolId transferPosition "(principal \"$MINTER_PRINCIPAL\", principal \"$testId\", 1:nat)"

    sleep 5

    echo "==> step 8.3 position index data"
    testPools=`dfx canister call PositionIndex getUserPools "(\"$testAccount\")"`
    echo "testPools: $testPools"
    currentPools=`dfx canister call PositionIndex getUserPools "(\"$currentAccount\")"`
    echo "currentPools: $currentPools"

    # ---check refund of ineffective amount---
    # echo "==> step 9 mint"
    # deposit $token0 1000000000
    # depositFrom $token1 1000000000
    
    # echo "==> step 9.1 balanceOf subaccount"
    # balanceOf $token0 $poolId $MINTER_PRINCIPAL

    # checkUnusedBalance

    # mint 24000 24900 900000000 1000000000 

    # checkUnusedBalance

    # echo "==> step 9 swap 1->0"
    # oneStepSwap $token1 200000000000 0

    # checkUnusedBalance
    
    echo
    echo "=== Running Withdraw Queue Test ==="
    testWithdrawQueue

    # Get swap record
    swap_record_result=$(dfx canister call $poolId getSwapRecordState --candid .dfx/local/canisters/SwapPool/SwapPool.did | idl2json)
    echo "$swap_record_result" > swap_record.json
    echo "Swap record has been saved to swap_record.json"
};

testBizFlow

echo ""
echo "=== ALL TESTS COMPLETED ==="
echo "✅ Business flow test completed successfully"
echo ""

dfx stop
mv dfx.json.bak dfx.json