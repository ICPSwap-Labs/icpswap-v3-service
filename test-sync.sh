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
echo "==>install DIP20"
dfx canister install DIP20A --argument="(\"DIPA Logo\", \"DIPA\", \"DIPA\", 8, $TOTAL_SUPPLY, principal \"$MINTER_PRINCIPAL\", $TRANS_FEE)"
dfx canister install DIP20B --argument="(\"DIPB Logo\", \"DIPB\", \"DIPB\", 8, $TOTAL_SUPPLY, principal \"$MINTER_PRINCIPAL\", $TRANS_FEE)"

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

dipAId=`dfx canister id DIP20A`
dipBId=`dfx canister id DIP20B`
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

# Check if upload_pool_wasm.sh exists and has execute permission
if [ ! -f "./upload_pool_wasm.sh" ]; then
    echo "Error: upload_pool_wasm.sh not found in current directory"
    exit 1
fi

# Make sure the script has execute permission
chmod +x ./upload_pool_wasm.sh

# Execute the script
sh ./upload_pool_wasm.sh

dfx canister call base_index addClient "(principal \"$swapFactoryId\")"

if [[ "$dipAId" < "$dipBId" ]]; then
    token0="$dipAId"
    token1="$dipBId"
else
    token0="$dipBId"
    token1="$dipAId"
fi
echo "======================================="
echo "=== token0: $token0"
echo "=== token1: $token1"
echo "======================================="

# subaccount=`dfx canister call Test getSubaccount |grep text__ |awk -F"text__" '{print substr($2,4,128)}'`
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

# create pool
function create_pool() #sqrtPriceX96
{
    dfx canister call ICRC2 icrc2_approve "(record{amount=1000000000000;created_at_time=null;expected_allowance=null;expires_at=null;fee=null;from_subaccount=null;memo=null;spender=record {owner= principal \"$(dfx canister id PasscodeManager)\";subaccount=null;}})"
    dfx canister call PasscodeManager depositFrom "(record {amount=100000000;fee=0;})"
    dfx canister call PasscodeManager requestPasscode "(principal \"$token0\", principal \"$token1\", 3000)"
    
    result=`dfx canister call SwapFactory createPool "(record {subnet = opt \"mainnet\"; token0 = record {address = \"$token0\"; standard = \"DIP20\";}; token1 = record {address = \"$token1\"; standard = \"DIP20\";}; fee = 3000; sqrtPriceX96 = \"$1\"})"`
    if [[ ! "$result" =~ " ok = record " ]]; then
        echo "\033[31mcreate pool fail. $result - \033[0m"
    fi
    echo "create_pool result: $result"
    poolId=`echo $result | awk -F"canisterId = principal \"" '{print $2}' | awk -F"\";" '{print $1}'`
    dfx canister call $dipAId approve "(principal \"$poolId\", $TOTAL_SUPPLY)"
    dfx canister call $dipBId approve "(principal \"$poolId\", $TOTAL_SUPPLY)"
    # dfx canister call $poolId getConfigCids
    dfx canister call PositionIndex updatePoolIds 
    
    balance=`dfx canister call Test testTokenAdapterBalanceOf "(\"$(dfx canister id ICRC2)\", \"ICRC2\", principal \"$poolId\", null)"`
    echo $balance
    balance=`dfx canister call Test testTokenAdapterBalanceOf "(\"$(dfx canister id ICRC2)\", \"ICRC2\", principal \"$(dfx canister id PasscodeManager)\", null)"`
    echo $balance
    dfx canister call PasscodeManager transferValidate "(principal \"$poolId\", $TOTAL_SUPPLY)"
    dfx canister call PasscodeManager transferValidate "(principal \"$poolId\", 100000000)"
    dfx canister call PasscodeManager transfer "(principal \"$poolId\", 100000000)"
    balance=`dfx canister call Test testTokenAdapterBalanceOf "(\"$(dfx canister id ICRC2)\", \"ICRC2\", principal \"$poolId\", null)"`
    echo $balance
}

