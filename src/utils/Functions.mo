import Bool "mo:base/Bool";
import Hash "mo:base/Hash";
import Text "mo:base/Text";
import Types "../Types";

module {

    type Token = Types.Token;

    public func tokenEqual(t1 : Token, t2 : Token) : Bool {
        return Text.equal(t1.address, t2.address) and Text.equal(t1.standard, t2.standard);
    };
    public func tokenHash(t : Token) : Hash.Hash {
        return Text.hash(t.address # t.standard);
    };
};
