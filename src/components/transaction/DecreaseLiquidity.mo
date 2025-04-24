import Types "./Types";
import Nat "mo:base/Nat";
import Text "mo:base/Text";

module {
    private func _updateStatus(info: Types.DecreaseLiquidityInfo, status: Types.DecreaseLiquidityStatus, err: ?Text): Types.DecreaseLiquidityInfo {
        {
            positionId = info.positionId;
            token0 = info.token0;
            token1 = info.token1;
            amount0 = info.amount0;
            amount1 = info.amount1;
            liquidity = info.liquidity;
            status = status;
            err = err;
        }
    };

    public func start(positionId: Nat, token0: Types.Token, token1: Types.Token, liquidity: Nat): Types.DecreaseLiquidityInfo {
        _updateStatus({
            positionId = positionId;
            token0 = token0;
            token1 = token1;
            amount0 = 0;
            amount1 = 0;
            liquidity = liquidity;
            status = #Created;
            err = null;
        }, #Created, null)
    };

    public func process(info: Types.DecreaseLiquidityInfo): Types.DecreaseLiquidityInfo {
        switch (info.status) {
            case (#Created) _updateStatus(info, #Completed, null);
            case (#Completed or #Failed) info;
        }
    };

    public func fail(info: Types.DecreaseLiquidityInfo, error: Text): Types.DecreaseLiquidityInfo {
        assert(info.status != #Completed);
        _updateStatus(info, #Failed, ?error)
    };
};