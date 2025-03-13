import Types "./Types";
import Result "mo:base/Result";

module {
    public func start(positionId: Nat, token0: Principal, token1: Principal): Types.ClaimInfo {
        return {
            positionId = positionId;
            token0 = token0;
            token1 = token1;
            amount0 = 0;
            amount1 = 0;
            status = #Created;
        };
    };
    public func success(info: Types.ClaimInfo, amount0: Nat, amount1: Nat): Result.Result<Types.ClaimInfo, Text> {
        return #ok({
            positionId = info.positionId;
            token0 = info.token0;
            token1 = info.token1;
            amount0 = amount0;
            amount1 = amount1;
            status = #Completed;
        });
    };
    public func fail(info: Types.ClaimInfo, error: Text): Result.Result<Types.ClaimInfo, Text> {
        return #ok({
            positionId = info.positionId; 
            token0 = info.token0;
            token1 = info.token1;
            amount0 = info.amount0;
            amount1 = info.amount1;
            status = #Failed(error);
        });
    };
    public func complete(info: Types.ClaimInfo): Result.Result<Types.ClaimInfo, Text> {
        return #ok({
            positionId = info.positionId;
            token0 = info.token0;
            token1 = info.token1;
            amount0 = info.amount0; 
            amount1 = info.amount1;
            status = #Completed;
        });
    };
    public func successAndComplete(info: Types.ClaimInfo, amount0: Nat, amount1: Nat): Result.Result<Types.ClaimInfo, Text> {
        return #ok({
            positionId = info.positionId;
            token0 = info.token0;
            token1 = info.token1;
            amount0 = amount0;  
            amount1 = amount1;
            status = #Completed;
        });
    };
};
