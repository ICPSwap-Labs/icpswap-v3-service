import Text "mo:base/Text";
import Nat "mo:base/Nat";
import Nat8 "mo:base/Nat8";
import Int "mo:base/Int";
import Hash "mo:base/Hash";
import List "mo:base/List";
import Principal "mo:base/Principal";
import Cycles "mo:base/ExperimentalCycles";
import Time "mo:base/Time";
import Timer "mo:base/Timer";
import Float "mo:base/Float";
import Debug "mo:base/Debug";
import Blob "mo:base/Blob";
import Buffer "mo:base/Buffer";
import HashMap "mo:base/HashMap";
import Error "mo:base/Error";
import Iter "mo:base/Iter";
import Option "mo:base/Option";
import Result "mo:base/Result";
import TokenAdapterTypes "mo:token-adapter/Types";
import TokenFactory "mo:token-adapter/TokenFactory";
import Types "./Types";
import AccountUtils "./utils/AccountUtils";
import Prim "mo:⛔";
import CollectionUtils "mo:commons/utils/CollectionUtils";
import SwapAgent "./SwapAgent";

shared (initMsg) actor class SwapAgentManager(
    governanceCid : ?Principal
) = this {

    private stable var _initCycles : Nat = 1860000000000;
    private stable var _poolAgentList : [(Principal, Principal)] = [];
    private var _poolAgentMap : HashMap.HashMap<Principal, Principal> = HashMap.fromIter(_poolAgentList.vals(), 0, Principal.equal, Principal.hash);

    private let IC0 = actor "aaaaa-aa" : actor {
        canister_status : { canister_id : Principal } -> async {
            settings : { controllers : [Principal] };
        };
        update_settings : {
            canister_id : Principal;
            settings : { controllers : [Principal] };
        } -> ();
    };

    public shared (msg) func createAgent(args : Types.CreateAgentArgs) : async Result.Result<Principal, Types.Error> {
        _checkAdminPermission(msg.caller);
        let poolAct = actor (Principal.toText(args.poolCid)) : Types.SwapPoolActor;
        let metadata = switch (await poolAct.metadata()) {
            case (#ok(metadata)) { metadata };
            case (#err(code)) { return #err(#InternalError("Verify pool metadata failed: " # debug_show (code))); };
        };

        if (not _lock()) {
            return #err(#InternalError("Please wait for previous creating job finished"));
        };

        var agentCid = switch (_poolAgentMap.get(args.poolCid)) {
            case (?agent) { agent };
            case (_) {
                try {
                    Cycles.add(_initCycles);
                    let agentActor = await SwapAgent.SwapAgent(metadata.token0, metadata.token1, args.poolCid, args.governanceCid);
                    let agent = Principal.fromActor(agentActor);
                    await _addAgentControllers(agent, [args.governanceCid]);
                    _poolAgentMap.put(args.poolCid, agent);
                    agent;
                } catch (e) {
                    throw Error.reject("Create agent failed: " # Error.message(e));
                };
            };
        };

        _unlock();

        return #ok(agentCid);
    };

    public shared (msg) func removeAgent(poolCid : Principal) : async ?Principal {
        _checkAdminPermission(msg.caller);
        _poolAgentMap.remove(poolCid);
    };

    public query func getAgent(poolCid : Principal) : async Result.Result<Principal, Types.Error> {
        switch (_poolAgentMap.get(poolCid)) {
            case (?agent) { #ok(agent) };
            case (_) { #err(#InternalError("No such agent.")) };
        };
    };

    public query func getPoolAgents() : async Result.Result<[(Principal, Principal)], Types.Error> {
        return #ok(Iter.toArray(_poolAgentMap.entries()));
    };

    public query func getCycleInfo() : async Result.Result<Types.CycleInfo, Types.Error> {
        return #ok({
            balance = Cycles.balance();
            available = Cycles.available();
        });
    };

    public shared (msg) func addAgentControllers(agentCid : Principal, controllers : [Principal]) : async () {
        _checkAdminPermission(msg.caller);
        await _addAgentControllers(agentCid, controllers);
    };

    public shared (msg) func removeAgentControllers(agentCid : Principal, controllers : [Principal]) : async () {
        _checkAdminPermission(msg.caller);
        if (not _checkAgentControllers(controllers)){
            throw Error.reject("SwapAgentManager must be the controller of SwapAgent");
        };
        await _removeAgentControllers(agentCid, controllers);
    };

    public shared (msg) func setAgentAdmins(agentCid : Principal, admins : [Principal]) : async () {
        _checkAdminPermission(msg.caller);
        await _setAgentAdmins(agentCid, admins);
    };

    private func _setAgentAdmins(agentCid : Principal, admins : [Principal]) : async () {
        let agentAct = actor (Principal.toText(agentCid)) : actor { setAdmins : shared ([Principal]) -> async (); };
        await agentAct.setAdmins(admins);
    };

    private func _addAgentControllers(agentCid : Principal, controllers : [Principal]) : async () {
        let { settings } = await IC0.canister_status({ canister_id = agentCid });
        var controllerList = List.append(List.fromArray(settings.controllers), List.fromArray(controllers));
        IC0.update_settings({ canister_id = agentCid; settings = { controllers = List.toArray(controllerList) }; });
    };

    private func _removeAgentControllers(agentCid : Principal, controllers : [Principal]) : async () {
        let buffer: Buffer.Buffer<Principal> = Buffer.Buffer<Principal>(0);
        let { settings } = await IC0.canister_status({ canister_id = agentCid });
        for (it in settings.controllers.vals()) {
            if (not CollectionUtils.arrayContains<Principal>(controllers, it, Principal.equal)) {
                buffer.add(it);
            };
        };
        IC0.update_settings({ canister_id = agentCid; settings = { controllers = Buffer.toArray<Principal>(buffer) }; });
    };

    private func _checkAgentControllers(controllers : [Principal]) : Bool {
        let managerCid : Principal = Principal.fromActor(this);
        for (it in controllers.vals()) {
            if (Principal.equal(it, managerCid)) {
                return false;
            };
        };
        true;
    };

    //--------------------------- Lock ------------------------------------
    private stable var _lockState : Types.LockState = {
        locked = false;
        time = 0;
    };
    private func _lock() : Bool {
        let now = Time.now();
        if ((not _lockState.locked) or ((now - _lockState.time) > 1000000000 * 60)) {
            _lockState := { locked = true; time = now };
            return true;
        };
        return false;
    };
    private func _unlock() {
        _lockState := { locked = false; time = 0 };
    };

    // --------------------------- ACL ------------------------------------
    private stable var _admins : [Principal] = [];
    public shared (msg) func setAdmins(admins : [Principal]) : async () {
        _checkControllerPermission(msg.caller);
        _admins := admins;
    };
    public query (msg) func getAdmins() : async [Principal] {
        return _admins;
    };
    private func _checkControllerPermission(caller : Principal) {
        assert (Prim.isController(caller));
    };
    private func _checkAdminPermission(caller : Principal) {
        assert (
            CollectionUtils.arrayContains<Principal>(_admins, caller, Principal.equal) or
            (switch (governanceCid) {case (?cid) { Principal.equal(caller, cid) }; case (_) { false };}) or
            Prim.isController(caller)
        );
    };

    // --------------------------- LIFE CYCLE -----------------------------------
    system func preupgrade() {
        _poolAgentList := Iter.toArray(_poolAgentMap.entries());
    };

    system func postupgrade() {
        _poolAgentList := [];
    };
};
