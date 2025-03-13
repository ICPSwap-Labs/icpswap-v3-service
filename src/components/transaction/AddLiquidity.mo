import Types "./Types";
import Result "mo:base/Result";

module {
    public func start(token0: Principal, token1: Principal) : Types.AddLiquidityInfo {
        return {
            token0 = token0;
            token1 = token1;
            amount0 = 0;
            amount1 = 0;
            deposit0 = null;
            deposit1 = null;
            positionId = 0;
            status = #Created;
        };
    };

    public func startDepositToken0(info: Types.AddLiquidityInfo, depositInfo: Types.DepositInfo) : Result.Result<Types.AddLiquidityInfo, Types.Error> {
        switch (info.status) {
            case (#Created) {
                return #ok({
                    token0 = info.token0;
                    token1 = info.token1;
                    amount0 = info.amount0;
                    amount1 = info.amount1;
                    deposit0 = ?depositInfo;
                    deposit1 = info.deposit1;
                    positionId = info.positionId;
                    status = #Token0DepositProcessing;
                });
            };
            case (_) {
                return #err("InvalidStatus: " # debug_show(info.status));
            };
        };
    };
    public func completeDepositToken0(info: Types.AddLiquidityInfo, depositInfo: Types.DepositInfo) : Result.Result<Types.AddLiquidityInfo, Types.Error> {
        switch (info.status) {
            case (#Token0DepositProcessing) {
                return #ok({
                    token0 = info.token0;
                    token1 = info.token1;
                    amount0 = info.amount0;
                    amount1 = info.amount1;
                    deposit0 = ?depositInfo;
                    deposit1 = info.deposit1;
                    positionId = info.positionId;
                    status = #Token0DepositCompleted;
                });
            };
            case (_) {
                return #err("InvalidStatus: " # debug_show(info.status));
            };
        };
    };
    public func startDepositToken1(info: Types.AddLiquidityInfo, depositInfo: Types.DepositInfo) : Result.Result<Types.AddLiquidityInfo, Types.Error> {
        switch (info.status) {
            case (#Token0DepositCompleted or #Created) {
                return #ok({
                    token0 = info.token0; 
                    token1 = info.token1;
                    amount0 = info.amount0;
                    amount1 = info.amount1;
                    deposit0 = info.deposit0;
                    deposit1 = ?depositInfo;
                    positionId = info.positionId;
                    status = #Token1DepositProcessing;  
                });
            };
            case (_) {
                return #err("InvalidStatus: " # debug_show(info.status));
            };
        };
    };
    public func completeDepositToken1(info: Types.AddLiquidityInfo, depositInfo: Types.DepositInfo) : Result.Result<Types.AddLiquidityInfo, Types.Error> {
        switch (info.status) {
            case (#Token1DepositProcessing) {
                return #ok({
                    token0 = info.token0;
                    token1 = info.token1;
                    amount0 = info.amount0;
                    amount1 = info.amount1;
                    deposit0 = info.deposit0;
                    deposit1 = ?depositInfo;
                    positionId = info.positionId;
                    status = #Token1DepositCompleted;
                });
            };
            case (_) {
                return #err("InvalidStatus: " # debug_show(info.status));
            };
        };
    };
    public func startMintLiquidity(info: Types.AddLiquidityInfo, positionId: Nat) : Result.Result<Types.AddLiquidityInfo, Types.Error> {
        switch (info.status) {
            case (#Token1DepositCompleted) {
                return #ok({
                    token0 = info.token0; 
                    token1 = info.token1;
                    amount0 = info.amount0;
                    amount1 = info.amount1;
                    deposit0 = info.deposit0;
                    deposit1 = info.deposit1;
                    positionId = positionId; 
                    status = #LiquidityMinting;
                });
            };
            case (_) {
                return #err("InvalidStatus: " # debug_show(info.status));
            };
        };
    };  
    public func complete(info: Types.AddLiquidityInfo, amount0: Nat, amount1: Nat) : Result.Result<Types.AddLiquidityInfo, Types.Error> {
        switch (info.status) {
            case (#LiquidityMinting) {
                return #ok({
                    token0 = info.token0;   
                    token1 = info.token1;
                    amount0 = amount0;
                    amount1 = amount1;
                    deposit0 = info.deposit0;
                    deposit1 = info.deposit1;
                    positionId = info.positionId;
                    status = #Completed;
                }); 
            };
            case (_) {
                return #err("InvalidStatus: " # debug_show(info.status));
            };
        };
    };
    public func fail(info: Types.AddLiquidityInfo, error: Types.Error) : Result.Result<Types.AddLiquidityInfo, Types.Error> {
        switch (info.status) {
            case (#LiquidityMinting) {
                return #ok({
                    token0 = info.token0;
                    token1 = info.token1;
                    amount0 = info.amount0;
                    amount1 = info.amount1;
                    deposit0 = info.deposit0;
                    deposit1 = info.deposit1;
                    positionId = info.positionId;
                    status = #Failed(error)
                });
            };
            case (_) {
                return #err("InvalidStatus: " # debug_show(info.status));
            };
        };
    };
    
    
};