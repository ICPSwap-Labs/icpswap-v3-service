import Text "mo:base/Text";
import Nat "mo:base/Nat";
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
    
}