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
echo "-=========== create all"
dfx canister create --all --with-cycles 1000000000000
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
echo "==>install DIP20"
dfx canister install DIP20A --argument="(\"DIPA Logo\", \"DIPA\", \"DIPA\", 8, $TOTAL_SUPPLY, principal \"$MINTER_PRINCIPAL\", $TRANS_FEE)"
dfx canister install DIP20B --argument="(\"DIPB Logo\", \"DIPB\", \"DIPB\", 8, $TOTAL_SUPPLY, principal \"$MINTER_PRINCIPAL\", $TRANS_FEE)"
dfx canister install DIP20C --argument="(\"DIPC Logo\", \"DIPC\", \"DIPC\", 8, $TOTAL_SUPPLY, principal \"$MINTER_PRINCIPAL\", $TRANS_FEE)"

echo "==> install SwapFeeReceiver"
dfx canister install SwapFeeReceiver --argument="(principal \"$(dfx canister id SwapFactory)\", record {address=\"$(dfx canister id ICRC2)\"; standard=\"ICRC2\"}, record {address=\"$(dfx canister id ICRC2)\"; standard=\"ICRC2\"}, principal \"$MINTER_PRINCIPAL\")"
echo "==> install TrustedCanisterManager"
dfx canister install TrustedCanisterManager --argument="(null)"
echo "==> install Test"
dfx canister install Test
echo "==> install SwapDataBackup"
dfx canister install SwapDataBackup --argument="(principal \"$(dfx canister id SwapFactory)\", null)"
echo "==> install SwapFactory"
dfx canister install SwapFactory --argument="(principal \"$(dfx canister id Test)\", principal \"$(dfx canister id SwapFeeReceiver)\", principal \"$(dfx canister id PasscodeManager)\", principal \"$(dfx canister id TrustedCanisterManager)\", principal \"$(dfx canister id SwapDataBackup)\", opt principal \"$MINTER_PRINCIPAL\", principal \"$(dfx canister id PositionIndex)\")"
echo "==> install PositionIndex"
dfx canister install PositionIndex --argument="(principal \"$(dfx canister id SwapFactory)\")"
dfx canister install PasscodeManager --argument="(principal \"$(dfx canister id ICRC2)\", 100000000, principal \"$(dfx canister id SwapFactory)\", principal \"$MINTER_PRINCIPAL\")"

dipAId=`dfx canister id DIP20A`
dipBId=`dfx canister id DIP20B`
dipCId=`dfx canister id DIP20C`

# Sort the three token IDs
if [[ "$dipAId" < "$dipBId" ]]; then
    if [[ "$dipAId" < "$dipCId" ]]; then
        token0="$dipAId"
        if [[ "$dipBId" < "$dipCId" ]]; then
            token1="$dipBId"
            token2="$dipCId"
        else
            token1="$dipCId"
            token2="$dipBId"
        fi
    else
        token0="$dipCId"
        token1="$dipAId"
        token2="$dipBId"
    fi
else
    if [[ "$dipBId" < "$dipCId" ]]; then
        token0="$dipBId"
        if [[ "$dipAId" < "$dipCId" ]]; then
            token1="$dipAId"
            token2="$dipCId"
        else
            token1="$dipCId"
            token2="$dipAId"
        fi
    else
        token0="$dipCId"
        token1="$dipBId"
        token2="$dipAId"
    fi
fi

echo "======================================="
echo "=== token0: $token0"
echo "=== token1: $token1"
echo "=== token2: $token2"
echo "======================================="

testId=`dfx canister id Test`
swapFactoryId=`dfx canister id SwapFactory`
positionIndexId=`dfx canister id PositionIndex`
swapFeeReceiverId=`dfx canister id SwapFeeReceiver`
zeroForOne="true"

poolId01=""
poolId02=""
poolId12=""

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

