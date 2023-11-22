import Principal "mo:base/Principal";
import Blob "mo:base/Blob";
import Nat8 "mo:base/Nat8";
import Array "mo:base/Array";
import Text "mo:base/Text";

module {

    public func principalToBlob(p: Principal): Blob {
        var arr: [Nat8] = Blob.toArray(Principal.toBlob(p));
        var defaultArr: [var Nat8] = Array.init<Nat8>(32, 0);
        defaultArr[0] := Nat8.fromNat(arr.size());
        var ind: Nat = 0;
        while (ind < arr.size() and ind < 32) {
            defaultArr[ind + 1] := arr[ind];
            ind := ind + 1;
        };
        return Blob.fromArray(Array.freeze(defaultArr));
    };

    public func isEmptyIdentity(caller: Principal): Bool {
        var principal = Principal.toText(caller);
        if (Text.equal(principal, "2vxsx-fae")) {
            return true;
        };
        return false;
    };
}