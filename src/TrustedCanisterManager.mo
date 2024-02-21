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

    private stable var _canisterIds : [Principal] = [];

    public shared (msg) func addCanisterId(canisterId : Principal) : async Bool {
        _checkPermission(msg.caller);
        var canisterIdList : List.List<Principal> = List.fromArray(_canisterIds);
        if (not CollectionUtils.listContains(canisterIdList, canisterId, Principal.equal)) {
            canisterIdList := List.push(canisterId, canisterIdList);
            _canisterIds := List.toArray(canisterIdList);
            true;
        } else {
            false;
        };
    };

    public shared (msg) func deleteCanisterId(canisterId : Principal) : async Bool {
        _checkPermission(msg.caller);
        _canisterIds := CollectionUtils.arrayRemove(_canisterIds, canisterId, Principal.equal);
        true;
    };

    public query (msg) func checkCanisterId(canisterId : Principal) : async Bool {
        if (CollectionUtils.arrayContains(_canisterIds, canisterId, Principal.equal)) {
            true;
        } else {
            false;
        };
    };

    public query (msg) func getCanisterIds() : async [Principal] {
        _canisterIds;
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
