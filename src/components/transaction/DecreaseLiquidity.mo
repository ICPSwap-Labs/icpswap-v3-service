import Types "./Types";
import Principal "mo:base/Principal";
import Nat "mo:base/Nat";
import Text "mo:base/Text";

module {
    public func start(positionId: Nat, token0: Principal, token1: Principal, liquidity: Nat): Types.DecreaseLiquidityInfo {
        return {
            positionId = positionId;
            token0 = token0;
            token1 = token1;
            amount0 = 0;
            amount1 = 0;
            liquidity = liquidity;
            status = #Created;
            err = null;
        };
    };

    public func process(info: Types.DecreaseLiquidityInfo): Types.DecreaseLiquidityInfo {
        switch (info.status) {
            case (#Created) {
                return {
                    positionId = info.positionId;
                    token0 = info.token0;
                    token1 = info.token1;
                    amount0 = info.amount0;
                    amount1 = info.amount1;
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

    public func fail(info: Types.DecreaseLiquidityInfo, error: Text): Types.DecreaseLiquidityInfo {
        assert(info.status != #Completed);
        return {
            positionId = info.positionId;
            token0 = info.token0;
            token1 = info.token1;
            amount0 = info.amount0;
            amount1 = info.amount1;
            liquidity = info.liquidity;
            status = #Failed;
            err = ?error;
        };
    };

};