import Types "./Types";

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
            liquidity = 0;
            status = #Created;
        };
    };

    public func startDepositToken0(info: Types.AddLiquidityInfo, depositInfo: Types.DepositInfo) : Types.AddLiquidityInfo {
        assert(info.status == #Created);
        return {
            token0 = info.token0;
            token1 = info.token1;
            amount0 = info.amount0;
            amount1 = info.amount1;
            deposit0 = ?depositInfo;
            deposit1 = info.deposit1;
            positionId = info.positionId;
            liquidity = info.liquidity;
            status = #Token0DepositProcessing;
        };
    };

    public func completeDepositToken0(info: Types.AddLiquidityInfo, depositInfo: Types.DepositInfo) : Types.AddLiquidityInfo {
        assert(info.status == #Token0DepositProcessing);
        return {
            token0 = info.token0;
            token1 = info.token1;
            amount0 = info.amount0;
            amount1 = info.amount1;
            deposit0 = ?depositInfo;
            deposit1 = info.deposit1;
            positionId = info.positionId;
            liquidity = info.liquidity;
            status = #Token0DepositCompleted;
        };
    };

    public func startDepositToken1(info: Types.AddLiquidityInfo, depositInfo: Types.DepositInfo) : Types.AddLiquidityInfo {
        assert(info.status == #Token0DepositCompleted or info.status == #Created);
        return {
            token0 = info.token0;
            token1 = info.token1;
            amount0 = info.amount0;
            amount1 = info.amount1;
            deposit0 = info.deposit0;
            deposit1 = ?depositInfo;
            positionId = info.positionId;
            liquidity = info.liquidity;
            status = #Token1DepositProcessing;
        };
    };

    public func completeDepositToken1(info: Types.AddLiquidityInfo, depositInfo: Types.DepositInfo) : Types.AddLiquidityInfo {
        assert(info.status == #Token1DepositProcessing);
        return {
            token0 = info.token0;
            token1 = info.token1;
            amount0 = info.amount0;
            amount1 = info.amount1;
            deposit0 = info.deposit0;
            deposit1 = ?depositInfo;
            positionId = info.positionId;
            liquidity = info.liquidity;
            status = #Token1DepositCompleted;
        };
    };

    public func startMintLiquidity(info: Types.AddLiquidityInfo, positionId: Nat) : Types.AddLiquidityInfo {
        assert(info.status == #Token1DepositCompleted);
        return {
            token0 = info.token0;
            token1 = info.token1;
            amount0 = info.amount0;
            amount1 = info.amount1;
            deposit0 = info.deposit0;
            deposit1 = info.deposit1;
            positionId = positionId;
            liquidity = info.liquidity;
            status = #LiquidityMinting;
        };
    };

    public func complete(info: Types.AddLiquidityInfo, amount0: Nat, amount1: Nat) : Types.AddLiquidityInfo {
        assert(info.status == #LiquidityMinting);
        return {
            token0 = info.token0;
            token1 = info.token1;
            amount0 = amount0;
            amount1 = amount1;
            deposit0 = info.deposit0;
            deposit1 = info.deposit1;
            positionId = info.positionId;
            liquidity = info.liquidity;
            status = #Completed;
        };
    };

    public func fail(info: Types.AddLiquidityInfo, error: Types.Error) : Types.AddLiquidityInfo {
        assert(info.status == #LiquidityMinting);
        return {
            token0 = info.token0;
            token1 = info.token1;
            amount0 = info.amount0;
            amount1 = info.amount1;
            deposit0 = info.deposit0;
            deposit1 = info.deposit1;
            positionId = info.positionId;
            liquidity = info.liquidity;
            status = #Failed(error);
        };
    };
};