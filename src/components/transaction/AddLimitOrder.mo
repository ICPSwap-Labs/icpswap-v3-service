import Types "./Types";
import Nat "mo:base/Nat";
import Text "mo:base/Text";

module {
    public func start(positionId: Nat): Types.AddLimitOrderInfo {
        return {
            positionId = positionId;
            status = #Created;
            err = null;
        };
    };

    public func process(info: Types.AddLimitOrderInfo): Types.AddLimitOrderInfo {
        switch (info.status) {
            case (#Created) {
                return {
                    positionId = info.positionId;
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

    public func fail(info: Types.AddLimitOrderInfo, error: Text): Types.AddLimitOrderInfo {
        assert(info.status != #Completed);
        return {
            positionId = info.positionId;
            status = #Failed;
            err = ?error;
        };
    };

}; 