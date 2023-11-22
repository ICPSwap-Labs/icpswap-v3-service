import Debug "mo:base/Debug";
import Nat "mo:base/Nat";
import Nat64 "mo:base/Nat64";
import Result "mo:base/Result";
import SafeUint "mo:commons/math/SafeUint";

module FullMath{

    type Uint256 = Nat;

    public func mulDiv(a: SafeUint.Uint256, b: SafeUint.Uint256, denominator: SafeUint.Uint256): Uint256 {
        return SafeUint.Uint256(a.val() * b.val() / denominator.val()).val();
    };

    public func mulDivRoundingUp(a: SafeUint.Uint256, b: SafeUint.Uint256, denominator: SafeUint.Uint256): Result.Result<Uint256, Text> {
        var result:SafeUint.Uint256 = SafeUint.Uint256(mulDiv(a, b, denominator));
        if (mulMod(a, b, denominator) > 0) {
            if(result.val() >= SafeUint.UINT_256_MAX){ return #err("FullMath illegal result"); };
            result := result.add(SafeUint.Uint256(1));
        };
        return #ok(result.val());
    };
    
    public func mulMod(x: SafeUint.Uint256, y: SafeUint.Uint256,z: SafeUint.Uint256): Uint256{
        var temp:SafeUint.Uint256 = x.mul(y);
        var r:SafeUint.Uint256 = temp.rem(z);
        return r.val();
    };
}
