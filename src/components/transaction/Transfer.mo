import Types "./Types";
import Principal "mo:base/Principal";
import Nat "mo:base/Nat";
import Text "mo:base/Text";
import Blob "mo:base/Blob";

module {
    public func start(token: Principal, from: Types.Account, to: Types.Account, amount: Nat, fee: Nat, memo: ?Blob): Types.Transfer {
        return {
            token = token;
            from = from;
            to = to;
            amount = amount;
            fee = fee;
            memo = memo;
            status = #Created;
        };
    };

    public func startAndProcess(token: Principal, from: Types.Account, to: Types.Account, amount: Nat, fee: Nat, memo: ?Blob): Types.Transfer {
        return {
            token = token;
            from = from;
            to = to;
            amount = amount;
            fee = fee;
            memo = memo;
            status = #Processing;
        };
    };

    public func process(transfer: Types.Transfer): Types.Transfer {
        assert(transfer.status == #Created);
        return {
            token = transfer.token;
            from = transfer.from;
            to = transfer.to;
            amount = transfer.amount;
            fee = transfer.fee;
            memo = transfer.memo;
            status = #Processing;
        };
    };

    public func complete(transfer: Types.Transfer, index: Nat): Types.Transfer {
        assert(transfer.status == #Processing);
        return {
            token = transfer.token;
            from = transfer.from;
            to = transfer.to;
            amount = transfer.amount;
            fee = transfer.fee;
            memo = transfer.memo;
            status = #Completed(index);
        };
    };

    public func fail(transfer: Types.Transfer, error: Text): Types.Transfer {
        assert(transfer.status == #Processing);
        return {
            token = transfer.token;
            from = transfer.from;
            to = transfer.to;
            amount = transfer.amount;
            fee = transfer.fee;
            memo = transfer.memo;
            status = #Failed(error);
        };
    };
};