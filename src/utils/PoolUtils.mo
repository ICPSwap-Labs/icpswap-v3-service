import Text "mo:base/Text";
import Nat "mo:base/Nat";
import Blob "mo:base/Blob";
import Nat8 "mo:base/Nat8";
import Nat64 "mo:base/Nat64";
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
}