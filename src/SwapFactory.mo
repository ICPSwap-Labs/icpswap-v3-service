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
import Func "./Functions";
import TokenAdapterTypes "mo:token-adapter/Types";
import TokenFactory "mo:token-adapter/TokenFactory";

shared (msg) actor class SwapFactory(
    infoCid : Principal,
    feeReceiverCid : Principal,
) = this {
    private type LockState = {
        locked : Bool;
        time : Time.Time;
    };
    private stable var _infoCid : Principal = infoCid;
    private stable var _feeReceiverCid : Principal = feeReceiverCid;
    /// configuration items
    private stable var _initCycles : Nat = 1860000000000;
    private stable var _feeTickSpacingEntries : [(Nat, Int)] = [(500, 10), (3000, 60), (10000, 200)];
    private stable var _poolDataState : PoolData.State = { poolEntries = []; removedPoolEntries = []; };

    private var _feeTickSpacingMap : HashMap.HashMap<Nat, Int> = HashMap.fromIter<Nat, Int>(_feeTickSpacingEntries.vals(), 10, Nat.equal, Hash.hash);
    private var _poolDataService : PoolData.Service = PoolData.Service(_poolDataState);
    private var _infoAct = actor (Principal.toText(_infoCid)) : Types.TxStorage;
    private let IC0 = actor "aaaaa-aa" : actor {
        canister_status : { canister_id : Principal } -> async { settings : { controllers : [Principal] }; };
        update_settings : { canister_id : Principal; settings : { controllers : [Principal]; } } -> ();
    };
    private stable var _lockState : LockState = { locked = false; time = 0};

    private func _lock() : Bool {
        let now = Time.now();
        if ((not _lockState.locked) or ((now - _lockState.time) > 1000000000 * 30)) {
            _lockState := { locked = true; time = now; };
            return true;
        };
        return false;
    };
    private func _unlock() {
        _lockState := { locked = false; time = 0};
    };
    /// create token pool, returns principal id.
    private func _createPool(token0 : Types.Token, token1 : Types.Token, fee : Nat, sqrtPriceX96 : Text, tickSpacing : Int) : async Types.PoolData {
        let (_token0, _token1) = PoolUtils.sort(token0, token1);
        try {
            let poolKey : Text = PoolUtils.getPoolKey(_token0, _token1, fee);
            switch (_poolDataService.getPools().get(poolKey)) {
                case (?pool) { return pool };
                case (_) {
                    Cycles.add(_initCycles);
                    let pool = await SwapPool.SwapPool(token0, token1, _infoCid, _feeReceiverCid);
                    await pool.init(fee, tickSpacing, SafeUint.Uint160(TextUtils.toNat(sqrtPriceX96)).val());
                    let poolId : Principal = Principal.fromActor(pool);
                    let poolData = {
                        key = poolKey;
                        token0 = _token0;
                        token1 = _token1;
                        fee = fee;
                        tickSpacing = tickSpacing;
                        canisterId = poolId;
                    } : Types.PoolData;
                    _poolDataService.putPool(poolKey, poolData);
                    await IC0Utils.update_settings_add_controller(poolId, msg.caller);
                    await _infoAct.addClient(poolId);
                    return poolData;
                };
            };
        } catch (e) {
            var errMsg = Error.message(e);
            throw Error.reject("create pool failed: " # errMsg);
        };
    };

    public shared (msg) func createPool(args : Types.CreatePoolArgs) : async Result.Result<Types.PoolData, Types.Error> {
        var tickSpacing = switch (_feeTickSpacingMap.get(args.fee)) {
            case (?feeAmountTickSpacingFee) { feeAmountTickSpacingFee };
            case (_) { 0 };
        };
        if (tickSpacing == 0) {
            return #err(#InternalError("TickSpacing cannot be 0"));
        };
        let poolKey : Text = PoolUtils.getPoolKey(args.token0, args.token1, args.fee);

        if (not _lock()) {
            return #err(#InternalError("Please wait for previous creating job finished"));
        };
        var poolData = switch (_poolDataService.getPools().get(poolKey)) {
            case (?pool) { pool };
            case (_) {
                let pool = await _createPool(args.token0, args.token1, args.fee, args.sqrtPriceX96, tickSpacing);
                pool
            };
        };
        _unlock();
        
        return #ok(poolData);
    };

    public shared (msg) func upgradePoolTokenStandard(poolCid : Principal, tokenCid : Principal) : async Result.Result<Text, Types.Error> {
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
                        await poolAct.upgradeTokenStandard(tokenCid);
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
    public shared (msg) func validateUpgradePoolTokenStandard(poolCid : Principal, tokenCid : Principal) : async Bool {
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

    public query (msg) func getPagedPools(offset : Nat, limit : Nat) : async Result.Result<Types.Page<Types.PoolData>, Types.Error> {
        let resultArr : Buffer.Buffer<Types.PoolData> = Buffer.Buffer<Types.PoolData>(0);
        var begin : Nat = 0;
        label l {
            for (poolData in _poolDataService.getPools().vals()) {
                if (begin >= offset and begin < (offset + limit)) {
                    resultArr.add(poolData);
                };
                if (begin >= (offset + limit)) { break l };
                begin := begin + 1;
            };
        };
        return #ok({
            totalElements = _poolDataService.getPools().size();
            content = Buffer.toArray(resultArr);
            offset = offset;
            limit = limit;
        });
    };

    public query func getRemovedPools() : async Result.Result<[Types.PoolData], Types.Error> {
        return #ok(Iter.toArray(_poolDataService.getRemovedPools().vals()));
    };

    public shared func getCycleInfo() : async Result.Result<Types.CycleInfo, Types.Error> {
        return #ok({
            balance = Cycles.balance();
            available = Cycles.available();
        });
    };

    // ---------------        Governance Functions              ----------------------
    public func restorePool(poolId : Principal) : async Text {
        let poolCid = _poolDataService.restorePool(Principal.toText(poolId));
    };
    public func validateRestorePool(poolId : Principal) : async Bool {
        true
    };
    public func removePool(args : Types.GetPoolArgs) : async Text {
        let poolKey : Text = PoolUtils.getPoolKey(args.token0, args.token1, args.fee);
        let poolCid = _poolDataService.removePool(poolKey);
    };
    public func validateRemovePool(args : Types.GetPoolArgs) : async Bool {
        true
    };
    // ---------------        Pools Governance Functions        ----------------------
    public shared (msg) func removePoolWithdrawErrorLog(poolCid : Principal, id : Nat, rollback : Bool) : async Result.Result<(), Types.Error> {
        var poolAct = actor (Principal.toText(poolCid)) : Types.SwapPoolActor;
        try {
            await poolAct.removeWithdrawErrorLog(id, rollback);
            return #ok(());
        } catch (e) {
            return #err(#InternalError("Remove withdraw error log failed: " # Error.message(e)));
        }
    };
    public shared func validateRemovePoolWithdrawErrorLog(poolCid : Principal, id : Nat, rollback : Bool) : async Bool {
        true;
    };
    public shared (msg) func setPoolAdmins(poolCid : Principal, admins : [Principal]) : async () {
        var poolAct = actor (Principal.toText(poolCid)) : Types.SwapPoolActor;
        await poolAct.setAdmins(admins);
    };
    public shared (msg) func validateSetPoolAdmins(poolCid : Principal, admins : [Principal]) : async Bool {
        true;
    };
    public func clearRemovedPool(canisterId : Principal) : async Text {
        let poolCid = _poolDataService.deletePool(Principal.toText(canisterId));
    };
    public func validateClearRemovedPool(canisterId : Principal) : async Bool {
        true;
    };
    public shared (msg) func addPoolControllers(poolCid : Principal, controllers : [Principal]) : async () {
        let { settings } = await IC0.canister_status({ canister_id = poolCid });
        var controllerList = List.append(List.fromArray(settings.controllers), List.fromArray(controllers));
        IC0.update_settings({ canister_id = poolCid; settings = { controllers = List.toArray(controllerList) }; });
    };
    public shared (msg) func validateAddPoolControllers(poolCid : Principal, controllers : [Principal]) : async Bool {
        true;
    };
    public shared (msg) func removePoolControllers(poolCid : Principal, controllers : [Principal]) : async () {
        let factoryCid : Principal = Principal.fromActor(this);
        for (it in controllers.vals()) {
            if (Principal.equal(it, factoryCid)) {
                throw Error.reject("Factory cannot be removed from pool");
            };
        };
        let buffer: Buffer.Buffer<Principal> = Buffer.Buffer<Principal>(0);

        let { settings } = await IC0.canister_status({ canister_id = poolCid });
        for (it in settings.controllers.vals()) {
            if (not CollectionUtils.arrayContains<Principal>(controllers, it, Principal.equal)) {
                buffer.add(it);
            };
        };
        IC0.update_settings({ canister_id = poolCid; settings = { controllers = Buffer.toArray<Principal>(buffer) }; });
    };
    public shared (msg) func validateRemovePoolControllers(poolCid : Principal, controllers : [Principal]) : async Bool {
        let factoryCid : Principal = Principal.fromActor(this);
        for (it in controllers.vals()) {
            if (Principal.equal(it, factoryCid)) {
                return false;
            };
        };
        true;
    };

    // --------------------------- Version Control      -------------------------------
    private var _version : Text = "3.2.4";
    public query func getVersion() : async Text { _version };
    
    system func preupgrade() {
        _feeTickSpacingEntries := Iter.toArray(_feeTickSpacingMap.entries());
        _poolDataState := _poolDataService.getState();
    };

    system func postupgrade() {
        _feeTickSpacingEntries := [];
    };

    system func inspect({
        arg : Blob;
        caller : Principal;
        msg : Types.SwapFactoryMsg;
    }) : Bool {
        return switch (msg) {
            // Controller
            case (#clearRemovedPool args)                   { Prim.isController(caller) };
            case (#removePool args)                         { Prim.isController(caller) };
            case (#removePoolWithdrawErrorLog args)         { Prim.isController(caller) };
            case (#restorePool args)                        { Prim.isController(caller) };
            case (#upgradePoolTokenStandard args)           { Prim.isController(caller) };
            case (#addPoolControllers args)                 { Prim.isController(caller) };
            case (#removePoolControllers args)              { Prim.isController(caller) };
            case (#setPoolAdmins args)                      { Prim.isController(caller) };
            case (#validateUpgradePoolTokenStandard args)   { Prim.isController(caller) };
            case (#validateRestorePool args)                { Prim.isController(caller) };
            case (#validateRemovePool args)                 { Prim.isController(caller) };
            case (#validateRemovePoolWithdrawErrorLog args) { Prim.isController(caller) };
            case (#validateSetPoolAdmins args)              { Prim.isController(caller) };
            case (#validateClearRemovedPool args)           { Prim.isController(caller) };
            case (#validateAddPoolControllers args)         { Prim.isController(caller) };
            case (#validateRemovePoolControllers args)      { Prim.isController(caller) };
            // Anyone
            case (_)                                   { true };
        };
    };

};
