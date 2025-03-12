import Types "./Types";
import Principal "mo:base/Principal";
import Nat "mo:base/Nat";
import Text "mo:base/Text";
import Blob "mo:base/Blob";
import Result "mo:base/Result";
import Transfer "./Transfer";

module {
    public func start(token: Principal, from: Types.Account, to: Types.Account, amount: Nat, fee: Nat, memo: ?Blob): Types.DepositInfo {
        return {
            transfer = Transfer.startAndProcess(token, from, to, amount, fee, memo);
            status = #Processing;
        };
    };
    public func success(deposit: Types.DepositInfo, transferIndex: Nat): Result.Result<Types.DepositInfo, Text> {
        switch (deposit.status) {
            case (#Processing) {
                switch (Transfer.complete(deposit.transfer, transferIndex)) {
                    case (#ok(transfer)) {
                        return #ok({
                            transfer = transfer;
                            status = #Success;
                        });
                    };
                    case (#err(error)) {
                        return #err(error);
                    };
                };
            };
            case (_) {
                return #err("DepositStatusError");
            };
        };
    };
    public func complete(deposit: Types.DepositInfo): Result.Result<Types.DepositInfo, Text> {
        switch (deposit.status) {
            case (#Success) {
                return #ok({
                    transfer = deposit.transfer;
                    status = #Completed;
                });
            };
            case (_) {
                return #err("DepositStatusError");
            };
        };
    };
    public func fail(deposit: Types.DepositInfo, error: Text): Result.Result<Types.DepositInfo, Text> {
        switch (deposit.status) {
            case (#Success) {
                switch (Transfer.fail(deposit.transfer, error)) {
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
                return #err("DepositStatusError");
            };
        };
    };
};