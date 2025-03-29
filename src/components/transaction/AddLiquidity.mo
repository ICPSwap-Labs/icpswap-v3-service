import Types "./Types";
import Principal "mo:base/Principal";
import Nat "mo:base/Nat";
import Text "mo:base/Text";

module {
    public func start(
        token0: Principal, 
        token1: Principal, 
        amount0: Nat, 
        amount1: Nat,
        positionId: Nat
    ): Types.AddLiquidityInfo {
        return {
            token0 = token0;
            token1 = token1;
            amount0 = amount0;
            amount1 = amount1;
            positionId = positionId;
            liquidity = 0;
            status = #Created;
            err = null;
        };
    };

    public func process(info: Types.AddLiquidityInfo): Types.AddLiquidityInfo {
        switch (info.status) {
            case (#Created) {
                return {
                    token0 = info.token0;
                    token1 = info.token1;
                    amount0 = info.amount0;
                    amount1 = info.amount1;
                    positionId = info.positionId;
                    liquidity = info.liquidity;
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

    public func fail(info: Types.AddLiquidityInfo, error: Text): Types.AddLiquidityInfo {
        assert(info.status != #Completed and info.status != #Failed);

        return {
            token0 = info.token0;
            token1 = info.token1;
            amount0 = info.amount0;
            amount1 = info.amount1;
            positionId = info.positionId;
            liquidity = info.liquidity;
            status = #Failed;
            err = ?error;
        };
    };
};