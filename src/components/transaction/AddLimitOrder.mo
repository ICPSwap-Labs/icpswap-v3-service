import Types "./Types";
import Nat "mo:base/Nat";
import Text "mo:base/Text";

module {
    public func start(positionId: Nat, token0: Types.Token, token1: Types.Token, amount0: Nat, amount1: Nat, tickLimit: Int): Types.AddLimitOrderInfo {
        return {
            positionId = positionId;
            token0 = token0;
            token1 = token1;
            token0AmountIn = amount0;
            token1AmountIn = amount1;
            tickLimit = tickLimit;
            status = #Created;
            err = null;
        };
    };

    public func process(info: Types.AddLimitOrderInfo): Types.AddLimitOrderInfo {
        switch (info.status) {
            case (#Created) {
                return {
                    positionId = info.positionId;
                    token0 = info.token0;
                    token1 = info.token1;
                    token0AmountIn = info.token0AmountIn;
                    token1AmountIn = info.token1AmountIn;
                    status = #Completed;
                    err = null;
                    tickLimit = info.tickLimit;
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
            token0 = info.token0;
            token1 = info.token1;
            token0AmountIn = info.token0AmountIn;
            token1AmountIn = info.token1AmountIn;
            status = #Failed;
            err = ?error;
            tickLimit = info.tickLimit;
        };
    };

}; 