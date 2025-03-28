import Types "./Types";
import Principal "mo:base/Principal";
import Nat "mo:base/Nat";
import Text "mo:base/Text";
import Blob "mo:base/Blob";

module {
    public func start(token: Principal, from: Types.Account, to: Types.Account, amount: Nat, fee: Nat, memo: ?Blob): Types.WithdrawInfo {
        return {
            status = #Created;
            transfer = {
                token = token;
                from = from;
                to = to;
                amount = amount;
                fee = fee;
                memo = memo;
                index = 0;
            };
            err = null;
        };
    };

    public func process(withdraw: Types.WithdrawInfo): Types.WithdrawInfo {
        switch (withdraw.status) {
            case (#Created) {
                return {
                    transfer = withdraw.transfer;
                    status = #CreditCompleted;
                    err = null;
                };
            };
            case (#CreditCompleted) {
                return {
                    transfer = withdraw.transfer;
                    status = #Completed;
                    err = null;
                };
            };
            case (#Completed) {
                return withdraw;
            };
            case (#Failed) {
                return withdraw;
            };
        };
    };

    public func fail(withdraw: Types.WithdrawInfo, error: Text): Types.WithdrawInfo {
        assert(withdraw.status != #Completed and withdraw.status != #Failed);
        return {
            transfer = withdraw.transfer;
            status = #Failed;
            err = ?error;
        };
    };
    
};