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
TRANS_FEE="0";
MINTER_PRINCIPAL="$(dfx identity get-principal)"
MINTER_WALLET="$(dfx identity get-wallet)"

# ========================= Install Canisters =========================
section_header "Installing Canisters"

echo "  Installing ICRC2..."
dfx canister install ICRC2 --argument="( record {name = \"ICRC2\"; symbol = \"ICRC2\"; decimals = 8; fee = 0; max_supply = 1_000_000_000_000; initial_balances = vec {record {record {owner = principal \"$MINTER_PRINCIPAL\";subaccount = null;};100_000_000}};min_burn_amount = 10_000;minting_account = null;advanced_settings = null; })"
echo "  Installing DIP20A & DIP20B..."
dfx canister install DIP20A --argument="(\"DIPA Logo\", \"DIPA\", \"DIPA\", 8, $TOTAL_SUPPLY, principal \"$MINTER_PRINCIPAL\", $TRANS_FEE)"
dfx canister install DIP20B --argument="(\"DIPB Logo\", \"DIPB\", \"DIPB\", 8, $TOTAL_SUPPLY, principal \"$MINTER_PRINCIPAL\", $TRANS_FEE)"
echo "  Installing SwapFeeReceiver..."
dfx canister install SwapFeeReceiver --argument="(principal \"$(dfx canister id SwapFactory)\", record {address=\"$(dfx canister id ICRC2)\"; standard=\"ICRC2\"}, record {address=\"$(dfx canister id ICRC2)\"; standard=\"ICRC2\"}, principal \"$MINTER_PRINCIPAL\")"
echo "  Installing TrustedCanisterManager..."
dfx canister install TrustedCanisterManager --argument="(null)"
echo "  Installing Test..."
dfx canister install Test
echo "  Installing SwapDataBackup..."
dfx canister install SwapDataBackup --argument="(principal \"$(dfx canister id SwapFactory)\", null)"
echo "  Installing SwapFactory..."
dfx canister install SwapFactory --argument="(principal \"$(dfx canister id SwapFeeReceiver)\", principal \"$(dfx canister id PasscodeManager)\", principal \"$(dfx canister id TrustedCanisterManager)\", principal \"$(dfx canister id SwapDataBackup)\", opt principal \"$MINTER_PRINCIPAL\", principal \"$(dfx canister id PositionIndex)\")"
echo "  Installing PositionIndex..."
dfx canister install PositionIndex --argument="(principal \"$(dfx canister id SwapFactory)\")"
dfx canister install PasscodeManager --argument="(principal \"$(dfx canister id ICRC2)\", 100000000, principal \"$(dfx canister id SwapFactory)\", principal \"$MINTER_PRINCIPAL\")"

dipAId=`dfx canister id DIP20A`
dipBId=`dfx canister id DIP20B`
testId=`dfx canister id Test`
swapFactoryId=`dfx canister id SwapFactory`
positionIndexId=`dfx canister id PositionIndex`
swapFeeReceiverId=`dfx canister id SwapFeeReceiver`
zeroForOne="true"

# ========================= Setup SwapPoolInstaller =========================
section_header "Setting up SwapPoolInstaller"

dfx deploy SwapPoolInstaller --argument="(principal \"$(dfx canister id SwapFactory)\", principal \"$(dfx canister id SwapFactory)\", principal \"$(dfx canister id PositionIndex)\")"
dfx canister update-settings SwapPoolInstaller --add-controller "$swapFactoryId"
dfx canister update-settings SwapPoolInstaller --remove-controller "$MINTER_WALLET"
MODULE_HASH=$(dfx canister call SwapPoolInstaller getStatus | sed -n 's/.*moduleHash = opt blob "\(.*\)".*/\1/p')
dfx canister call SwapFactory setInstallerModuleHash "(blob \"$MODULE_HASH\")"
dfx canister call SwapFactory getInstallerModuleHash
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

