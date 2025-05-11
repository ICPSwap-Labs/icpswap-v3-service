import Types "./Types";
import Principal "mo:base/Principal";
import Nat "mo:base/Nat";
import Text "mo:base/Text";
import Blob "mo:base/Blob";

module {
    private func _updateStatus(deposit: Types.DepositInfo, status: Types.DepositStatus, err: ?Text): Types.DepositInfo {
        {
            transfer = deposit.transfer;
            status = status;
            err = err;
        }
    };

    public func start(token: Principal, from: Types.Account, to: Types.Account, amount: Nat, fee: Nat, memo: ?Blob, standard: Text): Types.DepositInfo {
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
            err = null;
        }, #Created, null)
    };

    public func process(deposit: Types.DepositInfo): Types.DepositInfo {
        switch (deposit.status) {
            case (#Created) {
                if (deposit.transfer.amount == 0) {
                    _updateStatus(deposit, #Completed, null)
                } else {
                    _updateStatus(deposit, #TransferCompleted, null)
                }
            };
            case (#TransferCompleted) _updateStatus(deposit, #Completed, null);
            case (#Completed or #Failed) deposit;
        }
    };

    public func fail(deposit: Types.DepositInfo, error: Text): Types.DepositInfo {
        assert(deposit.status != #Completed);
        _updateStatus(deposit, #Failed, ?error)
    };
};