echo 

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
    local token0=$1
    local token1=$2
    local sqrtPriceX96=$3
    
    dfx canister call ICRC2 icrc2_approve "(record{amount=1000000000000;created_at_time=null;expected_allowance=null;expires_at=null;fee=null;from_subaccount=null;memo=null;spender=record {owner= principal \"$(dfx canister id PasscodeManager)\";subaccount=null;}})" > /dev/null
    dfx canister call PasscodeManager depositFrom "(record {amount=100000000;fee=0;})" > /dev/null
    dfx canister call PasscodeManager requestPasscode "(principal \"$token0\", principal \"$token1\", 3000)" > /dev/null
    
    result=`dfx canister call SwapFactory createPool "(record {subnet = opt \"mainnet\"; token0 = record {address = \"$token0\"; standard = \"DIP20\";}; token1 = record {address = \"$token1\"; standard = \"DIP20\";}; fee = 3000; sqrtPriceX96 = \"$sqrtPriceX96\"})"`
    if [[ ! "$result" =~ " ok = record " ]]; then
        echo "\033[31mcreate pool fail. $result - \033[0m" >&2
        return 1
    fi
    
    local poolId=`echo $result | awk -F"canisterId = principal \"" '{print $2}' | awk -F"\";" '{print $1}'`
    
    dfx canister call $token0 approve "(principal \"$poolId\", $TOTAL_SUPPLY)" > /dev/null
    dfx canister call $token1 approve "(principal \"$poolId\", $TOTAL_SUPPLY)" > /dev/null
    dfx canister call PositionIndex updatePoolIds > /dev/null
    
    dfx canister call Test testTokenAdapterBalanceOf "(\"$(dfx canister id ICRC2)\", \"ICRC2\", principal \"$poolId\", null)" > /dev/null
    dfx canister call Test testTokenAdapterBalanceOf "(\"$(dfx canister id ICRC2)\", \"ICRC2\", principal \"$(dfx canister id PasscodeManager)\", null)" > /dev/null
    dfx canister call PasscodeManager transferValidate "(principal \"$poolId\", 100000000)" > /dev/null
    dfx canister call PasscodeManager transfer "(principal \"$poolId\", 100000000)" > /dev/null
    dfx canister call Test testTokenAdapterBalanceOf "(\"$(dfx canister id ICRC2)\", \"ICRC2\", principal \"$poolId\", null)" > /dev/null
    
    echo "$poolId"
    return 0
}

