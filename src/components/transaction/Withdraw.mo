import Types "./Types";
import Principal "mo:base/Principal";
import Nat "mo:base/Nat";
import Text "mo:base/Text";
import Blob "mo:base/Blob";
import Transfer "./Transfer";
import Result "mo:base/Result";

module {
    public func start(token: Principal, from: Types.Account, to: Types.Account, amount: Nat, fee: Nat, memo: ?Blob): Types.WithdrawInfo {
        return {
            transfer = Transfer.start(token, from, to, amount, fee, memo);
            status = #Created;
        };
    };
    public func process(withdraw: Types.WithdrawInfo): Result.Result<Types.WithdrawInfo, Text> {
        switch (withdraw.status) {
            case (#Created) {
                switch (Transfer.process(withdraw.transfer)) {
                    case (#ok(transfer)) {
                        return #ok({
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
    public func success(withdraw: Types.WithdrawInfo, transferIndex: Nat): Result.Result<Types.WithdrawInfo, Text> {
        switch (withdraw.status) {
            case (#Processing) {
                switch (Transfer.complete(withdraw.transfer, transferIndex)) {
                    case (#ok(transfer)) {
                        return #ok({
                            transfer = transfer;
                            status = #Completed;
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
    public func fail(withdraw: Types.WithdrawInfo, error: Text): Result.Result<Types.WithdrawInfo, Text> {
        switch (withdraw.status) {
            case (#Processing) {
                switch (Transfer.fail(withdraw.transfer, error)) {
                    case (#ok(transfer)) {
                        return #ok({
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