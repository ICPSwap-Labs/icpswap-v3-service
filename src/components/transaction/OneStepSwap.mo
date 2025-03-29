import Types "./Types";
import Principal "mo:base/Principal";
import Text "mo:base/Text";
import Blob "mo:base/Blob";

module {
    public func start(
        tokenIn: Principal, 
        tokenOut: Principal, 
        amountIn: Nat,
        amountOut: Nat,
        amountInFee: Nat,
        amountOutFee: Nat,
        canisterId: Principal,
        caller: Principal,
        subaccount: ?Blob
    ): Types.OneStepSwapInfo {
        return {
            deposit = {
                transfer = {
                    token = tokenIn;
                    from = { owner = if(subaccount == null) { caller } else { canisterId }; subaccount = subaccount };
                    to = { owner = canisterId; subaccount = null };
                    amount = amountIn;
                    fee = amountInFee;
                    memo = null;
                    index = 0;
                };
                status = #Created;
                err = null;
            };
            withdraw = {
                transfer = {
                    token = tokenOut;
                    from = { owner = canisterId; subaccount = null };
                    to = { owner = caller; subaccount = null };
                    amount = amountOut;
                    fee = amountOutFee;
                    memo = null;
                    index = 0;
                };
                status = #Created;
                err = null;
            };
            swap = {
                tokenIn = tokenIn;
                tokenOut = tokenOut;
                amountIn = amountIn;
                amountOut = amountOut;
                status = #Created;
                err = null;
            };
            status = #Created;
            err = null;
        };
    };

    public func process(info: Types.OneStepSwapInfo): Types.OneStepSwapInfo {
        switch (info.status) {
            case (#Created) {
                return {
                    deposit = { info.deposit with status = #TransferCompleted };
                    withdraw = info.withdraw;
                    swap = info.swap;
                    status = #DepositTransferCompleted;
                    err = null;
                };
            };
            case (#DepositTransferCompleted) {
                return {
                    deposit = { info.deposit with status = #Completed };
                    withdraw = info.withdraw;
                    swap = info.swap;
                    status = #DepositCreditCompleted;
                    err = null;
                };
            };
            case (#DepositCreditCompleted) {
                return {
                    deposit = info.deposit;
                    withdraw = info.withdraw;
                    swap = info.swap;
                    status = #PreSwapCompleted;
                    err = null;
                };
            };
            case (#PreSwapCompleted) {
                return {
                    deposit = info.deposit;
                    withdraw = info.withdraw;
                    swap = { info.swap with status = #Completed };
                    status = #SwapCompleted;
                    err = null;
                };
            };
            case (#SwapCompleted) {
                return {
                    deposit = info.deposit;
                    withdraw = { info.withdraw with status = #CreditCompleted; amount = info.swap.amountOut; };
                    swap = info.swap;
                    status = #WithdrawCreditCompleted;
                    err = null;
                };
            };
            case (#WithdrawCreditCompleted) {
                return {
                    deposit = info.deposit;
                    withdraw = { info.withdraw with status = #Completed };
                    swap = info.swap;
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
            deposit = info.deposit;
            withdraw = info.withdraw;
            swap = info.swap;
            status = #Failed;
            err = ?error;
        };
    };
}; 