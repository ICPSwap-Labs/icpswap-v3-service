import Types "./Types";
import Nat "mo:base/Nat";
import Text "mo:base/Text";

module {
    public func start(positionId: Nat, token0: Types.Token, token1: Types.Token): Types.ExecuteLimitOrderInfo {
        return {
            positionId = positionId;
            token0 = token0;
            token1 = token1;
            token0AmountIn = 0;
            token1AmountIn = 0;
            token0AmountOut = 0;
            token1AmountOut = 0;
            status = #Created;
            err = null;
            tickLimit = 0;
        };
    };

    public func process(info: Types.ExecuteLimitOrderInfo): Types.ExecuteLimitOrderInfo {
        switch (info.status) {
            case (#Created) {
                return {
                    positionId = info.positionId;
                    token0 = info.token0;
                    token1 = info.token1;
                    token0AmountIn = info.token0AmountIn;
                    token1AmountIn = info.token1AmountIn;
                    token0AmountOut = info.token0AmountOut;
                    token1AmountOut = info.token1AmountOut;
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

    public func fail(info: Types.ExecuteLimitOrderInfo, error: Text): Types.ExecuteLimitOrderInfo {
        assert(info.status != #Completed);
        return {
            positionId = info.positionId;
            token0 = info.token0;
            token1 = info.token1;
            token0AmountIn = info.token0AmountIn;
            token1AmountIn = info.token1AmountIn;
            token0AmountOut = info.token0AmountOut;
            token1AmountOut = info.token1AmountOut;
            status = #Failed;
            err = ?error;
            tickLimit = info.tickLimit;
        };
    };

}; 