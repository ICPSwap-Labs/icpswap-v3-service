import Text "mo:base/Text";
import Array "mo:base/Array";
import Nat "mo:base/Nat";
import List "mo:base/List";
import Int "mo:base/Int";
import Hash "mo:base/Hash";
import Principal "mo:base/Principal";
import Cycles "mo:base/ExperimentalCycles";
import Time "mo:base/Time";
import Timer "mo:base/Timer";
import Debug "mo:base/Debug";
import Blob "mo:base/Blob";
import Buffer "mo:base/Buffer";
import HashMap "mo:base/HashMap";
import Iter "mo:base/Iter";
import Option "mo:base/Option";
import Result "mo:base/Result";
import Types "./Types";
import Bool "mo:base/Bool";
import Prim "mo:⛔";
import CollectionUtils "mo:commons/utils/CollectionUtils";
import Functions "./utils/Functions";

shared (initMsg) actor class TrustedCanisterManager(
    governanceCid : ?Principal
) = this {

    private stable var _canisters : [Principal] = [];

    public shared (msg) func addCanister(canister : Principal) : async Bool {
        _checkPermission(msg.caller);
        var canisterList : List.List<Principal> = List.fromArray(_canisters);
        if (not CollectionUtils.listContains(canisterList, canister, Principal.equal)) {
            canisterList := List.push(canister, canisterList);
            _canisters := List.toArray(canisterList);
            true;
        } else {
            false;
        };
    };

    public shared (msg) func deleteCanister(canister : Principal) : async Bool {
        _checkPermission(msg.caller);
        _canisters := CollectionUtils.arrayRemove(_canisters, canister, Principal.equal);
        true;
    };

    public query (msg) func isCanisterTrusted(canister : Principal) : async Bool {
        if (CollectionUtils.arrayContains(_canisters, canister, Principal.equal)) {
            true;
        } else {
            false;
        };
    };

    public query (msg) func getCanisters() : async [Principal] {
        _canisters;
    };

    public shared func getCycleInfo() : async Result.Result<Types.CycleInfo, Types.Error> {
        return #ok({
            balance = Cycles.balance();
            available = Cycles.available();
        });
    };

    private func _checkPermission(caller : Principal) {
        assert (Prim.isController(caller) or (switch (governanceCid) { case (?cid) { Principal.equal(caller, cid) }; case (_) { false } }));
    };

    system func preupgrade() {};

    system func postupgrade() {};
};
