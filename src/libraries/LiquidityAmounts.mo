import Nat "mo:base/Nat";
import Error "mo:base/Error";
import SafeUint "mo:commons/math/SafeUint";
import UintUtils "mo:commons/math/SafeUint/UintUtils";
import FullMath "./FullMath";
import FixedPoint96 "./FixedPoint96";

module {

    type Uint128 = Nat;
    type Uint256 = Nat;

    public func getLiquidityForAmount0(
        sqrtRatioAX96: SafeUint.Uint160, 
        sqrtRatioBX96: SafeUint.Uint160, 
        amount0: SafeUint.Uint256
    ): Uint128 {
        var _sqrtRatioAX96 = if(sqrtRatioAX96.val() > sqrtRatioBX96.val()){ sqrtRatioBX96 } else{ sqrtRatioAX96 };
        var _sqrtRatioBX96 = if(sqrtRatioAX96.val() > sqrtRatioBX96.val()){ sqrtRatioAX96 } else{ sqrtRatioBX96 };

        var _intermediate = FullMath.mulDiv(
            SafeUint.Uint256(_sqrtRatioAX96.val()), 
            SafeUint.Uint256(_sqrtRatioBX96.val()), 
            SafeUint.Uint256(FixedPoint96.Q96)
        );
        
        return SafeUint.Uint128(FullMath.mulDiv(
            amount0,
            SafeUint.Uint256(_intermediate),
            SafeUint.Uint256(_sqrtRatioBX96.sub(_sqrtRatioAX96).val())
        )).val();
    };

    public func getLiquidityForAmount1(
        sqrtRatioAX96: SafeUint.Uint160, 
        sqrtRatioBX96: SafeUint.Uint160, 
        amount1: SafeUint.Uint256
    ): Uint128 {
        var _sqrtRatioAX96 = if(sqrtRatioAX96.val() > sqrtRatioBX96.val()){ sqrtRatioBX96 } else{ sqrtRatioAX96 };
        var _sqrtRatioBX96 = if(sqrtRatioAX96.val() > sqrtRatioBX96.val()){ sqrtRatioAX96 } else{ sqrtRatioBX96 };

        return SafeUint.Uint128(FullMath.mulDiv(
            amount1,
            SafeUint.Uint256(FixedPoint96.Q96), 
            SafeUint.Uint256(_sqrtRatioBX96.sub(_sqrtRatioAX96).val())
        )).val();
    };

    public func getLiquidityForAmounts(
        sqrtRatioX96: SafeUint.Uint160, 
        sqrtRatioAX96: SafeUint.Uint160, 
        sqrtRatioBX96: SafeUint.Uint160, 
        amount0: SafeUint.Uint256, 
        amount1: SafeUint.Uint256
    ): Uint128 {
        var _sqrtRatioAX96 = if(sqrtRatioAX96.val() > sqrtRatioBX96.val()){ sqrtRatioBX96 } else{ sqrtRatioAX96 };
        var _sqrtRatioBX96 = if(sqrtRatioAX96.val() > sqrtRatioBX96.val()){ sqrtRatioAX96 } else{ sqrtRatioBX96 };

        var _liquidity = 0;

        if (sqrtRatioX96.val() <= _sqrtRatioAX96.val()) {
            _liquidity := getLiquidityForAmount0(_sqrtRatioAX96, _sqrtRatioBX96, amount0);
        } else if (sqrtRatioX96.val() < _sqrtRatioBX96.val()) {
            var _liquidity0 = getLiquidityForAmount0(sqrtRatioX96, _sqrtRatioBX96, amount0);
            var _liquidity1 = getLiquidityForAmount1(_sqrtRatioAX96, sqrtRatioX96, amount1);

            _liquidity := if (_liquidity0 < _liquidity1) { _liquidity0 } else { _liquidity1 };
        } else {
            _liquidity := getLiquidityForAmount1(_sqrtRatioAX96, _sqrtRatioBX96, amount1);
        };
        return _liquidity;
    };

    public func getAmount0ForLiquidity(
        sqrtRatioAX96: SafeUint.Uint160,
        sqrtRatioBX96: SafeUint.Uint160,
        liquidity: SafeUint.Uint128
    ): Uint256{
        var _sqrtRatioAX96 = if(sqrtRatioAX96.val() > sqrtRatioBX96.val()){ sqrtRatioBX96 } else{ sqrtRatioAX96 };
        var _sqrtRatioBX96 = if(sqrtRatioAX96.val() > sqrtRatioBX96.val()){ sqrtRatioAX96 } else{ sqrtRatioBX96 };
        
        return SafeUint.Uint256(FullMath.mulDiv(
                SafeUint.Uint256(liquidity.val()).bitshiftLeft(FixedPoint96.RESOLUTION),
                SafeUint.Uint256(_sqrtRatioBX96.sub(_sqrtRatioAX96).val()),
                SafeUint.Uint256(_sqrtRatioBX96.val())
            )).div(_sqrtRatioAX96).val();
    };

    public func getAmount1ForLiquidity(
        sqrtRatioAX96: SafeUint.Uint160,
        sqrtRatioBX96: SafeUint.Uint160,
        liquidity: SafeUint.Uint128
    ): Uint256{
        var _sqrtRatioAX96 = if(sqrtRatioAX96.val() > sqrtRatioBX96.val()){ sqrtRatioBX96 } else{ sqrtRatioAX96 };
        var _sqrtRatioBX96 = if(sqrtRatioAX96.val() > sqrtRatioBX96.val()){ sqrtRatioAX96 } else{ sqrtRatioBX96 };
        
        return FullMath.mulDiv(
            SafeUint.Uint256(liquidity.val()),
            SafeUint.Uint256(_sqrtRatioBX96.sub(_sqrtRatioAX96).val()), 
            SafeUint.Uint256(FixedPoint96.Q96)
        );
    };

    public func getAmountsForLiquidity(
        sqrtRatioX96: SafeUint.Uint160,
        sqrtRatioAX96: SafeUint.Uint160,
        sqrtRatioBX96: SafeUint.Uint160,
        liquidity: SafeUint.Uint128
    ) : { amount0: Uint256; amount1: Uint256 } {
        var _sqrtRatioAX96 = if(sqrtRatioAX96.val() > sqrtRatioBX96.val()){ sqrtRatioBX96 } else{ sqrtRatioAX96 };
        var _sqrtRatioBX96 = if(sqrtRatioAX96.val() > sqrtRatioBX96.val()){ sqrtRatioAX96 } else{ sqrtRatioBX96 };

        var amount0 = 0;
        var amount1 = 0;

        if (sqrtRatioX96.val() <= _sqrtRatioAX96.val()) {
            amount0 := getAmount0ForLiquidity(_sqrtRatioAX96, _sqrtRatioBX96, liquidity);
        } else if (sqrtRatioX96.val() < _sqrtRatioBX96.val()) {
            amount0 := getAmount0ForLiquidity(sqrtRatioX96, _sqrtRatioBX96, liquidity);
            amount1 := getAmount1ForLiquidity(_sqrtRatioAX96, sqrtRatioX96, liquidity);
        } else {
            amount1 := getAmount1ForLiquidity(_sqrtRatioAX96, _sqrtRatioBX96, liquidity);
        };

        return {
            amount0 = amount0;
            amount1 = amount1;
        };
    }
}
