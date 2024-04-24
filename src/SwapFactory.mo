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

shared (initMsg) actor class SwapFactory(
    infoCid : Principal,
    feeReceiverCid : Principal,
    passcodeManagerCid : Principal,
    trustedCanisterManagerCid : Principal,
    governanceCid : ?Principal,
) = this {
    private type LockState = {
        locked : Bool;
        time : Time.Time;
    };
    // private stable var _infoCid : Principal = infoCid;
    // private stable var _feeReceiverCid : Principal = feeReceiverCid;
    // private stable var _tokenWhitelist : Principal = tokenWhitelist;
    /// configuration items
    private stable var _initCycles : Nat = 1860000000000;
    private stable var _feeTickSpacingEntries : [(Nat, Int)] = [(500, 10), (3000, 60), (10000, 200)];
    private stable var _poolDataState : PoolData.State = { poolEntries = []; removedPoolEntries = []; };

    private stable var _principalPasscodes : [(Principal, [Types.Passcode])] = [];
    private var _principalPasscodeMap : HashMap.HashMap<Principal, [Types.Passcode]> = HashMap.fromIter(_principalPasscodes.vals(), 0, Principal.equal, Principal.hash);

    private var _feeTickSpacingMap : HashMap.HashMap<Nat, Int> = HashMap.fromIter<Nat, Int>(_feeTickSpacingEntries.vals(), 10, Nat.equal, Hash.hash);
    private var _poolDataService : PoolData.Service = PoolData.Service(_poolDataState);
    private var _infoAct = actor (Principal.toText(infoCid)) : Types.TxStorage;
    private let IC0 = actor "aaaaa-aa" : actor {
        canister_status : { canister_id : Principal } -> async { settings : { controllers : [Principal] }; };
        update_settings : { canister_id : Principal; settings : { controllers : [Principal]; } } -> ();
    };
    private stable var _lockState : LockState = { locked = false; time = 0};

    private func _lock() : Bool {
        let now = Time.now();
        if ((not _lockState.locked) or ((now - _lockState.time) > 1000000000 * 60)) {
            _lockState := { locked = true; time = now; };
            return true;
        };
        return false;
    };
    private func _unlock() {
        _lockState := { locked = false; time = 0};
    };

    public shared (msg) func createPool(args : Types.CreatePoolArgs) : async Result.Result<Types.PoolData, Types.Error> {
        if (not _validatePasscode(msg.caller, args)) { return #err(#InternalError("Please pay the fee for creating SwapPool.")); };
        if (Text.equal(args.token0.address, args.token1.address)) { return #err(#InternalError("Can not use the same token")); };
        var tickSpacing = switch (_feeTickSpacingMap.get(args.fee)) {
            case (?feeAmountTickSpacingFee) { feeAmountTickSpacingFee };
            case (_) { return #err(#InternalError("TickSpacing cannot be 0")); };
        };

        if (not _lock()) { return #err(#InternalError("Please wait for previous creating job finished")); };

        let (token0, token1) = PoolUtils.sort(args.token0, args.token1);
        let poolKey : Text = PoolUtils.getPoolKey(token0, token1, args.fee);
        var poolData = switch (_poolDataService.getPools().get(poolKey)) {
            case (?pool) { pool };
            case (_) {
                try {
                    if(not _deletePasscode(msg.caller, { token0 = Principal.fromText(token0.address); token1 = Principal.fromText(token1.address); fee = args.fee; })) {
                        return #err(#InternalError("Passcode is not existed."));
                    };
                    Cycles.add(_initCycles);
                    let pool = await SwapPool.SwapPool(token0, token1, infoCid, feeReceiverCid, trustedCanisterManagerCid);
                    await pool.init(args.fee, tickSpacing, SafeUint.Uint160(TextUtils.toNat(args.sqrtPriceX96)).val());
                    await IC0Utils.update_settings_add_controller(Principal.fromActor(pool), initMsg.caller);
                    await _infoAct.addClient(Principal.fromActor(pool));
                    let poolData = {
                        key = poolKey;
                        token0 = token0;
                        token1 = token1;
                        fee = args.fee;
                        tickSpacing = tickSpacing;
                        canisterId = Principal.fromActor(pool);
                    } : Types.PoolData;
                    _poolDataService.putPool(poolKey, poolData);
                    poolData;
                } catch (e) {
                    throw Error.reject("create pool failed: " # Error.message(e));
                };
            };
        };

        _unlock();
        
        return #ok(poolData);
    };

    public shared (msg) func addPasscode(principal: Principal, passcode: Types.Passcode): async Result.Result<(), Types.Error> {
        assert(Principal.equal(passcodeManagerCid, msg.caller));
        switch (_principalPasscodeMap.get(principal)) {
            case (?passcodes) {
                var passcodeList : List.List<Types.Passcode> = List.fromArray(passcodes);
                if (not CollectionUtils.arrayContains<Types.Passcode>(passcodes, passcode, _passcodeEqual)) {
                    passcodeList := List.push(passcode, passcodeList);
                    _principalPasscodeMap.put(principal, List.toArray(passcodeList));
                    return #ok;
                };
                return #err(#InternalError("Passcode is existed."));
            };
            case (_) {
                var passcodeList = List.nil<Types.Passcode>();
                passcodeList := List.push(passcode, passcodeList);
                _principalPasscodeMap.put(principal, List.toArray(passcodeList));
                return #ok;
            };
        };
    };

    public shared (msg) func deletePasscode(principal: Principal, passcode: Types.Passcode): async Result.Result<(), Types.Error> {
        assert(Principal.equal(passcodeManagerCid, msg.caller));
        if (_deletePasscode(principal, passcode)){
            return #ok;
        } else {
            return #err(#InternalError("Passcode is not exist."));
        };
    };

    public shared (msg) func upgradePoolTokenStandard(poolCid : Principal, tokenCid : Principal) : async Result.Result<Text, Types.Error> {
        _checkPermission(msg.caller);
        var poolAct = actor (Principal.toText(poolCid)) : Types.SwapPoolActor;
        switch (await poolAct.metadata()) {
            case (#ok(metadata)) {
                let token = if (Text.equal(Principal.toText(tokenCid), metadata.token0.address)) { 
                    metadata.token0
                } else if (Text.equal(Principal.toText(tokenCid), metadata.token1.address)) {
                    metadata.token1
                } else { 
                    return #err(#InternalError("Token not found in pool"));
                };
                let tokenAct = actor (token.address) : actor {
                    icrc1_supported_standards : query () -> async [{ url : Text; name : Text; }];
                };
                try {
                    var supportStandards = await tokenAct.icrc1_supported_standards();
                    var isSupportedICRC2 = false;
                    for (supportStandard in supportStandards.vals()) {
                        if (Text.equal("ICRC-2", supportStandard.name)) { isSupportedICRC2 := true; };
                    };
                    let poolKey : Text = PoolUtils.getPoolKey(metadata.token0, metadata.token1, metadata.fee);
                    if (isSupportedICRC2) {
                        let result = await poolAct.upgradeTokenStandard(tokenCid);
                        switch (await poolAct.metadata()) {
                            case (#ok(verifiedMetadata)) {
                                let verifiedToken = if (Text.equal(Principal.toText(tokenCid), verifiedMetadata.token0.address)) { 
                                    verifiedMetadata.token0
                                } else {
                                    verifiedMetadata.token1
                                };
                                if (Text.equal("ICRC2", verifiedToken.standard)) {
                                    let poolData = switch (_poolDataService.getPools().get(poolKey)) {
                                        case (?poolData) { poolData }; case (_) { return #err(#InternalError("Get pool data failed")); };
                                    };
                                    _poolDataService.putPool(
                                        poolKey,
                                        {
                                            key = poolData.key;
                                            token0 = {
                                                address = poolData.token0.address;
                                                standard = if (Text.equal(Principal.toText(tokenCid), poolData.token0.address)) { "ICRC2" } else { poolData.token0.standard };
                                            };
                                            token1 = {
                                                address = poolData.token1.address;
                                                standard = if (Text.equal(Principal.toText(tokenCid), poolData.token1.address)) { "ICRC2" } else { poolData.token1.standard };
                                            };
                                            fee = poolData.fee;
                                            tickSpacing = poolData.tickSpacing;
                                            canisterId = poolData.canisterId;
                                        },
                                    );
                                } else {
                                    return #err(#InternalError("Check upgrading failed"));
                                };
                            };
                            case (#err(code)) { return #err(#InternalError("Verify pool metadata failed: " # debug_show (code))); };
                        };
                    } else {
                        return #err(#InternalError("Check icrc1_supported_standards failed"));
                    };
                } catch (e) {
                    return #err(#InternalError("Get icrc1_supported_standards failed: " # Error.message(e)));
                };
                return #ok("Change standard successfully.");
            };
            case (#err(code)) {
                return #err(#InternalError("Get pool metadata failed: " # debug_show (code)));
            };
        };
    };

    /// get pool by token addresses and fee.
    public query func getPool(args : Types.GetPoolArgs) : async Result.Result<Types.PoolData, Types.Error> {
        let poolKey : Text = PoolUtils.getPoolKey(args.token0, args.token1, args.fee);
        Debug.print("poolKey-> " # debug_show (poolKey));
        switch (_poolDataService.getPools().get(poolKey)) {
            case (?pool) { #ok(pool) };
            case (_) { #err(#CommonError) };
        };
    };

    public query func getPools() : async Result.Result<[Types.PoolData], Types.Error> {
        return #ok(Iter.toArray(_poolDataService.getPools().vals()));
    };

    public query func getRemovedPools() : async Result.Result<[Types.PoolData], Types.Error> {
        return #ok(Iter.toArray(_poolDataService.getRemovedPools().vals()));
    };

    public query func getGovernanceCid() : async Result.Result<?Principal, Types.Error> {
        return #ok(governanceCid);
    };

    public query func getInitArgs() : async Result.Result<{    
        infoCid : Principal;
        feeReceiverCid : Principal;
        passcodeManagerCid : Principal;
        trustedCanisterManagerCid : Principal;
        governanceCid : ?Principal;
    }, Types.Error> {
        #ok({
            infoCid = infoCid;
            feeReceiverCid = feeReceiverCid;
            passcodeManagerCid = passcodeManagerCid;
            trustedCanisterManagerCid = trustedCanisterManagerCid;
            governanceCid = governanceCid;  
        });
    };

    public query func getPrincipalPasscodes(): async Result.Result<[(Principal, [Types.Passcode])], Types.Error> {
        return #ok(Iter.toArray(_principalPasscodeMap.entries()));
    };

    public query func getPasscodesByPrincipal(principal: Principal): async Result.Result<[Types.Passcode], Types.Error> {
        switch (_principalPasscodeMap.get(principal)) {
            case (?passcodes) { return #ok(passcodes); };
            case (_) { return #ok([]); };
        };
    };

    public shared func getCycleInfo() : async Result.Result<Types.CycleInfo, Types.Error> {
        return #ok({
            balance = Cycles.balance();
            available = Cycles.available();
        });
    };

    // ---------------        Governance Functions              ----------------------
    public shared (msg) func restorePool(poolId : Principal) : async Text {
        _checkPermission(msg.caller);
        switch (_poolDataService.getRemovedPools().get(Principal.toText(poolId))) {
            case (?poolData) {
                // check if the pool is existed
                switch (_poolDataService.getPools().get(poolData.key)) {
                    case (?poolData) { return "Failed: A new SwapPool of identical pairs has been created."; };
                    case (_) { return _poolDataService.restorePool(Principal.toText(poolId)); };
                };
            };
            case (_) { return "Failed: No such SwapPool."; };
        };
    };

    public shared (msg) func removePool(args : Types.GetPoolArgs) : async Text {
        _checkPermission(msg.caller);
        let poolKey : Text = PoolUtils.getPoolKey(args.token0, args.token1, args.fee);
        let poolCid = _poolDataService.removePool(poolKey);
    };

    // ---------------        Pools Governance Functions        ----------------------
    public shared (msg) func removePoolErrorTransferLog(poolCid : Principal, id : Nat, rollback : Bool) : async Result.Result<(), Types.Error> {
        _checkPermission(msg.caller);
        var poolAct = actor (Principal.toText(poolCid)) : Types.SwapPoolActor;
        try {
            await poolAct.removeErrorTransferLog(id, rollback);
            return #ok(());
        } catch (e) {
            return #err(#InternalError("Remove withdraw error log failed: " # Error.message(e)));
        }
    };

    public shared (msg) func setPoolAdmins(poolCid : Principal, admins : [Principal]) : async () {
        _checkPermission(msg.caller);
        await _setPoolAdmins(poolCid, admins);
    };

    public shared (msg) func clearRemovedPool(canisterId : Principal) : async Text {
        _checkPermission(msg.caller);
        let poolCid = _poolDataService.deletePool(Principal.toText(canisterId));
    };

    public shared (msg) func addPoolControllers(poolCid : Principal, controllers : [Principal]) : async () {
        _checkPermission(msg.caller);
        await _addPoolControllers(poolCid, controllers);
    };

    public shared (msg) func removePoolControllers(poolCid : Principal, controllers : [Principal]) : async () {
        _checkPermission(msg.caller);
        if (not _checkPoolControllers(controllers)){
            throw Error.reject("SwapFactory must be the controller of SwapPool");
        };
        await _removePoolControllers(poolCid, controllers);
    };

    public shared (msg) func batchSetPoolAdmins(poolCids : [Principal], admins : [Principal]) : async () {
        _checkPermission(msg.caller);
        for (poolCid in poolCids.vals()) {
            await _setPoolAdmins(poolCid, admins);
        };
    };

    public shared (msg) func batchAddPoolControllers(poolCids : [Principal], controllers : [Principal]) : async () {
        _checkPermission(msg.caller);
        for (poolCid in poolCids.vals()) {
            await _addPoolControllers(poolCid, controllers);
        };
    };

    public shared (msg) func batchRemovePoolControllers(poolCids : [Principal], controllers : [Principal]) : async () {
        _checkPermission(msg.caller);
        if (not _checkPoolControllers(controllers)){
            throw Error.reject("SwapFactory must be the controller of SwapPool");
        };
        for (poolCid in poolCids.vals()) {
            await _removePoolControllers(poolCid, controllers);
        };
    };

    private func _setPoolAdmins(poolCid : Principal, admins : [Principal]) : async () {
        var poolAct = actor (Principal.toText(poolCid)) : Types.SwapPoolActor;
        await poolAct.setAdmins(admins);
    };

    private func _addPoolControllers(poolCid : Principal, controllers : [Principal]) : async () {
        let { settings } = await IC0.canister_status({ canister_id = poolCid });
        var controllerList = List.append(List.fromArray(settings.controllers), List.fromArray(controllers));
        IC0.update_settings({ canister_id = poolCid; settings = { controllers = List.toArray(controllerList) }; });
    };

    private func _removePoolControllers(poolCid : Principal, controllers : [Principal]) : async () {
        let buffer: Buffer.Buffer<Principal> = Buffer.Buffer<Principal>(0);
        let { settings } = await IC0.canister_status({ canister_id = poolCid });
        for (it in settings.controllers.vals()) {
            if (not CollectionUtils.arrayContains<Principal>(controllers, it, Principal.equal)) {
                buffer.add(it);
            };
        };
        IC0.update_settings({ canister_id = poolCid; settings = { controllers = Buffer.toArray<Principal>(buffer) }; });
    };

    private func _checkPoolControllers(controllers : [Principal]) : Bool {
        let factoryCid : Principal = Principal.fromActor(this);
        for (it in controllers.vals()) {
            if (Principal.equal(it, factoryCid)) {
                return false;
            };
        };
        true;
    };

    private func _checkPermission(caller : Principal) {
        assert(_hasPermission(caller));
    };

    private func _hasPermission(caller: Principal): Bool {
        return Prim.isController(caller) or (switch (governanceCid) {case (?cid) { Principal.equal(caller, cid) }; case (_) { false };});
    };

    private func _validatePasscode(principal: Principal, args: Types.CreatePoolArgs): Bool {
        switch (_principalPasscodeMap.get(principal)) {
            case (?passcodes) {
                let (token0, token1) = PoolUtils.sort(args.token0, args.token1);
                var passcode = { token0 = Principal.fromText(token0.address); token1 = Principal.fromText(token1.address); fee = args.fee; };
                if (CollectionUtils.arrayContains<Types.Passcode>(passcodes, passcode, _passcodeEqual)) { return true; } else { return false; };
            };
            case (_) { return false; };
        };
    };

    private func _deletePasscode(principal: Principal, passcode: Types.Passcode): Bool {
        switch (_principalPasscodeMap.get(principal)) {
            case (?passcodes) {
                if (CollectionUtils.arrayContains<Types.Passcode>(passcodes, passcode, _passcodeEqual)) {
                    var passcodesNew = CollectionUtils.arrayRemove(passcodes, passcode, _passcodeEqual);
                    if (0 == passcodesNew.size()) {
                        ignore _principalPasscodeMap.remove(principal);
                    } else {
                        _principalPasscodeMap.put(principal, passcodesNew);
                    };
                    return true;
                } else {
                    return false;
                };
            };
            case (_) { return false; };
        };
    };

    private func _passcodeEqual(p1 : Types.Passcode, p2 : Types.Passcode) : Bool { 
        Principal.equal(p1.token0, p2.token0) and  Principal.equal(p1.token1, p2.token1) and Nat.equal(p1.fee, p2.fee)
    };

    // --------------------------- Version Control      -------------------------------
    private var _version : Text = "3.4.0";
    public query func getVersion() : async Text { _version };
    
    system func preupgrade() {
        _feeTickSpacingEntries := Iter.toArray(_feeTickSpacingMap.entries());
        _principalPasscodes := Iter.toArray(_principalPasscodeMap.entries());
        _poolDataState := _poolDataService.getState();
    };

    system func postupgrade() {
        _feeTickSpacingEntries := [];
        _principalPasscodes := [];
    };

    system func inspect({
        arg : Blob;
        caller : Principal;
        msg : Types.SwapFactoryMsg;
    }) : Bool {
        return switch (msg) {
            // Controller
            case (#clearRemovedPool args)                   { _hasPermission(caller) };
            case (#removePool args)                         { _hasPermission(caller) };
            case (#removePoolErrorTransferLog args)         { _hasPermission(caller) };
            case (#restorePool args)                        { _hasPermission(caller) };
            case (#upgradePoolTokenStandard args)           { _hasPermission(caller) };
            case (#addPoolControllers args)                 { _hasPermission(caller) };
            case (#removePoolControllers args)              { _hasPermission(caller) };
            case (#setPoolAdmins args)                      { _hasPermission(caller) };
            case (#batchAddPoolControllers args)            { _hasPermission(caller) };
            case (#batchRemovePoolControllers args)         { _hasPermission(caller) };
            case (#batchSetPoolAdmins args)                 { _hasPermission(caller) };
            // Anyone
            case (_)                                   { true };
        };
    };

};
