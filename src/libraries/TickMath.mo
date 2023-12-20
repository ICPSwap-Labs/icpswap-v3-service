import Bool "mo:base/Bool";
import Debug "mo:base/Debug";
import Float "mo:base/Float";
import Int "mo:base/Int";
import Nat "mo:base/Nat";
import Text "mo:base/Text";
import Result "mo:base/Result";

import LogicUtils "mo:commons/utils/LogicUtils";
import IntUtils "mo:commons/math/SafeInt/IntUtils";
import UintUtils "mo:commons/math/SafeUint/UintUtils";
import SafeInt "mo:commons/math/SafeInt";
import SafeUint "mo:commons/math/SafeUint";
import BitwiseInt "mo:commons/math/BitwiseInt";
import BitwiseNat "mo:commons/math/BitwiseNat";

import Tick "./Tick";
import SqrtPriceMath "./SqrtPriceMath";

module {

    type Int24 = Int;
    type Int256 = Int;
    type Uint160 = Nat;
    type Uint256 = Nat;

    public func getSqrtRatioAtTick(tick: SafeInt.Int24): Result.Result<Uint160, Text> {
        var absTick: SafeUint.Uint256 = SafeUint.Uint256(
            if (tick.val() < 0) {
                IntUtils.toNat(-(SafeInt.Int256(tick.val()).val()), 256)
            } else {
                IntUtils.toNat(SafeInt.Int256(tick.val()).val(), 256)
            }
        );
        if(absTick.val() > Tick.MAX_TICK){ return #err("TickMath getSqrtRatioAtTick illegal args"); };

        var ratio: SafeUint.Uint256 = SafeUint.Uint256(LogicUtils.ternary<Uint256>(absTick.bitand(SafeUint.Uint256(0x01)).val() != 0, 0xfffcb933bd6fad37aa2d162d1a594001, 0x100000000000000000000000000000000));
        if (absTick.bitand(SafeUint.Uint256(0x02)).val() != 0) {ratio := ratio.mul(SafeUint.Uint256(0xfff97272373d413259a46990580e213a)).bitshiftRight(128);};
        if (absTick.bitand(SafeUint.Uint256(0x04)).val() != 0) {ratio := ratio.mul(SafeUint.Uint256(0xfff2e50f5f656932ef12357cf3c7fdcc)).bitshiftRight(128);};
        if (absTick.bitand(SafeUint.Uint256(0x08)).val() != 0) {ratio := ratio.mul(SafeUint.Uint256(0xffe5caca7e10e4e61c3624eaa0941cd0)).bitshiftRight(128);};
        if (absTick.bitand(SafeUint.Uint256(0x10)).val() != 0) {ratio := ratio.mul(SafeUint.Uint256(0xffcb9843d60f6159c9db58835c926644)).bitshiftRight(128);};
        if (absTick.bitand(SafeUint.Uint256(0x20)).val() != 0) {ratio := ratio.mul(SafeUint.Uint256(0xff973b41fa98c081472e6896dfb254c0)).bitshiftRight(128);};
        if (absTick.bitand(SafeUint.Uint256(0x40)).val() != 0) {ratio := ratio.mul(SafeUint.Uint256(0xff2ea16466c96a3843ec78b326b52861)).bitshiftRight(128);};
        if (absTick.bitand(SafeUint.Uint256(0x80)).val() != 0) {ratio := ratio.mul(SafeUint.Uint256(0xfe5dee046a99a2a811c461f1969c3053)).bitshiftRight(128);};
        if (absTick.bitand(SafeUint.Uint256(0x100)).val() != 0) {ratio := ratio.mul(SafeUint.Uint256(0xfcbe86c7900a88aedcffc83b479aa3a4)).bitshiftRight(128);};
        if (absTick.bitand(SafeUint.Uint256(0x200)).val() != 0) {ratio := ratio.mul(SafeUint.Uint256(0xf987a7253ac413176f2b074cf7815e54)).bitshiftRight(128);};
        if (absTick.bitand(SafeUint.Uint256(0x400)).val() != 0) {ratio := ratio.mul(SafeUint.Uint256(0xf3392b0822b70005940c7a398e4b70f3)).bitshiftRight(128);};
        if (absTick.bitand(SafeUint.Uint256(0x800)).val() != 0) {ratio := ratio.mul(SafeUint.Uint256(0xe7159475a2c29b7443b29c7fa6e889d9)).bitshiftRight(128);};
        if (absTick.bitand(SafeUint.Uint256(0x1000)).val() != 0) {ratio := ratio.mul(SafeUint.Uint256(0xd097f3bdfd2022b8845ad8f792aa5825)).bitshiftRight(128);};
        if (absTick.bitand(SafeUint.Uint256(0x2000)).val() != 0) {ratio := ratio.mul(SafeUint.Uint256(0xa9f746462d870fdf8a65dc1f90e061e5)).bitshiftRight(128);};
        if (absTick.bitand(SafeUint.Uint256(0x4000)).val() != 0) {ratio := ratio.mul(SafeUint.Uint256(0x70d869a156d2a1b890bb3df62baf32f7)).bitshiftRight(128);};
        if (absTick.bitand(SafeUint.Uint256(0x8000)).val() != 0) {ratio := ratio.mul(SafeUint.Uint256(0x31be135f97d08fd981231505542fcfa6)).bitshiftRight(128);};
        if (absTick.bitand(SafeUint.Uint256(0x10000)).val() != 0) {ratio := ratio.mul(SafeUint.Uint256(0x9aa508b5b7a84e1c677de54f3e99bc9)).bitshiftRight(128);};
        if (absTick.bitand(SafeUint.Uint256(0x20000)).val() != 0) {ratio := ratio.mul(SafeUint.Uint256(0x5d6af8dedb81196699c329225ee604)).bitshiftRight(128);};
        if (absTick.bitand(SafeUint.Uint256(0x40000)).val() != 0) {ratio := ratio.mul(SafeUint.Uint256(0x2216e584f5fa1ea926041bedfe98)).bitshiftRight(128);};
        if (absTick.bitand(SafeUint.Uint256(0x80000)).val() != 0) {ratio := ratio.mul(SafeUint.Uint256(0x48a170391f7dc42444e8fa2)).bitshiftRight(128);};

        if (tick.val() > 0) ratio := SafeUint.Uint256(SafeUint.UINT_256_MAX).div(ratio); //type(uint256).max / ratio;
        let sqrtPriceX96:SafeUint.Uint160 = SafeUint.Uint160(
            ratio.bitshiftRight(32).add(
                SafeUint.Uint256(if (ratio.rem(SafeUint.Uint256(1).bitshiftLeft(32)).val() == 0) {0} else {1})
            ).val()
        );
        return #ok(sqrtPriceX96.val());
    };

    public func getTickAtSqrtRatio(sqrtPriceX96: SafeUint.Uint160): Result.Result<Int24, Text> {
        // second inequality must be < because the price can never reach the price at the max tick
        if(not ((sqrtPriceX96.val() >= SqrtPriceMath.MIN_SQRT_RATIO) and (sqrtPriceX96.val() < SqrtPriceMath.MAX_SQRT_RATIO))){ return #err("TickMath getTickAtSqrtRatio illegal args") };
        var ratio: SafeUint.Uint256 = SafeUint.Uint256(sqrtPriceX96.val()).bitshiftLeft(32);
        var r: SafeUint.Uint256 = ratio;
        var msb: SafeUint.Uint256 = SafeUint.Uint256(0);
        var f: SafeUint.Uint256 = SafeUint.Uint256(LogicUtils.ternary<Uint256>((r.val() > 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF), 1, 0)).bitshiftLeft(7);
        msb := msb.bitor(f);
        r := r.bitshiftRight(f.val());

        f := SafeUint.Uint256(LogicUtils.ternary<Uint256>((r.val() > 0xFFFFFFFFFFFFFFFF), 1, 0)).bitshiftLeft(6);
        msb := msb.bitor(f);
        r := r.bitshiftRight(f.val());

        f := SafeUint.Uint256(LogicUtils.ternary<Uint256>((r.val() > 0xFFFFFFFF), 1, 0)).bitshiftLeft(5);
        msb := msb.bitor(f);
        r := r.bitshiftRight(f.val());

        f := SafeUint.Uint256(LogicUtils.ternary<Uint256>((r.val() > 0xFFFF), 1, 0)).bitshiftLeft(4);
        msb := msb.bitor(f);
        r := r.bitshiftRight(f.val());

        f := SafeUint.Uint256(LogicUtils.ternary<Uint256>((r.val() > 0xFF), 1, 0)).bitshiftLeft(3);
        msb := msb.bitor(f);
        r := r.bitshiftRight(f.val());
        
        f := SafeUint.Uint256(LogicUtils.ternary<Uint256>((r.val() > 0xF), 1, 0)).bitshiftLeft(2);
        msb := msb.bitor(f);
        r := r.bitshiftRight(f.val());
        
        f := SafeUint.Uint256(LogicUtils.ternary<Uint256>((r.val() > 0x3), 1, 0)).bitshiftLeft(1);
        msb := msb.bitor(f);
        r := r.bitshiftRight(f.val());

        f := SafeUint.Uint256(LogicUtils.ternary<Uint256>((r.val() > 1), 1, 0));
        msb := msb.bitor(f);
        
        if (msb.val() >= 128) {
            r := ratio.bitshiftRight(msb.sub(SafeUint.Uint256(127)).val());
        } else {
            r := ratio.bitshiftLeft(SafeUint.Uint256(127).sub(msb).val());
        };

        var log2: SafeInt.Int256 = SafeInt.Int256(IntUtils.toInt(msb.val(), 256)).sub(SafeInt.Int256(128)).bitshiftLeft(64);

        r := r.mul(r).bitshiftRight(127);
        f := r.bitshiftRight(128);
        log2 := log2.bitor(SafeInt.Int256(IntUtils.toInt(f.bitshiftLeft(63).val(), 256)));
        r := r.bitshiftRight(f.val());

        r := r.mul(r).bitshiftRight(127);
        f := r.bitshiftRight(128);
        log2 := log2.bitor(SafeInt.Int256(IntUtils.toInt(f.bitshiftLeft(62).val(), 256)));
        r := r.bitshiftRight(f.val());

        r := r.mul(r).bitshiftRight(127);
        f := r.bitshiftRight(128);
        log2 := log2.bitor(SafeInt.Int256(IntUtils.toInt(f.bitshiftLeft(61).val(), 256)));
        r := r.bitshiftRight(f.val());

        r := r.mul(r).bitshiftRight(127);
        f := r.bitshiftRight(128);
        log2 := log2.bitor(SafeInt.Int256(IntUtils.toInt(f.bitshiftLeft(60).val(), 256)));
        r := r.bitshiftRight(f.val());
    
        r := r.mul(r).bitshiftRight(127);
        f := r.bitshiftRight(128);
        log2 := log2.bitor(SafeInt.Int256(IntUtils.toInt(f.bitshiftLeft(59).val(), 256)));
        r := r.bitshiftRight(f.val());
        
        r := r.mul(r).bitshiftRight(127);
        f := r.bitshiftRight(128);
        log2 := log2.bitor(SafeInt.Int256(IntUtils.toInt(f.bitshiftLeft(58).val(), 256)));
        r := r.bitshiftRight(f.val());

        r := r.mul(r).bitshiftRight(127);
        f := r.bitshiftRight(128);
        log2 := log2.bitor(SafeInt.Int256(IntUtils.toInt(f.bitshiftLeft(57).val(), 256)));
        r := r.bitshiftRight(f.val());

        r := r.mul(r).bitshiftRight(127);
        f := r.bitshiftRight(128);
        log2 := log2.bitor(SafeInt.Int256(IntUtils.toInt(f.bitshiftLeft(56).val(), 256)));
        r := r.bitshiftRight(f.val());

        r := r.mul(r).bitshiftRight(127);
        f := r.bitshiftRight(128);
        log2 := log2.bitor(SafeInt.Int256(IntUtils.toInt(f.bitshiftLeft(55).val(), 256)));
        r := r.bitshiftRight(f.val());

        r := r.mul(r).bitshiftRight(127);
        f := r.bitshiftRight(128);
        log2 := log2.bitor(SafeInt.Int256(IntUtils.toInt(f.bitshiftLeft(54).val(), 256)));
        r := r.bitshiftRight(f.val());

        r := r.mul(r).bitshiftRight(127);
        f := r.bitshiftRight(128);
        log2 := log2.bitor(SafeInt.Int256(IntUtils.toInt(f.bitshiftLeft(53).val(), 256)));
        r := r.bitshiftRight(f.val());

        r := r.mul(r).bitshiftRight(127);
        f := r.bitshiftRight(128);
        log2 := log2.bitor(SafeInt.Int256(IntUtils.toInt(f.bitshiftLeft(52).val(), 256)));
        r := r.bitshiftRight(f.val());

        r := r.mul(r).bitshiftRight(127);
        f := r.bitshiftRight(128);
        log2 := log2.bitor(SafeInt.Int256(IntUtils.toInt(f.bitshiftLeft(51).val(), 256)));
        r := r.bitshiftRight(f.val());

        r := r.mul(r).bitshiftRight(127);
        f := r.bitshiftRight(128);
        log2 := log2.bitor(SafeInt.Int256(IntUtils.toInt(f.bitshiftLeft(50).val(), 256)));
        r := r.bitshiftRight(f.val());
        
        var logSqrt10001: SafeInt.Int256 = log2.mul(SafeInt.Int256(255738958999603826347141));

        var tickLow: SafeInt.Int24 = logSqrt10001.sub(SafeInt.Int256(3402992956809132418596140100660247210)).bitshiftRight(128);
        var tickHigh: SafeInt.Int24 = logSqrt10001.add(SafeInt.Int256(291339464771989622907027621153398088495)).bitshiftRight(128);

        var sqrtRatioAtTick = switch (getSqrtRatioAtTick(tickHigh)) {
            case (#ok(result)) { result; };
            case (#err(code)) { return #err("TickMath getSqrtRatioAtTick failed: " # debug_show(code)); };
        };
        var tick: SafeInt.Int24 = if (tickLow.val() == tickHigh.val()) {
            tickLow;
        } else if (sqrtRatioAtTick <= sqrtPriceX96.val()) {
            tickHigh;
        } else {
            tickLow;
        };
        return #ok(tick.val());
    };
}
