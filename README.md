# ICPSwap Service V3

The code is written in Motoko and developed in the DFINITY command-line execution [environment](https://internetcomputer.org/docs/current/references/cli-reference/dfx-parent). Please follow the documentation [here](https://internetcomputer.org/docs/current/developer-docs/setup/install/#installing-the-ic-sdk-1) to setup IC SDK environment and related command-line tools.  

## Introduction

**SwapFactory**: As the top-layer canister, the SwapFactory presides over the creation and regulation of SwapPools. It upholds a meticulously curated index of all SwapPools, thereby enacting a seamless and high-caliber oversight for enhanced administrative finesse.

**SwapPool**: The SwapPool stands as the pivotal business canister of the Swap module. It is endowed with comprehensive transactional capabilities — from liquidity adjustments to the facilitation of trades, swapping of specific token pairs, and the strategic accumulation of swap fees — making it the linchpin of the platform’s operational prowess.

**PositionIndex**: To navigate the dispersion of user positions across myriad SwapPools, the PositionIndex serves as the centralized beacon of this structure. It contains a list of the SwapPools in which the user holds positions, ensuring a transparent and streamlined user asset tracking system.

**PasscodeManager**: It is designed to allow each user who wants to create a SwapPool to pay 1 ICP and then get a passcode with which to go to the SwapFactory and create a SwapPool.

## Local Testing

Run the `test-data-accuracy.sh` script to see how the whole swap process is working.

```bash
sh test-data-accuracy.sh
```

In the script, we use some external canisters to make the whole swap process run.

Data collection canister:
 - base_index
 - node_index
 - price

Token canister:
 - DIP20A
 - DIP20B
 - ICRC2

Tool canister:
 - Test

Regarding these canisters, only the data collection canisters are self-developed by ICPSwap, the rest can be found in the current project, or other projects that have been open-sourced in IC ecosystem. We have a plan to open source this part of the code later, for now, please use the compiled wasm and did files in the current project.

When running the `test-data-accuracy.sh` script for the first time, a balance check error occurs after the 'step 10 decrease' step. That's because in ICPSwap, when the user withdraws the swap fee, 20% of the fee is kept in the SwapPool, but the check data in the test script doesn't include this difference. 

So we can find the function *_distributeFee* in SwapPool.mo.

Comment out these two lines
```motoko
var swapFee0Repurchase = SafeUint.Uint128(swapFee0Total).div(SafeUint.Uint128(10)).mul(SafeUint.Uint128(2)).val();

var swapFee1Repurchase = SafeUint.Uint128(swapFee1Total).div(SafeUint.Uint128(10)).mul(SafeUint.Uint128(2)).val();
```

Uncomment these two lines
```motoko
var swapFee0Repurchase = 0;

var swapFee1Repurchase = 0;
```

Then the test script will run successfully.