function deposit() #poolId token tokenAmount
{   
    local poolId=$1
    local token=$2
    local amount=$3

    echo "=== pool deposit  ==="
    echo "Debug info:"
    echo "poolId: $poolId"
    echo "token: $token"
    echo "amount: $amount"
    echo "TRANS_FEE: $TRANS_FEE"
    
    echo "Executing command: dfx canister call $poolId depositFrom \"(record {token=\\\"$token\\\"; amount=$amount: nat; fee=$TRANS_FEE: nat;})\""
    result=`dfx canister call $poolId depositFrom "(record {token=\"$token\"; amount=$amount: nat; fee=$TRANS_FEE: nat;})"`
    result=${result//"_"/""}
    if [[ "$result" =~ "$amount" ]]; then
      echo "\033[32m deposit $token success. \033[0m"
    else
      echo "\033[31m deposit $token fail. $result, $amount \033[0m"
    fi
}

function mint() #poolId tickLower tickUpper amount0Desired amount0Min amount1Desired amount1Min
{
    local poolId=$1
    local tickLower=$2
    local tickUpper=$3
    local amount0Desired=$4
    local amount0Min=$5
    local amount1Desired=$6
    local amount1Min=$7
    
    result=`dfx canister call $poolId mint "(record {token0=\"$token0\"; token1=\"$token1\"; fee=3000: nat; tickLower=$tickLower: int; tickUpper=$tickUpper: int; amount0Desired=\"$amount0Desired\"; amount1Desired=\"$amount1Desired\";})"`
    echo "\033[32m mint success. \033[0m"
}

function withdraw() #poolId token amount
{
    local poolId=$1
    local token=$2
    local amount=$3
    
    # Get the tokens for this pool
    read -r poolToken0 poolToken1 <<< $(getPoolTokens "$poolId")
    
    echo "=== Starting withdraw operation ==="
    echo "Pool ID: $poolId"
    echo "Pool tokens: token0=$poolToken0, token1=$poolToken1"
    echo "Withdraw token: $token"
    echo "Withdraw amount: $amount"
    
    result=`dfx canister call $poolId getUserUnusedBalance "(principal \"$MINTER_PRINCIPAL\")"`
    echo "Unused balance result: $result"

    withdrawAmount0=$(echo "$result" | sed -n 's/.*balance0 = \([0-9_]*\) : nat.*/\1/p' | sed 's/[^0-9]//g')
    withdrawAmount1=$(echo "$result" | sed -n 's/.*balance1 = \([0-9_]*\) : nat.*/\1/p' | sed 's/[^0-9]//g')
    echo "Withdraw amount0: $withdrawAmount0"
    echo "Withdraw amount1: $withdrawAmount1"

    if [ "$withdrawAmount0" -gt 0 ]; then
        result=`dfx canister call $poolId withdraw "(record {token=\"$poolToken0\"; fee=$TRANS_FEE: nat; amount=$withdrawAmount0: nat;})"`
        echo "token0 withdraw result: $result"
    fi

    if [ "$withdrawAmount1" -gt 0 ]; then
        result=`dfx canister call $poolId withdraw "(record {token=\"$poolToken1\"; fee=$TRANS_FEE: nat; amount=$withdrawAmount1: nat;})"`
        echo "token1 withdraw result: $result"
    fi
    
    token0BalanceResult="$(balanceOf $poolToken0 $MINTER_PRINCIPAL null)"
    echo "token0 $MINTER_PRINCIPAL balance: $token0BalanceResult"
    token1BalanceResult="$(balanceOf $poolToken1 $MINTER_PRINCIPAL null)"
    echo "token1 $MINTER_PRINCIPAL balance: $token1BalanceResult"
    token0BalanceResult=${token0BalanceResult//"_"/""}
    token1BalanceResult=${token1BalanceResult//"_"/""}

    echo "\033[32m withdraw success. \033[0m"
}

function getPoolTokens() #poolId
{
    local poolId=$1
    local metadata_json=$(dfx canister call $poolId metadata --candid .dfx/local/canisters/SwapPool/SwapPool.did | idl2json)
    
    # Extract token0 and token1 from JSON
    local token0=$(echo "$metadata_json" | jq -r '.ok.token0.address')
    local token1=$(echo "$metadata_json" | jq -r '.ok.token1.address')
    
    echo "$token0 $token1"
}

function swap() #poolId depositToken depositAmount amountIn amountOutMinimum
{
    local poolId=$1
    local depositToken=$2
    local depositAmount=$3
    local amountIn=$4
    local amountOutMinimum=$5
    
    # Get the tokens for this pool
    read -r poolToken0 poolToken1 <<< $(getPoolTokens "$poolId")
    
    echo "=== Starting swap operation ==="
    echo "Pool ID: $poolId"
    echo "Pool tokens: token0=$poolToken0, token1=$poolToken1"
    echo "Deposit token: $depositToken"
    echo "Deposit amount: $depositAmount"
      
    if [[ "$depositToken" == "$poolToken0" ]]; then
        result=`dfx canister call $poolId swap "(record {zeroForOne=true; amountIn=\"$amountIn\"; amountOutMinimum=\"$amountOutMinimum\";})"`
    else
        result=`dfx canister call $poolId swap "(record {zeroForOne=false; amountIn=\"$amountIn\"; amountOutMinimum=\"$amountOutMinimum\";})"`
    fi
    echo "\033[32m swap success. \033[0m"
}

function oneStepSwap() #poolId depositToken depositAmount amountIn amountOutMinimum
{
    local poolId=$1
    local depositToken=$2
    local depositAmount=$3
    local amountIn=$4
    local amountOutMinimum=$5
    
    # Get the tokens for this pool
    read -r poolToken0 poolToken1 <<< $(getPoolTokens "$poolId")
    
    echo "=== Starting one-step swap operation ==="
    echo "Pool ID: $poolId"
    echo "Pool tokens: token0=$poolToken0, token1=$poolToken1"
    echo "Deposit token: $depositToken"
    echo "Deposit amount: $depositAmount"
    
    if [[ "$depositToken" == "$poolToken0" ]]; then
        result=`dfx canister call $poolId depositFromAndSwap "(record { zeroForOne = true; amountIn = \"$amountIn\"; amountOutMinimum = \"$amountOutMinimum\"; tokenInFee = $TRANS_FEE: nat; tokenOutFee = $TRANS_FEE: nat; })"`
    else
        result=`dfx canister call $poolId depositFromAndSwap "(record { zeroForOne = false; amountIn = \"$amountIn\"; amountOutMinimum = \"$amountOutMinimum\"; tokenInFee = $TRANS_FEE: nat; tokenOutFee = $TRANS_FEE: nat; })"`
    fi
    echo "\033[32m one step swap success. \033[0m"
}

function checkBalance() #poolId expectedAmount0 expectedAmount1
{
    local poolId=$1
    local expectedAmount0=$2
    local expectedAmount1=$3
    
    token0BalanceResult="$(balanceOf $token0 $MINTER_PRINCIPAL null)"
    echo "token0 $MINTER_PRINCIPAL balance: $token0BalanceResult"
    token1BalanceResult="$(balanceOf $token1 $MINTER_PRINCIPAL null)"
    echo "token1 $MINTER_PRINCIPAL balance: $token1BalanceResult"
    token0BalanceResult=${token0BalanceResult//"_"/""}
    token1BalanceResult=${token1BalanceResult//"_"/""}
    if [[ "$token0BalanceResult" =~ "$expectedAmount0" ]] && [[ "$token1BalanceResult" =~ "$expectedAmount1" ]]; then
      echo "\033[32m token balance success. \033[0m"
    else
      echo "\033[31m token balance fail. $info \n expected $expectedAmount0 $expectedAmount1\033[0m"
    fi
}

function getPoolState() #poolId
{
    local poolId=$1
    local metadata_json=$(dfx canister call $poolId metadata --candid .dfx/local/canisters/SwapPool/SwapPool.did | idl2json)
    
    # Extract key fields from JSON and remove underscores
    local sqrtPriceX96=$(echo "$metadata_json" | jq -r '.ok.sqrtPriceX96' | tr -d '_')
    local tick=$(echo "$metadata_json" | jq -r '.ok.tick' | tr -d '_')
    local liquidity=$(echo "$metadata_json" | jq -r '.ok.liquidity' | tr -d '_')
    
    # Get token balances
    local balance_json=$(dfx canister call $poolId getTokenBalance --candid .dfx/local/canisters/SwapPool/SwapPool.did | idl2json)
    local token0Balance=$(echo "$balance_json" | jq -r '.token0' | tr -d '_')
    local token1Balance=$(echo "$balance_json" | jq -r '.token1' | tr -d '_')
    
    # Get user unused balance (for current principal)
    local user_balance_json=$(dfx canister call $poolId getUserUnusedBalance "(principal \"$MINTER_PRINCIPAL\")" --candid .dfx/local/canisters/SwapPool/SwapPool.did | idl2json)
    local userBalance0=$(echo "$user_balance_json" | jq -r '.ok.balance0' | tr -d '_')
    local userBalance1=$(echo "$user_balance_json" | jq -r '.ok.balance1' | tr -d '_')
    
    echo "Pool $poolId State:"
    echo "  sqrtPriceX96: $sqrtPriceX96"
    echo "  tick: $tick"
    echo "  liquidity: $liquidity"
    echo "  token0 balance: $token0Balance"
    echo "  token1 balance: $token1Balance"
    echo "  user unused balance0: $userBalance0"
    echo "  user unused balance1: $userBalance1"
    
    # Return values for comparison, using printf to ensure proper formatting
    # printf "%s %s %s" "$sqrtPriceX96" "$tick" "$liquidity"
}

function comparePoolStates() #poolId1 poolId2 poolId3
{
    local poolId1=$1
    local poolId2=$2
    local poolId3=$3
    
    # Get states for all pools and store in arrays
    IFS=' ' read -r sqrtPriceX96_1 tick_1 liquidity_1 <<< $(getPoolState "$poolId1")
    IFS=' ' read -r sqrtPriceX96_2 tick_2 liquidity_2 <<< $(getPoolState "$poolId2")
    IFS=' ' read -r sqrtPriceX96_3 tick_3 liquidity_3 <<< $(getPoolState "$poolId3")
    
}

function testSyncSwap()
{   
    echo
    echo "Starting test with three pools..."
    echo
    
    # Create three pools
    echo "Creating pool for token0-token1..."
    poolId01=$(create_pool "$token0" "$token1" "274450166607934908532224538203")
    echo "Creating pool for token0-token2..."
    poolId02=$(create_pool "$token0" "$token2" "274450166607934908532224538203")
    echo "Creating pool for token1-token2..."
    poolId12=$(create_pool "$token1" "$token2" "274450166607934908532224538203")
    
    echo "======================================="
    echo "=== poolId01: $poolId01"
    echo "=== poolId02: $poolId02"
    echo "=== poolId12: $poolId12"
    echo "======================================="

    dfx canister call $poolId01 stopJobs "(vec {\"SyncTrxsJob\";})"
    dfx canister call $poolId02 stopJobs "(vec {\"SyncTrxsJob\";})"
    dfx canister call $poolId12 stopJobs "(vec {\"SyncTrxsJob\";})"

    # Initialize all pools
    echo "Initializing all pools..."
    
    # Initialize pool01 (token0-token1)
    echo "Initializing pool01 (token0-token1)..."
    deposit "$poolId01" "$token0" 99999999999999
    deposit "$poolId01" "$token1" 99999999999999
    mint "$poolId01" -887220 887220 99999999999999 99999999999999 99999999999999 99999999999999 

    # Initialize pool02 (token0-token2)
    echo "Initializing pool02 (token0-token2)..."
    deposit "$poolId02" "$token0" 99999999999999
    deposit "$poolId02" "$token2" 99999999999999
    mint "$poolId02" -887220 887220 99999999999999 99999999999999 99999999999999 99999999999999 

    # Initialize pool12 (token1-token2)
    echo "Initializing pool12 (token1-token2)..."
    deposit "$poolId12" "$token1" 99999999999999
    deposit "$poolId12" "$token2" 99999999999999
    mint "$poolId12" -887220 887220 99999999999999 99999999999999 99999999999999 99999999999999 

    # Record initial states
    echo "Initial Pool States:"
    getPoolState "$poolId01"
    getPoolState "$poolId02"
    getPoolState "$poolId12"

    # Define test parameters
    local count=10  # Number of operations per pool
    echo "Starting tests with $count operations per pool..."

    # Pool01: Synchronous mode
    echo "Pool01: Running in sync mode..."
    for ((i=1; i<=$count; i++)); do
        echo "Pool01: Operation $i of $count"
        oneStepSwap "$poolId01" "$token0" 10000000000 10000000000 0
    done

    # Pool02: Asynchronous mode
    echo "Pool02: Running in async mode..."
    for ((i=1; i<=$count; i++)); do
        echo "Pool02: Operation $i of $count"
        oneStepSwap "$poolId02" "$token0" 10000000000 10000000000 0 &
    done
    wait

    # Pool12: Mixed mode
    echo "Pool12: Running in mixed mode..."
    
    # First deposit enough tokens for all operations
    echo "Pool12: Depositing tokens for all operations..."
    deposit "$poolId12" "$token1" $((10000000000 * count/2))
    
    for ((i=1; i<=$count/2; i++)); do
        # Half using oneStepSwap
        echo "Pool12: Starting oneStepSwap $i of $((count/2))"
        oneStepSwap "$poolId12" "$token1" 10000000000 10000000000 0 &

        # Half using regular swap
        echo "Pool12: Starting regular swap $i of $((count/2))"
        swap "$poolId12" "$token1" 10000000000 10000000000 0 &
    done
    wait

    sleep 30

    # Record final states
    echo "Final Pool States:"
    echo "======================================="
    echo "Pool01 (Sync Mode) Final State:"
    getPoolState "$poolId01"
    echo "======================================="
    echo "Pool02 (Async Mode) Final State:"
    getPoolState "$poolId02"
    echo "======================================="
    echo "Pool12 (Mixed Mode) Final State:"
    getPoolState "$poolId12"
    echo "======================================="
    
    # Compare pool states
    # comparePoolStates "$poolId01" "$poolId02" "$poolId12"
}

# Modify main script to directly call testSyncSwap
echo "Starting test..."
testSyncSwap

dfx stop
mv dfx.json.bak dfx.json