import Types "./Types";
import Principal "mo:base/Principal";
import Nat "mo:base/Nat";
import Blob "mo:base/Blob";
import Refund "./Refund";

module {
    public func start(tokenIn: Principal, tokenOut: Principal, amountIn: Types.Amount): Types.SwapInfo {
        return {
            tokenIn = tokenIn;
            tokenOut = tokenOut;
            amountIn = amountIn;
            amountOut = 0;
            deposit = null;
            withdraw = null;
            refundToken0 = null;
            refundToken1 = null;
            status = #Created;
        };
    };

    public func startDeposit(swap: Types.SwapInfo, deposit: Types.DepositInfo): Types.SwapInfo {
        assert(swap.status == #Created);
        return {
            tokenIn = swap.tokenIn;
            tokenOut = swap.tokenOut;
            amountIn = swap.amountIn;
            amountOut = swap.amountOut;
            deposit = ?deposit;
            withdraw = swap.withdraw;
            refundToken0 = swap.refundToken0;
            refundToken1 = swap.refundToken1;
            status = #DepositProcessing;
        };
    };

    public func completeDeposit(swap: Types.SwapInfo, deposit: Types.DepositInfo): Types.SwapInfo {
        assert(swap.status == #DepositProcessing);
        return {
            tokenIn = swap.tokenIn;
            tokenOut = swap.tokenOut;
            amountIn = swap.amountIn;
            amountOut = swap.amountOut;
            deposit = ?deposit;
            withdraw = swap.withdraw;
            refundToken0 = swap.refundToken0;
            refundToken1 = swap.refundToken1;
            status = #DepositCompleted;
        };
    };

    public func failDeposit(swap: Types.SwapInfo, deposit: Types.DepositInfo): Types.SwapInfo {
        assert(swap.status == #DepositProcessing);
        return {
            tokenIn = swap.tokenIn;
            tokenOut = swap.tokenOut;
            amountIn = swap.amountIn;
            amountOut = swap.amountOut;
            deposit = ?deposit;
            withdraw = swap.withdraw;
            refundToken0 = swap.refundToken0;
            refundToken1 = swap.refundToken1;
            status = #Failed("DepositFailed");
        };
    };

    public func startWithdraw(swap: Types.SwapInfo, withdraw: Types.WithdrawInfo): Types.SwapInfo {
        assert(swap.status == #SwapSuccess);
        return {
            tokenIn = swap.tokenIn;
            tokenOut = swap.tokenOut;
            amountIn = swap.amountIn;
            amountOut = swap.amountOut;
            deposit = swap.deposit;
            withdraw = ?withdraw;
            refundToken0 = swap.refundToken0;
            refundToken1 = swap.refundToken1;
            status = #WithdrawProcessing;
        };
    };

    public func processWithdraw(swap: Types.SwapInfo, withdraw: Types.WithdrawInfo): Types.SwapInfo {
        assert(swap.status == #WithdrawProcessing);
        return {
            tokenIn = swap.tokenIn;
            tokenOut = swap.tokenOut;
            amountIn = swap.amountIn;
            amountOut = swap.amountOut;
            deposit = swap.deposit;
            withdraw = ?withdraw;
            refundToken0 = swap.refundToken0;
            refundToken1 = swap.refundToken1;
            status = #WithdrawProcessing;
        };
    };

    public func completeWithdraw(swap: Types.SwapInfo, withdraw: Types.WithdrawInfo): Types.SwapInfo {
        assert(swap.status == #WithdrawProcessing);
        return {
            tokenIn = swap.tokenIn;
            tokenOut = swap.tokenOut;
            amountIn = swap.amountIn;
            amountOut = swap.amountOut;
            deposit = swap.deposit;
            withdraw = ?withdraw;
            refundToken0 = swap.refundToken0;
            refundToken1 = swap.refundToken1;
            status = #Completed;
        };
    };

    public func failWithdraw(swap: Types.SwapInfo, withdraw: Types.WithdrawInfo): Types.SwapInfo {
        assert(swap.status == #WithdrawProcessing);
        return {
            tokenIn = swap.tokenIn;
            tokenOut = swap.tokenOut;
            amountIn = swap.amountIn;
            amountOut = swap.amountOut;
            deposit = swap.deposit;
            withdraw = ?withdraw;
            refundToken0 = swap.refundToken0;
            refundToken1 = swap.refundToken1;
            status = #Failed("WithdrawFailed");
        };
    };

    public func processSwap(swap: Types.SwapInfo, amountIn: Nat): Types.SwapInfo {
        assert(swap.status == #DepositCompleted or swap.status == #Created);
        return {
            tokenIn = swap.tokenIn;
            tokenOut = swap.tokenOut;
            amountIn = amountIn;
            amountOut = swap.amountOut;
            deposit = swap.deposit;
            withdraw = swap.withdraw;
            refundToken0 = swap.refundToken0;
            refundToken1 = swap.refundToken1;
            status = #SwapStarted;
        };
    };

    public func completeSwap(swap: Types.SwapInfo, amountOut: Nat): Types.SwapInfo {
        assert(swap.status == #SwapStarted);
        return {
            tokenIn = swap.tokenIn;
            tokenOut = swap.tokenOut;
            amountIn = swap.amountIn;
            amountOut = amountOut;
            deposit = swap.deposit;
            withdraw = swap.withdraw;
            refundToken0 = swap.refundToken0;
            refundToken1 = swap.refundToken1;
            status = #SwapSuccess;
        };
    };

    public func successAndComplete(swap: Types.SwapInfo, amountOut: Nat): Types.SwapInfo {
        assert(swap.status == #Created);
        return {
            tokenIn = swap.tokenIn;
            tokenOut = swap.tokenOut;
            amountIn = swap.amountIn;
            amountOut = amountOut;
            deposit = swap.deposit;
            withdraw = swap.withdraw;
            refundToken0 = swap.refundToken0;
            refundToken1 = swap.refundToken1;
            status = #Completed;
        };
    };

    public func failSwap(swap: Types.SwapInfo, error: Text): Types.SwapInfo {
        assert(swap.status == #DepositProcessing or swap.status == #DepositCompleted);
        return {
            tokenIn = swap.tokenIn;
            tokenOut = swap.tokenOut;
            amountIn = swap.amountIn;
            amountOut = swap.amountOut;
            deposit = swap.deposit;
            withdraw = swap.withdraw;
            refundToken0 = swap.refundToken0;
            refundToken1 = swap.refundToken1;
            status = #Failed(error);
        };
    };

    public func startAndProcessRefund(swap: Types.SwapInfo, token: Principal, from: Types.Account, to: Types.Account, amount: Nat, fee: Nat, memo: ?Blob): Types.SwapInfo {
        assert(
            switch(swap.status) {
                case (#Failed(_)) { true };
                case (_) { false };
            }
        );
        assert(swap.refundToken0 == null);
        
        return {
            tokenIn = swap.tokenIn;
            tokenOut = swap.tokenOut;
            amountIn = swap.amountIn;
            amountOut = swap.amountOut;
            deposit = swap.deposit;
            withdraw = swap.withdraw;
            refundToken0 = ?Refund.startAndProcess(token, from, to, amount, fee, memo);
            refundToken1 = swap.refundToken1;
            status = swap.status;
        };
    };

    public func completeRefund(swap: Types.SwapInfo, index: Nat): Types.SwapInfo {
        assert(swap.refundToken0 != null);
        let refundToken0 = switch(swap.refundToken0) {
            case (?r) { r };
            case (null) { assert(false); loop { } };
        };
        
        return {
            tokenIn = swap.tokenIn;
            tokenOut = swap.tokenOut;
            amountIn = swap.amountIn;
            amountOut = swap.amountOut;
            deposit = swap.deposit;
            withdraw = swap.withdraw;
            refundToken0 = ?Refund.success(refundToken0, index);
            refundToken1 = swap.refundToken1;
            status = swap.status;
        };
    };

    public func failRefund(swap: Types.SwapInfo, error: Text): Types.SwapInfo {
        assert(swap.refundToken0 != null);
        let refundToken0 = switch(swap.refundToken0) {
            case (?r) { r };
            case (null) { assert(false); loop { } };
        };
        
        return {
            tokenIn = swap.tokenIn;
            tokenOut = swap.tokenOut;
            amountIn = swap.amountIn;
            amountOut = swap.amountOut;
            deposit = swap.deposit;
            withdraw = swap.withdraw;
            refundToken0 = ?Refund.fail(refundToken0, error);
            refundToken1 = swap.refundToken1;
            status = swap.status;
        };
    };
};