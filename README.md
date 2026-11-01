# ICPSwap Service V3

The code is written in Motoko and developed in the DFINITY command-line execution [environment](https://internetcomputer.org/docs/current/references/cli-reference/dfx-parent). Please follow the documentation [here](https://internetcomputer.org/docs/current/developer-docs/setup/install/#installing-the-ic-sdk-1) to setup IC SDK environment and related command-line tools.  

## Introduction

ICPSwap V3 is a Uniswap V3-style concentrated liquidity AMM on the Internet Computer. It supports liquidity provision within custom price ranges, limit orders, one-step deposit-and-swap, and ICRC-21 consent messages for wallet integration.

## Architecture

### Canisters

**SwapFactory** — The top-layer canister that creates and manages SwapPools. Maintains the pool registry, handles the structured upgrade pipeline (backup, pause, upgrade, resume), and coordinates with SwapPoolInstaller for pool deployment.

**SwapPool** — The core business canister. Handles liquidity management (mint, increase, decrease), swaps, limit orders, claims, deposits, withdrawals, and position transfers. Each pool serves a single token pair at a specific fee tier.

**SwapPoolInstaller** — Deploys new SwapPool canisters on behalf of SwapFactory. Holds the pool WASM module and handles `install_code` calls.

**PositionIndex** — Centralized index mapping users to the pools where they hold positions. Auto-syncs the pool list from SwapFactory every 300 seconds.

**PasscodeManager** — Manages pool creation permissions. Users pay 1 ICP to receive a passcode, which is then consumed when creating a new pool via SwapFactory.

**SwapFeeReceiver** — Collects protocol fees from all pools. Periodically claims accumulated fees, swaps non-ICP tokens to ICP, optionally swaps ICP to ICS, and burns ICS by transferring to the governance canister.

**SwapDataBackup** — Backs up pool state before upgrades. Stores snapshots of positions, ticks, balances, limit orders, and withdraw queue for disaster recovery.

**TrustedCanisterManager** — Maintains a whitelist of trusted token canisters for mistransfer recovery operations.

**SwapFactoryValidator** — Validates SNS governance proposals (e.g., `batchAddPoolControllers`, `addPoolInstallers`) before execution.

**DeletedSwapPool** — Replacement canister for decommissioned pools. Refunds user unused balances, transfers remaining tokens to the fee receiver, and recycles cycles.

### Components (src/components/)

| Component | Purpose |
|---|---|
| `PositionTick` | Manages positions, ticks, tick bitmaps, and user position IDs |
| `TokenHolder` | Tracks per-user unused token balances (deposit/withdraw accounting) |
| `TokenAmount` | Pool-level token amount tracking (telemetry/accounting) |
| `SwapRecord` | Buffers swap records for async sync to external data canisters |
| `WasmManager` | Chunked WASM upload, staging, and activation with uploader isolation |
| `Job` | Recurring job scheduler with activity-based auto-pause/resume |
| `ICRC21` | ICRC-21 consent message generation for all user-facing operations |
| `UpgradeTask` | Orchestrates the structured pool upgrade pipeline |
| `PoolData` | Pool metadata storage and indexing |

### Math Libraries (src/libraries/)

Faithful translations of Uniswap V3 Solidity math libraries to Motoko:

| Library | Purpose |
|---|---|
| `FullMath` | Full-precision multiply-divide with rounding (unbounded Nat) |
| `SqrtPriceMath` | Price ↔ token amount conversions using sqrt price (Q96 format) |
| `SwapMath` | Per-step swap computation (amounts, fees, price impact) |
| `TickMath` | Tick ↔ sqrt price ratio conversions |
| `Tick` | Tick state management (liquidity tracking, fee growth) |
| `TickBitmap` | Bitmap for efficient initialized tick discovery |
| `LiquidityMath` | Safe liquidity addition/subtraction |
| `LiquidityAmounts` | Liquidity ↔ token amount conversions for a price range |
| `FixedPoint96` / `FixedPoint128` | Q96 and Q128 fixed-point constants |
| `BitMath` | Most/least significant bit operations |
| `UnsafeMath` | Division with rounding up |
| `BlockTimestamp` | Current time in seconds |

### Transaction State Machine (src/components/transaction/)

Each user operation is tracked as a transaction with a typed state machine:

| Module | States |
|---|---|
| `Deposit` | Created → TransferCompleted → Completed / Failed |
| `Withdraw` | Created → CreditCompleted → Completed / Failed |
| `Refund` | Created → CreditCompleted → Completed / Failed |
| `AddLiquidity` | Created → Completed / Failed |
| `DecreaseLiquidity` | Created → Completed / Failed |
| `Claim` | Created → Completed / Failed |
| `Swap` | Created → Completed / Failed |
| `OneStepSwap` | Created → DepositTransferCompleted → DepositCreditCompleted → PreSwapCompleted → SwapCompleted → WithdrawCreditCompleted → Completed / Failed |
| `TransferPosition` | Created → Completed / Failed |
| `AddLimitOrder` | Created → Completed / Failed |
| `RemoveLimitOrder` | Created → LimitOrderDeleted → Completed / Failed |
| `ExecuteLimitOrder` | Created → Completed / Failed |

### Utilities (src/utils/)

| Utility | Purpose |
|---|---|
| `PoolUtils` | Pool key generation, token sorting, Nat-to-Blob encoding, hex parsing |
| `AccountUtils` | Principal-to-subaccount blob conversion |
| `Functions` | Token equality and hashing helpers |

## Key Features

### Limit Orders

Users can place limit orders on positions. When the pool tick crosses the limit price, the order is automatically executed:

1. `_checkLimitOrder` — triggered after each swap, finds all matching orders and pushes to stack
2. `_autoDecrease` (message 1) — pops from stack, sets pending execution
3. `_executeAutoDecrease` (message 2) — executes the decrease liquidity, enqueues token withdrawal

Failed executions are retried up to 3 times. Permanently failed orders are moved to `_failedLimitOrders` (queryable via `getFailedLimitOrders`).

### Withdraw Queue

All token withdrawals (from user withdraw, decrease liquidity, claim, limit order execution) go through an async queue (`_processWithdrawQueue`) with 500ms spacing. The pool records a dequeued transfer in stable in-flight state before calling the token canister. `getWithdrawQueueInfo` shows queued items; `getInFlightWithdrawals` shows dequeued transfers whose workers have not finished the pool's existing success/failure handling. Returned failures remain in the existing failed-transaction records. A failed status alone does not prove nonpayment on the ledger.

After 10 minutes without progress, the next watchdog check or newly enqueued withdrawal starts the remaining queue under a new generation. It does not retry the in-flight transfer, because the token canister may still complete the original call. Later transfers may run while that call remains unresolved. An operator must compare the transaction with the token ledger before resolving or compensating it. `restartWithdrawQueueProcessing(true)` also resumes only queued items. After an upgrade, the pool retains in-flight records and restarts only queued items.

Recovery needs enough cycles to execute. If low cycles disable timer dispatch, a top-up alone may leave the queue idle until a new withdrawal or an administrator restarts it.

### Structured Upgrade Pipeline

Pool upgrades follow a safe pipeline managed by SwapFactory:

1. `setAvailable(false)` — pause pool
2. `SwapDataBackup.backup()` — snapshot all state
3. Stop canister
4. Upgrade WASM
5. Start canister  
6. `setAvailable(true)` — resume pool

### ICRC Standards Support

- **ICRC-10** — Supported standards declaration
- **ICRC-21** — Consent messages for all user operations (deposit, withdraw, swap, mint, claim, transfer position, limit orders, etc.)
- **ICRC-28** — Trusted origins for wallet integration

## Dependencies

Managed via [vessel](https://github.com/dfinity/vessel):

- `base` — Motoko standard library
- `commons` — SafeUint/SafeInt math, collection utilities, principal utilities
- `token-adapter` — Unified interface for DIP20, ICRC-1, ICRC-2, EXT, ICP token standards
- `sha224` / `sha256` — Hash functions

## Local Testing

The withdrawal queue regression test builds the pool and runs it against a delayed mock ledger in an isolated PocketIC network. It advances time past the watchdog deadline, verifies that the later payout completes first, and checks that the delayed reply does not cause a duplicate payment. The mock ledger tests queue control flow, not ledger balance accounting. Tested with Motoko 0.11.1, vessel 0.8.0, dfx 0.31.0 and Python 3.

```bash
MOC=/path/to/moc VESSEL=/path/to/vessel bash test/withdraw-queue/run.sh
```

Run the `test-data-accuracy.sh` script to see how the whole swap process is working.

```bash
sh test-data-accuracy.sh
```

In the script, we use some external canisters to make the whole swap process run.

Token canister:
 - DIP20A
 - DIP20B
 - ICRC2

Tool canister:
 - Test

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

## Operations Scripts

| Script | Purpose |
|---|---|
| `build.sh` | Build all canisters |
| `upload-pool-wasm.sh` | Upload SwapPool WASM to factory/installer in chunks |
| `upgrade-pool.sh` | Manual single-pool upgrade (development only) |
| `test-data-accuracy.sh` | End-to-end swap accuracy test |
| `test-biz-flow.sh` | Business flow integration test |
| `test-sync.sh` | Data sync test |
