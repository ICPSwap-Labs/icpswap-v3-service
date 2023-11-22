import Nat "mo:base/Nat";
import SafeUint "mo:commons/math/SafeUint";

module {
    type Uint256 = Nat;

    public func divRoundingUp(x:SafeUint.Uint256, y:SafeUint.Uint256): Uint256 {
       return x.div(y).add(SafeUint.Uint256(gt(x.rem(y).val(), 0))).val()
    };

    private func gt(x: Nat, y: Nat): Nat {
        var r = 0;
        if (x > y) {
            r := 1
        };
        r;
    };
}
