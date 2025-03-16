import Types "./Types";
import Principal "mo:base/Principal";
import Nat "mo:base/Nat";
import Text "mo:base/Text";
import Blob "mo:base/Blob";
import Transfer "./Transfer";

module {
    public func start(token: Principal, from: Types.Account, to: Types.Account, amount: Nat, fee: Nat, memo: ?Blob): Types.WithdrawInfo {
        return {
            transfer = Transfer.start(token, from, to, amount, fee, memo);
            status = #Created;
        };
    };

    public func process(withdraw: Types.WithdrawInfo): Types.WithdrawInfo {
        assert(withdraw.status == #Created);
        let transfer = Transfer.process(withdraw.transfer);
        return {
            transfer = transfer;
            status = #Processing;
        };
    };

    public func success(withdraw: Types.WithdrawInfo, transferIndex: Nat): Types.WithdrawInfo {
        assert(withdraw.status == #Processing);
        let transfer = Transfer.complete(withdraw.transfer, transferIndex);
        return {
            transfer = transfer;
            status = #Completed;
        };
    };

    public func fail(withdraw: Types.WithdrawInfo, error: Text): Types.WithdrawInfo {
        assert(withdraw.status == #Processing);
        let transfer = Transfer.fail(withdraw.transfer, error);
        return {
            transfer = transfer;
            status = #Failed(error);
        };
    };
};