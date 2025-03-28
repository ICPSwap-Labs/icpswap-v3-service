import Time "mo:base/Time";
import Principal "mo:base/Principal";
import Text "mo:base/Text";
import Blob "mo:base/Blob";
import Nat "mo:base/Nat";

module {
    public type Amount = Nat;
    public type Account = {
        owner: Principal;
        subaccount: ?Blob;
    };
    public type Error = Text;
    public type Transaction = {
        id: Nat;
        timestamp: Time.Time;
        owner: Principal;
        canisterId: Principal;
        action: Action;
    };

    public type Action = {
        #Deposit: DepositInfo;
        #Withdraw: WithdrawInfo;
        #Refund: RefundInfo;
        #AddLiquidity: AddLiquidityInfo;
        #DecreaseLiquidity: DecreaseLiquidityInfo;
        #Claim: ClaimInfo;
        #Swap: SwapInfo;
        #OneStepSwap: OneStepSwapInfo;
        #TransferPosition: TransferPositionInfo;
        #AddLimitOrder: AddLimitOrderInfo;
        #RemoveLimitOrder: RemoveLimitOrderInfo;
        #ExecuteLimitOrder: ExecuteLimitOrderInfo;
    };

    public type DepositStatus = {
        #Created;
        #TransferCompleted;
        #Completed;
        #Failed;
    };

    public type WithdrawStatus = {
        #Created;
        #CreditCompleted;
        #Completed;
        #Failed;
    };

    public type RefundStatus = {
        #Created;
        #CreditCompleted;
        #Completed;
        #Failed;
    };

    public type AddLiquidityStatus = {
        #Created;
        #Completed;
        #Failed;
    };

    public type DecreaseLiquidityStatus = {
        #Created;
        #Completed;
        #Failed;
    };

    public type ClaimStatus = {
        #Created;
        #Completed;
        #Failed;
    };

    public type SwapStatus = {
        #Created;
        #Completed;
        #Failed;
    };

    public type OneStepSwapStatus = {
        #Created;
        #DepositTransferCompleted;
        #DepositCreditCompleted;
        #PreSwapCompleted;
        #SwapCompleted;
        // #WithdrawTransferCompleted;
        #WithdrawCreditCompleted;
        #Completed;
        #Failed;
    };

    public type TransferPositionStatus = {
        #Created;
        #Completed;
        #Failed;
    };

    public type AddLimitOrderStatus = {
        #Created;
        #Completed;
        #Failed;
    };

    public type RemoveLimitOrderStatus = {
        #Created;
        #RemoveLimitOrderCompleted;
        #Completed;
        #Failed;
    };

    public type ExecuteLimitOrderStatus = {
        #Created;
        #ExecuteLimitOrderCompleted;
        #Completed;
        #Failed;
    };

    public type Transfer = {
        token: Principal;
        from: Account;
        to: Account;
        amount: Nat;
        fee: Nat;
        memo: ?Blob;
        index: Nat;
    };

    public type DepositInfo = {
        transfer: Transfer;
        status: DepositStatus;
        err: ?Error;
    };

    public type WithdrawInfo = {
        transfer: Transfer;
        status: WithdrawStatus;
        err: ?Error;
    };

    public type RefundInfo = {
        failedIndex: Nat;
        transfer: Transfer;
        status: RefundStatus;
        err: ?Error;
    };

    public type AddLiquidityInfo = {
        positionId: Nat;
        token0: Principal;
        token1: Principal;
        amount0: Nat;
        amount1: Nat;
        status: AddLiquidityStatus;
        liquidity: Nat;
        err: ?Error;
    };

    public type DecreaseLiquidityInfo = {
        positionId: Nat;
        token0: Principal;
        token1: Principal;
        amount0: Nat;
        amount1: Nat;
        status: DecreaseLiquidityStatus;
        liquidity: Nat;
        err: ?Error;
    };

    public type ClaimInfo = {
        positionId: Nat;
        token0: Principal;
        token1: Principal;
        amount0: Nat;
        amount1: Nat;
        status: ClaimStatus;
        err: ?Error;
    };

    public type SwapInfo = {
        tokenIn: Principal;
        tokenOut: Principal;
        amountIn: Amount;
        amountOut: Nat;
        status: SwapStatus;
        err: ?Error;
    };

    public type OneStepSwapInfo = {
        tokenIn: Principal;
        tokenOut: Principal;
        amountIn: Amount;
        amountOut: Nat;
        deposit: ?DepositInfo;
        withdraw: ?WithdrawInfo;
        status: OneStepSwapStatus;
        err: ?Error;
    };

    public type TransferPositionInfo = {
        positionId: Nat;
        from: Account;
        to: Account;
        status: TransferPositionStatus;
        err: ?Error;
    };

    public type AddLimitOrderInfo = {
        positionId: Nat;
        status: AddLimitOrderStatus;
        err: ?Error;
    };

    public type RemoveLimitOrderInfo = {
        positionId: Nat;
        status: RemoveLimitOrderStatus;
        err: ?Error;
    };

    public type ExecuteLimitOrderInfo = {
        positionId: Nat;
        status: ExecuteLimitOrderStatus;
        err: ?Error;
    };

}