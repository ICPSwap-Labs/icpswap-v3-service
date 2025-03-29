import Types "./Types";
import Principal "mo:base/Principal";
import Nat "mo:base/Nat";
import Text "mo:base/Text";
import Blob "mo:base/Blob";

module {
    public func start(token: Principal, from: Types.Account, to: Types.Account, amount: Nat, fee: Nat, memo: ?Blob): Types.DepositInfo {
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

    public func process(deposit: Types.DepositInfo): Types.DepositInfo {
        switch (deposit.status) {
            case (#Created) {
                if (deposit.transfer.amount == 0) {
                    return {
                        transfer = deposit.transfer;
                        status = #Completed;
                        err = null;
                    };
                };
                return {
                    transfer = deposit.transfer;
                    status = #TransferCompleted;
                    err = null;
                };
            };
            case (#TransferCompleted) {
                return {
                    transfer = deposit.transfer;
                    status = #Completed;
                    err = null;
                };
            };
            case (#Completed) {
                return deposit;
            };
            case (#Failed) {
                return deposit;
            };
        };
    };

    public func fail(deposit: Types.DepositInfo, error: Text): Types.DepositInfo {
        assert(deposit.status != #Completed);
        return {
            transfer = deposit.transfer;
            status = #Failed;
            err = ?error;
        };
    };
    
};