import Text "mo:base/Text";
import Nat "mo:base/Nat";
import Blob "mo:base/Blob";
import Nat8 "mo:base/Nat8";
import Array "mo:base/Array";
import Types "../Types";

module {

    public func getPoolKey(token0: Types.Token, token1: Types.Token, fee: Nat): Text {
        if (token0.address > token1.address) {
            token1.address # "_" # token0.address # "_" # Nat.toText(fee);
        } else {
            token0.address # "_" # token1.address # "_" # Nat.toText(fee);
        };
    };

    public func sort(token0: Types.Token, token1: Types.Token): (Types.Token, Types.Token) {
        if (token0.address > token1.address) {
            (token1, token0)
        } else {
            (token0, token1)
        };
    };
    public func natToBlob(x: Nat): Blob {
        let arr: [Nat8] = fromNat(8, x);
        return Blob.fromArray(arr);
    };
    public func fromNat(len : Nat, n : Nat) : [Nat8] {
        let ith_byte = func(i : Nat) : Nat8 {
        	assert(i < len);
            let shift : Nat = 8 * (len - 1 - i);
            Nat8.fromIntWrap(n / 2 ** shift)
        };
        return Array.tabulate<Nat8>(len, ith_byte);
    };

    public func hexToNat8Array(hex: Text): [Nat8] {
        let chars = Text.toIter(hex);
        let size = Text.size(hex) / 2;
        let arr = Array.init<Nat8>(size, 0);
        var i = 0;
        var j = 0;
        var current: Nat8 = 0;
        for (char in chars) {
            let digit = switch (char) {
                case ('0') 0;
                case ('1') 1;
                case ('2') 2;
                case ('3') 3;
                case ('4') 4;
                case ('5') 5;
                case ('6') 6;
                case ('7') 7;
                case ('8') 8;
                case ('9') 9;
                case ('a') 10;
                case ('b') 11;
                case ('c') 12;
                case ('d') 13;
                case ('e') 14;
                case ('f') 15;
                case ('A') 10;
                case ('B') 11;
                case ('C') 12;
                case ('D') 13;
                case ('E') 14;
                case ('F') 15;
                case (_) 0;
            };
            if (i % 2 == 0) {
                current := Nat8.fromNat(digit * 16);
            } else {
                current := current + Nat8.fromNat(digit);
                arr[j] := current;
                j += 1;
            };
            i += 1;
        };
        Array.freeze(arr);
    };
}