import Text "mo:base/Text";
import Nat "mo:base/Nat";
import Error "mo:base/Error";
import Bool "mo:base/Bool";
import Principal "mo:base/Principal";
import Cycles "mo:base/ExperimentalCycles";
import Result "mo:base/Result";
import PoolUtils "./utils/PoolUtils";
import Types "./Types";

shared (initMsg) actor class SwapFactoryValidator(factoryCid : Principal, governanceCid : Principal) = this {

    public type Result = {
        #Ok : Text;
        #Err : Text;
    };

    private var _factoryAct = actor (Principal.toText(factoryCid)) : Types.SwapFactoryActor;

    // public shared ({ caller }) func clearRemovedPoolValidate(canisterId : Principal) : async Result {
    //     assert (Principal.equal(caller, governanceCid));
    //     switch (await _factoryAct.getRemovedPools()) {
    //         case (#ok(pools)) {
    //             for (it in pools.vals()) {
    //                 if (Principal.equal(canisterId, it.canisterId)) {
    //                     return #Ok(debug_show (canisterId));
    //                 };
    //             };
    //             return #Err(Principal.toText(canisterId) # " doesn't exist.");
    //         };
    //         case (#err(msg)) {
    //             return #Err(debug_show (msg));
    //         };
    //     };
    // };

    public shared ({ caller }) func removePoolValidate(args : Types.GetPoolArgs) : async Result {
        assert (Principal.equal(caller, governanceCid));
        switch (await _factoryAct.getPool(args)) {
            case (#ok(pool)) {
                return #Ok(debug_show (args));
            };
            case (#err(msg)) {
                return #Err(debug_show (msg));
            };
        };
    };

    // public shared ({ caller }) func removePoolWithdrawErrorLogValidate(poolCid : Principal, id : Nat, rollback : Bool) : async Result {
    //     assert (Principal.equal(caller, governanceCid));

    //     if (rollback) {
    //         return #Err("rollback can only be false.");
    //     };

    //     if (not (await _checkPool(poolCid))) {
    //         return #Err(Principal.toText(poolCid) # " doesn't exist.");
    //     };
    //     var poolAct = actor (Principal.toText(poolCid)) : Types.SwapPoolActor;
    //     switch (await poolAct.getTransferLogs()) {
    //         case (#ok(logs)) {
    //             for (it in logs.vals()) {
    //                 if (Nat.equal(id, it.index)) {
    //                     return #Ok(debug_show (poolCid) # ", " # debug_show (id) # ", " # debug_show (rollback));
    //                 };
    //             };
    //             return #Err(Nat.toText(id) # " doesn't exist.");
    //         };
    //         case (#err(msg)) {
    //             return #Err(debug_show (msg));
    //         };
    //     };
    // };

    // public shared ({ caller }) func restorePoolValidate(poolId : Principal) : async Result {
    //     assert (Principal.equal(caller, governanceCid));

    //     // check if particular pair exists

    //     // check if the version is too old

    //     // check token's canister id and standard

    //     switch (await _factoryAct.getRemovedPools()) {
    //         case (#ok(pools)) {
    //             for (it in pools.vals()) {
    //                 if (Principal.equal(poolId, it.canisterId)) {
    //                     return #Ok(debug_show (poolId));
    //                 };
    //             };
    //             return #Err(Principal.toText(poolId) # " doesn't exist.");
    //         };
    //         case (#err(msg)) {
    //             return #Err(debug_show (msg));
    //         };
    //     };
    // };

    public shared ({ caller }) func upgradePoolTokenStandardValidate(poolCid : Principal, tokenCid : Principal) : async Result {
        assert (Principal.equal(caller, governanceCid));
        if (not (await _checkPool(poolCid))) {
            return #Err(Principal.toText(poolCid) # " doesn't exist.");
        };
        var poolAct = actor (Principal.toText(poolCid)) : Types.SwapPoolActor;
        switch (await poolAct.metadata()) {
            case (#ok(metadata)) {
                let token = if (Text.equal(Principal.toText(tokenCid), metadata.token0.address)) {
                    metadata.token0;
                } else if (Text.equal(Principal.toText(tokenCid), metadata.token1.address)) {
                    metadata.token1;
                } else {
                    return #Err("Token not found in pool");
                };
                let tokenAct = actor (token.address) : actor {
                    icrc1_supported_standards : query () -> async [{
                        url : Text;
                        name : Text;
                    }];
                };
                try {
                    var supportStandards = await tokenAct.icrc1_supported_standards();
                    var isICRC2Supported = false;
                    label l {
                        for (supportStandard in supportStandards.vals()) {
                            if (Text.equal("ICRC-2", supportStandard.name)) {
                                isICRC2Supported := true;
                                break l;
                            };
                        };
                    };
                    if (isICRC2Supported) {
                        return #Ok(debug_show (poolCid) # ", " # debug_show (tokenCid));
                    } else {
                        return #Err("Check icrc1_supported_standards failed");
                    };
                } catch (e) {
                    return #Err("Get icrc1_supported_standards failed: " # Error.message(e));
                };
            };
            case (#err(code)) {
                return #Err("Get pool metadata failed: " # debug_show (code));
            };
        };
    };

    public shared ({ caller }) func addPoolControllersValidate(poolCid : Principal, controllers : [Principal]) : async Result {
        assert (Principal.equal(caller, governanceCid));
        if (not (await _checkPool(poolCid))) {
            return #Err(Principal.toText(poolCid) # " doesn't exist.");
        };
        return #Ok(debug_show (poolCid) # ", " # debug_show (controllers));
    };

    public shared ({ caller }) func removePoolControllersValidate(poolCid : Principal, controllers : [Principal]) : async Result {
        assert (Principal.equal(caller, governanceCid));
        if (not (await _checkPool(poolCid))) {
            return #Err(Principal.toText(poolCid) # " doesn't exist.");
        };
        for (it in controllers.vals()) {
            if (Principal.equal(it, factoryCid)) {
                return #Err("SwapFactory must be the controller of SwapPool");
            };
        };
        return #Ok(debug_show (poolCid) # ", " # debug_show (controllers));
    };

    // public shared ({ caller }) func setPoolAvailableValidate(poolCid : Principal, available : Bool) : async Result {
    //     assert (Principal.equal(caller, governanceCid));
    //     if (not (await _checkPool(poolCid))) {
    //         return #Err(Principal.toText(poolCid) # " doesn't exist.");
    //     };
    //     return #Ok(debug_show (poolCid) # ", " # debug_show (available));
    // };

    public shared ({ caller }) func setPoolAdminsValidate(poolCid : Principal, admins : [Principal]) : async Result {
        assert (Principal.equal(caller, governanceCid));
        if (not (await _checkPool(poolCid))) {
            return #Err(Principal.toText(poolCid) # " doesn't exist.");
        };
        return #Ok(debug_show (poolCid) # ", " # debug_show (admins));
    };

    public shared ({ caller }) func batchAddPoolControllersValidate(poolCids : [Principal], controllers : [Principal]) : async Result {
        assert (Principal.equal(caller, governanceCid));
        switch (await _checkPools(poolCids)) {
            case (#ok(r)) {
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
            case (#ok(r)) {
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
        switch (await _checkPools(poolCids)) {
            case (#ok(r)) {
                return #Ok(debug_show (poolCids) # ", " # debug_show (admins));
            };
            case (#err(msg)) {
                return #Err(debug_show (msg));
            };
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
            case (#err(msg)) {
                return false;
            };
        };
    };

    private func _checkPools(poolCids : [Principal]) : async Result.Result<Text, Text> {
        switch (await _factoryAct.getPools()) {
            case (#ok(pools)) {
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
                    if (not found) {
                        return #err(Principal.toText(it1) # " doesn't exist.");
                    };
                };
                return #ok("");
            };
            case (#err(msg)) {
                return #err("Get pools failed: " # debug_show (msg));
            };
        };
    };

};
