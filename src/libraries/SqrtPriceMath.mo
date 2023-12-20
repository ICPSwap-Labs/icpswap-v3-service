import Bool "mo:base/Bool";
import Debug "mo:base/Debug";
import Int "mo:base/Int";
import Nat "mo:base/Nat";
import Nat16 "mo:base/Nat16";
import Result "mo:base/Result";

import BitwiseInt "mo:commons/math/BitwiseInt";
import BitwiseNat "mo:commons/math/BitwiseNat";
import SafeUint "mo:commons/math/SafeUint";
import SafeInt "mo:commons/math/SafeInt";
import IntUtils "mo:commons/math/SafeInt/IntUtils";

import FixedPoint96 "./FixedPoint96";
import FullMath "./FullMath";
import UnsafeMath "./UnsafeMath";


module SqrtPriceMath {

    public let MIN_SQRT_RATIO = 4295128739;
    public let MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;

    type Uint160 = Nat;
    type Uint128 = Nat;
    type Uint256 = Nat;
    type Int160 = Int;
    type Int128 = Int;
    type Int256 = Int;

    public func getNextSqrtPriceFromAmount0RoundingUp(
        sqrtPX96: SafeUint.Uint160, liquidity: SafeUint.Uint128, amount: SafeUint.Uint256, add: Bool
    ): Result.Result<Uint160, Text> {
        // we short circuit amount == 0 because the result is otherwise not guaranteed to equal the input price
        if (amount.val() == 0) return #ok(sqrtPX96.val());
        var numerator1:SafeUint.Uint256 = SafeUint.Uint256(liquidity.val()).bitshiftLeft(FixedPoint96.RESOLUTION);
        var product:SafeUint.Uint256 = amount.mul(SafeUint.Uint256(sqrtPX96.val()));
        if (add) {
            if (product.div(amount).val() == sqrtPX96.val()) {
                var denominator:SafeUint.Uint256 = numerator1.add(product);
                if (denominator.val() >= numerator1.val()) {
                    return switch(FullMath.mulDivRoundingUp(SafeUint.Uint256(numerator1.val()), SafeUint.Uint256(sqrtPX96.val()), SafeUint.Uint256(denominator.val()))) {
                        case (#ok(result)) {
                            #ok(SafeUint.Uint160(result).val());
                        };
                        case (#err(err)){
                            #err(err)
                        }
                    };
                }
            };
            return #ok(SafeUint.Uint160(
                UnsafeMath.divRoundingUp(numerator1, numerator1.div(SafeUint.Uint256(sqrtPX96.val())).add(amount))
            ).val());
        } else {
            // if the product overflows, we know the denominator underflows
            // in addition, we must check that the denominator does not underflow
            // require((product = amount * sqrtPX96) / amount == sqrtPX96 && numerator1 > product);
            if(not ((product.div(amount).val() == sqrtPX96.val()) and (numerator1.val() > product.val()))){ return #err("SqrtPriceMath illegal args"); };
            
            var denominator:SafeUint.Uint256 = numerator1.sub(product);
            return switch(FullMath.mulDivRoundingUp(SafeUint.Uint256(numerator1.val()), SafeUint.Uint256(sqrtPX96.val()), SafeUint.Uint256(denominator.val()))) {
                case (#ok(result)) {
                    #ok(SafeUint.Uint160(result).val());
                };
                case (#err(err)) {
                    #err(err)
                }
            };
        }
    };

    public func getNextSqrtPriceFromAmount1RoundingDown(
        sqrtPX96:SafeUint.Uint160, liquidity: SafeUint.Uint128, amount: SafeUint.Uint256, add: Bool
    ): Result.Result<Uint160, Text> {
        // if we're adding (subtracting), rounding down asserts rounding the quotient down (up)
        // in both cases, avoid a mulDiv for most inputs
        if (add) {
            var quotient:SafeUint.Uint256 = if (amount.val() <= SafeUint.UINT_160_MAX){
                amount.bitshiftLeft(FixedPoint96.RESOLUTION).div(liquidity);
            } else {
                SafeUint.Uint256(FullMath.mulDiv(amount, SafeUint.Uint256(FixedPoint96.Q96), SafeUint.Uint256(liquidity.val())))
            };
            return #ok(SafeUint.Uint160(
                SafeUint.Uint256(sqrtPX96.val()).add(quotient).val()
            ).val());
        } else {
            var quotient:SafeUint.Uint256 = switch (FullMath.mulDivRoundingUp(amount, SafeUint.Uint256(FixedPoint96.Q96), SafeUint.Uint256(liquidity.val()))) {
                case (#ok(result)) { SafeUint.Uint256(result); };
                case (#err(code)) { return #err("SqrtPriceMath FullMath.mulDivRoundingUp failed: " # debug_show(code)); };
            };
            if (amount.val() <= SafeUint.UINT_160_MAX){
                quotient := SafeUint.Uint256(UnsafeMath.divRoundingUp(amount.bitshiftLeft(FixedPoint96.RESOLUTION), SafeUint.Uint256(liquidity.val())));
            };
            if(sqrtPX96.val() <= quotient.val()){ return #err("SqrtPriceMath illegal args"); };
            // always fits 160 bits
            if(sqrtPX96.val() > quotient.val()){ 
                return #ok(SafeUint.Uint160(SafeUint.Uint256(sqrtPX96.val()).sub(quotient).val()).val());
            } else{ return #ok(0); };
        };
    };

    public func getNextSqrtPriceFromInput(
        sqrtPX96: SafeUint.Uint160, liquidity: SafeUint.Uint128, amountIn: SafeUint.Uint256, zeroForOne: Bool
    ): Result.Result<Uint160, Text> {
        if(sqrtPX96.val() <= 0 or liquidity.val() <= 0){ return #err("SqrtPriceMath getNextSqrtPriceFromInput illegal args") };
        // round to make sure that we don't pass the target price
        if (zeroForOne){
            return getNextSqrtPriceFromAmount0RoundingUp(SafeUint.Uint160(sqrtPX96.val()), SafeUint.Uint128(liquidity.val()), SafeUint.Uint256(amountIn.val()), true)
        };
        return getNextSqrtPriceFromAmount1RoundingDown(SafeUint.Uint160(sqrtPX96.val()), SafeUint.Uint128(liquidity.val()), SafeUint.Uint256(amountIn.val()), true);
    };

    public func getNextSqrtPriceFromOutput(
        sqrtPX96: SafeUint.Uint160, liquidity: SafeUint.Uint128, amountOut: SafeUint.Uint256, zeroForOne: Bool
    ): Result.Result<Uint160, Text> {
        if(sqrtPX96.val() <= 0 or liquidity.val() <= 0){ return #err("SqrtPriceMath getNextSqrtPriceFromOutput illegal args") };
        // round to make sure that we pass the target price
        if (zeroForOne){
            return getNextSqrtPriceFromAmount1RoundingDown(sqrtPX96, liquidity, amountOut, false);
        };
        return getNextSqrtPriceFromAmount0RoundingUp(sqrtPX96, liquidity, amountOut, false);
    };

    public func getAmount0DeltaNat(
        _sqrtRatioAX96: SafeUint.Uint160, _sqrtRatioBX96: SafeUint.Uint160, liquidity: SafeUint.Uint128, roundUp: Bool
    ): Result.Result<Uint256, Text> {
        var sqrtRatioAX96 = _sqrtRatioAX96;
        var sqrtRatioBX96 = _sqrtRatioBX96;
        if (sqrtRatioAX96.val() > sqrtRatioBX96.val()) {
            sqrtRatioAX96 := _sqrtRatioBX96;
            sqrtRatioBX96 := _sqrtRatioAX96;
        };
        var numerator1: SafeUint.Uint256 = SafeUint.Uint256(liquidity.val()).bitshiftLeft(FixedPoint96.RESOLUTION);
        var numerator2: SafeUint.Uint256 = SafeUint.Uint256(sqrtRatioBX96.val()).sub(SafeUint.Uint256(sqrtRatioAX96.val()));

        if(_sqrtRatioAX96.val() <= 0){ return #err("SqrtPriceMath getAmount0DeltaNat illegal args"); };

        if (roundUp){
            var tempResult = switch (FullMath.mulDivRoundingUp(numerator1, numerator2, SafeUint.Uint256(_sqrtRatioBX96.val()))) {
                case (#ok(result)) { result; };
                case (#err(code)) { return #err("SqrtPriceMath getAmount0DeltaNat FullMath.mulDivRoundingUp failed: " # debug_show(code)); };
            };
            return #ok(UnsafeMath.divRoundingUp(
                SafeUint.Uint256(tempResult),
                SafeUint.Uint256(sqrtRatioAX96.val())
            ));
        };
        let md: SafeUint.Uint256 = SafeUint.Uint256(FullMath.mulDiv(numerator1, numerator2, SafeUint.Uint256(_sqrtRatioBX96.val())));
        return #ok(md.div(_sqrtRatioAX96).val());
    };

    public func getAmount1DeltaNat(
        _sqrtRatioAX96: SafeUint.Uint160, _sqrtRatioBX96: SafeUint.Uint160, liquidity: SafeUint.Uint128, roundUp: Bool
    ): Result.Result<Uint256, Text> {
        var sqrtRatioAX96 = _sqrtRatioAX96;
        var sqrtRatioBX96 = _sqrtRatioBX96;
        if (sqrtRatioAX96.val() > sqrtRatioBX96.val()){
            sqrtRatioAX96 := _sqrtRatioBX96;
            sqrtRatioBX96 := _sqrtRatioAX96
        };
        return if (roundUp) {
            FullMath.mulDivRoundingUp(SafeUint.Uint256(liquidity.val()), SafeUint.Uint256(sqrtRatioBX96.sub(sqrtRatioAX96).val()), SafeUint.Uint256(FixedPoint96.Q96));
        } else {
            #ok(FullMath.mulDiv(SafeUint.Uint256(liquidity.val()), SafeUint.Uint256(sqrtRatioBX96.sub(sqrtRatioAX96).val()), SafeUint.Uint256(FixedPoint96.Q96)));
        };
    };

    public func getAmount0Delta(
        sqrtRatioAX96: SafeUint.Uint160, sqrtRatioBX96: SafeUint.Uint160, liquidity: SafeInt.Int128
    ): Result.Result<Int256, Text> {
        if (liquidity.val() < 0){
            var amount0DeltaNat = switch (getAmount0DeltaNat(sqrtRatioAX96, sqrtRatioBX96, SafeUint.Uint128(IntUtils.toNat(liquidity.neg().val(), 128)), false)) {
                case (#ok(result)) { result; };
                case (#err(code)) { return #err("SqrtPriceMath getAmount0DeltaNat failed: "# debug_show(code)); };
            };
            return #ok(-(amount0DeltaNat));
        }else {
            var amount0DeltaNat = switch (getAmount0DeltaNat(sqrtRatioAX96, sqrtRatioBX96, SafeUint.Uint128(IntUtils.toNat(liquidity.val(), 128)), true)) {
                case (#ok(result)) { result; };
                case (#err(code)) { return #err("SqrtPriceMath getAmount0DeltaNat failed: "# debug_show(code)); };
            };
            return #ok(amount0DeltaNat);
        };
    };

    public func getAmount1Delta(
        sqrtRatioAX96: SafeUint.Uint160, sqrtRatioBX96: SafeUint.Uint160, liquidity: SafeInt.Int128
    ): Result.Result<Int256, Text> { 
        if(liquidity.val() < 0) {
            var amount1DeltaNat = switch (getAmount1DeltaNat(sqrtRatioAX96, sqrtRatioBX96, SafeUint.Uint128(IntUtils.toNat(liquidity.neg().val(), 128)), false)) {
                case (#ok(result)) { result; };
                case (#err(code)) { return #err("SqrtPriceMath getAmount1DeltaNat failed: " # debug_show(code)); };
            };
            return #ok(-(amount1DeltaNat));
        } else {
            var amount1DeltaNat = switch (getAmount1DeltaNat(sqrtRatioAX96, sqrtRatioBX96,  SafeUint.Uint128(IntUtils.toNat(liquidity.val(), 128)), true)) {
                case (#ok(result)) { result; };
                case (#err(code)) { return #err("SqrtPriceMath getAmount1DeltaNat failed: " # debug_show(code)); };
            };
            return #ok(amount1DeltaNat);
        }
    };
}
