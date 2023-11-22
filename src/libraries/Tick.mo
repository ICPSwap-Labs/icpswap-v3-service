import Bool "mo:base/Bool";
import Debug "mo:base/Debug";
import HashMap "mo:base/HashMap";
import Int "mo:base/Int";
import Nat "mo:base/Nat";
import Text "mo:base/Text";
import Result "mo:base/Result";

import SafeUint "mo:commons/math/SafeUint";
import SafeInt "mo:commons/math/SafeInt";
import IntUtils "mo:commons/math/SafeInt/IntUtils";
import LiquidityMath "./LiquidityMath";
import Types "../Types";

module {

    public let MIN_TICK = -887272;
    public let MAX_TICK = 887272;

    type Int128 = Int;
    type Int24 = Int;
    type Int56 = Int;
    type Uint8 = Nat;
    type Uint24 = Nat;
    type Uint32 = Nat;
    type Uint128 = Nat;
    type Uint160 = Nat;
    type Uint256 = Nat;

    public func tickSpacingToMaxLiquidityPerTick(tickSpacing: SafeInt.Int24): Uint128 {
        var minTick:SafeInt.Int24 = SafeInt.Int24(MIN_TICK).div(tickSpacing).mul(tickSpacing);
        var maxTick:SafeInt.Int24 = SafeInt.Int24(MAX_TICK).div(tickSpacing).mul(tickSpacing);
        var numTicks:SafeUint.Uint24 = SafeUint.Uint24(
            IntUtils.toNat(
                maxTick.sub(minTick).div(tickSpacing).val(),
                24
            )
        ).add(SafeUint.Uint24(1));
        return SafeUint.Uint128(SafeUint.UINT_128_MAX).div(numTicks).val();
    };

    public func getFeeGrowthInside(
        self: HashMap.HashMap<Text, Types.TickInfo>,
        tickLower: SafeInt.Int24,
        tickUpper: SafeInt.Int24,
        tickCurrent: SafeInt.Int24,
        feeGrowthGlobal0X128: SafeUint.Uint256,
        feeGrowthGlobal1X128: SafeUint.Uint256
    ): {
        feeGrowthInside0X128: Nat;
        feeGrowthInside1X128: Nat;
    } {
        var nullTicks: Types.TickInfo = {
            var liquidityGross = 0;
            var liquidityNet = 0;
            var feeGrowthOutside0X128 = 0;
            var feeGrowthOutside1X128 = 0;
            var tickCumulativeOutside = 0;
            var secondsPerLiquidityOutsideX128 = 0;
            var secondsOutside = 0;
            var initialized = false;
        };
        var lower: Types.TickInfo = switch(self.get(Int.toText(tickLower.val()))){
            case(?_tick){_tick;};
            case (_){nullTicks;}
        };
        var upper: Types.TickInfo = switch(self.get(Int.toText(tickUpper.val()))){
            case(?_tick){_tick;};
            case (_){nullTicks;}
        };

        var feeGrowthBelow0X128 :SafeUint.Uint256 = SafeUint.Uint256(0);
        var feeGrowthBelow1X128 :SafeUint.Uint256 = SafeUint.Uint256(0);
        if (tickCurrent.val() >= tickLower.val()) {
            feeGrowthBelow0X128 := SafeUint.Uint256(lower.feeGrowthOutside0X128);
            feeGrowthBelow1X128 := SafeUint.Uint256(lower.feeGrowthOutside1X128);
        } else {
            feeGrowthBelow0X128 := feeGrowthGlobal0X128.sub(SafeUint.Uint256(lower.feeGrowthOutside0X128));
            feeGrowthBelow1X128 := feeGrowthGlobal1X128.sub(SafeUint.Uint256(lower.feeGrowthOutside1X128));
        };

        var feeGrowthAbove0X128 :SafeUint.Uint256 = SafeUint.Uint256(0);
        var feeGrowthAbove1X128 :SafeUint.Uint256 = SafeUint.Uint256(0);
        if (tickCurrent.val() < tickUpper.val()) {
            feeGrowthAbove0X128 := SafeUint.Uint256(upper.feeGrowthOutside0X128);
            feeGrowthAbove1X128 := SafeUint.Uint256(upper.feeGrowthOutside1X128);
        } else {
            feeGrowthAbove0X128 := feeGrowthGlobal0X128.sub(SafeUint.Uint256(upper.feeGrowthOutside0X128));
            feeGrowthAbove1X128 := feeGrowthGlobal1X128.sub(SafeUint.Uint256(upper.feeGrowthOutside1X128));
        };
        
        return {
            feeGrowthInside0X128 = feeGrowthGlobal0X128.sub(feeGrowthBelow0X128).sub(feeGrowthAbove0X128).val();
            feeGrowthInside1X128 = feeGrowthGlobal1X128.sub(feeGrowthBelow1X128).sub(feeGrowthAbove1X128).val();
        }
    };

   public func update(
        self: HashMap.HashMap<Text, Types.TickInfo>,
        tick: SafeInt.Int24,
        tickCurrent: SafeInt.Int24,
        liquidityDelta:SafeInt.Int128,
        feeGrowthGlobal0X128:SafeUint.Uint256,
        feeGrowthGlobal1X128:SafeUint.Uint256,
        secondsPerLiquidityCumulativeX128:SafeUint.Uint160,
        tickCumulative:SafeInt.Int56,
        time:SafeUint.Uint32,
        upper:Bool,
        maxLiquidity:SafeUint.Uint128
    ): Result.Result<{
        liquidityGross: Nat;
        liquidityNet: Int;
        feeGrowthOutside0X128: Nat;
        feeGrowthOutside1X128: Nat;
        tickCumulativeOutside: Int;
        secondsPerLiquidityOutsideX128: Nat;
        secondsOutside: Nat;
        initialized: Bool;
        updateResult: Bool;
    }, Text> {
        var info: Types.TickInfo = switch(self.get(Int.toText(tick.val()))){
            case(?_tick){_tick;};
            case (_){{
                var liquidityGross = 0;
                var liquidityNet = 0;
                var feeGrowthOutside0X128 = 0;
                var feeGrowthOutside1X128 = 0;
                var tickCumulativeOutside = 0;
                var secondsPerLiquidityOutsideX128 = 0;
                var secondsOutside = 0;
                var initialized = false;
            };}
        };
        var tempTick: Types.TickInfo = {
            var liquidityGross = info.liquidityGross;
            var liquidityNet = info.liquidityNet;
            var feeGrowthOutside0X128 = info.feeGrowthOutside0X128;
            var feeGrowthOutside1X128 = info.feeGrowthOutside1X128;
            var tickCumulativeOutside = info.tickCumulativeOutside;
            var secondsPerLiquidityOutsideX128 = info.secondsPerLiquidityOutsideX128;
            var secondsOutside = info.secondsOutside;
            var initialized = info.initialized;
        };
        
        var liquidityGrossBefore :SafeUint.Uint128 = SafeUint.Uint128(tempTick.liquidityGross);
        // Debug.print("Tick update: liquidityGrossBefore=" # debug_show(liquidityGrossBefore.val()) # ",liquidityDelta=" # debug_show(liquidityDelta.val()));
        var liquidityGrossAfter :SafeUint.Uint128 = switch (LiquidityMath.addDelta(liquidityGrossBefore, liquidityDelta)) {
                case (#ok(result)) { SafeUint.Uint128(result); };
                case (#err(code)) { return #err("Tick LiquidityMath.addDelta failed " # debug_show(code)); };
        };
        // Debug.print("Tick update: liquidityGrossAfter=" # debug_show(liquidityGrossAfter.val()) # ",maxLiquidity=" # debug_show(maxLiquidity.val()));
        if (liquidityGrossAfter.val() > maxLiquidity.val()) {
            return #err("Tick illegal liquidityGrossAfter: liquidityGrossAfter=" # debug_show(liquidityGrossAfter.val()) # ", maxLiquidity=" # debug_show(maxLiquidity.val())); 
        };

        if (liquidityGrossBefore.val() == 0) {
            if (tick.val() <= tickCurrent.val()) {
                tempTick.feeGrowthOutside0X128 := feeGrowthGlobal0X128.val();
                tempTick.feeGrowthOutside1X128 := feeGrowthGlobal1X128.val();
                tempTick.secondsPerLiquidityOutsideX128 := secondsPerLiquidityCumulativeX128.val();
                tempTick.tickCumulativeOutside := tickCumulative.val();
                tempTick.secondsOutside := time.val();
            };
            tempTick.initialized := true;
        };

        tempTick.liquidityGross := liquidityGrossAfter.val();
        tempTick.liquidityNet := if (upper) { 
            SafeInt.Int128(
                SafeInt.Int256(tempTick.liquidityNet).sub(
                    SafeInt.Int256(liquidityDelta.val())
                ).val()
            ).val() 
        } else {
            SafeInt.Int128(
                SafeInt.Int256(tempTick.liquidityNet).add(
                    SafeInt.Int256(liquidityDelta.val())
                ).val()
            ).val()
        };
      
        return #ok({
            liquidityGross = tempTick.liquidityGross;
            liquidityNet = tempTick.liquidityNet;
            feeGrowthOutside0X128 = tempTick.feeGrowthOutside0X128;
            feeGrowthOutside1X128 = tempTick.feeGrowthOutside1X128;
            tickCumulativeOutside = tempTick.tickCumulativeOutside;
            secondsPerLiquidityOutsideX128 = tempTick.secondsPerLiquidityOutsideX128;
            secondsOutside = tempTick.secondsOutside;
            initialized = tempTick.initialized;
            updateResult = Bool.notEqual((liquidityGrossAfter.val() == 0), (liquidityGrossBefore.val() == 0));
        });
    };

    public func clear(self: HashMap.HashMap<Text, Types.TickInfo>, tick: SafeInt.Int24) {
        self.delete(Int.toText(tick.val()));
    };

    public func cross(
        self: HashMap.HashMap<Text, Types.TickInfo>, 
        tick: SafeInt.Int24, 
        feeGrowthGlobal0X128: SafeUint.Uint256, 
        feeGrowthGlobal1X128: SafeUint.Uint256, 
        secondsPerLiquidityCumulativeX128: SafeUint.Uint160, 
        tickCumulative: SafeInt.Int56, 
        time: SafeUint.Uint32
    ): Types.TickInfo {
        var tempTick: Types.TickInfo = {
            var liquidityGross = 0;
            var liquidityNet = 0;
            var feeGrowthOutside0X128 = 0;
            var feeGrowthOutside1X128 = 0;
            var tickCumulativeOutside = 0;
            var secondsPerLiquidityOutsideX128 = 0;
            var secondsOutside = 0;
            var initialized = true;
        };
        var info: Types.TickInfo = switch(self.get(Int.toText(tick.val()))){
            case(?_tick){_tick;};
            case(_){tempTick;}
        };
        tempTick.liquidityGross := info.liquidityGross;
        tempTick.liquidityNet := info.liquidityNet;
        tempTick.feeGrowthOutside0X128 := feeGrowthGlobal0X128.sub(SafeUint.Uint256(info.feeGrowthOutside0X128)).val();
        tempTick.feeGrowthOutside1X128 := feeGrowthGlobal1X128.sub(SafeUint.Uint256(info.feeGrowthOutside1X128)).val();
        tempTick.tickCumulativeOutside := tickCumulative.sub(SafeInt.Int56(info.tickCumulativeOutside)).val();
        tempTick.secondsPerLiquidityOutsideX128 := secondsPerLiquidityCumulativeX128.sub(SafeUint.Uint160(info.secondsPerLiquidityOutsideX128)).val();
        tempTick.secondsOutside := time.sub(SafeUint.Uint32(info.secondsOutside)).val();
        tempTick.initialized := info.initialized;
        return tempTick;
    }
}
