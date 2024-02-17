import Blob "mo:base/Blob";
import Bool "mo:base/Bool";
import Time "mo:base/Time";
import Hash "mo:base/Hash";
import Int "mo:base/Int";
import Nat "mo:base/Nat";
import Nat32 "mo:base/Nat32";
import Principal "mo:base/Principal";
import Result "mo:base/Result";
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
