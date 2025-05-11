import Types "./Types";
import Nat "mo:base/Nat";
import Text "mo:base/Text";

module {
    private func _updateStatus(info: Types.ExecuteLimitOrderInfo, status: Types.ExecuteLimitOrderStatus, err: ?Text): Types.ExecuteLimitOrderInfo {
        {
            positionId = info.positionId;
            token0 = info.token0;
            token1 = info.token1;
            token0AmountIn = info.token0AmountIn;
            token1AmountIn = info.token1AmountIn;
            token0AmountOut = info.token0AmountOut;
            token1AmountOut = info.token1AmountOut;
            tickLimit = info.tickLimit;
            status = status;
            err = err;
        }
    };

    public func start(positionId: Nat, token0: Types.Token, token1: Types.Token, token0InAmount: Nat, token1InAmount: Nat, tickLimit: Int): Types.ExecuteLimitOrderInfo {
        _updateStatus({
            positionId = positionId;
            token0 = token0;
            token1 = token1;
            token0AmountIn = token0InAmount;
            token1AmountIn = token1InAmount;
            token0AmountOut = 0;
            token1AmountOut = 0;
            tickLimit = tickLimit;
            status = #Created;
            err = null;
        }, #Created, null)
    };

    public func process(info: Types.ExecuteLimitOrderInfo): Types.ExecuteLimitOrderInfo {
        switch (info.status) {
            case (#Created) _updateStatus(info, #Completed, null);
            case (#Completed or #Failed) info;
        }
    };

    public func fail(info: Types.ExecuteLimitOrderInfo, error: Text): Types.ExecuteLimitOrderInfo {
        assert(info.status != #Completed);
        _updateStatus(info, #Failed, ?error)
    };
}; 