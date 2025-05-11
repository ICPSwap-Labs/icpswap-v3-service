import Types "./Types";
import Nat "mo:base/Nat";
import Text "mo:base/Text";

module {
    private func _updateStatus(info: Types.AddLiquidityInfo, status: Types.AddLiquidityStatus, err: ?Text): Types.AddLiquidityInfo {
        {
            token0 = info.token0;
            token1 = info.token1;
            amount0 = info.amount0;
            amount1 = info.amount1;
            positionId = info.positionId;
            liquidity = info.liquidity;
            status = status;
            err = err;
        }
    };

    public func start(
        token0: Types.Token, 
        token1: Types.Token, 
        amount0: Nat, 
        amount1: Nat,
        positionId: Nat
    ): Types.AddLiquidityInfo {
        _updateStatus({
            token0 = token0;
            token1 = token1;
            amount0 = amount0;
            amount1 = amount1;
            positionId = positionId;
            liquidity = 0;
            status = #Created;
            err = null;
        }, #Created, null)
    };

    public func process(info: Types.AddLiquidityInfo): Types.AddLiquidityInfo {
        switch (info.status) {
            case (#Created) _updateStatus(info, #Completed, null);
            case (#Completed or #Failed) info;
        }
    };

    public func fail(info: Types.AddLiquidityInfo, error: Text): Types.AddLiquidityInfo {
        assert(info.status != #Completed and info.status != #Failed);
        _updateStatus(info, #Failed, ?error)
    };
};