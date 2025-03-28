import Types "./Types";
import Nat "mo:base/Nat";
import Text "mo:base/Text";

module {
    public func start(positionId: Nat): Types.ExecuteLimitOrderInfo {
        return {
            positionId = positionId;
            status = #Created;
            err = null;
        };
    };

    public func process(info: Types.ExecuteLimitOrderInfo): Types.ExecuteLimitOrderInfo {
        switch (info.status) {
            case (#Created) {
                return {
                    positionId = info.positionId;
                    status = #ExecuteLimitOrderCompleted;
                    err = null;
                };
            };
            case (#ExecuteLimitOrderCompleted) {
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

    public func fail(info: Types.ExecuteLimitOrderInfo, error: Text): Types.ExecuteLimitOrderInfo {
        assert(info.status != #Completed);
        return {
            positionId = info.positionId;
            status = #Failed;
            err = ?error;
        };
    };

}; 