if [[ "$dipAId" < "$dipBId" ]]; then
    token0="$dipAId"
    token1="$dipBId"
else
    token0="$dipBId"
    token1="$dipAId"
fi
echo ""
echo "  token0: $token0"
echo "  token1: $token1"

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

function create_pool()
{
    section_header "Creating Pool (sqrtPriceX96=$1)"
    dfx canister call ICRC2 icrc2_approve "(record{amount=1000000000000;created_at_time=null;expected_allowance=null;expires_at=null;fee=null;from_subaccount=null;memo=null;spender=record {owner= principal \"$(dfx canister id PasscodeManager)\";subaccount=null;}})"
    dfx canister call PasscodeManager depositFrom "(record {amount=100000000;fee=0;})"
    dfx canister call PasscodeManager requestPasscode "(principal \"$token0\", principal \"$token1\", 3000)"

    result=`dfx canister call SwapFactory createPool "(record {subnet = opt \"mainnet\"; token0 = record {address = \"$token0\"; standard = \"DIP20\";}; token1 = record {address = \"$token1\"; standard = \"DIP20\";}; fee = 3000; sqrtPriceX96 = \"$1\"})"`
    if [[ ! "$result" =~ " ok = record " ]]; then
        fail "create_pool: $result"
        return
    fi
    poolId=`echo $result | awk -F"canisterId = principal \"" '{print $2}' | awk -F"\";" '{print $1}'`
    dfx canister call $dipAId approve "(principal \"$poolId\", $TOTAL_SUPPLY)"
    dfx canister call $dipBId approve "(principal \"$poolId\", $TOTAL_SUPPLY)"
    dfx canister call PositionIndex updatePoolIds
    dfx canister call PasscodeManager transferValidate "(principal \"$poolId\", 100000000)"
    dfx canister call PasscodeManager transfer "(principal \"$poolId\", 100000000)"
    echo "  Pool created: $poolId"
}

