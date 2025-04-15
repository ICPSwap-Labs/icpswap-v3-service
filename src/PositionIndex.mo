import Text "mo:base/Text";
import Nat "mo:base/Nat";
import List "mo:base/List";
import Principal "mo:base/Principal";
import Cycles "mo:base/ExperimentalCycles";
import Timer "mo:base/Timer";
import Buffer "mo:base/Buffer";
import HashMap "mo:base/HashMap";
import Iter "mo:base/Iter";
import Result "mo:base/Result";
import Bool "mo:base/Bool";
import Prim "mo:⛔";

import ListUtils "mo:commons/utils/ListUtils";
import CollectionUtils "mo:commons/utils/CollectionUtils";
import PrincipalUtils "mo:commons/utils/PrincipalUtils";

import Types "./Types";
import ICRCTypes "./ICRCTypes";
import ICRC21 "./components/ICRC21";

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
            case (#err(_)) {};
        };
    };

    private func _autoUpdatePoolIds() : async () { await _updatePoolIds(); };
    let __updatePoolIdsPer30s = Timer.recurringTimer<system>(#seconds(30), _autoUpdatePoolIds);

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

    public shared func updatePoolIds() : async () {
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

    public shared func getCycleInfo() : async Result.Result<Types.CycleInfo, Types.Error> {
        return #ok({
            balance = Cycles.balance();
            available = Cycles.available();
        });
    };

    // --------------------------- ICRC28 ------------------------------------
    private stable var _icrc28_trusted_origins : [Text] = [
        "https://standards.identitykit.xyz",
        "https://dev.standards.identitykit.xyz",
        "https://demo.identitykit.xyz",
        "https://dev.demo.identitykit.xyz",
        "http://localhost:3001",
        "http://localhost:3002",
        "https://nfid.one",
        "https://dev.nfid.one",
        "https://app.icpswap.com",
        "https://bplw4-cqaaa-aaaag-qcb7q-cai.icp0.io"
    ];
    public shared(msg) func setIcrc28TrustedOrigins(origins: [Text]) : async Result.Result<Bool, ()> {
        assert(Prim.isController(msg.caller));
        _icrc28_trusted_origins := origins;
        return #ok(true);
    };
    public func icrc28_trusted_origins() : async ICRCTypes.Icrc28TrustedOriginsResponse {
        return {trusted_origins = _icrc28_trusted_origins};
    };
    public query func icrc10_supported_standards() : async [{ url : Text; name : Text }] {
        return ICRC21.icrc10_supported_standards();
    };
    public shared func icrc21_canister_call_consent_message(request : ICRCTypes.Icrc21ConsentMessageRequest) : async ICRCTypes.Icrc21ConsentMessageResponse {
        return ICRC21.icrc21_canister_call_consent_message(request);
    };

    // --------------------------- Version Control ------------------------------------
    private var _version : Text = "3.6.0";
    public query func getVersion() : async Text { _version };

    system func preupgrade() {
        _userPoolEntries := Iter.toArray(_userPools.entries());
    };

    system func postupgrade() {
        _userPoolEntries := [];
    };
};
