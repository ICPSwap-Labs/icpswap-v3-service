import Types "./Types";
import Principal "mo:base/Principal";
import Nat "mo:base/Nat";
import Text "mo:base/Text";
import Blob "mo:base/Blob";

module {
    private func _updateStatus(refund: Types.RefundInfo, status: Types.RefundStatus, err: ?Text): Types.RefundInfo {
        {
            transfer = refund.transfer;
            status = status;
            err = err;
            relatedIndex = refund.relatedIndex;
        }
    };

    public func start(token: Principal, from: Types.Account, to: Types.Account, amount: Nat, fee: Nat, memo: ?Blob, relatedIndex: Nat, standard: Text): Types.RefundInfo {
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
            relatedIndex = relatedIndex;
            err = null;
        }, #Created, null)
    };

    public func process(refund: Types.RefundInfo): Types.RefundInfo {
        switch (refund.status) {
            case (#Created) _updateStatus(refund, #CreditCompleted, null);
            case (#CreditCompleted) _updateStatus(refund, #Completed, null);
            case (#Completed or #Failed) refund;
        }
    };

    public func fail(refund: Types.RefundInfo, error: Text): Types.RefundInfo {
        assert(refund.status != #Completed);
        _updateStatus(refund, #Failed, ?error)
    };
};