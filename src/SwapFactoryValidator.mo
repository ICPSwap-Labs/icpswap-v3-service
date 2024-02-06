import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Bool "mo:base/Bool";
import Buffer "mo:base/Buffer";
import Char "mo:base/Char";
import Cycles "mo:base/ExperimentalCycles";
import Debug "mo:base/Debug";
import Error "mo:base/Error";
import Hash "mo:base/Hash";
import HashMap "mo:base/HashMap";
import Int "mo:base/Int";
import Iter "mo:base/Iter";
import List "mo:base/List";
import Nat "mo:base/Nat";
import Nat32 "mo:base/Nat32";
import Option "mo:base/Option";
import Prim "mo:⛔";
import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Text "mo:base/Text";
import Time "mo:base/Time";
import SHA256 "mo:sha256/SHA256";
import SafeUint "mo:commons/math/SafeUint";
import TextUtils "mo:commons/utils/TextUtils";
import IC0Utils "mo:commons/utils/IC0Utils";
import CollectionUtils "mo:commons/utils/CollectionUtils";
import PoolUtils "./utils/PoolUtils";
import PoolData "./components/PoolData";
import SwapPool "./SwapPool";
import Types "./Types";
import TokenAdapterTypes "mo:token-adapter/Types";
import TokenFactory "mo:token-adapter/TokenFactory";

shared (initMsg) actor class SwapFactoryValidator() = this {
    public shared (msg) func validateUpgradePoolTokenStandard(poolCid : Principal, tokenCid : Principal) : async Bool {
        // _checkPermission(msg.caller);
        var poolAct = actor (Principal.toText(poolCid)) : Types.SwapPoolActor;
        switch (await poolAct.metadata()) {
            case (#ok(metadata)) {
                let token = if (Text.equal(Principal.toText(tokenCid), metadata.token0.address)) { 
                    metadata.token0
                } else if (Text.equal(Principal.toText(tokenCid), metadata.token1.address)) {
                    metadata.token1
                } else { 
                    return false;
                };
                let tokenAct = actor (token.address) : actor {
                    icrc1_supported_standards : query () -> async [{ url : Text; name : Text; }];
                };
                try {
                    var supportStandards = await tokenAct.icrc1_supported_standards();
                    var isSupportedICRC2 = false;
                    for (supportStandard in supportStandards.vals()) {
                        if (Text.equal("ICRC-2", supportStandard.name)) {
                            return true;
                        };
                    };
                } catch (e) {
                    return false;
                };
                return false;
            };
            case (#err(code)) {
                return false;
            };
        };
    };

    public shared (msg) func validateRestorePool(poolId : Principal) : async Bool {
        // _checkPermission(msg.caller);
        true
    };

    public shared (msg) func validateRemovePool(args : Types.GetPoolArgs) : async Bool {
        // _checkPermission(msg.caller);
        true
    };

    public shared (msg) func validateRemovePoolWithdrawErrorLog(poolCid : Principal, id : Nat, rollback : Bool) : async Bool {
        // _checkPermission(msg.caller);
        true;
    };

    public shared (msg) func validateSetPoolAdmins(poolCid : Principal, admins : [Principal]) : async Bool {
        // _checkPermission(msg.caller);
        true;
    };

    public shared (msg) func validateClearRemovedPool(canisterId : Principal) : async Bool {
        // _checkPermission(msg.caller);
        true;
    };
        
    public shared (msg) func validateAddPoolControllers(poolCid : Principal, controllers : [Principal]) : async Bool {
        // _checkPermission(msg.caller);
        true;
    };

    // public shared (msg) func validateRemovePoolControllers(poolCid : Principal, controllers : [Principal]) : async Bool {
    //     _checkPermission(msg.caller);
    //     _checkPoolControllers(controllers);
    // };

    public shared (msg) func validateBatchSetPoolAdmins(poolCids : [Principal], admins : [Principal]) : async Bool {
        // _checkPermission(msg.caller);
        true;
    };

    public shared (msg) func validateBatchAddPoolControllers(poolCids : [Principal], controllers : [Principal]) : async Bool {
        // _checkPermission(msg.caller);
        true;
    };

    // public shared (msg) func validateBatchRemovePoolControllers(poolCids : [Principal], controllers : [Principal]) : async Bool {
    //     _checkPermission(msg.caller);
    //     _checkPoolControllers(controllers);
    // };
};