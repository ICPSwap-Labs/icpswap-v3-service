import Bool "mo:base/Bool";
import Debug "mo:base/Debug";
import Error "mo:base/Error";
import Int "mo:base/Int";
import Nat "mo:base/Nat";
import Text "mo:base/Text";
import Result "mo:base/Result";
import SafeUint "mo:commons/math/SafeUint";
import SafeInt "mo:commons/math/SafeInt";
import IntUtils "mo:commons/math/SafeInt/IntUtils";

import FullMath "./FullMath";
import SqrtPriceMath "./SqrtPriceMath";

module {
    type Uint160 = Nat;
    type Uint128 = Nat;
    type Uint256 = Nat;
    type Int256 = Int;

    public let Nat1e6 = 1000000;

    public func computeSwapStep(
        sqrtRatioCurrentX96: SafeUint.Uint160, 
        sqrtRatioTargetX96: SafeUint.Uint160, 
        liquidity: SafeUint.Uint128, 
        amountRemaining: SafeInt.Int256, 
        feePips: SafeUint.Uint24
    ): Result.Result<{
        sqrtRatioNextX96: Uint160; 
        amountIn: Uint256; 
        amountOut: Uint256; 
        feeAmount: Uint256;
    }, Text> {
        var zeroForOne:Bool = sqrtRatioCurrentX96.val() >= sqrtRatioTargetX96.val();
        var exactIn:Bool = amountRemaining.val() >= 0;

        var sqrtRatioNextX96:SafeUint.Uint160 = SafeUint.Uint160(0);
        var amountIn:SafeUint.Uint256 = SafeUint.Uint256(0);
        var amountOut:SafeUint.Uint256 = SafeUint.Uint256(0);
        var feeAmount:SafeUint.Uint256 = SafeUint.Uint256(0);
        
        if (exactIn) {
            var amountRemainingLessFee:SafeUint.Uint256 = SafeUint.Uint256(FullMath.mulDiv(
                SafeUint.Uint256(IntUtils.toNat(amountRemaining.val(), 256)), 
                SafeUint.Uint256(Nat1e6).sub(SafeUint.Uint256(feePips.val())), 
                SafeUint.Uint256(Nat1e6)
            ));
            
            amountIn := if(zeroForOne) {
                switch (SqrtPriceMath.getAmount0DeltaNat(sqrtRatioTargetX96, sqrtRatioCurrentX96, liquidity, true)) {
                    case (#ok(result)) { SafeUint.Uint256(result); };
                    case (#err(code)) { return #err("SwapMath SqrtPriceMath.getAmount0DeltaNat failed: " # debug_show(code)); };
                };
            } else {
                switch (SqrtPriceMath.getAmount1DeltaNat(sqrtRatioCurrentX96, sqrtRatioTargetX96, liquidity, true)) {
                    case (#ok(result)) { SafeUint.Uint256(result); };
                    case (#err(code)) { return #err("SwapMath SqrtPriceMath.getAmount1DeltaNat failed: " # debug_show(code)); };
                };
            };

            if (amountRemainingLessFee.val() >= amountIn.val()) {
                sqrtRatioNextX96 := sqrtRatioTargetX96;
            } else {
                sqrtRatioNextX96 := switch (SqrtPriceMath.getNextSqrtPriceFromInput(
                    sqrtRatioCurrentX96, liquidity, amountRemainingLessFee, zeroForOne
                )) {
                    case (#ok(result)) { SafeUint.Uint160(result); };
                    case (#err(code)) { return #err("SwapMath SqrtPriceMath.getNextSqrtPriceFromInput failed: " # debug_show(code)); };
                };
            };
        } 
        else {
            amountOut := if (zeroForOne) {
                switch (SqrtPriceMath.getAmount1DeltaNat(sqrtRatioTargetX96, sqrtRatioCurrentX96, liquidity, false)) {
                    case (#ok(result)) { SafeUint.Uint256(result); };
                    case (#err(code)) { return #err("SwapMath SqrtPriceMath.getAmount1DeltaNat failed: " # debug_show(code)); };
                };
            } else {
                switch (SqrtPriceMath.getAmount0DeltaNat(sqrtRatioCurrentX96, sqrtRatioTargetX96, liquidity, false)) {
                    case (#ok(result)) { SafeUint.Uint256(result); };
                    case (#err(code)) { return #err("SwapMath SqrtPriceMath.getAmount0DeltaNat failed: " # debug_show(code)); };
                };
            };
            
            if (SafeUint.Uint256(IntUtils.toNat(amountRemaining.neg().val(), 256)).val() >= amountOut.val()) {
                sqrtRatioNextX96 := sqrtRatioTargetX96;
            } else {
                sqrtRatioNextX96 := switch (SqrtPriceMath.getNextSqrtPriceFromOutput(
                    sqrtRatioCurrentX96, liquidity, SafeUint.Uint256(IntUtils.toNat(amountRemaining.neg().val(), 256)), zeroForOne
                )) {
                    case (#ok(result)) { SafeUint.Uint160(result); };
                    case (#err(code)) { return #err("SwapMath SqrtPriceMath.getNextSqrtPriceFromOutput failed: " # debug_show(code)); };
                };
            };
        };

        var max: Bool = sqrtRatioTargetX96.val() == sqrtRatioNextX96.val();
        // get the input/output amounts
        if (zeroForOne) {
            amountIn := if (max and exactIn){ amountIn; } else {
                switch (SqrtPriceMath.getAmount0DeltaNat(sqrtRatioNextX96, sqrtRatioCurrentX96, liquidity, true)) {
                    case (#ok(result)) { SafeUint.Uint256(result); };
                    case (#err(code)) { return #err("SwapMath SqrtPriceMath.getAmount0DeltaNat failed: " # debug_show(code)); };
                };
            };
            amountOut := if (max and (not exactIn)){ amountOut; } else {
                switch (SqrtPriceMath.getAmount1DeltaNat(sqrtRatioNextX96, sqrtRatioCurrentX96, liquidity, false)) {
                    case (#ok(result)) { SafeUint.Uint256(result); };
                    case (#err(code)) { return #err("SwapMath SqrtPriceMath.getAmount1DeltaNat failed: " # debug_show(code)); };
                };
            };
        } else {
            amountIn := if (max and exactIn){ amountIn; } else {
                switch (SqrtPriceMath.getAmount1DeltaNat(sqrtRatioCurrentX96, sqrtRatioNextX96, liquidity, true)) {
                    case (#ok(result)) { SafeUint.Uint256(result); };
                    case (#err(code)) { return #err("SwapMath SqrtPriceMath.getAmount1DeltaNat failed: " # debug_show(code)); };
                };
            };
            amountOut := if (max and (not exactIn)){ amountOut; } else {
                switch (SqrtPriceMath.getAmount0DeltaNat(sqrtRatioCurrentX96, sqrtRatioNextX96, liquidity, false)) {
                    case (#ok(result)) { SafeUint.Uint256(result); };
                    case (#err(code)) { return #err("SwapMath SqrtPriceMath.getAmount0DeltaNat failed: " # debug_show(code)); };
                };
            }
        };

        // cap the output amount to not exceed the remaining output amount
        if ((not exactIn) and (amountOut.val() > SafeUint.Uint256(IntUtils.toNat(amountRemaining.neg().val(), 256)).val())) {
            amountOut := SafeUint.Uint256(IntUtils.toNat(amountRemaining.neg().val(), 256));
        };

        if (exactIn and sqrtRatioNextX96.val() != sqrtRatioTargetX96.val()) {
            feeAmount := SafeUint.Uint256(IntUtils.toNat(amountRemaining.val(), 256)).sub(amountIn);
        } else {
            feeAmount := switch (FullMath.mulDivRoundingUp(amountIn, SafeUint.Uint256(feePips.val()), SafeUint.Uint256(Nat1e6).sub(SafeUint.Uint256(feePips.val())))) {
                case (#ok(result)) { SafeUint.Uint256(result); };
                case (#err(code)) { return #err("SwapMath FullMath.mulDivRoundingUp failed: " # debug_show(code)); };
            };
        };

        return #ok({
            sqrtRatioNextX96 = sqrtRatioNextX96.val();
            amountIn = amountIn.val();
            amountOut = amountOut.val();
            feeAmount = feeAmount.val();
        });
    }
}
