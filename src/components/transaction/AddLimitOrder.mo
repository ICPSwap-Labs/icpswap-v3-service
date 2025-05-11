import Types "./Types";
import Nat "mo:base/Nat";
import Text "mo:base/Text";

module {
    private func _updateStatus(info: Types.AddLimitOrderInfo, status: Types.AddLimitOrderStatus, err: ?Text): Types.AddLimitOrderInfo {
        {
            positionId = info.positionId;
            token0 = info.token0;
            token1 = info.token1;
            token0AmountIn = info.token0AmountIn;
            token1AmountIn = info.token1AmountIn;
            tickLimit = info.tickLimit;
            status = status;
            err = err;
        }
    };

    public func start(positionId: Nat, token0: Types.Token, token1: Types.Token, amount0: Nat, amount1: Nat, tickLimit: Int): Types.AddLimitOrderInfo {
        _updateStatus({
            positionId = positionId;
            token0 = token0;
            token1 = token1;
            token0AmountIn = amount0;
            token1AmountIn = amount1;
            tickLimit = tickLimit;
            status = #Created;
            err = null;
        }, #Created, null)
    };

    public func process(info: Types.AddLimitOrderInfo): Types.AddLimitOrderInfo {
        switch (info.status) {
            case (#Created) _updateStatus(info, #Completed, null);
            case (#Completed or #Failed) info;
        }
    };

    public func fail(info: Types.AddLimitOrderInfo, error: Text): Types.AddLimitOrderInfo {
        assert(info.status != #Completed);
        _updateStatus(info, #Failed, ?error)
    };
}; 