function deposit()
{
    result=`dfx canister call $poolId depositFrom "(record {token = \"$1\"; amount = $2: nat; fee = $TRANS_FEE: nat; })"`
    result=${result//"_"/""}
    if [[ "$result" =~ "$2" ]]; then
        echo "  deposit $1 ok ($2)"
    else
        echo "\033[31m  deposit $1 FAILED: $result \033[0m"
    fi
}

function mint()
{
    deposit $token0 $3
    deposit $token1 $5
    result=`dfx canister call $poolId mint "(record { token0 = \"$token0\"; token1 = \"$token1\"; fee = 3000: nat; tickLower = $1: int; tickUpper = $2: int; amount0Desired = \"$3\"; amount1Desired = \"$5\"; })"`
    info=`dfx canister call $poolId metadata`
    info=${info//"_"/""}
    if [[ "$info" =~ "$7" ]] && [[ "$info" =~ "$8" ]] && [[ "$info" =~ "$9" ]]; then
        pass "mint (liquidity=$7, tick=$8)"
    else
        fail "mint: expected liquidity=$7 tick=$8 sqrtPrice=$9, got: $info"
    fi
    dfx canister call PositionIndex addPoolId "(\"$poolId\")"
}

function increase()
{
    deposit $token0 $2
    deposit $token1 $4
    result=`dfx canister call $poolId increaseLiquidity "(record { positionId = $1 :nat; amount0Desired = \"$2\"; amount1Desired = \"$4\"; })"`
    info=`dfx canister call $poolId metadata`
    info=${info//"_"/""}
    if [[ "$info" =~ "$6" ]] && [[ "$info" =~ "$7" ]] && [[ "$info" =~ "$8" ]]; then
        pass "increase (positionId=$1, liquidity=$6)"
    else
        fail "increase: expected liquidity=$6 tick=$7 sqrtPrice=$8, got: $info"
    fi
}

function decrease()
{
    result=`dfx canister call $poolId decreaseLiquidity "(record { positionId = $1 :nat; liquidity = \"$2\"; })"`

    sleep 10

    result=`dfx canister call $poolId getUserUnusedBalance "(principal \"$MINTER_PRINCIPAL\")"`
    withdrawAmount0=$(echo "$result" | sed -n 's/.*balance0 = \([0-9_]*\) : nat.*/\1/p' | sed 's/[^0-9]//g')
    withdrawAmount1=$(echo "$result" | sed -n 's/.*balance1 = \([0-9_]*\) : nat.*/\1/p' | sed 's/[^0-9]//g')

    if [ "$withdrawAmount0" -ne 0 ]; then
        dfx canister call $poolId withdraw "(record {token = \"$token0\"; fee = $TRANS_FEE: nat; amount = $withdrawAmount0: nat;})" > /dev/null 2>&1
    fi
    if [ "$withdrawAmount1" -ne 0 ]; then
        dfx canister call $poolId withdraw "(record {token = \"$token1\"; fee = $TRANS_FEE: nat; amount = $withdrawAmount1: nat;})" > /dev/null 2>&1
    fi

    sleep 2

    info=`dfx canister call $poolId metadata`
    info=${info//"_"/""}
    if [[ "$info" =~ "$5" ]] && [[ "$info" =~ "$6" ]] && [[ "$info" =~ "$7" ]]; then
        pass "decrease (positionId=$1, liquidity=$5)"
    else
        fail "decrease: expected liquidity=$5 tick=$6 sqrtPrice=$7, got: $info"
    fi
    dfx canister call PositionIndex removePoolId "(\"$poolId\")"
}

function swap()
{
    deposit $1 $2
    if [[ "$1" =~ "$token0" ]]; then
        result=`dfx canister call $poolId swap "(record { zeroForOne = true; amountIn = \"$3\"; amountOutMinimum = \"$4\"; })"`
    else
        result=`dfx canister call $poolId swap "(record { zeroForOne = false; amountIn = \"$3\"; amountOutMinimum = \"$4\"; })"`
    fi

    result=`dfx canister call $poolId getUserUnusedBalance "(principal \"$MINTER_PRINCIPAL\")"`
    withdrawAmount0=$(echo "$result" | sed -n 's/.*balance0 = \([0-9_]*\) : nat.*/\1/p' | sed 's/[^0-9]//g')
    withdrawAmount1=$(echo "$result" | sed -n 's/.*balance1 = \([0-9_]*\) : nat.*/\1/p' | sed 's/[^0-9]//g')

    dfx canister call $poolId withdraw "(record {token = \"$token0\"; fee = $TRANS_FEE: nat; amount = $withdrawAmount0: nat;})" > /dev/null 2>&1
    dfx canister call $poolId withdraw "(record {token = \"$token1\"; fee = $TRANS_FEE: nat; amount = $withdrawAmount1: nat;})" > /dev/null 2>&1

    sleep 2

    token0BalanceResult="$(balanceOf $token0 $MINTER_PRINCIPAL null)"
    token1BalanceResult="$(balanceOf $token1 $MINTER_PRINCIPAL null)"
    info=`dfx canister call $poolId metadata`
    info=${info//"_"/""}
    token0BalanceResult=${token0BalanceResult//"_"/""}
    token1BalanceResult=${token1BalanceResult//"_"/""}
    if [[ "$info" =~ "$5" ]] && [[ "$info" =~ "$6" ]] && [[ "$info" =~ "$7" ]] && [[ "$token0BalanceResult" =~ "$8" ]] && [[ "$token1BalanceResult" =~ "$9" ]]; then
        pass "swap (amountIn=$3, liquidity=$5, tick=$6)"
    else
        fail "swap: expected liquidity=$5 tick=$6 bal0=$8 bal1=$9"
    fi
}

function oneStepSwap()
{
    if [[ "$1" =~ "$token0" ]]; then
        result=`dfx canister call $poolId depositFromAndSwap "(record { zeroForOne = true; amountIn = \"$3\"; amountOutMinimum = \"$4\"; tokenInFee = $TRANS_FEE: nat; tokenOutFee = $TRANS_FEE: nat; })"`
    else
        result=`dfx canister call $poolId depositFromAndSwap "(record { zeroForOne = false; amountIn = \"$3\"; amountOutMinimum = \"$4\"; tokenInFee = $TRANS_FEE: nat; tokenOutFee = $TRANS_FEE: nat; })"`
    fi

    result=`dfx canister call $poolId getUserUnusedBalance "(principal \"$MINTER_PRINCIPAL\")"`
    withdrawAmount0=$(echo "$result" | sed -n 's/.*balance0 = \([0-9_]*\) : nat.*/\1/p' | sed 's/[^0-9]//g')
    withdrawAmount1=$(echo "$result" | sed -n 's/.*balance1 = \([0-9_]*\) : nat.*/\1/p' | sed 's/[^0-9]//g')

    dfx canister call $poolId withdraw "(record {token = \"$token0\"; fee = $TRANS_FEE: nat; amount = $withdrawAmount0: nat;})" > /dev/null 2>&1
    dfx canister call $poolId withdraw "(record {token = \"$token1\"; fee = $TRANS_FEE: nat; amount = $withdrawAmount1: nat;})" > /dev/null 2>&1

    sleep 2

    token0BalanceResult="$(balanceOf $token0 $MINTER_PRINCIPAL null)"
    token1BalanceResult="$(balanceOf $token1 $MINTER_PRINCIPAL null)"
    info=`dfx canister call $poolId metadata`
    info=${info//"_"/""}
    token0BalanceResult=${token0BalanceResult//"_"/""}
    token1BalanceResult=${token1BalanceResult//"_"/""}
    if [[ "$info" =~ "$5" ]] && [[ "$info" =~ "$6" ]] && [[ "$info" =~ "$7" ]] && [[ "$token0BalanceResult" =~ "$8" ]] && [[ "$token1BalanceResult" =~ "$9" ]]; then
        pass "oneStepSwap (amountIn=$3, liquidity=$5, tick=$6)"
    else
        fail "oneStepSwap: expected liquidity=$5 tick=$6 bal0=$8 bal1=$9"
    fi
}

function checkBalance()
{
    sleep 2
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

# ========================= Test Cases =========================

function testMintSwap()
{
    create_pool 274450166607934908532224538203

    step_header 0 "Stop sync jobs"
    dfx canister call $poolId stopJobs "(vec {\"SyncTrxsJob\";})"

    step_header 1 "Mint initial position"
    mint -23040 46080 100000000000 92884678893 1667302813453 1573153132015 529634421680 24850 274450166607934908532224538203
    checkBalance 999999900000000000 999998332697186547

    step_header 2 "OneStepSwap (token0 -> token1)"
    oneStepSwap $token0 100000000000 100000000000 658322113914 529634421680 14808 166123716848874888729218662825 999999800000000000 999999056851511853

    step_header 3 "Swap (token1 -> token0)"
    swap $token1 200300000000 200300000000 34999517311 529634421680 18116 195996761539654227777570705349 999999838499469043 999998856551511853

    step_header 4 "Mint second position"
    mint -16080 92220 2340200000000 2228546458622 12026457043801 11272984126445 6464892363717 18116 195996761539654227777570705349
    checkBalance 999997498299469043 999986830094468052

    step_header 5 "OneStepSwap large (token1 -> token0)"
    oneStepSwap $token1 900934100000000 900934100000000 2274000482681 0 887271 1461446703485210103287273052203988822378723970341 999999999699999993 999398897657090959

    step_header 6 "Swap (token0 -> token1)"
    swap $token0 10000000000 10000000000 78411589305243 5935257942037 89098 6815937996742481301561907102830 999999989699999993 999485150405326727

    step_header 7 "Mint third position"
    mint 45000 115140 109232300000000 102249810937012 988000352041693230 931015571568576453 12913790762040195 89098 6815937996742481301561907102830
    checkBalance 999890757399999993 11484798363633497

    step_header 8 "Swap (token0 -> token1)"
    swap $token0 20000000000 20000000000 134142648626931 12913790762040195 89095 6815032711583577861813878240260 999890737399999993 11632355277123122

    step_header 9 "OneStepSwap large (token0 -> token1)"
    oneStepSwap $token0 200203100000000 200203100000000 576342038450924726 12913790762040195 72181 2925487520681317622364346051650 999690534299999993 645608597573140321

    step_header 10 "Decrease position 3"
    decrease 3 12907855504098158 292494852582912 329709405464581002 5935257942037 72181 2925487520681317622364346051650
    checkBalance 999999897676227395 999776597617446358

    step_header 11 "Decrease position 2"
    decrease 2 5935257942037 94237330101 205255638225991 0 72181 2925487520681317622364346051650
    checkBalance 999999999699999990 999994851527904526

    step_header 12 "Swap (token0 -> token1)"
    swap $token0 200000000000 200000000000 381035193378 529634421680 14832 166321252212714690643584399335 999999799699999990 999999042915031684

    step_header 14 "Mint position (token0 only, out of range)"
    mint 52980 92100 1000200000000 1000200000000 0 0 529634421680 14832 166321252212714690643584399335
    checkBalance 999998799499999990 999999042915031684

    step_header 15 "OneStepSwap (token1 -> token0)"
    oneStepSwap $token1 4924352000000 4924352000000 184529093407 16470362268400 53041 1123584027070855708721216766866 999999002482002738 999994118563031684

    step_header 16 "Mint position (token0 only, out of range)"
    mint 99060 104340 2049400000000 2049400000000 0 0 16470362268400 53041 1123584027070855708721216766866
    checkBalance 999996953082002738 999994118563031684

    step_header 17 "Swap large (token1 -> token0)"
    swap $token1 1485050200000000 1485050200000000 909090550569 1250435266521266 99067 11220156202796378238345461253400 999997953081608364 998509068363031684

    step_header 18 "Swap (token0 -> token1)"
    swap $token0 1011995000000 1011995000000 1347093299165243 529634421680 44143 720104365939390610499544462530 999996941086608364 999990870992113452

    step_header 19 "Decrease position 1"
    decrease 1 132408605420 666394000 1099859408249 397225816260 44143 720104365939390610499544462530
    checkBalance 999996943347140782 999992057837146576

    step_header 20 "Swap (token0 -> token1)"
    swap $token0 29300000000 29300000000 1314921229992 397225816260 33905 431611857389378483182039517039 999996914047140782 999993504250499568

    step_header 21 "Increase position 1"
    increase 1 20300000000 18227981755 1244701317746 1176893828604 639777973999 33905 431611857389378483182039517039
    checkBalance 999996893747140782 999992259549181822

    step_header 22 "Swap massive (token1 -> token0)"
    dfx canister call $dipAId approve "(principal \"$poolId\", $TOTAL_SUPPLY)"
    dfx canister call $dipBId approve "(principal \"$poolId\", $TOTAL_SUPPLY)"
    swap $token1 515977001200000000 515977001200000000 282104104996 0 887271 1461446703485210103287273052203988822378723970341 999999996892295739 944931945772461540

    step_header 23 "Swap (token0 -> token1)"
    swap $token0 1000000000 1000000000 30792199830315 1250435266521266 104337 14602149588923138925101933711806 999999995892295739 944965817192274887

    step_header 24 "Swap (token1 -> token0)"
    swap $token1 33969900000000 33969900000000 906271879 1250435266521266 104339 14604295480606908301311147523433 999999996889194806 944931847292274887

    step_header 25 "Swap small (token1 -> token0)"
    swap $token1 3435320000 3435320000 91635 1250435266521266 104339 14604295697617397560526319750504 999999996889295605 944931843856954887
};

testMintSwap

summary

dfx stop
mv dfx.json.bak dfx.json
