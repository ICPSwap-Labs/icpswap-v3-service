import Result "mo:base/Result";
import Types "./Types";

import Refund "Refund";
module {
    public func start(positionId : Nat, token0 : Principal, token1 : Principal): Types.DecreaseLiquidityInfo {
        return {
            positionId = positionId;
            token0 = token0;
            token1 = token1;
            amount0 = 0;
            amount1 = 0;
            status = #Created;
            withdraw0 = null;
            withdraw1 = null;
        };
    };
    public func success(decreaseLiquidity : Types.DecreaseLiquidityInfo, amount0 : Nat, amount1 : Nat): Result.Result<Types.DecreaseLiquidityInfo, Text> {
        return #ok({
            positionId = decreaseLiquidity.positionId;
            token0 = decreaseLiquidity.token0;
            token1 = decreaseLiquidity.token1;
            amount0 = amount0;
            amount1 = amount1;
            status = #DecreaseSuccess;
            withdraw0 = decreaseLiquidity.withdraw0;
            withdraw1 = decreaseLiquidity.withdraw1;
        });
    };
    public func fail(decreaseLiquidity : Types.DecreaseLiquidityInfo, error : Text): Result.Result<Types.DecreaseLiquidityInfo, Text> {
        return #ok({
            positionId = decreaseLiquidity.positionId;
            token0 = decreaseLiquidity.token0;
            token1 = decreaseLiquidity.token1;
            amount0 = decreaseLiquidity.amount0;
            amount1 = decreaseLiquidity.amount1;
            status = #Failed(error);
            withdraw0 = decreaseLiquidity.withdraw0;
            withdraw1 = decreaseLiquidity.withdraw1;
        });
    };
    public func startWithdrawToken0(decreaseLiquidity : Types.DecreaseLiquidityInfo, withdraw : Types.WithdrawInfo): Result.Result<Types.DecreaseLiquidityInfo, Text> {
        return #ok({
            positionId = decreaseLiquidity.positionId;
            token0 = decreaseLiquidity.token0;
            token1 = decreaseLiquidity.token1;
            amount0 = decreaseLiquidity.amount0;
            amount1 = decreaseLiquidity.amount1;
            status = #Withdraw0Processing;
            withdraw0 = ?withdraw;
            withdraw1 = decreaseLiquidity.withdraw1;
        });
    };
    public func completeWithdrawToken0(decreaseLiquidity : Types.DecreaseLiquidityInfo, withdraw : Types.WithdrawInfo): Result.Result<Types.DecreaseLiquidityInfo, Text> {
        return #ok({
            positionId = decreaseLiquidity.positionId;
            token0 = decreaseLiquidity.token0;
            token1 = decreaseLiquidity.token1;
            amount0 = decreaseLiquidity.amount0;
            amount1 = decreaseLiquidity.amount1;
            status = #Withdraw0Completed;
            withdraw0 = ?withdraw;
            withdraw1 = decreaseLiquidity.withdraw1;
        });
    };
    public func failWithdrawToken0(decreaseLiquidity : Types.DecreaseLiquidityInfo, withdraw : Types.WithdrawInfo): Result.Result<Types.DecreaseLiquidityInfo, Text> {
        return #ok({
            positionId = decreaseLiquidity.positionId;
            token0 = decreaseLiquidity.token0;
            token1 = decreaseLiquidity.token1;
            amount0 = decreaseLiquidity.amount0;
            amount1 = decreaseLiquidity.amount1;
            status = #Failed("Withdraw0Failed");
            withdraw0 = ?withdraw;
            withdraw1 = decreaseLiquidity.withdraw1;  
        });
    };
    public func startWithdrawToken1(decreaseLiquidity : Types.DecreaseLiquidityInfo, withdraw : Types.WithdrawInfo): Result.Result<Types.DecreaseLiquidityInfo, Text> {
        return #ok({
            positionId = decreaseLiquidity.positionId;
            token0 = decreaseLiquidity.token0;
            token1 = decreaseLiquidity.token1;
            amount0 = decreaseLiquidity.amount0;
            amount1 = decreaseLiquidity.amount1;
            status = #Withdraw1Processing;
            withdraw0 = decreaseLiquidity.withdraw0;
            withdraw1 = ?withdraw;
        });
    };
    public func completeWithdrawToken1(decreaseLiquidity : Types.DecreaseLiquidityInfo, withdraw : Types.WithdrawInfo): Result.Result<Types.DecreaseLiquidityInfo, Text> {
        return #ok({
            positionId = decreaseLiquidity.positionId;
            token0 = decreaseLiquidity.token0;
            token1 = decreaseLiquidity.token1;
            amount0 = decreaseLiquidity.amount0;
            amount1 = decreaseLiquidity.amount1;
            status = #Withdraw1Completed;
            withdraw0 = decreaseLiquidity.withdraw0;
            withdraw1 = ?withdraw;
        });
    };
    public func failWithdrawToken1(decreaseLiquidity : Types.DecreaseLiquidityInfo, withdraw : Types.WithdrawInfo): Result.Result<Types.DecreaseLiquidityInfo, Text> {
        return #ok({
            positionId = decreaseLiquidity.positionId;
            token0 = decreaseLiquidity.token0;
            token1 = decreaseLiquidity.token1;
            amount0 = decreaseLiquidity.amount0;
            amount1 = decreaseLiquidity.amount1;
            status = #Failed("Withdraw1Failed");
            withdraw0 = decreaseLiquidity.withdraw0;
            withdraw1 = ?withdraw;
        });
    };
    public func complete(decreaseLiquidity : Types.DecreaseLiquidityInfo): Result.Result<Types.DecreaseLiquidityInfo, Text> {
        return #ok({
            positionId = decreaseLiquidity.positionId;
            token0 = decreaseLiquidity.token0;
            token1 = decreaseLiquidity.token1;
            amount0 = decreaseLiquidity.amount0;
            amount1 = decreaseLiquidity.amount1;
            status = #Completed;
            withdraw0 = decreaseLiquidity.withdraw0;
            withdraw1 = decreaseLiquidity.withdraw1;
        });
    };
    public func successAndComplete(decreaseLiquidity : Types.DecreaseLiquidityInfo, amount0: Nat, amount1: Nat): Result.Result<Types.DecreaseLiquidityInfo, Text> {
        return #ok({
            positionId = decreaseLiquidity.positionId;
            token0 = decreaseLiquidity.token0;
            token1 = decreaseLiquidity.token1;
            amount0 = amount0;
            amount1 = amount1;
            status = #Completed;
            withdraw0 = decreaseLiquidity.withdraw0;
            withdraw1 = decreaseLiquidity.withdraw1;
        });
    };
}