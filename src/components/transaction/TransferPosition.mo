import Types "./Types";
import Nat "mo:base/Nat";
import Text "mo:base/Text";

module {
    private func _updateStatus(info: Types.TransferPositionInfo, status: Types.TransferPositionStatus, err: ?Text): Types.TransferPositionInfo {
        {
            positionId = info.positionId;
            from = info.from;
            to = info.to;
            token0Amount = info.token0Amount;
            token1Amount = info.token1Amount;
            status = status;
            err = err;
        }
    };

    public func start(positionId: Nat, from: Types.Account, to: Types.Account): Types.TransferPositionInfo {
        _updateStatus({
            positionId = positionId;
            from = from;
            to = to;
            token0Amount = 0;
            token1Amount = 0;
            status = #Created;
            err = null;
        }, #Created, null)
    };

    public func process(info: Types.TransferPositionInfo): Types.TransferPositionInfo {
        switch (info.status) {
            case (#Created) _updateStatus(info, #Completed, null);
            case (#Completed or #Failed) info;
        }
    };

    public func fail(info: Types.TransferPositionInfo, error: Text): Types.TransferPositionInfo {
        assert(info.status != #Completed);
        _updateStatus(info, #Failed, ?error)
    };
};
