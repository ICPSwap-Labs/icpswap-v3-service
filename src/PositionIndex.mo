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
import ListUtils "mo:commons/utils/ListUtils";
import Bool "mo:base/Bool";
import CollectionUtils "mo:commons/utils/CollectionUtils";
import PrincipalUtils "mo:commons/utils/PrincipalUtils";
import Prim "mo:⛔";

shared (initMsg) actor class PositionIndex(
    factoryCid : Principal
) {

    private stable var _poolIds : [Text] = [];
    private stable var _userPoolEntries : [(Text, [Text])] = [];
    private var _userPools : HashMap.HashMap<Text, [Text]> = HashMap.fromIter<Text, [Text]>(_userPoolEntries.vals(), 0, Text.equal, Text.hash);

    private var _factoryAct = actor (Principal.toText(factoryCid)) : Types.SwapFactoryActor;

    private func _updatePoolIds() : async () {
        switch (await _factoryAct.getPools()) {
            case (#ok(pools)) {
                var poolIds : Buffer.Buffer<Text> = Buffer.Buffer<Text>(0);
                for (pool in pools.vals()) {
                    poolIds.add(Principal.toText(pool.canisterId));
                };
                _poolIds := Buffer.toArray(poolIds);
            };
            case (#err(msg)) {};
        };
    };

    private func _autoUpdatePoolIds() : async () {
        await _updatePoolIds();
    };
    let __updatePoolIdsPer30s = Timer.recurringTimer(
        #seconds(30),
        _autoUpdatePoolIds,
    );

    public shared (msg) func addPoolId(poolId : Text) : async Result.Result<Bool, Types.Error> {
        var user : Text = PrincipalUtils.toAddress(msg.caller);
        if (ListUtils.arrayContains(_poolIds, poolId, Text.equal)) {
            switch (_userPools.get(user)) {
                case (?poolArray) {
                    var poolList : List.List<Text> = List.fromArray(poolArray);
                    if (not ListUtils.arrayContains(poolArray, poolId, Text.equal)) {
                        poolList := List.push(poolId, poolList);
                        _userPools.put(user, List.toArray(poolList));
                    };
                };
                case (_) {
                    var poolList = List.nil<Text>();
                    poolList := List.push(poolId, poolList);
                    _userPools.put(user, List.toArray(poolList));
                };
            };
            return #ok(true);
        } else {
            return #err(#InternalError("invalid pool id"));
        };
    };

    public shared (msg) func removePoolId(poolId : Text) : async Result.Result<Bool, Types.Error> {
        var user : Text = PrincipalUtils.toAddress(msg.caller);
        // check if the user owns positions in the pool
        var poolAct = actor (poolId) : Types.SwapPoolActor;
        switch (await poolAct.getUserPositionIdsByPrincipal(msg.caller)) {
            case (#ok(positionIds)) {
                if (Nat.equal(positionIds.size(), 0)) {
                    switch (_userPools.get(user)) {
                        case (?poolArray) {
                            _userPools.put(user, CollectionUtils.arrayRemove(poolArray, poolId, Text.equal));
                        };
                        case (_) {};
                    };
                };
            };
            case (#err(msg)) {};
        };
        return #ok(true);
    };

    public shared (msg) func removePoolIdWithoutCheck(poolId : Text) : async Result.Result<Bool, Types.Error> {
        var user : Text = PrincipalUtils.toAddress(msg.caller);
        switch (_userPools.get(user)) {
            case (?poolArray) {
                _userPools.put(user, CollectionUtils.arrayRemove(poolArray, poolId, Text.equal));
            };
            case (_) {};
        };
        return #ok(true);
    };

    public shared (msg) func updatePoolIds() : async () {
        await _updatePoolIds();
    };

    public query func getUserPools(user : Text) : async Result.Result<[Text], Types.Error> {
        switch (_userPools.get(user)) {
            case (?poolArray) {
                return #ok(poolArray);
            };
            case (_) {
                return #ok([]);
            };
        };
    };

    public query func getPools() : async Result.Result<[Text], Types.Error> {
        return #ok(_poolIds);
    };

    public shared (msg) func getCycleInfo() : async Result.Result<Types.CycleInfo, Types.Error> {
        return #ok({
            balance = Cycles.balance();
            available = Cycles.available();
        });
    };

    system func preupgrade() {
        _userPoolEntries := Iter.toArray(_userPools.entries());
    };

    system func postupgrade() {
        _userPoolEntries := [];
    };
};
