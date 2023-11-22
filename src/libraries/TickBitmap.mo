import Bool "mo:base/Bool";
import Debug "mo:base/Debug";
import HashMap "mo:base/HashMap";
import Int "mo:base/Int";
import Nat "mo:base/Nat";
import Nat8 "mo:base/Nat8";
import Result "mo:base/Result";

import SafeInt "mo:commons/math/SafeInt";
import SafeUint "mo:commons/math/SafeUint";
import IntUtils "mo:commons/math/SafeInt/IntUtils";
import UintUtils "mo:commons/math/SafeUint/UintUtils";

import BitMath "./BitMath";

module TickBitmap {
    
    type Int24 = Int;
    type Int16 = Int;
    type Int256 = Int;
    type Uint8 = Nat;
    type Uint256 = Nat;

    public func position(tick:SafeInt.Int24): {
        wordPos:Int;
        bitPos:Nat
    } {
        return {
            wordPos = SafeInt.Int16(tick.bitshiftRight(8).val()).val();
            bitPos = SafeUint.Uint8(IntUtils.toNat(tick.rem(SafeInt.Int24(256)).val(), 8)).val();
        }
    };

    public func flipTick(
        self:HashMap.HashMap<Int16, Uint256>,
        tick:SafeInt.Int24,
        tickSpacing:SafeInt.Int24
    ): Result.Result<{
        wordPos: Int;
        tickStatus: Nat;
    }, Text> {
        if(tick.rem(tickSpacing).val() != 0){ return #err("illegal args");};

        var data = position(tick.div(tickSpacing));
        var mask:SafeUint.Uint256 = SafeUint.Uint256(1).bitshiftLeft(data.bitPos);

        var tickStatus_temp:SafeUint.Uint256 = SafeUint.Uint256(switch(self.get(data.wordPos)){
            case (?tickStatus_temp){tickStatus_temp;};
            case (_){0;};
        });

        tickStatus_temp := tickStatus_temp.bitxor(mask);

        return #ok({
            wordPos = data.wordPos;
            tickStatus = tickStatus_temp.val();
        });
    };

    public func nextInitializedTickWithinOneWord(
        self:HashMap.HashMap<Int16, Uint256>,
        tick: SafeInt.Int24, 
        tickSpacing: SafeInt.Int24, 
        lte: Bool,
    ): Result.Result<{next: Int24; initialized: Bool}, Text> {
        var compressed:SafeInt.Int24 = tick.div(tickSpacing);
        if (tick.val() < 0 and tick.rem(tickSpacing).val() != 0) {compressed := compressed.sub(SafeInt.Int24(1));};

        var next:Int24 = 0;
        var initialized :Bool = false;

         // round towards negative infinity
        if (lte) {
            var data = position(compressed);
            var wordPos:Int16 = data.wordPos;
            var bitPos:Uint8 = data.bitPos;
            // all the 1s at or to the right of the current bitPos
            var mask :SafeUint.Uint256 = SafeUint.Uint256(1).bitshiftLeft(bitPos).sub(SafeUint.Uint256(1)).add(SafeUint.Uint256(1).bitshiftLeft(bitPos));
            var _self_wordPos = SafeUint.Uint256(switch(self.get(wordPos)){case(?_wordPos){_wordPos};case(_){0};});
            var masked :SafeUint.Uint256 = _self_wordPos.bitand(mask);

            // if there are no initialized ticks to the right of or at the current tick, return rightmost in the word
            initialized := masked.val() != 0;

            // overflow/underflow is possible, but prevented externally by limiting both tickSpacing and tick
            next := if (initialized){
                var mostSignificantBit = SafeUint.Uint8(switch (BitMath.mostSignificantBit(masked)) {
                    case (#ok(result)) { result; };
                    case (#err(code)) { return #err("TickBitmap BitMath.mostSignificantBit failed: " # debug_show(code)); };
                });
                compressed.sub(SafeInt.Int24(IntUtils.toInt(SafeUint.Uint8(bitPos).sub(mostSignificantBit).val(), 24))).mul(tickSpacing).val();
            } else { 
                compressed.sub(SafeInt.Int24(IntUtils.toInt(bitPos, 24))).mul(tickSpacing).val()
            };
        } else {
            // start from the word of the next tick, since the current tick state doesn't matter
            var data = position(compressed.add(SafeInt.Int24(1)));
            var wordPos :Int16 = data.wordPos; 
            var bitPos :Uint8 = data.bitPos;
            // all the 1s at or to the left of the bitPos
            var mask:SafeUint.Uint256 = SafeUint.Uint256(SafeUint.UINT_256_MAX).sub(SafeUint.Uint256(1).bitshiftLeft(bitPos).sub(SafeUint.Uint256(1)));
            var _self_wordPos = SafeUint.Uint256(switch(self.get(wordPos)){case(?_wordPos){_wordPos};case(_){0};});
            var masked:SafeUint.Uint256 = _self_wordPos.bitand(mask);
            // if there are no initialized ticks to the left of the current tick, return leftmost in the word
            initialized := masked.val() != 0;

            // overflow/underflow is possible, but prevented externally by limiting both tickSpacing and tick
            next := if (initialized){
                var leastSignificantBit:SafeUint.Uint8 = SafeUint.Uint8(switch (BitMath.leastSignificantBit(masked)) {
                    case (#ok(result)) { result; };
                    case (#err(code)) { return #err("TickBitmap BitMath.leastSignificantBit failed: " # debug_show(code)); };
                });
                compressed.add(SafeInt.Int24(1)).add(
                    SafeInt.Int24(IntUtils.toInt(leastSignificantBit.sub(SafeUint.Uint24(bitPos)).val(), 24))
                ).mul(
                    tickSpacing
                ).val();
            } else {
                compressed.add(SafeInt.Int24(1)).add(
                    SafeInt.Int24(IntUtils.toInt(SafeUint.Uint24(SafeUint.UINT_8_MAX).sub(SafeUint.Uint24(bitPos)).val(), 24))
                ).mul(
                    tickSpacing
                ).val();
            };
        };
        
        return #ok({
            next = next;
            initialized = initialized;
        });
    }
}
