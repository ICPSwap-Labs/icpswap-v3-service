import Types "./Types";
import Nat "mo:base/Nat";
import Text "mo:base/Text";

module {
    public func start(positionId: Nat, token0: Types.Token, token1: Types.Token): Types.RemoveLimitOrderInfo {
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

    public func process(info: Types.RemoveLimitOrderInfo): Types.RemoveLimitOrderInfo {
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
                    status = #LimitOrderDeleted;
                    err = null;
                    tickLimit = info.tickLimit;
                };
            };
            case (#LimitOrderDeleted) {
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

    public func fail(info: Types.RemoveLimitOrderInfo, error: Text): Types.RemoveLimitOrderInfo {
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