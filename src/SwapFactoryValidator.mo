import Array "mo:base/Array";
import Text "mo:base/Text";
import Bool "mo:base/Bool";
import Principal "mo:base/Principal";
import Cycles "mo:base/ExperimentalCycles";
import Result "mo:base/Result";
import Types "./Types";
import Buffer "mo:base/Buffer";

shared (initMsg) actor class SwapFactoryValidator(factoryCid : Principal, governanceCid : Principal) = this {

    public type Result = { #Ok : Text; #Err : Text; };

    private var _factoryAct = actor (Principal.toText(factoryCid)) : Types.SwapFactoryActor;

    public shared ({ caller }) func batchClearRemovedPoolValidate(poolCids : [Principal]) : async Result {
        assert (Principal.equal(caller, governanceCid));
        switch (await _factoryAct.getRemovedPools()) {
            case (#ok(pools)) {
                for (poolCid in poolCids.vals()) {
                    var existingFlag = false;
                    for (it in pools.vals()) {
                        if (Principal.equal(poolCid, it.canisterId)) {
                            existingFlag := true;
                        };
                    };
                    if (not existingFlag) { return #Err(Principal.toText(poolCid) # " doesn't exist."); };
                };
                return #Ok(debug_show (poolCids));
            };
            case (#err(msg)) {
                return #Err(debug_show (msg));
            };
        };
    };

    public shared ({ caller }) func batchRemovePoolsValidate(poolCids : [Principal]) : async Result {
        assert (Principal.equal(caller, governanceCid));
        switch (await _factoryAct.getPools()) {
            case (#ok(pools)) {
                for (poolCid in poolCids.vals()) {
                    var existingFlag = false;
                    for (it in pools.vals()) {
                        if (Principal.equal(poolCid, it.canisterId)) {
                            existingFlag := true;
                        };
                    };
                    if (not existingFlag) { return #Err(Principal.toText(poolCid) # " doesn't exist."); };
                };
                return #Ok(debug_show (poolCids));
            };
            case (#err(msg)) {
                return #Err(debug_show (msg));
            };
        };
    };

    public shared ({ caller }) func batchSetPoolAvailableValidate(poolCids : [Principal], available : Bool) : async Result {
        assert (Principal.equal(caller, governanceCid));
        switch (await _checkPools(poolCids)) {
            case (#ok(_)) { return #Ok(debug_show (poolCids) # ", " # debug_show (available)); };
            case (#err(msg)) { return #Err(debug_show (msg)); };
        };
    };

    public shared ({ caller }) func batchSetPoolLimitOrderAvailableValidate(poolCids : [Principal], available : Bool) : async Result {
        assert (Principal.equal(caller, governanceCid));
        switch (await _checkPools(poolCids)) {
            case (#ok(_)) { return #Ok(debug_show (poolCids) # ", " # debug_show (available)); };
            case (#err(msg)) { return #Err(debug_show (msg)); };
        };
    };

    public shared ({ caller }) func setAdminsValidate(admins : [Principal]) : async Result {
        assert (Principal.equal(caller, governanceCid));
        // Check for anonymous principals
        for (admin in admins.vals()) {
            if (Principal.isAnonymous(admin)) {
                return #Err("Anonymous principals cannot be pool admins");
            };
        };
        return #Ok(debug_show (admins));
    };

    public shared ({ caller }) func batchAddPoolControllersValidate(poolCids : [Principal], controllers : [Principal]) : async Result {
        assert (Principal.equal(caller, governanceCid));
        switch (await _checkAllPools(poolCids)) {
            case (#ok(_)) {
                return #Ok(debug_show (poolCids) # ", " # debug_show (controllers));
            };
            case (#err(msg)) {
                return #Err(debug_show (msg));
            };
        };
    };

    public shared ({ caller }) func batchRemovePoolControllersValidate(poolCids : [Principal], controllers : [Principal]) : async Result {
        assert (Principal.equal(caller, governanceCid));
        switch (await _checkPools(poolCids)) {
            case (#ok(_)) {
                for (it in controllers.vals()) {
                    if (Principal.equal(it, factoryCid)) {
                        return #Err("SwapFactory must be the controller of SwapPool");
                    };
                };
                return #Ok(debug_show (poolCids) # ", " # debug_show (controllers));
            };
            case (#err(msg)) {
                return #Err(debug_show (msg));
            };
        };
    };

    public shared ({ caller }) func batchSetPoolAdminsValidate(poolCids : [Principal], admins : [Principal]) : async Result {
        assert (Principal.equal(caller, governanceCid));
        // Check for anonymous principals
        for (admin in admins.vals()) {
            if (Principal.isAnonymous(admin)) {
                return #Err("Anonymous principals cannot be pool admins");
            };
        };
        switch (await _checkPools(poolCids)) {
            case (#ok(_)) {
                return #Ok(debug_show (poolCids) # ", " # debug_show (admins));
            };
            case (#err(msg)) {
                return #Err(debug_show (msg));
            };
        };
    };

    public shared ({ caller }) func setUpgradePoolListValidate(args : Types.UpgradePoolArgs) : async Result {
        assert (Principal.equal(caller, governanceCid));
        // set a limit on the number of upgrade tasks
        if (Array.size(args.poolIds) > 500) { return #Err("The number of canisters to be upgraded cannot be set to more than 500"); };
        // check task map is empty
        switch (await _factoryAct.getPendingUpgradePoolList()) {
            case (#ok(list)) {
                if (Array.size(list) > 0) {
                    return #Err("Please wait until the upgrade task list is empty");
                };
            };
            case (#err(msg)) {
                return #Err("Get pending upgrade pool list failed: " # debug_show(msg));
            };
        };        
        switch (await _checkPools(args.poolIds)) {
            case (#ok(_)) { return #Ok(debug_show (args)); };
            case (#err(msg)) { return #Err(debug_show (msg)); };
        };
    };

    public query func getInitArgs() : async Result.Result<{    
        factoryCid : Principal;
        governanceCid : Principal;
    }, Types.Error> {
        #ok({
            factoryCid = factoryCid;
            governanceCid = governanceCid;
        });
    };

    public shared func getCycleInfo() : async Result.Result<Types.CycleInfo, Types.Error> {
        return #ok({
            balance = Cycles.balance();
            available = Cycles.available();
        });
    };

    private func _checkPool(poolCid : Principal) : async Bool {
        switch (await _factoryAct.getPools()) {
            case (#ok(pools)) {
                for (it in pools.vals()) {
                    if (Principal.equal(poolCid, it.canisterId)) {
                        return true;
                    };
                };
                return false;
            };
            case (#err(_)) {
                return false;
            };
        };
    };

    private func _checkRemovedPool(poolCid : Principal) : async Bool {
        switch (await _factoryAct.getRemovedPools()) {
            case (#ok(pools)) {
                for (it in pools.vals()) {
                    if (Principal.equal(poolCid, it.canisterId)) {
                        return true;
                    };
                };
                return false;
            };
            case (#err(_)) {
                return false;
            };
        };
    };

    private func _checkPoolsHelper(poolCids: [Principal], pools: [Types.PoolData]) : Result.Result<Text, Text> {
        for (it1 in poolCids.vals()) {
            var found = false;
            label l {
                for (it2 in pools.vals()) {
                    if (Principal.equal(it1, it2.canisterId)) {
                        found := true;
                        break l;
                    };
                };
            };
            if (not found) { return #err(Principal.toText(it1) # " doesn't exist."); };
        };
        return #ok("");
    };

    private func _checkPools(poolCids : [Principal]) : async Result.Result<Text, Text> {
        switch (await _factoryAct.getPools()) {
            case (#ok(pools)) { _checkPoolsHelper(poolCids, pools); };
            case (#err(msg)) { #err("Get pools failed: " # debug_show (msg)); };
        };
    };

    private func _checkRemovedPools(poolCids : [Principal]) : async Result.Result<Text, Text> {
        switch (await _factoryAct.getRemovedPools()) {
            case (#ok(pools)) { _checkPoolsHelper(poolCids, pools); };
            case (#err(msg)) { #err("Get removed pools failed: " # debug_show (msg)); };
        };
    };

    private func _checkAllPools(poolCids : [Principal]) : async Result.Result<Text, Text> {
        var poolDataBuffer : Buffer.Buffer<Types.PoolData> = Buffer.Buffer<Types.PoolData>(0);  
        switch (await _factoryAct.getPools()) {
            case (#ok(pools)) {
                for (it in pools.vals()) {
                    poolDataBuffer.add(it);
                };
            };
            case (#err(msg)) { return #err("Get pools failed: " # debug_show (msg)); };
        };
        switch (await _factoryAct.getRemovedPools()) {
            case (#ok(removedPools)) {
                for (it in removedPools.vals()) {
                    poolDataBuffer.add(it);
                };
            };
            case (#err(msg)) { return #err("Get removed pools failed: " # debug_show (msg)); };
        };
        return _checkPoolsHelper(poolCids, Buffer.toArray(poolDataBuffer));
    };

};
