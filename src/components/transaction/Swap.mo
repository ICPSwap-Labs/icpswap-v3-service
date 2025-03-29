import Types "./Types";
import Principal "mo:base/Principal";
import Text "mo:base/Text";

module {
    public func start(tokenIn: Principal, tokenOut: Principal, amountIn: Types.Amount): Types.SwapInfo {
        return {
            tokenIn = tokenIn;
            tokenOut = tokenOut;
            amountIn = amountIn;
            amountOut = 0;
            status = #Created;
            err = null;
        };
    };

    public func process(info: Types.SwapInfo): Types.SwapInfo {
        switch (info.status) {
            case (#Created) {
                return {
                    tokenIn = info.tokenIn;
                    tokenOut = info.tokenOut;
                    amountIn = info.amountIn;
                    amountOut = info.amountOut;
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

    public func fail(info: Types.SwapInfo, error: Text): Types.SwapInfo {
        assert(info.status != #Completed);
        return {
            tokenIn = info.tokenIn;
            tokenOut = info.tokenOut;
            amountIn = info.amountIn;
            amountOut = info.amountOut;
            status = #Failed;
            err = ?error;
        };
    };

};