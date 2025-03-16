import Types "./Types";
import Principal "mo:base/Principal";
import Nat "mo:base/Nat";
import Text "mo:base/Text";
import Blob "mo:base/Blob";
import Transfer "./Transfer";

module {
    public func start(token: Principal, from: Types.Account, to: Types.Account, amount: Nat, fee: Nat, memo: ?Blob): Types.RefundInfo {
        return {
            token = token;
            transfer = Transfer.start(token, from, to, amount, fee, memo);
            status = #Created;
        };
    };

    public func startAndProcess(token: Principal, from: Types.Account, to: Types.Account, amount: Nat, fee: Nat, memo: ?Blob): Types.RefundInfo {
        return {
            token = token;
            transfer = Transfer.startAndProcess(token, from, to, amount, fee, memo);
            status = #Created;
        };
    };

    public func process(refund: Types.RefundInfo): Types.RefundInfo {
        assert(refund.status == #Created);
        return {
            token = refund.token;
            transfer = Transfer.process(refund.transfer);
            status = #Processing;
        };
    };

    public func success(refund: Types.RefundInfo, transferIndex: Nat): Types.RefundInfo {
        assert(refund.status == #Processing);
        return {
            token = refund.token;
            transfer = Transfer.complete(refund.transfer, transferIndex);
            status = #Completed;
        };
    };

    public func fail(refund: Types.RefundInfo, error: Text): Types.RefundInfo {
        assert(refund.status == #Processing);
        return {
            token = refund.token;
            transfer = Transfer.fail(refund.transfer, error);
            status = #Failed(error);
        };
    };
};