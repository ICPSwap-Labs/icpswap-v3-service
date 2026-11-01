import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Principal "mo:base/Principal";

actor class MockLedger() {
    type Account = { owner : Principal; subaccount : ?Blob };
    type TransferArgs = {
        from : Account;
        from_subaccount : ?Blob;
        to : Account;
        amount : Nat;
        fee : ?Nat;
        memo : ?Blob;
        created_at_time : ?Nat64;
    };
    type TransferFromArgs = {
        from : Account;
        to : Account;
        amount : Nat;
        fee : ?Nat;
        memo : ?Blob;
        created_at_time : ?Nat64;
    };
    let ic = actor "aaaaa-aa" : actor { raw_rand : () -> async Blob };
    stable var nextBlock : Nat = 1;
    stable var delayCalls : Nat = 0;
    stable var transfers : [TransferArgs] = [];

    public shared func setDelay(calls : Nat) : async () { delayCalls := calls };
    public query func getTransfers() : async [TransferArgs] { transfers };
    public query func icrc1_fee() : async Nat { 1 };

    public shared func icrc2_transfer_from(_ : TransferFromArgs) : async { #Ok : Nat } {
        let block = nextBlock;
        nextBlock += 1;
        #Ok(block);
    };

    public shared func icrc1_transfer(args : TransferArgs) : async { #Ok : Nat } {
        let delay = delayCalls;
        var n : Nat = 0;
        while (n < delay) {
            ignore await ic.raw_rand();
            n += 1;
        };
        let block = nextBlock;
        nextBlock += 1;
        transfers := Array.append(transfers, [args]);
        #Ok(block);
    };
};
