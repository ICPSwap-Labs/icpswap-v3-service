import Types "./Types";
import Principal "mo:base/Principal";
import Nat "mo:base/Nat";
import Text "mo:base/Text";
import Blob "mo:base/Blob";
import Transfer "./Transfer";

module {
    public func start(token: Principal, from: Types.Account, to: Types.Account, amount: Nat, fee: Nat, memo: ?Blob): Types.DepositInfo {
        return {
            transfer = Transfer.startAndProcess(token, from, to, amount, fee, memo);
            status = #Processing;
        };
    };

    public func success(deposit: Types.DepositInfo, transferIndex: Nat): Types.DepositInfo {
        assert(deposit.status == #Processing);
        let transfer = Transfer.complete(deposit.transfer, transferIndex);
        return {
            transfer = transfer;
            status = #Success;
        };
    };

    public func complete(deposit: Types.DepositInfo): Types.DepositInfo {
        assert(deposit.status == #Success);
        return {
            transfer = deposit.transfer;
            status = #Completed;
        };
    };

    public func fail(deposit: Types.DepositInfo, error: Text): Types.DepositInfo {
        assert(deposit.status == #Success);
        let transfer = Transfer.fail(deposit.transfer, error);
        return {
            transfer = transfer;
            status = #Failed(error);
        };
    };
};