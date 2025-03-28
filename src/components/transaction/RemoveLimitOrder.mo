import Types "./Types";
import Nat "mo:base/Nat";
import Text "mo:base/Text";

module {
    public func start(positionId: Nat): Types.RemoveLimitOrderInfo {
        return {
            positionId = positionId;
            status = #Created;
            err = null;
        };
    };

    public func process(info: Types.RemoveLimitOrderInfo): Types.RemoveLimitOrderInfo {
        switch (info.status) {
            case (#Created) {
                return {
                    positionId = info.positionId;
                    status = #RemoveLimitOrderCompleted;
                    err = null;
                };
            };
            case (#RemoveLimitOrderCompleted) {
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

    public func fail(info: Types.RemoveLimitOrderInfo, error: Text): Types.RemoveLimitOrderInfo {
        assert(info.status != #Completed);
        return {
            positionId = info.positionId;
            status = #Failed;
            err = ?error;
        };
    };

}; 