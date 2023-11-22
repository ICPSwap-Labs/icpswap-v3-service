import Int "mo:base/Int";
import Nat "mo:base/Nat";

import Result "mo:base/Result";
import IntUtils "mo:commons/math/SafeInt/IntUtils";
import SafeUint "mo:commons/math/SafeUint";
import SafeInt "mo:commons/math/SafeInt";

module {
    type Uint128 = Nat;
    type Int128 = Int;

    public func addDelta(x: SafeUint.Uint128, y: SafeInt.Int128): Result.Result<Uint128, Text> {
        var z:SafeUint.Uint128 = SafeUint.Uint128(0);
        if (y.val() < 0) {
            z := x.sub(SafeUint.Uint128(IntUtils.toNat(-(y.val()), 128)));
            if(z.val() > x.val()){ return #err("addDelta failed z > x : z=" # debug_show(z.val()) # ", x=" # debug_show(x.val())); };
        } else {
            z := x.add(SafeUint.Uint128(IntUtils.toNat(y.val(), 128)));
            if(z.val() < x.val()){ return #err("addDelta failed z < x : z=" # debug_show(z.val()) # ", x=" # debug_show(x.val())); };
        };
        return #ok(z.val());
    }
}
