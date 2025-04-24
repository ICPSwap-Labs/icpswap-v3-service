import Types "./Types";
import Text "mo:base/Text";

module {
    private func _updateStatus(info: Types.SwapInfo, status: Types.SwapStatus, err: ?Text): Types.SwapInfo {
        {
            tokenIn = info.tokenIn;
            tokenOut = info.tokenOut;
            amountIn = info.amountIn;
            amountOut = info.amountOut;
            amountInFee = info.amountInFee;
            amountOutFee = info.amountOutFee;
            status = status;
            err = err;
        }
    };

    public func start(tokenIn: Types.Token, tokenOut: Types.Token, amountIn: Types.Amount): Types.SwapInfo {
        _updateStatus({
            tokenIn = tokenIn;
            tokenOut = tokenOut;
            amountIn = amountIn;
            amountOut = 0;
            amountInFee = 0;
            amountOutFee = 0;
            status = #Created;
            err = null;
        }, #Created, null)
    };

    public func process(info: Types.SwapInfo): Types.SwapInfo {
        switch (info.status) {
            case (#Created) _updateStatus(info, #Completed, null);
            case (#Completed or #Failed) info;
        }
    };

    public func fail(info: Types.SwapInfo, error: Text): Types.SwapInfo {
        assert(info.status != #Completed);
        _updateStatus(info, #Failed, ?error)
    };
};