import Types "./Types";
import Principal "mo:base/Principal";
import Nat "mo:base/Nat";
import Text "mo:base/Text";
import Blob "mo:base/Blob";

module {
    private func _updateStatus(withdraw: Types.WithdrawInfo, status: Types.WithdrawStatus, err: ?Text): Types.WithdrawInfo {
        {
            transfer = withdraw.transfer;
            status = status;
            err = err;
        }
    };

    public func start(token: Principal, from: Types.Account, to: Types.Account, amount: Nat, fee: Nat, memo: ?Blob, standard: Text): Types.WithdrawInfo {
        _updateStatus({
            status = #Created;
            transfer = {
                token = token;
                from = from;
                to = to;
                amount = amount;
                fee = fee;
                memo = memo;
                index = 0;
                standard = standard;
            };
            err = null;
        }, #Created, null)
    };

    public func process(withdraw: Types.WithdrawInfo): Types.WithdrawInfo {
        switch (withdraw.status) {
            case (#Created) _updateStatus(withdraw, #CreditCompleted, null);
            case (#CreditCompleted) _updateStatus(withdraw, #Completed, null);
            case (#Completed or #Failed) withdraw;
        }
    };

    public func fail(withdraw: Types.WithdrawInfo, error: Text): Types.WithdrawInfo {
        assert(withdraw.status != #Completed and withdraw.status != #Failed);
        _updateStatus(withdraw, #Failed, ?error)
    };
};