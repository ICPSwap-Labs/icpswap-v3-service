import Types "./Types";
import Principal "mo:base/Principal";
import Nat "mo:base/Nat";
import Blob "mo:base/Blob";
import Result "mo:base/Result";
import Deposit "./Deposit";
import Withdraw "./Withdraw";
import Refund "./Refund";
import Debug "mo:base/Debug";
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
    public func startDeposit(swap: Types.SwapInfo, deposit: Types.DepositInfo): Result.Result<Types.SwapInfo, Text> {
        switch (swap.status) {
            case (#Created) {
                return #ok({
                    tokenIn = swap.tokenIn;
                    tokenOut = swap.tokenOut;
                    amountIn = swap.amountIn;
                    amountOut = swap.amountOut;
                    deposit = ?deposit;
                    withdraw = swap.withdraw;
                    refundToken0 = swap.refundToken0;
                    refundToken1 = swap.refundToken1;
                    status = #DepositProcessing;
                });
            };
            case (_) {
                Debug.print("==> -- startDeposit --" # debug_show(swap.status));
                return #err("SwapStatusError");
            };
        };
    };
    public func completeDeposit(swap: Types.SwapInfo, deposit: Types.DepositInfo): Result.Result<Types.SwapInfo, Text> {
        switch (swap.status) {
            case (#DepositProcessing) {
                return #ok({
                    tokenIn = swap.tokenIn;
                    tokenOut = swap.tokenOut;
                    amountIn = swap.amountIn;
                    amountOut = swap.amountOut;
                    deposit = ?deposit;
                    withdraw = swap.withdraw;
                    refundToken0 = swap.refundToken0;
                    refundToken1 = swap.refundToken1;
                    status = #DepositCompleted;
                });
            };
            case (_) {
                Debug.print("==> -- completeDeposit --" # debug_show(swap.status));
                return #err("SwapStatusError");
            };
        };
    };
    public func failDeposit(swap: Types.SwapInfo, deposit: Types.DepositInfo): Result.Result<Types.SwapInfo, Text> {
        switch (swap.status) {
            case (#DepositProcessing) {
                return #ok({
                    tokenIn = swap.tokenIn;
                    tokenOut = swap.tokenOut;
                    amountIn = swap.amountIn;
                    amountOut = swap.amountOut;
                    deposit = ?deposit;
                    withdraw = swap.withdraw;
                    refundToken0 = swap.refundToken0;
                    refundToken1 = swap.refundToken1;
                    status = #Failed("DepositFailed");
                });
            };
            case (_) {
                Debug.print("==> -- failDeposit --" # debug_show(swap.status));
                return #err("SwapStatusError");
            };
        };
    };
    public func startWithdraw(swap: Types.SwapInfo, withdraw: Types.WithdrawInfo): Result.Result<Types.SwapInfo, Text> {
        switch (swap.status) {
            case (#SwapSuccess) {
                return #ok({
                    tokenIn = swap.tokenIn;
                    tokenOut = swap.tokenOut;
                    amountIn = swap.amountIn;
                    amountOut = swap.amountOut;
                    deposit = swap.deposit;
                    withdraw = ?withdraw;
                    refundToken0 = swap.refundToken0;
                    refundToken1 = swap.refundToken1;
                    status = #WithdrawProcessing;
                });
            };
            case (_) {
                Debug.print("==> -- startWithdraw --" # debug_show(swap.status));
                return #err("SwapStatusError");
            };
        };
    };
    public func processWithdraw(swap: Types.SwapInfo, withdraw: Types.WithdrawInfo): Result.Result<Types.SwapInfo, Text> {
        switch (swap.status) {
            case (#WithdrawProcessing) {
                return #ok({
                    tokenIn = swap.tokenIn;
                    tokenOut = swap.tokenOut;
                    amountIn = swap.amountIn;
                    amountOut = swap.amountOut;
                    deposit = swap.deposit;
                    withdraw = ?withdraw;
                    refundToken0 = swap.refundToken0;
                    refundToken1 = swap.refundToken1;
                    status = #WithdrawProcessing;
                });
            };
            case (_) {
                Debug.print("==> -- processWithdraw --" # debug_show(swap.status));
                return #err("SwapStatusError");
            };
        };
    };
    public func completeWithdraw(swap: Types.SwapInfo, withdraw: Types.WithdrawInfo): Result.Result<Types.SwapInfo, Text> {
        switch (swap.status) {
            case (#WithdrawProcessing) {
                return #ok({
                    tokenIn = swap.tokenIn;
                    tokenOut = swap.tokenOut;
                    amountIn = swap.amountIn;
                    amountOut = swap.amountOut;
                    deposit = swap.deposit;
                    withdraw = ?withdraw;
                    refundToken0 = swap.refundToken0;
                    refundToken1 = swap.refundToken1;
                    status = #Completed;
                });
            };
            case (_) {
                Debug.print("==> -- completeWithdraw --" # debug_show(swap.status));
                return #err("SwapStatusError");
            };
        };
    };
    public func failWithdraw(swap: Types.SwapInfo, withdraw: Types.WithdrawInfo): Result.Result<Types.SwapInfo, Text> {
        switch (swap.status) {
            case (#WithdrawProcessing) {
                return #ok({
                    tokenIn = swap.tokenIn;
                    tokenOut = swap.tokenOut;
                    amountIn = swap.amountIn;
                    amountOut = swap.amountOut;
                    deposit = swap.deposit;
                    withdraw = ?withdraw;
                    refundToken0 = swap.refundToken0;
                    refundToken1 = swap.refundToken1;
                    status = #Failed("WithdrawFailed");
                });
            };
            case (_) {
                Debug.print("==> -- failWithdraw --" # debug_show(swap.status));
                return #err("SwapStatusError");
            };
        };
    };
    public func processSwap(swap: Types.SwapInfo, amountIn: Nat): Result.Result<Types.SwapInfo, Text> {
        switch (swap.status) {
            case (#DepositCompleted or #Created) {
                return #ok({
                    tokenIn = swap.tokenIn;
                    tokenOut = swap.tokenOut;
                    amountIn = amountIn;
                    amountOut = swap.amountOut;
                    deposit = swap.deposit;
                    withdraw = swap.withdraw;
                    refundToken0 = swap.refundToken0;
                    refundToken1 = swap.refundToken1;
                    status = #SwapStarted;
                });
            };
            case (_) {
                Debug.print("==> -- processSwap --" # debug_show(swap.status));
                return #err("SwapStatusError");
            };
        };
    };
    public func completeSwap(swap: Types.SwapInfo, amountOut: Nat): Result.Result<Types.SwapInfo, Text> {
        switch (swap.status) {
            case (#SwapStarted) {
                return #ok({
                    tokenIn = swap.tokenIn;
                    tokenOut = swap.tokenOut;
                    amountIn = swap.amountIn;
                    amountOut = amountOut;
                    deposit = swap.deposit;
                    withdraw = swap.withdraw;
                    refundToken0 = swap.refundToken0;
                    refundToken1 = swap.refundToken1;
                    status = #SwapSuccess;
                });
            };
            case (_) {
                Debug.print("==> -- completeSwap --" # debug_show(swap.status));
                return #err("SwapStatusError");
            };
        };
    };
    public func failSwap(swap: Types.SwapInfo, error: Text): Result.Result<Types.SwapInfo, Text> {
        switch (swap.status) {
            case (#DepositProcessing or #DepositCompleted) {
                return #ok({
                    tokenIn = swap.tokenIn;
                    tokenOut = swap.tokenOut;
                    amountIn = swap.amountIn;
                    amountOut = swap.amountOut;
                    deposit = swap.deposit;
                    withdraw = swap.withdraw;
                    refundToken0 = swap.refundToken0;
                    refundToken1 = swap.refundToken1;
                    status = #Failed(error);
                });
            };
            case (_) {
                Debug.print("==> -- failSwap --" # debug_show(swap.status));
                return #err("SwapStatusError");
            };
        };
    };
    public func startAndProcessRefund(swap: Types.SwapInfo, token: Principal, from: Types.Account, to: Types.Account, amount: Nat, fee: Nat, memo: ?Blob): Result.Result<Types.SwapInfo, Text> {
        switch (swap.status) {
            case (#Failed(_msg)) {
                switch (swap.refundToken0) {
                    case (null) {
                        return #ok({
                            tokenIn = swap.tokenIn;
                            tokenOut = swap.tokenOut;
                            amountIn = swap.amountIn;
                            amountOut = swap.amountOut;
                            deposit = swap.deposit;
                            withdraw = swap.withdraw;
                            refundToken0 = ?Refund.startAndProcess(token, from, to, amount, fee, memo);
                            refundToken1 = swap.refundToken1;
                            status = swap.status;
                        });
                    };
                    case (?_refundToken0) {
                        return #err("SwapStatusError");
                    };
                };
            };
            case (_) {
                Debug.print("==> -- startAndProcessRefund --" # debug_show(swap.status));
                return #err("SwapStatusError");
            };
        };
    };
    public func completeRefund(swap: Types.SwapInfo, index: Nat): Result.Result<Types.SwapInfo, Text> {
        switch (swap.refundToken0) {
            case (null) {
                return #err("SwapStatusError");
            };
            case (?refundToken0) {
                let newRefundToken0 = switch(Refund.success(refundToken0, index)) {
                    case (#ok(refundToken0)) { refundToken0 };
                    case (#err(e)) { return #err(e) };
                };
                return #ok({
                    tokenIn = swap.tokenIn;
                    tokenOut = swap.tokenOut;
                    amountIn = swap.amountIn;
                    amountOut = swap.amountOut;
                    deposit = swap.deposit;
                    withdraw = swap.withdraw;
                    refundToken0 = ?newRefundToken0;
                    refundToken1 = swap.refundToken1;
                    status = swap.status;
                });
            };
        };
    };
    public func failRefund(swap: Types.SwapInfo, error: Text): Result.Result<Types.SwapInfo, Text> {
        switch (swap.refundToken0) {
            case (null) {
                return #err("SwapStatusError");
            };
            case (?refundToken0) {
                let newRefundToken0 = switch(Refund.fail(refundToken0, error)) {
                    case (#ok(refundToken0)) { refundToken0 };
                    case (#err(e)) { return #err(e) };
                };
                return #ok({
                    tokenIn = swap.tokenIn;
                    tokenOut = swap.tokenOut;
                    amountIn = swap.amountIn;
                    amountOut = swap.amountOut;
                    deposit = swap.deposit;
                    withdraw = swap.withdraw;
                    refundToken0 = ?newRefundToken0;
                    refundToken1 = swap.refundToken1;
                    status = swap.status;
                });
            };
        };
    };
};