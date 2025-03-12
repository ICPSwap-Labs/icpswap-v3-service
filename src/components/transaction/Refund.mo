import Types "./Types";
import Principal "mo:base/Principal";
import Nat "mo:base/Nat";
import Text "mo:base/Text";
import Blob "mo:base/Blob";
import Transfer "./Transfer";
import Result "mo:base/Result";

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
    public func process(refund: Types.RefundInfo): Result.Result<Types.RefundInfo, Text> {
        switch (refund.status) {
            case (#Created) {
                switch (Transfer.process(refund.transfer)) {
                    case (#ok(transfer)) {
                        return #ok({
                            token = refund.token;
                            transfer = transfer;
                            status = #Processing;
                        });
                    };
                    case (#err(error)) {
                        return #err(error);
                    };
                };
            };
            case (_) {
                return #err("WithdrawStatusError");
            };
        };
    };
    public func success(refund: Types.RefundInfo, transferIndex: Nat): Result.Result<Types.RefundInfo, Text> {
        switch (refund.status) {
            case (#Processing) {
                switch (Transfer.complete(refund.transfer, transferIndex)) {
                    case (#ok(transfer)) {
                        return #ok({
                            token = refund.token;
                            transfer = transfer;
                            status = #Completed
                        });
                    };
                    case (#err(error)) {
                        return #err(error);
                    };
                };
            };
            case (_) {
                return #err("WithdrawStatusError");
            };
        };
    };
    public func fail(refund: Types.RefundInfo, error: Text): Result.Result<Types.RefundInfo, Text> {
        switch (refund.status) {
            case (#Processing) {
                switch (Transfer.fail(refund.transfer, error)) {
                    case (#ok(transfer)) {
                        return #ok({
                            token = refund.token;
                            transfer = transfer;
                            status = #Failed(error);
                        });
                    };
                    case (#err(error)) {
                        return #err(error);
                    };
                };
            };
            case (_) {
                return #err("WithdrawStatusError");
            };
        };
    };
};