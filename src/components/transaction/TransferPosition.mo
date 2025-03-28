import Types "./Types";
import Nat "mo:base/Nat";
import Text "mo:base/Text";

module {
    public func start(positionId: Nat, from: Types.Account, to: Types.Account): Types.TransferPositionInfo {
        return {
            positionId = positionId;
            from = from;
            to = to;
            status = #Created;
            err = null;
        };
    };

    public func process(info: Types.TransferPositionInfo): Types.TransferPositionInfo {
        switch (info.status) {
            case (#Created) {
                return {
                    positionId = info.positionId;
                    from = info.from;
                    to = info.to;
                    status = #Completed;
                    err = null;
                };
            };
            case (#Completed) {
                return info;
            };
            case (#Failed) {
                return info;
            };
        };
    };

    public func fail(info: Types.TransferPositionInfo, error: Text): Types.TransferPositionInfo {
        assert(info.status != #Completed);
        return {
            positionId = info.positionId;
            from = info.from;
            to = info.to;
            status = #Failed;
            err = ?error;
        };
    };

};
