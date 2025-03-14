import Time "mo:base/Time";
import Principal "mo:base/Principal";
import Result "mo:base/Result";
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
        #Swap: SwapInfo;
        #Withdraw: WithdrawInfo;
        #AddLiquidity: AddLiquidityInfo;
        #DecreaseLiquidity: DecreaseLiquidityInfo;
        #Claim: ClaimInfo;
        #TransferPosition: TransferPositionInfo;
    };
    public type Transfer = {
        token: Principal;
        from: Account;
        to: Account;
        amount: Nat;
        fee: Nat;
        memo: ?Blob;
        status: TransferStatus;
    };
    public type TransferStatus = {
        #Created;
        #Processing;
        #Completed: Nat;
        #Failed: Error;
    };
    public type SwapInfo = {
        tokenIn: Principal;
        tokenOut: Principal;
        amountIn: Amount;
        amountOut: Nat;
        deposit: ?DepositInfo;
        withdraw: ?WithdrawInfo;
        refundToken0: ?RefundInfo;
        refundToken1: ?RefundInfo;
        status: SwapStatus;
    };
    public type SwapStatus = {
        #Created;
        #DepositProcessing;
        #DepositCompleted;
        #SwapStarted;
        #SwapSuccess;
        #WithdrawProcessing;
        #Completed;
        #Failed: Error;
    };
    public type DepositInfo = {
        transfer: Transfer;
        status: DepositStatus;
    };
    public type WithdrawInfo = {
        transfer: Transfer;
        status: WithdrawStatus;
    };
    public type DepositStatus = {
        #Processing;
        #Success;
        #Completed;
        #Failed: Error; 
    };
    public type WithdrawStatus = {
        #Created;
        #Processing;
        #Completed;
        #Failed: Error;
    };
    public type RefundInfo = {
        token: Principal;
        transfer: Transfer;
        status: RefundStatus;
    };
    public type AddLiquidityInfo = {
        token0: Principal;
        token1: Principal;
        amount0: Nat;
        amount1: Nat;
        deposit0: ?DepositInfo;
        deposit1: ?DepositInfo;
        positionId: Nat;
        status: AddLiquidityStatus;
        liquidity: Nat;
    };
    public type AddLiquidityStatus = {
        #Created;
        #Token0DepositProcessing;
        #Token0DepositCompleted;
        #Token1DepositProcessing;
        #Token1DepositCompleted;
        #LiquidityMinting;
        #Completed;
        #Failed: Error;
    };
    public type RefundStatus = {
        #Created;
        #Processing;
        #Completed;
        #Failed: Error;
    };
    public type DecreaseLiquidityInfo = {
        token0: Principal;
        token1: Principal;
        amount0: Nat;
        amount1: Nat;
        positionId: Nat;
        withdraw0: ?WithdrawInfo;
        withdraw1: ?WithdrawInfo;
        status: DecreaseLiquidityStatus;
        liquidity: Nat;
    };
    public type DecreaseLiquidityStatus = {
        #Created;
        #DecreaseSuccess;
        #Withdraw0Processing;
        #Withdraw0Completed;
        #Withdraw1Processing;
        #Withdraw1Completed;
        #Completed;
        #Failed: Error;
    };
    public type ClaimInfo = {
        positionId: Nat;
        token0: Principal;
        token1: Principal;
        amount0: Nat;
        amount1: Nat;
        status: ClaimStatus;
    };
    public type ClaimStatus = {
        #Created;
        #Processing;
        #Completed;
        #Failed: Error;
    };
    public type TransferPositionInfo = {
        positionId: Nat;
        from: Account;
        to: Account;
        status: TransferPositionStatus;
    };
    public type TransferPositionStatus = {
        #Completed;
    };
   
}