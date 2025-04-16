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
    public type Token = {
        address : Principal;
        standard : Text;
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
        #LimitOrderDeleted;
        #Completed;
        #Failed;
    };

    public type ExecuteLimitOrderStatus = {
        #Created;
        #Completed;
        #Failed;
    };

    public type Transfer = {
        token: Principal;
        standard: Text;
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
        token0: Token;
        token1: Token;
        amount0: Nat;
        amount1: Nat;
        status: AddLiquidityStatus;
        liquidity: Nat;
        err: ?Error;
    };

    public type DecreaseLiquidityInfo = {
        positionId: Nat;
        token0: Token;
        token1: Token;
        amount0: Nat;
        amount1: Nat;
        status: DecreaseLiquidityStatus;
        liquidity: Nat;
        err: ?Error;
    };

    public type ClaimInfo = {
        positionId: Nat;
        token0: Token;
        token1: Token;
        amount0: Nat;
        amount1: Nat;
        status: ClaimStatus;
        err: ?Error;
    };

    public type SwapInfo = {
        tokenIn: Token;
        tokenOut: Token;
        amountIn: Amount;
        amountOut: Nat;
        amountInFee: Nat;
        amountOutFee: Nat;
        status: SwapStatus;
        err: ?Error;
    };

    public type OneStepSwapInfo = {
        deposit: DepositInfo;
        withdraw: WithdrawInfo;
        swap: SwapInfo;
        status: OneStepSwapStatus;
        err: ?Error;
    };

    public type TransferPositionInfo = {
        positionId: Nat;
        from: Account;
        to: Account;
        token0Amount: Nat;
        token1Amount: Nat;
        status: TransferPositionStatus;
        err: ?Error;
    };

    public type AddLimitOrderInfo = {
        positionId: Nat;
        token0: Token;
        token1: Token;
        token0AmountIn: Nat;
        token1AmountIn: Nat;
        tickLimit: Int;
        status: AddLimitOrderStatus;
        err: ?Error;
    };

    public type RemoveLimitOrderInfo = {
        positionId: Nat;
        token0: Token;
        token1: Token;
        token0AmountIn: Nat;
        token1AmountIn: Nat;
        token0AmountOut: Nat;
        token1AmountOut: Nat;
        tickLimit: Int;
        status: RemoveLimitOrderStatus;
        err: ?Error;
    };

    public type ExecuteLimitOrderInfo = {
        positionId: Nat;
        token0: Token;
        token1: Token;
        token0AmountIn: Nat;
        token1AmountIn: Nat;
        token0AmountOut: Nat;
        token1AmountOut: Nat;
        tickLimit: Int;
        status: ExecuteLimitOrderStatus;
        err: ?Error;
    };

}