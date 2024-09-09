#!/bin/bash
# set -e
# clear
dfx stop
rm -rf .dfx
mv dfx.json dfx.json.bak
cat > dfx.json <<- EOF
{
  "canisters": {
    "SwapFeeReceiver": {
      "main": "./src/SwapFeeReceiver.mo",
      "type": "motoko"
    },
    "SwapFactory": {
      "main": "./src/SwapFactory.mo",
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
TOTAL_SUPPLY="1000000000000000000"
# TRANS_FEE="100000000";
TRANS_FEE="0";
MINTER_PRINCIPAL="$(dfx identity get-principal)"

dfx start --clean --background
echo "-=========== create all"
dfx canister create --all
echo "-=========== build all"
dfx build
echo
echo "==> Install canisters"
echo
echo "==> install ICRC2"
dfx canister install ICRC2 --argument="( record {name = \"ICRC2\"; symbol = \"ICRC2\"; decimals = 8; fee = 0; max_supply = 1_000_000_000_000; initial_balances = vec {record {record {owner = principal \"$MINTER_PRINCIPAL\";subaccount = null;};100_000_000}};min_burn_amount = 10_000;minting_account = null;advanced_settings = null; })"
echo "==>install DIP20"
dfx canister install DIP20A --argument="(\"DIPA Logo\", \"DIPA\", \"DIPA\", 8, $TOTAL_SUPPLY, principal \"$MINTER_PRINCIPAL\", $TRANS_FEE)"
dfx canister install DIP20B --argument="(\"DIPB Logo\", \"DIPB\", \"DIPB\", 8, $TOTAL_SUPPLY, principal \"$MINTER_PRINCIPAL\", $TRANS_FEE)"

echo "==> install SwapFeeReceiver"
dfx canister install SwapFeeReceiver
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
echo "==> install SwapFactory"
dfx canister install SwapFactory --argument="(principal \"$(dfx canister id base_index)\", principal \"$(dfx canister id SwapFeeReceiver)\", principal \"$(dfx canister id PasscodeManager)\", principal \"$(dfx canister id TrustedCanisterManager)\", null)"
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
    echo "=== create pool...  ==="
    dfx canister call ICRC2 icrc2_approve "(record{amount=1000000000000;created_at_time=null;expected_allowance=null;expires_at=null;fee=null;from_subaccount=null;memo=null;spender=record {owner= principal \"$(dfx canister id PasscodeManager)\";subaccount=null;}})"
    dfx canister call PasscodeManager depositFrom "(record {amount=100000000;fee=0;})"
    dfx canister call PasscodeManager requestPasscode "(principal \"$token0\", principal \"$token1\", 3000)"
    
    result=`dfx canister call SwapFactory createPool "(record {token0 = record {address = \"$token0\"; standard = \"DIP20\";}; token1 = record {address = \"$token1\"; standard = \"DIP20\";}; fee = 3000; sqrtPriceX96 = \"$1\"})"`
    if [[ ! "$result" =~ " ok = record " ]]; then
        echo "\033[31mcreate pool fail. $result - \033[0m"
    fi
    echo "create_pool result: $result"
    poolId=`echo $result | awk -F"canisterId = principal \"" '{print $2}' | awk -F"\";" '{print $1}'`
    dfx canister call $dipAId approve "(principal \"$poolId\", $TOTAL_SUPPLY)"
    dfx canister call $dipBId approve "(principal \"$poolId\", $TOTAL_SUPPLY)"
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

function depost() # token tokenAmount
{
    echo "=== pool deposit...  ==="
    dfx canister call $poolId depositFrom "(record {token = \"$1\"; amount = $2: nat; fee = $TRANS_FEE: nat; })"
    echo "\033[32m deposit $1 success. \033[0m"
}

function mint(){ # tickLower tickUpper amount0Desired amount0Min amount1Desired amount1Min ### liquidity tickCurrent sqrtRatioX96
    echo "=== mint... ==="
    dfx canister call $poolId mint "(record { token0 = \"$token0\"; token1 = \"$token1\"; fee = 3000: nat; tickLower = $1: int; tickUpper = $2: int; amount0Desired = \"$3\"; amount1Desired = \"$5\"; })"
    echo "\033[32m mint success. \033[0m"
    dfx canister call PositionIndex addPoolId "(\"$poolId\")"
}

function increase() #positionId amount0Desired amount0Min amount1Desired amount1Min ### liquidity tickCurrent sqrtRatioX96
{
    echo "=== increase... ==="
    dfx canister call $poolId increaseLiquidity "(record { positionId = $1 :nat; amount0Desired = \"$2\"; amount1Desired = \"$4\"; })"
    echo "\033[32m increase success. \033[0m"
}

function decrease() #positionId liquidity amount0Min amount1Min ### liquidity tickCurrent sqrtRatioX96
{
    echo "=== decrease... ==="
    result=`dfx canister call $poolId getUserPosition "($1: nat)"`
    result=`dfx canister call $poolId decreaseLiquidity "(record { positionId = $1 :nat; liquidity = \"$2\"; })"`
    echo "decrease result: $result"

    withdrawAll

    echo "\033[32m decrease liquidity success. \033[0m"
    dfx canister call PositionIndex removePoolId "(\"$poolId\")"
}

function quote() #amountIn amountOutMinimum
{ 
    echo "=== quote... ==="
    result=`dfx canister call $poolId quote "(record { zeroForOne = true; amountIn = \"$1\"; amountOutMinimum = \"$2\"; })"`
    echo "quote result: $result"
}

function swap() #depostToken depostAmount amountIn amountOutMinimum ### liquidity tickCurrent sqrtRatioX96  token0BalanceAmount token1BalanceAmount zeroForOne
{
    echo "=== swap... ==="
    depost $1 $2    
    if [[ "$1" =~ "$token0" ]]; then
        result=`dfx canister call $poolId swap "(record { zeroForOne = true; amountIn = \"$3\"; amountOutMinimum = \"$4\"; })"`
    else
        result=`dfx canister call $poolId swap "(record { zeroForOne = false; amountIn = \"$3\"; amountOutMinimum = \"$4\"; })"`
    fi
    echo "swap result: $result"
    echo "\033[32m swap success. \033[0m"
}

function withdrawToken0()
{
    result=`dfx canister call $poolId withdraw "(record {token = \"$token0\"; fee = $TRANS_FEE: nat; amount = $1: nat;})"`
    echo "token0 withdraw result: $result"

    echo "\033[32m withdraw token0 success. \033[0m"
}

function withdrawToken1()
{
    result=`dfx canister call $poolId withdraw "(record {token = \"$token1\"; fee = $TRANS_FEE: nat; amount = $1: nat;})"`
    echo "token1 withdraw result: $result"

    echo "\033[32m withdraw success. \033[0m"
}

function withdrawAll()
{
    result=`dfx canister call $poolId getUserUnusedBalance "(principal \"$MINTER_PRINCIPAL\")"`
    echo "user unused balance result: $result"

    withdrawAmount0=${result#*=}
    withdrawAmount0=${withdrawAmount0#*=}
    withdrawAmount0=${withdrawAmount0%:*}
    withdrawAmount0=${withdrawAmount0//" "/""}
    # echo "withdraw amount0: $withdrawAmount0"

    withdrawAmount1=${result##*=}
    withdrawAmount1=${withdrawAmount1%:*}
    withdrawAmount1=${withdrawAmount1//" "/""}
    # echo "withdraw amount1: $withdrawAmount1"


      result=`dfx canister call $poolId withdraw "(record {token = \"$token0\"; fee = $TRANS_FEE: nat; amount = $withdrawAmount0: nat;})"`
      echo "token0 withdraw result: $result"

      result=`dfx canister call $poolId withdraw "(record {token = \"$token1\"; fee = $TRANS_FEE: nat; amount = $withdrawAmount1: nat;})"`
      echo "token1 withdraw result: $result"

    echo "\033[32m withdraw success. \033[0m"
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

function lockUserPositionForOneMinute() #positionId
{
    echo "=== lock user position... ==="
    current_timestamp=$(date +%s)
    one_minutes_seconds=$((60 * 1))
    one_minutes_later_nanoseconds_timestamp=$(((current_timestamp + one_minutes_seconds) * 1000000000))

    result=`dfx canister call $poolId lockUserPosition "(record {positionId = $1: nat; expirationTime = $one_minutes_later_nanoseconds_timestamp: nat})"`
    echo "lockUserPosition result: $result"
}

function test_limit_order()
{   
    echo
    echo test limit order process
    echo
    #sqrtPriceX96
    create_pool 274450166607934908532224538203

    echo "current tick is: 24850"

    echo
    echo "==> step 1 mint"
    depost $token0 100000000000
    depost $token1 1667302813453
    #tickLower tickUpper amount0Desired amount0Min amount1Desired amount1Min ### liquidity tickCurrent sqrtRatioX96
    mint -23040 46080 100000000000 92884678893 1667302813453 1573153132015 529634421680 24850 274450166607934908532224538203

    echo "==> add invalid limit order 1"
    dfx canister call $poolId addLimitOrder "(record { positionId = 1 :nat; tickLimit = 36080 :int; })"

    lockUserPositionForOneMinute 1
    decrease 1 529634421680 292494852582912 329709405464581002 5935257942037 72181 2925487520681317622364346051650

    echo
    echo "==> step 2 mint"
    depost $token0 100000000000
    depost $token1 1667302813453
    #tickLower tickUpper amount0Desired amount0Min amount1Desired amount1Min ### liquidity tickCurrent sqrtRatioX96
    mint 24900 36060 100000000000 92884678893 1667302813453 1573153132015 529634421680 24850 274450166607934908532224538203

    echo "==> add upper limit order 2"
    dfx canister call $poolId addLimitOrder "(record { positionId = 2 :nat; tickLimit = 36060 :int; })"

    echo
    echo "==> step 3 mint"
    depost $token0 100000000000
    depost $token1 1667302813453
    #tickLower tickUpper amount0Desired amount0Min amount1Desired amount1Min ### liquidity tickCurrent sqrtRatioX96
    mint -23040 0 100000000000 92884678893 1667302813453 1573153132015 529634421680 24850 274450166607934908532224538203
    
    echo "==> add lower limit order 3"
    dfx canister call $poolId addLimitOrder "(record { positionId = 3 :nat; tickLimit = -23040 :int; })"

    withdrawAll

    # sleep 20

    echo "==> step 4 swap"
    #depostToken depostAmount amountIn amountOutMinimum ### liquidity tickCurrent sqrtRatioX96 token0BalanceAmount token1BalanceAmount
    swap $token0 500000000000 500000000000 0 529634421680 14808 166123716848874888729218662825 999999800000000000 999999056851511853

    echo "current tick is: -805"

    withdrawToken1 1422005536592

    # sleep 20

    withdrawAll

    echo "==> step 5 swap"
    #depostToken depostAmount amountIn amountOutMinimum ### liquidity tickCurrent sqrtRatioX96 token0BalanceAmount token1BalanceAmount
    swap $token1 5000000000000 5000000000000 0 529634421680 18116 195996761539654227777570705349 999999838499469043 999998856551511853

    echo "current tick is: 36535"
    
    withdrawToken0 666150050320

    # sleep 20

    withdrawAll
    
    echo "==> step 6 decrease"
    #positionId liquidity amount0Min amount1Min ###  liquidity tickCurrent sqrtRatioX96
    decrease 1 529634421680 292494852582912 329709405464581002 5935257942037 72181 2925487520681317622364346051650

};

test_limit_order

dfx stop
mv dfx.json.bak dfx.json