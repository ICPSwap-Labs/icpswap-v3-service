import Types "./Types";
import Principal "mo:base/Principal";
import Nat "mo:base/Nat";
import Text "mo:base/Text";
import Blob "mo:base/Blob";

module {
    public func start(token: Principal, from: Types.Account, to: Types.Account, amount: Nat, fee: Nat, memo: ?Blob, failedIndex: Nat, standard: Text): Types.RefundInfo {
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
                standard = standard;
            };
            failedIndex = failedIndex;
            err = null;
        };
    };

    public func process(refund: Types.RefundInfo): Types.RefundInfo {
        switch (refund.status) {
            case (#Created) {
                return {
                    transfer = refund.transfer;
                    status = #CreditCompleted;
                    err = null;
                    failedIndex = refund.failedIndex;
                };
            };
            case (#CreditCompleted) {
                return {
                    transfer = refund.transfer;
                    status = #Completed;
                    err = null;
                    failedIndex = refund.failedIndex;
                };
            };
            case (#Completed) {
                return refund;
            };
            case (#Failed) {
                return refund;
            };
        };
    };

    public func fail(refund: Types.RefundInfo, error: Text): Types.RefundInfo {
        assert(refund.status != #Completed);
        return {
            transfer = refund.transfer;
            status = #Failed;
            err = ?error;
            failedIndex = refund.failedIndex;
        };
    };
};