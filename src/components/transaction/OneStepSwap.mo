import Types "./Types";
import Principal "mo:base/Principal";
import Text "mo:base/Text";
import Blob "mo:base/Blob";

module {
    private func _updateStatus(info: Types.OneStepSwapInfo, status: Types.OneStepSwapStatus, err: ?Text): Types.OneStepSwapInfo {
        {
            deposit = info.deposit;
            withdraw = info.withdraw;
            swap = info.swap;
            status = status;
            err = err;
        }
    };

    private func _updateDepositStatus(deposit: Types.DepositInfo, status: Types.DepositStatus): Types.DepositInfo {
        { deposit with status = status }
    };

    private func _updateWithdrawStatus(withdraw: Types.WithdrawInfo, status: Types.WithdrawStatus): Types.WithdrawInfo {
        { withdraw with status = status }
    };

    private func _updateWithdrawAmount(withdraw: Types.WithdrawInfo, amount: Nat): Types.WithdrawInfo {
        { withdraw with transfer = { withdraw.transfer with amount = amount } }
    };

    private func _updateSwapStatus(swap: Types.SwapInfo, status: Types.SwapStatus): Types.SwapInfo {
        { swap with status = status }
    };

    public func start(
        tokenIn: Types.Token, 
        tokenOut: Types.Token, 
        amountIn: Nat,
        amountOut: Nat,
        amountInFee: Nat,
        amountOutFee: Nat,
        canisterId: Principal,
        caller: Principal,
        subaccount: ?Blob
    ): Types.OneStepSwapInfo {
        _updateStatus({
            deposit = {
                transfer = {
                    token = tokenIn.address;
                    from = { owner = if(subaccount == null) { caller } else { canisterId }; subaccount = subaccount };
                    to = { owner = canisterId; subaccount = null };
                    amount = amountIn;
                    fee = amountInFee;
                    memo = null;
                    index = 0;
                    standard = tokenIn.standard;
                };
                status = #Created;
                err = null;
            };
            withdraw = {
                transfer = {
                    token = tokenOut.address;
                    from = { owner = canisterId; subaccount = null };
                    to = { owner = caller; subaccount = null };
                    amount = amountOut;
                    fee = amountOutFee;
                    memo = null;
                    index = 0;
                    standard = tokenOut.standard;
                };
                status = #Created;
                err = null;
            };
            swap = {
                tokenIn = tokenIn;
                tokenOut = tokenOut;
                amountIn = amountIn;
                amountOut = amountOut;
                amountInFee = amountInFee;
                amountOutFee = amountOutFee;
                status = #Created;
                err = null;
            };
            status = #Created;
            err = null;
        }, #Created, null)
    };

    public func process(info: Types.OneStepSwapInfo): Types.OneStepSwapInfo {
        switch (info.status) {
            case (#Created) {
                _updateStatus({
                    deposit = _updateDepositStatus(info.deposit, #TransferCompleted);
                    withdraw = info.withdraw;
                    swap = info.swap;
                    status = #DepositTransferCompleted;
                    err = null;
                }, #DepositTransferCompleted, null)
            };
            case (#DepositTransferCompleted) {
                _updateStatus({
                    deposit = _updateDepositStatus(info.deposit, #Completed);
                    withdraw = info.withdraw;
                    swap = info.swap;
                    status = #DepositCreditCompleted;
                    err = null;
                }, #DepositCreditCompleted, null)
            };
            case (#DepositCreditCompleted) {
                _updateStatus({
                    deposit = info.deposit;
                    withdraw = info.withdraw;
                    swap = info.swap;
                    status = #PreSwapCompleted;
                    err = null;
                }, #PreSwapCompleted, null)
            };
            case (#PreSwapCompleted) {
                _updateStatus({
                    deposit = info.deposit;
                    withdraw = info.withdraw;
                    swap = _updateSwapStatus(info.swap, #Completed);
                    status = #SwapCompleted;
                    err = null;
                }, #SwapCompleted, null)
            };
            case (#SwapCompleted) {
                _updateStatus({
                    deposit = info.deposit;
                    withdraw = _updateWithdrawAmount(_updateWithdrawStatus(info.withdraw, #CreditCompleted), info.swap.amountOut);
                    swap = info.swap;
                    status = #WithdrawCreditCompleted;
                    err = null;
                }, #WithdrawCreditCompleted, null)
            };
            case (#WithdrawCreditCompleted) {
                _updateStatus({
                    deposit = info.deposit;
                    withdraw = _updateWithdrawStatus(info.withdraw, #Completed);
                    swap = info.swap;
                    status = #Completed;
                    err = null;
                }, #Completed, null)
            };
            case (#Completed or #Failed) info;
        }
    };

    public func fail(info: Types.OneStepSwapInfo, error: Text): Types.OneStepSwapInfo {
        assert(info.status != #Completed);
        _updateStatus(info, #Failed, ?error)
    };
}; 