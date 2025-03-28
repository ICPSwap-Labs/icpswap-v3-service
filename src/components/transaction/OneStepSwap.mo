import Types "./Types";
import Principal "mo:base/Principal";
import Text "mo:base/Text";

module {
    public func start(tokenIn: Principal, tokenOut: Principal, amountIn: Types.Amount): Types.OneStepSwapInfo {
        return {
            tokenIn = tokenIn;
            tokenOut = tokenOut;
            amountIn = amountIn;
            amountOut = 0;
            deposit = null;
            withdraw = null;
            status = #Created;
            err = null;
        };
    };

    public func process(info: Types.OneStepSwapInfo): Types.OneStepSwapInfo {
        switch (info.status) {
            case (#Created) {
                return {
                    tokenIn = info.tokenIn;
                    tokenOut = info.tokenOut;
                    amountIn = info.amountIn;
                    amountOut = info.amountOut;
                    deposit = info.deposit;
                    withdraw = info.withdraw;
                    status = #DepositTransferCompleted;
                    err = null;
                };
            };
            case (#DepositTransferCompleted) {
                return {
                    tokenIn = info.tokenIn;
                    tokenOut = info.tokenOut;
                    amountIn = info.amountIn;
                    amountOut = info.amountOut;
                    deposit = info.deposit;
                    withdraw = info.withdraw;
                    status = #DepositCreditCompleted;
                    err = null;
                };
            };
            case (#DepositCreditCompleted) {
                return {
                    tokenIn = info.tokenIn;
                    tokenOut = info.tokenOut;
                    amountIn = info.amountIn;
                    amountOut = info.amountOut;
                    deposit = info.deposit;
                    withdraw = info.withdraw;
                    status = #PreSwapCompleted;
                    err = null;
                };
            };
            case (#PreSwapCompleted) {
                return {
                    tokenIn = info.tokenIn;
                    tokenOut = info.tokenOut;
                    amountIn = info.amountIn;
                    amountOut = info.amountOut;
                    deposit = info.deposit;
                    withdraw = info.withdraw;
                    status = #SwapCompleted;
                    err = null;
                };
            };
            case (#SwapCompleted) {
                return {
                    tokenIn = info.tokenIn;
                    tokenOut = info.tokenOut;
                    amountIn = info.amountIn;
                    amountOut = info.amountOut;
                    deposit = info.deposit;
                    withdraw = info.withdraw;
                    status = #WithdrawCreditCompleted;
                    err = null;
                };
            };
            case (#WithdrawCreditCompleted) {
                return {
                    tokenIn = info.tokenIn;
                    tokenOut = info.tokenOut;
                    amountIn = info.amountIn;
                    amountOut = info.amountOut;
                    deposit = info.deposit;
                    withdraw = info.withdraw;
                    status = #Completed;
                    err = null;
                };
            };
            case (#Completed) {
                return info;
            };
            case (#Failed) {
                return info;
            };
        };
    };

    public func fail(info: Types.OneStepSwapInfo, error: Text): Types.OneStepSwapInfo {
        assert(info.status != #Completed);
        return {
            tokenIn = info.tokenIn;
            tokenOut = info.tokenOut;
            amountIn = info.amountIn;
            amountOut = info.amountOut;
            deposit = info.deposit;
            withdraw = info.withdraw;
            status = #Failed;
            err = ?error;
        };
    };

}; 