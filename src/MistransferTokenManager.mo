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

shared (initMsg) actor class MistransferTokenManager(
    governanceCid : ?Principal
) = this {

    private stable var _tokens : [Types.Token] = [];

    public shared (msg) func addToken(token : Types.Token) : async Result.Result<Bool, Types.Error> {
        _checkPermission(msg.caller);
        var tokenList : List.List<Types.Token> = List.fromArray(_tokens);
        if (not CollectionUtils.listContains(tokenList, token, Functions.tokenEqual)) {
            tokenList := List.push(token, tokenList);
            _tokens := List.toArray(tokenList);
        };
        return #ok(true);
    };

    public shared (msg) func deleteToken(token : Types.Token) : async Result.Result<Bool, Types.Error> {
        _checkPermission(msg.caller);
        _tokens := CollectionUtils.arrayRemove(_tokens, token, Functions.tokenEqual);
        return #ok(true);
    };

    public query (msg) func checkToken(token : Types.Token) : async Bool {
        if (CollectionUtils.arrayContains(_tokens, token, Functions.tokenEqual)) {
            true;
        } else {
            false;
        };
    };

    public query (msg) func getTokens() : async Result.Result<[Types.Token], Types.Error> {
        #ok(_tokens);
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
