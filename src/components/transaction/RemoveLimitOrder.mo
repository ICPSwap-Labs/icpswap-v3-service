import Types "./Types";
import Nat "mo:base/Nat";
import Text "mo:base/Text";

module {
    private func _updateStatus(info: Types.RemoveLimitOrderInfo, status: Types.RemoveLimitOrderStatus, err: ?Text): Types.RemoveLimitOrderInfo {
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

    public func start(positionId: Nat, token0: Types.Token, token1: Types.Token): Types.RemoveLimitOrderInfo {
        _updateStatus({
            positionId = positionId;
            token0 = token0;
            token1 = token1;
            token0AmountIn = 0;
            token1AmountIn = 0;
            token0AmountOut = 0;
            token1AmountOut = 0;
            tickLimit = 0;
            status = #Created;
            err = null;
        }, #Created, null)
    };

    public func process(info: Types.RemoveLimitOrderInfo): Types.RemoveLimitOrderInfo {
        switch (info.status) {
            case (#Created) _updateStatus(info, #LimitOrderDeleted, null);
            case (#LimitOrderDeleted) _updateStatus(info, #Completed, null);
            case (#Completed or #Failed) info;
        }
    };

    public func fail(info: Types.RemoveLimitOrderInfo, error: Text): Types.RemoveLimitOrderInfo {
        assert(info.status != #Completed);
        _updateStatus(info, #Failed, ?error)
    };
}; 