import Text "mo:base/Text";
import Nat "mo:base/Nat";
import Error "mo:base/Error";
import Bool "mo:base/Bool";
import Principal "mo:base/Principal";
import Result "mo:base/Result";
import PoolUtils "./utils/PoolUtils";
import Types "./Types";

shared (initMsg) actor class SwapFactoryValidator(factoryCid : Principal, governanceCid : Principal) = this {

    private var _factoryAct = actor (Principal.toText(factoryCid)) : Types.SwapFactoryActor;

    public shared ({ caller }) func clearRemovedPoolValidate(canisterId : Principal) : async Result.Result<Text, Text> {
        assert (Principal.equal(caller, governanceCid));
        switch (await _factoryAct.getRemovedPools()) {
            case (#ok(pools)) {
                for (it in pools.vals()) {
                    if (Principal.equal(canisterId, it.canisterId)) {
                        return #ok(debug_show (canisterId));
                    };
                };
                return #err(Principal.toText(canisterId) # " not exist.");
            };
            case (#err(msg)) {
                return #err(debug_show (msg));
            };
        };
    };

    public shared ({ caller }) func removePoolValidate(args : Types.GetPoolArgs) : async Result.Result<Text, Text> {
        assert (Principal.equal(caller, governanceCid));
        switch (await _factoryAct.getPool(args)) {
            case (#ok(pool)) {
                return #ok(debug_show (args));
            };
            case (#err(msg)) {
                return #err(debug_show (msg));
            };
        };
    };

    public shared ({ caller }) func removePoolWithdrawErrorLogValidate(poolCid : Principal, id : Nat, rollback : Bool) : async Result.Result<Text, Text> {
        assert (Principal.equal(caller, governanceCid));
        if (not (await _checkPool(poolCid))) {
            return #err(Principal.toText(poolCid) # " not exist.");
        };
        var poolAct = actor (Principal.toText(poolCid)) : Types.SwapPoolActor;
        switch (await poolAct.getTransferLogs()) {
            case (#ok(logs)) {
                for (it in logs.vals()) {
                    if (Nat.equal(id, it.index)) {
                        return #ok(debug_show(poolCid) # ", " # debug_show(id) # ", " # debug_show(rollback));
                    };
                };
                return #err(Nat.toText(id) # " not exist.");
            };
            case (#err(msg)) {
                return #err(debug_show (msg));
            };
        };
    };

    public shared ({ caller }) func restorePoolValidate(poolId : Principal) : async Result.Result<Text, Text> {
        assert (Principal.equal(caller, governanceCid));
        switch (await _factoryAct.getRemovedPools()) {
            case (#ok(pools)) {
                for (it in pools.vals()) {
                    if (Principal.equal(poolId, it.canisterId)) {
                        return #ok(debug_show (poolId));
                    };
                };
                return #err(Principal.toText(poolId) # " not exist.");
            };
            case (#err(msg)) {
                return #err(debug_show (msg));
            };
        };
    };

    public shared ({ caller }) func upgradePoolTokenStandardValidate(poolCid : Principal, tokenCid : Principal) : async Result.Result<Text, Text> {
        assert (Principal.equal(caller, governanceCid));
        if (not (await _checkPool(poolCid))) {
            return #err(Principal.toText(poolCid) # " not exist.");
        };
        var poolAct = actor (Principal.toText(poolCid)) : Types.SwapPoolActor;
        switch (await poolAct.metadata()) {
            case (#ok(metadata)) {
                let token = if (Text.equal(Principal.toText(tokenCid), metadata.token0.address)) {
                    metadata.token0;
                } else if (Text.equal(Principal.toText(tokenCid), metadata.token1.address)) {
                    metadata.token1;
                } else {
                    return #err("Token not found in pool");
                };
                let tokenAct = actor (token.address) : actor {
                    icrc1_supported_standards : query () -> async [{
                        url : Text;
                        name : Text;
                    }];
                };
                try {
                    var supportStandards = await tokenAct.icrc1_supported_standards();
                    var isSupportedICRC2 = false;
                    for (supportStandard in supportStandards.vals()) {
                        if (Text.equal("ICRC-2", supportStandard.name)) {
                            isSupportedICRC2 := true;
                        };
                    };
                    if (isSupportedICRC2) {
                        return #ok(debug_show(poolCid) # ", " # debug_show(tokenCid));
                    } else {
                        return #err("Check icrc1_supported_standards failed");
                    };
                } catch (e) {
                    return #err("Get icrc1_supported_standards failed: " # Error.message(e));
                };
            };
            case (#err(code)) {
                return #err("Get pool metadata failed: " # debug_show (code));
            };
        };
    };

    public shared ({ caller }) func addPoolControllersValidate(poolCid : Principal, controllers : [Principal]) : async Result.Result<Text, Text> {
        assert (Principal.equal(caller, governanceCid));
        if (not (await _checkPool(poolCid))) {
            return #err(Principal.toText(poolCid) # " not exist.");
        };
        return #ok(debug_show(poolCid) # ", " # debug_show (controllers));
    };

    public shared ({ caller }) func removePoolControllersValidate(poolCid : Principal, controllers : [Principal]) : async Result.Result<Text, Text> {
        assert (Principal.equal(caller, governanceCid));
        if (not (await _checkPool(poolCid))) {
            return #err(Principal.toText(poolCid) # " not exist.");
        };
        for (it in controllers.vals()) {
            if (Principal.equal(it, factoryCid)) {
                return #err("SwapFactory must be the controller of SwapPool");
            };
        };
        return #ok(debug_show(poolCid) # ", " # debug_show (controllers));
    };

    public shared ({ caller }) func setPoolAdminsValidate(poolCid : Principal, admins : [Principal]) : async Result.Result<Text, Text> {
        assert (Principal.equal(caller, governanceCid));
        if (not (await _checkPool(poolCid))) {
            return #err(Principal.toText(poolCid) # " not exist.");
        };
        return #ok(debug_show(poolCid) # ", " # debug_show (admins));
    };

    public shared ({ caller }) func batchAddPoolControllersValidate(poolCids : [Principal], controllers : [Principal]) : async Result.Result<Text, Text> {
        assert (Principal.equal(caller, governanceCid));
        switch (await _checkPools(poolCids)) {
            case (#ok(r)) {
                return #ok(debug_show (poolCids) # ", " # debug_show (controllers));
            };
            case (#err(msg)) {
                return #err(debug_show (msg));
            };
        };
    };

    public shared ({ caller }) func batchRemovePoolControllersValidate(poolCids : [Principal], controllers : [Principal]) : async Result.Result<Text, Text> {
        assert (Principal.equal(caller, governanceCid));
        switch (await _checkPools(poolCids)) {
            case (#ok(r)) {
                for (it in controllers.vals()) {
                    if (Principal.equal(it, factoryCid)) {
                        return #err("SwapFactory must be the controller of SwapPool");
                    };
                };
                return #ok(debug_show (poolCids) # ", " # debug_show (controllers));
            };
            case (#err(msg)) {
                return #err(debug_show (msg));
            };
        };
    };

    public shared ({ caller }) func batchSetPoolAdminsValidate(poolCids : [Principal], admins : [Principal]) : async Result.Result<Text, Text> {
        assert (Principal.equal(caller, governanceCid));
        switch (await _checkPools(poolCids)) {
            case (#ok(r)) {
                return #ok(debug_show (poolCids) # ", " # debug_show (admins));
            };
            case (#err(msg)) {
                return #err(debug_show (msg));
            };
        };
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
                        return #err(Principal.toText(it1) # " not exist.");
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