function deposit() # token tokenAmount
{   
    echo "=== pool deposit  ==="
    result=`dfx canister call $poolId depositFrom "(record {token = \"$1\"; amount = $2: nat; fee = $TRANS_FEE: nat; })"`
    result=${result//"_"/""}
    if [[ "$result" =~ "$2" ]]; then
      echo "\033[32m deposit $1 success. \033[0m"
    else
      echo "\033[31m deposit $1 fail. $result, $2 \033[0m"
    fi
}

function mint(){ #tickLower tickUpper amount0Desired amount0Min amount1Desired amount1Min
    result=`dfx canister call $poolId mint "(record { token0 = \"$token0\"; token1 = \"$token1\"; fee = 3000: nat; tickLower = $1: int; tickUpper = $2: int; amount0Desired = \"$3\"; amount1Desired = \"$5\"; })"`
    echo "\033[32m mint success. \033[0m"

    dfx canister call PositionIndex addPoolId "(\"$poolId\")"
}

function withdraw() #token amount
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
    
    token0BalanceResult="$(balanceOf $token0 $MINTER_PRINCIPAL null)"
    echo "token0 $MINTER_PRINCIPAL balance: $token0BalanceResult"
    token1BalanceResult="$(balanceOf $token1 $MINTER_PRINCIPAL null)"
    echo "token1 $MINTER_PRINCIPAL balance: $token1BalanceResult"
    token0BalanceResult=${token0BalanceResult//"_"/""}
    token1BalanceResult=${token1BalanceResult//"_"/""}

    echo "\033[32m withdraw success. \033[0m"
}

function swap() #depositToken depositAmount amountIn amountOutMinimum ### liquidity tickCurrent sqrtRatioX96  token0BalanceAmount token1BalanceAmount zeroForOne
{
    echo "=== swap... ==="
    deposit $1 $2    
    if [[ "$1" =~ "$token0" ]]; then
        result=`dfx canister call $poolId swap "(record { zeroForOne = true; amountIn = \"$3\"; amountOutMinimum = \"$4\"; })"`
    else
        result=`dfx canister call $poolId swap "(record { zeroForOne = false; amountIn = \"$3\"; amountOutMinimum = \"$4\"; })"`
    fi
    echo "\033[32m swap success. \033[0m"
}

function oneStepSwap() #depositToken depositAmount amountIn amountOutMinimum ### liquidity tickCurrent sqrtRatioX96  token0BalanceAmount token1BalanceAmount zeroForOne
{
    echo "=== swap... ==="
    if [[ "$1" =~ "$token0" ]]; then
        result=`dfx canister call $poolId depositFromAndSwap "(record { zeroForOne = true; amountIn = \"$3\"; amountOutMinimum = \"$4\"; tokenInFee = $TRANS_FEE: nat; tokenOutFee = $TRANS_FEE: nat; })"`
    else
        result=`dfx canister call $poolId depositFromAndSwap "(record { zeroForOne = false; amountIn = \"$3\"; amountOutMinimum = \"$4\"; tokenInFee = $TRANS_FEE: nat; tokenOutFee = $TRANS_FEE: nat; })"`
    fi
    echo "\033[32m swap success. \033[0m"
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

function testSyncSwap()
{   
    local mode=$1  # "sync" or "async"
    local count=$2 # number of times to execute
    
    echo
    echo test mint process
    echo
    #sqrtPriceX96
    create_pool 274450166607934908532224538203

    echo
    echo "==> step 1 mint"
    deposit $token0 99999999999999
    deposit $token1 99999999999999
    #tickLower tickUpper amount0Desired amount0Min amount1Desired amount1Min
    mint -887220 887220 99999999999999 99999999999999 99999999999999 99999999999999 

    echo "==> step 2 withdraw"
    withdraw

    echo "==> swap begin"

    if [ "$mode" = "sync" ]; then
        echo "Executing $count synchronous swaps..."
        for ((i=1; i<=$count; i++)); do
            echo "Swap $i of $count"
            oneStepSwap $token0 10000000000 10000000000 0
        done
    else
        echo "Executing $count asynchronous swaps..."
        for ((i=1; i<=$count; i++)); do
            echo "Starting swap $i of $count"
            oneStepSwap $token0 10000000000 10000000000 0 &
        done
        wait  # Wait for all background processes to complete
    fi
    
    echo "==> swap end"

    echo "==> metadata"
    result=`dfx canister call $poolId metadata`
    echo $result
};

# Check if parameters are provided
if [ $# -lt 2 ]; then
    echo "Usage: $0 <mode> <count>"
    echo "  mode: sync or async"
    echo "  count: number of times to execute"
    exit 1
fi

testSyncSwap "$1" "$2"

# dfx stop
# mv dfx.json.bak dfx.json