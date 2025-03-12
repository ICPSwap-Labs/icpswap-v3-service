import Types "./Types";
import Principal "mo:base/Principal";
import Nat "mo:base/Nat";
import Text "mo:base/Text";
import Blob "mo:base/Blob";
import Result "mo:base/Result";
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
    public func process(transfer: Types.Transfer): Result.Result<Types.Transfer, Text> {
        switch (transfer.status) {
            case (#Created) {
                return #ok({
                    token = transfer.token;
                    from = transfer.from;
                    to = transfer.to;
                    amount = transfer.amount;
                    fee = transfer.fee;
                    memo = transfer.memo;
                    status = #Processing;
                });
            };
            case (_) {
                return #err("Transfer completed");
            };
        };
    };
    public func complete(transfer: Types.Transfer, index: Nat): Result.Result<Types.Transfer, Text> {
        switch (transfer.status) {
            case (#Processing) {
                return #ok({
                    token = transfer.token;
                    from = transfer.from;
                    to = transfer.to;
                    amount = transfer.amount;
                    fee = transfer.fee;
                    memo = transfer.memo;
                    status = #Completed(index);
                });
            };
            case (_) {
                return #err("Transfer completed");
            };
        };
    };
    public func fail(transfer: Types.Transfer, error: Text): Result.Result<Types.Transfer, Text> {
        switch (transfer.status) {
            case (#Processing) {
                return #ok({
                    token = transfer.token;
                    from = transfer.from;
                    to = transfer.to;
                    amount = transfer.amount;
                    fee = transfer.fee;
                    memo = transfer.memo;
                    status = #Failed(error);
                });
            };
            case (_) {
                return #err("Transfer completed");
            };
        };
    };
};