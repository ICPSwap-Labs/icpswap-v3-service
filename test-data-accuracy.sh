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
# TRANS_FEE="100000000";
TRANS_FEE="0";
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

# Check if upload-pool-wasm.sh exists and has execute permission
if [ ! -f "./upload-pool-wasm.sh" ]; then
    echo "Error: upload-pool-wasm.sh not found in current directory"
    exit 1
fi

# Make sure the script has execute permission
chmod +x ./upload-pool-wasm.sh

# Execute the script
sh ./upload-pool-wasm.sh

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
    
    dfx canister call PasscodeManager transferValidate "(principal \"$poolId\", 100000000)"
    dfx canister call PasscodeManager transfer "(principal \"$poolId\", 100000000)"

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

function mint(){ #tickLower tickUpper amount0Desired amount0Min amount1Desired amount1Min ### liquidity tickCurrent sqrtRatioX96
    result=`dfx canister call $poolId mint "(record { token0 = \"$token0\"; token1 = \"$token1\"; fee = 3000: nat; tickLower = $1: int; tickUpper = $2: int; amount0Desired = \"$3\"; amount1Desired = \"$5\"; })"`
    info=`dfx canister call $poolId metadata`
    info=${info//"_"/""}
    if [[ "$info" =~ "$7" ]] && [[ "$info" =~ "$8" ]] && [[ "$info" =~ "$9" ]]; then
      echo "\033[32m mint success. \033[0m"
    else
      echo "\033[31m mint fail. $info \n expected $7 $8 $9 \033[0m"
    fi
    dfx canister call PositionIndex addPoolId "(\"$poolId\")"
}


function increase() #positionId amount0Desired amount0Min amount1Desired amount1Min ### liquidity tickCurrent sqrtRatioX96
{
    echo "=== increase... ==="
    result=`dfx canister call $poolId increaseLiquidity "(record { positionId = $1 :nat; amount0Desired = \"$2\"; amount1Desired = \"$4\"; })"`
    echo "increase result: $result"
    
    info=`dfx canister call $poolId metadata`
    info=${info//"_"/""}
    if [[ "$info" =~ "$6" ]] && [[ "$info" =~ "$7" ]] && [[ "$info" =~ "$8" ]]; then
      echo "\033[32m increase success. \033[0m"
    else
      echo "\033[31m increase fail. $info \n expected $6 $7 $8 \033[0m"
    fi
}

function decrease() #positionId liquidity amount0Min amount1Min ### liquidity tickCurrent sqrtRatioX96
{
    echo "=== decrease... ==="
    result=`dfx canister call $poolId getUserPosition "($1: nat)"`
    echo "user position result: $result"
    result=`dfx canister call $poolId decreaseLiquidity "(record { positionId = $1 :nat; liquidity = \"$2\"; })"`
    echo "decrease result: $result"

    sleep 10

    result=`dfx canister call $poolId getUserUnusedBalance "(principal \"$MINTER_PRINCIPAL\")"`
    echo "unused balance result: $result"

    withdrawAmount0=$(echo "$result" | sed -n 's/.*balance0 = \([0-9_]*\) : nat.*/\1/p' | sed 's/[^0-9]//g')
    withdrawAmount1=$(echo "$result" | sed -n 's/.*balance1 = \([0-9_]*\) : nat.*/\1/p' | sed 's/[^0-9]//g')
    echo "withdraw amount0: $withdrawAmount0"
    echo "withdraw amount1: $withdrawAmount1"

    if [ "$withdrawAmount0" -ne 0 ]; then
      result=`dfx canister call $poolId withdraw "(record {token = \"$token0\"; fee = $TRANS_FEE: nat; amount = $withdrawAmount0: nat;})"`
      echo "token0 withdraw result: $result"
    fi
    if [ "$withdrawAmount1" -ne 0 ]; then
      result=`dfx canister call $poolId withdraw "(record {token = \"$token1\"; fee = $TRANS_FEE: nat; amount = $withdrawAmount1: nat;})"`
      echo "token1 withdraw result: $result"
    fi

    info=`dfx canister call $poolId metadata`
    info=${info//"_"/""}
    if [[ "$info" =~ "$5" ]] && [[ "$info" =~ "$6" ]] && [[ "$info" =~ "$7" ]]; then
      echo "\033[32m decrease liquidity success. \033[0m"
    else
      echo "\033[31m decrease liquidity fail. $info \n expected $5 $6 $7 \033[0m"
    fi
    dfx canister call PositionIndex removePoolId "(\"$poolId\")"
}

function quote() #amountIn amountOutMinimum
{ 
    echo "=== quote... ==="
    result=`dfx canister call $poolId quote "(record { zeroForOne = true; amountIn = \"$1\"; amountOutMinimum = \"$2\"; })"`
    echo "quote result: $result"
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
    echo "swap result: $result"

    result=`dfx canister call $poolId getUserUnusedBalance "(principal \"$MINTER_PRINCIPAL\")"`
    echo "unused balance result: $result"

    withdrawAmount0=$(echo "$result" | sed -n 's/.*balance0 = \([0-9_]*\) : nat.*/\1/p' | sed 's/[^0-9]//g')
    withdrawAmount1=$(echo "$result" | sed -n 's/.*balance1 = \([0-9_]*\) : nat.*/\1/p' | sed 's/[^0-9]//g')
    echo "withdraw amount0: $withdrawAmount0"
    echo "withdraw amount1: $withdrawAmount1"

    result=`dfx canister call $poolId withdraw "(record {token = \"$token0\"; fee = $TRANS_FEE: nat; amount = $withdrawAmount0: nat;})"`
    echo "token0 withdraw result: $result"
    result=`dfx canister call $poolId withdraw "(record {token = \"$token1\"; fee = $TRANS_FEE: nat; amount = $withdrawAmount1: nat;})"`
    echo "token1 withdraw result: $result"
    
    token0BalanceResult="$(balanceOf $token0 $MINTER_PRINCIPAL null)"
    echo "token0 $MINTER_PRINCIPAL balance: $token0BalanceResult"
    token1BalanceResult="$(balanceOf $token1 $MINTER_PRINCIPAL null)"
    echo "token1 $MINTER_PRINCIPAL balance: $token1BalanceResult"
    info=`dfx canister call $poolId metadata`
    info=${info//"_"/""}
    token0BalanceResult=${token0BalanceResult//"_"/""}
    token1BalanceResult=${token1BalanceResult//"_"/""}
    if [[ "$info" =~ "$5" ]] && [[ "$info" =~ "$6" ]] && [[ "$info" =~ "$7" ]] && [[ "$token0BalanceResult" =~ "$8" ]] && [[ "$token1BalanceResult" =~ "$9" ]]; then
      echo "\033[32m swap success. \033[0m"
    else
      echo "\033[31m swap fail. $info \n expected $5 $6 $7 $8 $9\033[0m"
    fi
}

function oneStepSwap() #depositToken depositAmount amountIn amountOutMinimum ### liquidity tickCurrent sqrtRatioX96  token0BalanceAmount token1BalanceAmount zeroForOne
{
    echo "=== swap... ==="
    if [[ "$1" =~ "$token0" ]]; then
        result=`dfx canister call $poolId depositFromAndSwap "(record { zeroForOne = true; amountIn = \"$3\"; amountOutMinimum = \"$4\"; tokenInFee = $TRANS_FEE: nat; tokenOutFee = $TRANS_FEE: nat; })"`
    else
        result=`dfx canister call $poolId depositFromAndSwap "(record { zeroForOne = false; amountIn = \"$3\"; amountOutMinimum = \"$4\"; tokenInFee = $TRANS_FEE: nat; tokenOutFee = $TRANS_FEE: nat; })"`
    fi
    echo "swap result: $result"

    result=`dfx canister call $poolId getUserUnusedBalance "(principal \"$MINTER_PRINCIPAL\")"`
    echo "unused balance result: $result"

    withdrawAmount0=$(echo "$result" | sed -n 's/.*balance0 = \([0-9_]*\) : nat.*/\1/p' | sed 's/[^0-9]//g')
    withdrawAmount1=$(echo "$result" | sed -n 's/.*balance1 = \([0-9_]*\) : nat.*/\1/p' | sed 's/[^0-9]//g')
    echo "withdraw amount0: $withdrawAmount0"
    echo "withdraw amount1: $withdrawAmount1"

    result=`dfx canister call $poolId withdraw "(record {token = \"$token0\"; fee = $TRANS_FEE: nat; amount = $withdrawAmount0: nat;})"`
    echo "token0 withdraw result: $result"
    result=`dfx canister call $poolId withdraw "(record {token = \"$token1\"; fee = $TRANS_FEE: nat; amount = $withdrawAmount1: nat;})"`
    echo "token1 withdraw result: $result"
    
    token0BalanceResult="$(balanceOf $token0 $MINTER_PRINCIPAL null)"
    echo "token0 $MINTER_PRINCIPAL balance: $token0BalanceResult"
    token1BalanceResult="$(balanceOf $token1 $MINTER_PRINCIPAL null)"
    echo "token1 $MINTER_PRINCIPAL balance: $token1BalanceResult"
    info=`dfx canister call $poolId metadata`
    info=${info//"_"/""}
    token0BalanceResult=${token0BalanceResult//"_"/""}
    token1BalanceResult=${token1BalanceResult//"_"/""}
    if [[ "$info" =~ "$5" ]] && [[ "$info" =~ "$6" ]] && [[ "$info" =~ "$7" ]] && [[ "$token0BalanceResult" =~ "$8" ]] && [[ "$token1BalanceResult" =~ "$9" ]]; then
      echo "\033[32m swap success. \033[0m"
    else
      echo "\033[31m swap fail. $info \n expected $5 $6 $7 $8 $9\033[0m"
    fi
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

function income() #positionId tickLower tickUpper
{
    echo "=== refreshIncome... ==="
    result=`dfx canister call $poolId refreshIncome "($1: nat)"`
    echo "refreshIncome result: $result"
    result=`dfx canister call $poolId getUserPosition "($1: nat)"`
    result=`dfx canister call $poolId getPosition "(record {tickLower = $2: int; tickUpper = $3: int})"`
}

#----------------- test rollback ------------------------
allBalanceBefore=""
allBalanceAfter=""
positionsBefore=""
positionsAfter=""
ticksBefore=""
ticksAfter=""
userPositionsBefore=""
userPositionsAfter=""
metadataBefore=""
metadataAfter=""
tokenStateBefore=""
tokenStateAfter=""
recordBefore=""
recordAfter=""
function checkRollback() 
{
    if [ "$positionsBefore" = "$positionsAfter" ]; then
      echo "\033[32m positions are same. \033[0m"
    else
      echo "\033[31m positions are not same. \033[0m"
    fi

    if [ "$ticksBefore" = "$ticksAfter" ]; then
      echo "\033[32m ticks are same. \033[0m"
    else
      echo "\033[31m ticks are not same. \033[0m"
    fi

    if [ "$userPositionsBefore" = "$userPositionsAfter" ]; then
      echo "\033[32m user positions are same. \033[0m"
    else
      echo "\033[31m user positions are not same. \033[0m"
    fi

    if [ "$allBalanceBefore" = "$allBalanceAfter" ]; then
      echo "\033[32m user balance are same. \033[0m"
    else
      echo "\033[31m user balance are not same. \033[0m"
    fi

    if [ "$tokenStateBefore" = "$tokenStateAfter" ]; then
      echo "\033[32m token state are same. \033[0m"
    else
      echo "\033[31m token state are not same. \033[0m"
    fi

    if [ "$recordBefore" = "$recordAfter" ]; then
      echo "\033[32m record are same. \033[0m"
    else
      echo "\033[31m record are not same. \033[0m"
    fi

    echo $metadataBefore
    echo $metadataAfter
}
function recordBefore() 
{
    allBalanceBefore=`dfx canister call $poolId allTokenBalance "(0: nat, 100: nat)"`
    positionsBefore=`dfx canister call $poolId getPositions "(0: nat, 100: nat)"`
    ticksBefore=`dfx canister call $poolId getTicks "(0: nat, 100: nat)"`
    userPositionsBefore=`dfx canister call $poolId getUserPositions "(0: nat, 100: nat)"`
    metadataBefore=`dfx canister call $poolId metadata`
    tokenStateBefore=`dfx canister call $poolId getTokenAmountState`
    recordBefore=`dfx canister call $poolId getSwapRecordState`
}
function recordAfter() 
{
    allBalanceAfter=`dfx canister call $poolId allTokenBalance "(0: nat, 100: nat)"`
    positionsAfter=`dfx canister call $poolId getPositions "(0: nat, 100: nat)"`
    ticksAfter=`dfx canister call $poolId getTicks "(0: nat, 100: nat)"`
    userPositionsAfter=`dfx canister call $poolId getUserPositions "(0: nat, 100: nat)"`
    metadataAfter=`dfx canister call $poolId metadata`
    tokenStateAfter=`dfx canister call $poolId getTokenAmountState`
    recordAfter=`dfx canister call $poolId getSwapRecordState`
}
#----------------- test rollback ------------------------

#----------------- test withdraw mistransfer balance ------------------------
function withdraw_mistransfer()
{

    dfx canister call TrustedCanisterManager addCanister "(principal \"$(dfx canister id ICRC2)\")"
    result=`dfx canister call TrustedCanisterManager getCanisters`
    echo "getCanisters: $result"

    dfx canister call ICRC2 icrc1_transfer "(record {from_subaccount = null; to = record {owner = principal \"$poolId\"; subaccount = opt blob \"$subaccount\";}; amount = 100000000:nat; fee = opt $TRANS_FEE; memo = null; created_at_time = null;})"

    result=`dfx canister call $poolId withdrawMistransferBalance "(record {address = \"$(dfx canister id ICRC2)\"; standard = \"ICRC1\";})"`
    echo "withdrawMistransferBalance: $result"

    dfx canister call TrustedCanisterManager deleteCanister "(principal \"$(dfx canister id ICRC2)\")"
    result=`dfx canister call TrustedCanisterManager getCanisters`
    echo "getCanisters: $result"

    result=`dfx canister call SwapFactory getInitArgs`
    echo "SwapFactory getInitArgs: $result"
}
#----------------- test withdraw mistransfer balance ------------------------

#----------------- test factory passcode crud ------------------------
function test_factory_passcode()
{
    result=`dfx canister call SwapFactory addPasscode "(principal \"$(dfx identity get-principal)\", record { token0 = principal \"$token0\"; token1 = principal \"$token1\"; fee = 3000; })"`
    echo "SwapFactory addPasscode: $result"

    result=`dfx canister call SwapFactory getPrincipalPasscodes`
    echo "SwapFactory getPrincipalPasscodes: $result"
    
    result=`dfx canister call SwapFactory deletePasscode "(principal \"$(dfx identity get-principal)\", record { token0 = principal \"$token0\"; token1 = principal \"$token1\"; fee = 3000; })"`
    echo "SwapFactory deletePasscode: $result"
}
#----------------- test factory passcode crud ------------------------

function testMintSwap()
{   
    echo
    echo test mint process
    echo
    #sqrtPriceX96
    create_pool 274450166607934908532224538203

    echo "==> step 0 stop jobs"
    dfx canister call $poolId stopJobs "(vec {\"SyncTrxsJob\";})"

    # withdraw_mistransfer

    # test_factory_passcode

    echo
    echo "==> step 1 mint"
    deposit $token0 100000000000
    deposit $token1 1667302813453
    #tickLower tickUpper amount0Desired amount0Min amount1Desired amount1Min ### liquidity tickCurrent sqrtRatioX96
    mint -23040 46080 100000000000 92884678893 1667302813453 1573153132015 529634421680 24850 274450166607934908532224538203
    #token0BalanceAmount token1BalanceAmount
    checkBalance 999999900000000000 999998332697186547

    echo "==> step 2 swap"
    #depositToken depositAmount amountIn amountOutMinimum ### liquidity tickCurrent sqrtRatioX96 token0BalanceAmount token1BalanceAmount
    # swap $token0 100000000000 100000000000 658322113914 529634421680 14808 166123716848874888729218662825 999999800000000000 999999056851511853
    oneStepSwap $token0 100000000000 100000000000 658322113914 529634421680 14808 166123716848874888729218662825 999999800000000000 999999056851511853

    echo "==> step 3 swap"
    #depositToken depositAmount amountIn amountOutMinimum ### liquidity tickCurrent sqrtRatioX96 token0BalanceAmount token1BalanceAmount
    swap $token1 200300000000 200300000000 34999517311 529634421680 18116 195996761539654227777570705349 999999838499469043 999998856551511853

    echo "==> step 4 mint"
    deposit $token0 2340200000000
    deposit $token1 12026457043801
    #tickLower tickUpper amount0Desired amount0Min amount1Desired amount1Min ### liquidity tickCurrent sqrtRatioX96
    mint -16080 92220 2340200000000 2228546458622 12026457043801 11272984126445 6464892363717 18116 195996761539654227777570705349
    #token0BalanceAmount token1BalanceAmount
    checkBalance 999997498299469043 999986830094468052

    echo "==> step 5 swap"
    #depositToken depositAmount amountIn amountOutMinimum ### liquidity tickCurrent sqrtRatioX96 token0BalanceAmount token1BalanceAmount
    # swap $token1 900934100000000 900934100000000 2274000482681 0 887271 1461446703485210103287273052203988822378723970341 999999999699999993 999398897657090959
    oneStepSwap $token1 900934100000000 900934100000000 2274000482681 0 887271 1461446703485210103287273052203988822378723970341 999999999699999993 999398897657090959

    echo "==> step 6 swap"
    #depositToken depositAmount amountIn amountOutMinimum ### liquidity tickCurrent sqrtRatioX96 token0BalanceAmount token1BalanceAmount
    swap $token0 10000000000 10000000000 78411589305243 5935257942037 89098 6815937996742481301561907102830 999999989699999993 999485150405326727

    echo "==> step 7 mint"
    deposit $token0 109232300000000
    deposit $token1 988000352041693230
    #tickLower tickUpper amount0Desired amount0Min amount1Desired amount1Min ### liquidity tickCurrent sqrtRatioX96
    mint 45000 115140 109232300000000 102249810937012 988000352041693230 931015571568576453 12913790762040195 89098 6815937996742481301561907102830
    #token0BalanceAmount token1BalanceAmount
    checkBalance 999890757399999993 11484798363633497

    echo "==> step 8 swap"
    #depositToken depositAmount amountIn amountOutMinimum ### liquidity tickCurrent sqrtRatioX96 token0BalanceAmount token1BalanceAmount
    swap $token0 20000000000 20000000000 134142648626931 12913790762040195 89095 6815032711583577861813878240260 999890737399999993 11632355277123122

    echo "==> step 9 swap"
    #depositToken depositAmount amountIn amountOutMinimum ### liquidity tickCurrent sqrtRatioX96 token0BalanceAmount token1BalanceAmount
    # swap $token0 200203100000000 200203100000000 576342038450924726 12913790762040195 72181 2925487520681317622364346051650 999690534299999993 645608597573140321
    oneStepSwap $token0 200203100000000 200203100000000 576342038450924726 12913790762040195 72181 2925487520681317622364346051650 999690534299999993 645608597573140321

    echo "==> step 10 decrease"
    #positionId liquidity amount0Min amount1Min ###  liquidity tickCurrent sqrtRatioX96
    decrease 3 12907855504098158 292494852582912 329709405464581002 5935257942037 72181 2925487520681317622364346051650
    #token0BalanceAmount token1BalanceAmount
    checkBalance 999999897676227395 999776597617446358

    echo "==> step 11 decrease"
    #positionId liquidity amount0Min amount1Min ###  liquidity tickCurrent sqrtRatioX96
    decrease 2 5935257942037 94237330101 205255638225991 0 72181 2925487520681317622364346051650
    #token0BalanceAmount token1BalanceAmount
    checkBalance 999999999699999990 999994851527904526

    echo "==> step 12 swap"
    #depositToken depositAmount amountIn amountOutMinimum ### liquidity tickCurrent sqrtRatioX96 token0BalanceAmount token1BalanceAmount
    swap $token0 200000000000 200000000000 381035193378 529634421680 14832 166321252212714690643584399335 999999799699999990 999999042915031684

    echo "==> step 14 mint"
    deposit $token0 1000200000000
    deposit $token1 0
    #tickLower tickUpper amount0Desired amount0Min amount1Desired amount1Min ### liquidity tickCurrent sqrtRatioX96
    mint 52980 92100 1000200000000 1000200000000 0 0 529634421680 14832 166321252212714690643584399335
    #token0BalanceAmount token1BalanceAmount
    checkBalance 999998799499999990 999999042915031684

    echo "==> step 15 swap"
    #depositToken depositAmount amountIn amountOutMinimum ### liquidity tickCurrent sqrtRatioX96 token0BalanceAmount token1BalanceAmount
    # swap $token1 4924352000000 4924352000000 184529093407 16470362268400 53041 1123584027070855708721216766866 999999002482002738 999994118563031684
    oneStepSwap $token1 4924352000000 4924352000000 184529093407 16470362268400 53041 1123584027070855708721216766866 999999002482002738 999994118563031684 

    echo "==> step 16 mint"
    deposit $token0 2049400000000
    deposit $token1 0
    #tickLower tickUpper amount0Desired amount0Min amount1Desired amount1Min ### liquidity tickCurrent sqrtRatioX96
    mint 99060 104340 2049400000000 2049400000000 0 0 16470362268400 53041 1123584027070855708721216766866
    #token0BalanceAmount token1BalanceAmount
    checkBalance 999996953082002738 999994118563031684

    echo "==> step 17 swap"
    #depositToken depositAmount amountIn amountOutMinimum ### liquidity tickCurrent sqrtRatioX96 token0BalanceAmount token1BalanceAmount
    swap $token1 1485050200000000 1485050200000000 909090550569 1250435266521266 99067 11220156202796378238345461253400 999997953081608364 998509068363031684

    echo "==> step 18 swap"
    #depositToken depositAmount amountIn amountOutMinimum ### liquidity tickCurrent sqrtRatioX96 token0BalanceAmount token1BalanceAmount
    swap $token0 1011995000000 1011995000000 1347093299165243 529634421680 44143 720104365939390610499544462530 999996941086608364 999990870992113452

    echo "==> step 19 decrease"
    #positionId liquidity amount0Min amount1Min ###  liquidity tickCurrent sqrtRatioX96
    decrease 1 132408605420 666394000 1099859408249 397225816260 44143 720104365939390610499544462530
    #token0BalanceAmount token1BalanceAmount
    checkBalance 999996943347140782 999992057837146576

    echo "==> step 20 swap"
    #depositToken depositAmount amountIn amountOutMinimum ### liquidity tickCurrent sqrtRatioX96 token0BalanceAmount token1BalanceAmount
    swap $token0 29300000000 29300000000 1314921229992 397225816260 33905 431611857389378483182039517039 999996914047140782 999993504250499568

    echo "==> step 21 increase"
    deposit $token0 20300000000
    deposit $token1 1244701317746
    #positionId amount0Desired amount0Min amount1Desired amount1Min ### liquidity tickCurrent sqrtRatioX96
    increase 1 20300000000 18227981755 1244701317746 1176893828604 639777973999 33905 431611857389378483182039517039
    #token0BalanceAmount token1BalanceAmount
    checkBalance 999996893747140782 999992259549181822

    echo "==> step 22 swap"
    dfx canister call $dipAId approve "(principal \"$poolId\", $TOTAL_SUPPLY)"
    dfx canister call $dipBId approve "(principal \"$poolId\", $TOTAL_SUPPLY)"
    #depositToken depositAmount amountIn amountOutMinimum ### liquidity tickCurrent sqrtRatioX96 token0BalanceAmount token1BalanceAmount
    swap $token1 515977001200000000 515977001200000000 282104104996 0 887271 1461446703485210103287273052203988822378723970341 999999996892295739 944931945772461540

    echo "==> step 23 swap"
    #depositToken depositAmount amountIn amountOutMinimum ### liquidity tickCurrent sqrtRatioX96 token0BalanceAmount token1BalanceAmount
    swap $token0 1000000000 1000000000 30792199830315 1250435266521266 104337 14602149588923138925101933711806 999999995892295739 944965817192274887

    echo "==> step 24 swap"
    #depositToken depositAmount amountIn amountOutMinimum ### liquidity tickCurrent sqrtRatioX96 token0BalanceAmount token1BalanceAmount
    swap $token1 33969900000000 33969900000000 906271879 1250435266521266 104339 14604295480606908301311147523433 999999996889194806 944931847292274887

    echo "==> step 25 swap"
    #depositToken depositAmount amountIn amountOutMinimum ### liquidity tickCurrent sqrtRatioX96 token0BalanceAmount token1BalanceAmount
    swap $token1 3435320000 3435320000 91635 1250435266521266 104339 14604295697617397560526319750504 999999996889295605 944931843856954887

};

testMintSwap

dfx stop
mv dfx.json.bak dfx.json