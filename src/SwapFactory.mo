import Array "mo:base/Array";
import Bool "mo:base/Bool";
import Buffer "mo:base/Buffer";
import Blob "mo:base/Blob";
import Cycles "mo:base/ExperimentalCycles";
import Debug "mo:base/Debug";
import Error "mo:base/Error";
import Hash "mo:base/Hash";
import HashMap "mo:base/HashMap";
import Int "mo:base/Int";
import Iter "mo:base/Iter";
import List "mo:base/List";
import Nat "mo:base/Nat";
import Timer "mo:base/Timer";
import Prim "mo:⛔";
import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Text "mo:base/Text";
import Time "mo:base/Time";
import SafeUint "mo:commons/math/SafeUint";
import TextUtils "mo:commons/utils/TextUtils";
import IC0Utils "mo:commons/utils/IC0Utils";
import CollectionUtils "mo:commons/utils/CollectionUtils";
import PoolUtils "./utils/PoolUtils";
import PoolData "./components/PoolData";
import UpgradeTask "./components/UpgradeTask";
import SwapPool "./SwapPool";
import Types "./Types";

shared (initMsg) actor class SwapFactory(
    infoCid : Principal,
    feeReceiverCid : Principal,
    passcodeManagerCid : Principal,
    trustedCanisterManagerCid : Principal,
    backupCid : Principal,
    governanceCid : ?Principal,
) = this {
    private type LockState = {
        locked : Bool;
        time : Time.Time;
    };

    /// configuration items
    private stable var _initCycles : Nat = 1860000000000;
    private stable var _feeTickSpacingEntries : [(Nat, Int)] = [(500, 10), (3000, 60), (10000, 200)];
    private stable var _poolDataState : PoolData.State = { poolEntries = []; removedPoolEntries = []; };

    private stable var _principalPasscodes : [(Principal, [Types.Passcode])] = [];
    private var _principalPasscodeMap : HashMap.HashMap<Principal, [Types.Passcode]> = HashMap.fromIter(_principalPasscodes.vals(), 0, Principal.equal, Principal.hash);

    private var _feeTickSpacingMap : HashMap.HashMap<Nat, Int> = HashMap.fromIter<Nat, Int>(_feeTickSpacingEntries.vals(), 10, Nat.equal, Hash.hash);
    private var _poolDataService : PoolData.Service = PoolData.Service(_poolDataState);
    private var _infoAct = actor (Principal.toText(infoCid)) : Types.TxStorage;
    private stable var _lockState : LockState = { locked = false; time = 0};

    // upgrade task
    private stable var _nextPoolVersion : Text = "3.5.0";
    private stable var _backupAct = actor (Principal.toText(backupCid)) : Types.SwapDataBackupActor;
    private stable var _currentUpgradeTask : ?Types.PoolUpgradeTask = null;
    private stable var _pendingUpgradePoolList = List.nil<Types.PoolData>();
    private stable var _upgradeFailedPoolList = List.nil<Types.PoolData>();
    // upgrade history
    private stable var _poolUpgradeTaskHis : [(Principal, [Types.PoolUpgradeTask])] = [];
    private var _poolUpgradeTaskHisMap : HashMap.HashMap<Principal, [Types.PoolUpgradeTask]> = HashMap.fromIter(_poolUpgradeTaskHis.vals(), 0, Principal.equal, Principal.hash);

    public shared (msg) func createPool(args : Types.CreatePoolArgs) : async Result.Result<Types.PoolData, Types.Error> {
        if (not _validatePasscode(msg.caller, args)) { return #err(#InternalError("Please pay the fee for creating SwapPool.")); };
        if (Text.equal(args.token0.address, args.token1.address)) { return #err(#InternalError("Can not use the same token")); };
        if (not _checkStandard(args.token0.standard)) { return #err(#UnsupportedToken("Wrong token0 standard.")); };
        if (not _checkStandard(args.token1.standard)) { return #err(#UnsupportedToken("Wrong token1 standard.")); };
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
                    Cycles.add<system>(_initCycles);
                    let pool = await SwapPool.SwapPool(token0, token1, infoCid, feeReceiverCid, trustedCanisterManagerCid);
                    await pool.init(args.fee, tickSpacing, SafeUint.Uint160(TextUtils.toNat(args.sqrtPriceX96)).val());
                    await IC0Utils.update_settings_add_controller(Principal.fromActor(pool), [initMsg.caller]);
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
                } catch (_e) {
                    throw Error.reject("create pool failed: " # Error.message(_e));
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
                        await poolAct.upgradeTokenStandard(tokenCid);
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
        backupCid : Principal;
        governanceCid : ?Principal;
    }, Types.Error> {
        #ok({
            infoCid = infoCid;
            feeReceiverCid = feeReceiverCid;
            passcodeManagerCid = passcodeManagerCid;
            trustedCanisterManagerCid = trustedCanisterManagerCid;
            backupCid = backupCid;
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
    
    public query func getPendingUpgradePoolList() : async Result.Result<[Types.PoolData], Types.Error> {
        return #ok(List.toArray(_pendingUpgradePoolList));
    };

    public query func getCurrentUpgradeTask() : async Result.Result<?Types.PoolUpgradeTask, Types.Error> {
        return #ok(_currentUpgradeTask);
    };

    public query func getAllPoolUpgradeTaskHis() : async Result.Result<[(Principal, [Types.PoolUpgradeTask])], Types.Error> {
        return #ok(Iter.toArray(_poolUpgradeTaskHisMap.entries()));
    };

    public query func getPoolUpgradeTaskHis(poolCid: Principal) : async Result.Result<[Types.PoolUpgradeTask], Types.Error> {
        switch (_poolUpgradeTaskHisMap.get(poolCid)) { case (?list) { return #ok(list); }; case (_) { return #ok([]); }; };
    };

    public query func getUpgradeFailedPoolList() : async Result.Result<[Types.PoolData], Types.Error> {
        return #ok(List.toArray(_upgradeFailedPoolList));
    };

    public query func getNextPoolVersion() : async Text {
        _nextPoolVersion;
    };

    public shared func getCycleInfo() : async Result.Result<Types.CycleInfo, Types.Error> {
        return #ok({
            balance = Cycles.balance();
            available = Cycles.available();
        });
    };

    // ---------------        Governance Functions              ----------------------

    public shared (msg) func removePool(args : Types.GetPoolArgs) : async Text {
        _checkPermission(msg.caller);
        let poolKey : Text = PoolUtils.getPoolKey(args.token0, args.token1, args.fee);
        _poolDataService.removePool(poolKey);
    };

    public shared (msg) func batchRemovePools(poolCids : [Principal]) : async Result.Result<(), Types.Error> {
        _checkPermission(msg.caller);
        // Check if all cids are SwapPools
        for (poolCid in poolCids.vals()) {
            var found = false;
            label poolCheck for ((poolKey, poolData) in _poolDataService.getPools().entries()) {
                if (Principal.equal(poolCid, poolData.canisterId)) {
                    found := true;
                    break poolCheck;
                };
            };
            if (not found) {
                return #err(#InternalError("Canister " # Principal.toText(poolCid) # " is not a SwapPool"));
            };
        };

        // Remove all pools
        for (poolCid in poolCids.vals()) {
            label removePool for ((poolKey, poolData) in _poolDataService.getPools().entries()) {
                if (Principal.equal(poolCid, poolData.canisterId)) {
                    ignore _poolDataService.removePool(poolKey);
                    break removePool;
                };
            };
        };
        #ok();
    };

    public shared (msg) func setUpgradePoolList(args : Types.UpgradePoolArgs) : async Result.Result<(), Types.Error> {
        _checkPermission(msg.caller);
        // check if task map is empty
        if (List.size(_pendingUpgradePoolList) > 0) { return #err(#InternalError("Please wait until the upgrade task list is empty")); };
        // set a limit on the number of upgrade tasks
        if (Array.size(args.poolIds) > 100) { return #err(#InternalError("The number of canisters to be upgraded cannot be set to more than 100")); };
        for (poolId in args.poolIds.vals()) {
            label l {
                for ((poolKey, pooldata) in _poolDataService.getPools().entries()) {
                    if (Principal.equal(poolId, pooldata.canisterId)) {
                        _pendingUpgradePoolList := List.push(pooldata, _pendingUpgradePoolList);
                    };
                };
            };
        };
        ignore Timer.setTimer<system>(#seconds (10), _execUpgrade);
        return #ok();
    };

    public shared (msg) func clearRemovedPool(canisterId : Principal) : async Text {
        _checkPermission(msg.caller);
        _poolDataService.deletePool(Principal.toText(canisterId));
    };

    public shared (msg) func batchClearRemovedPool(poolCids : [Principal]) : async () {
        _checkPermission(msg.caller);
        for (poolCid in poolCids.vals()) {
            ignore _poolDataService.deletePool(Principal.toText(poolCid));
        };
    };

    public shared (msg) func clearPoolUpgradeTaskHis() : async () {
        _checkPermission(msg.caller);
        _poolUpgradeTaskHis := [];
        _poolUpgradeTaskHisMap := HashMap.fromIter(_poolUpgradeTaskHis.vals(), 0, Principal.equal, Principal.hash);
    };

    public shared (msg) func clearUpgradeFailedPoolList() : async () {
        _checkPermission(msg.caller);
        _upgradeFailedPoolList := List.nil<Types.PoolData>();
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

    public shared (msg) func setPoolAvailable(poolCid : Principal, available : Bool) : async () {
        _checkPermission(msg.caller);
        await _setPoolAvailable(poolCid, available);
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

    public shared (msg) func batchSetPoolAvailable(poolCids : [Principal], available : Bool) : async () {
        _checkPermission(msg.caller);
        for (poolCid in poolCids.vals()) {
            await _setPoolAvailable(poolCid, available);
        };
    };

    public shared (msg) func batchSetPoolLimitOrderAvailable(poolCids : [Principal], available : Bool) : async () {
        _checkPermission(msg.caller);
        for (poolCid in poolCids.vals()) {
            await _setLimitOrderAvailable(poolCid, available);
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

    private func _setPoolAdmins(poolCid : Principal, admins : [Principal]) : async () {
        var poolAct = actor (Principal.toText(poolCid)) : Types.SwapPoolActor;
        await poolAct.setAdmins(admins);
    };

    private func _setPoolAvailable(poolCid : Principal, available : Bool) : async () {
        var poolAct = actor (Principal.toText(poolCid)) : Types.SwapPoolActor;
        await poolAct.setAvailable(available);
    };

    private func _setLimitOrderAvailable(poolCid : Principal, available : Bool) : async () {
        var poolAct = actor (Principal.toText(poolCid)) : Types.SwapPoolActor;
        await poolAct.setLimitOrderAvailable(available);
    };

    private func _addPoolControllers(poolCid : Principal, controllers : [Principal]) : async () {
         await IC0Utils.update_settings_add_controller(poolCid, controllers);
    };

    private func _removePoolControllers(poolCid : Principal, controllers : [Principal]) : async () {
        await IC0Utils.update_settings_remove_controller(poolCid, controllers);
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

    private func _checkPoolVersion(poolId : Principal) : async Bool {
        try {
            let pool = actor(Principal.toText(poolId)) : actor { getVersion : shared query () -> async Text };
            let version = await pool.getVersion();
            let v1 = Text.split(version, #text("."));
            let v2 = Text.split(_nextPoolVersion, #text("."));
            let v1Iter = Iter.map<Text,Nat>(v1, func(x) = switch(Nat.fromText(x)) { case(?n) n; case(_) 0 });
            let v2Iter = Iter.map<Text,Nat>(v2, func(x) = switch(Nat.fromText(x)) { case(?n) n; case(_) 0 });
            let v1Arr = Iter.toArray(v1Iter);
            let v2Arr = Iter.toArray(v2Iter);
            if (v1Arr[0] < v2Arr[0]) { true }
            else if (v1Arr[0] > v2Arr[0]) { false }
            else if (v1Arr[1] < v2Arr[1]) { true }
            else if (v1Arr[1] > v2Arr[1]) { false }
            else { v1Arr[2] < v2Arr[2] };
        } catch (_) {
            false;
        };
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
    
    private func _checkStandard(standard : Text) : Bool {
        if (
            Text.notEqual(standard, "DIP20") 
            and Text.notEqual(standard, "DIP20-WICP") 
            and Text.notEqual(standard, "DIP20-XTC") 
            and Text.notEqual(standard, "EXT") 
            and Text.notEqual(standard, "ICRC1") 
            and Text.notEqual(standard, "ICRC2") 
            and Text.notEqual(standard, "ICRC3") 
            and Text.notEqual(standard, "ICP")
        ) {
            return false;
        };
        return true;
    };

    private func _setNextUpgradeTask() : ?Types.PoolUpgradeTask {
        let (poolData, list) = List.pop(_pendingUpgradePoolList);
        _pendingUpgradePoolList := list;
        switch (poolData) {
            case (?pd) {
                _currentUpgradeTask := ? {
                    poolData = pd;
                    moduleHashBefore = null;
                    moduleHashAfter = null;
                    backup = { timestamp = 0; isDone = false; isSent = false; retryCount = 0; };
                    turnOffAvailable = { timestamp = 0; isDone = false; };
                    stop = { timestamp = 0; isDone = false; };
                    upgrade = { timestamp = 0; isDone = false; };
                    start = { timestamp = 0; isDone = false; };
                    turnOnAvailable = { timestamp = 0; isDone = false; };
                };
                _currentUpgradeTask;
            };
            case (_) { null; };
        };
    };

    private func _addTaskHis(task : Types.PoolUpgradeTask) : () {
        var tempTasks : Buffer.Buffer<Types.PoolUpgradeTask> = Buffer.Buffer<Types.PoolUpgradeTask>(0);
        var currentTaskList = switch (_poolUpgradeTaskHisMap.get(task.poolData.canisterId)) { case (?list) { list }; case (_) { [] }; };
        for (t in currentTaskList.vals()) { tempTasks.add(t) };
        tempTasks.add(task);
        _poolUpgradeTaskHisMap.put(task.poolData.canisterId, Buffer.toArray(tempTasks));
    };

    private func _execUpgrade() : async () {
        switch (_currentUpgradeTask) {
            case (?task) {
                try {
                    // check if the pool version is the same as the next version
                    let isVersionMatch = await _checkPoolVersion(task.poolData.canisterId);
                    if (isVersionMatch) {
                        _currentUpgradeTask := null;
                        if (null != _setNextUpgradeTask()) { 
                            ignore Timer.setTimer<system>(#seconds (0), _execUpgrade); 
                        };
                        return;
                    };
                    // execute step
                    if (not task.backup.isDone) {
                        if (not task.backup.isSent) {
                            var currentTask = await UpgradeTask.stepBackup(task, backupCid);
                            _currentUpgradeTask := ?currentTask;
                            ignore Timer.setTimer<system>(#seconds (30), _execUpgrade);
                        } else {
                            // timer to check if backup is done
                            switch (await _backupAct.isBackupDone(task.poolData.canisterId)) {
                                case (#ok(isDone)) {
                                    if (isDone) {
                                        _currentUpgradeTask := ?{
                                            poolData = task.poolData;
                                            moduleHashBefore = task.moduleHashBefore;
                                            moduleHashAfter = task.moduleHashAfter;
                                            backup = { timestamp = task.backup.timestamp; isDone = true; isSent = true; retryCount = task.backup.retryCount; };
                                            turnOffAvailable = task.turnOffAvailable;
                                            stop = task.stop;
                                            upgrade = task.upgrade;
                                            start = task.start;
                                            turnOnAvailable = task.turnOnAvailable;
                                        };
                                        ignore Timer.setTimer<system>(#seconds (0), _execUpgrade);
                                    } else {
                                        let newRetryCount = task.backup.retryCount + 1;
                                        if (newRetryCount > 3) {
                                            _upgradeFailedPoolList := List.push(task.poolData, _upgradeFailedPoolList);
                                            _currentUpgradeTask := null;
                                            if (null != _setNextUpgradeTask()) { ignore Timer.setTimer<system>(#seconds (0), _execUpgrade); };
                                        } else {
                                            _currentUpgradeTask := ?{
                                                poolData = task.poolData;
                                                moduleHashBefore = task.moduleHashBefore;
                                                moduleHashAfter = task.moduleHashAfter;
                                                backup = { timestamp = task.backup.timestamp; isDone = false; isSent = true; retryCount = newRetryCount; };
                                                turnOffAvailable = task.turnOffAvailable;
                                                stop = task.stop;
                                                upgrade = task.upgrade;
                                                start = task.start;
                                                turnOnAvailable = task.turnOnAvailable;
                                            };
                                            ignore Timer.setTimer<system>(#seconds (30), _execUpgrade);
                                        };
                                    };
                                };
                                case (#err(_)) {
                                    _upgradeFailedPoolList := List.push(task.poolData, _upgradeFailedPoolList);
                                    _currentUpgradeTask := null;
                                    if (null != _setNextUpgradeTask()) { ignore Timer.setTimer<system>(#seconds (0), _execUpgrade); };
                                };
                            };
                        };
                    } else if (not task.turnOffAvailable.isDone) {
                        var currentTask = await UpgradeTask.stepTurnOffAvailable(task);
                        _currentUpgradeTask := ?currentTask;
                        ignore Timer.setTimer<system>(#seconds (10), _execUpgrade);
                    } else if (not task.stop.isDone) {
                        var currentTask = await UpgradeTask.stepStop(task);
                        _currentUpgradeTask := ?currentTask;
                        ignore Timer.setTimer<system>(#seconds (5), _execUpgrade);
                    } else if (not task.upgrade.isDone) {
                        var currentTask = await UpgradeTask.stepUpgrade(task, infoCid, feeReceiverCid, trustedCanisterManagerCid);
                        _currentUpgradeTask := ?currentTask;
                        ignore Timer.setTimer<system>(#seconds (5), _execUpgrade);
                    } else if (not task.start.isDone) {
                        var currentTask = await UpgradeTask.stepStart(task);
                        _currentUpgradeTask := ?currentTask;
                        ignore Timer.setTimer<system>(#seconds (5), _execUpgrade);
                    } else if (not task.turnOnAvailable.isDone) {
                        var currentTask = await UpgradeTask.stepTurnOnAvailable(task);
                        ignore _backupAct.removeBackupData(task.poolData.canisterId);
                        _addTaskHis(currentTask);
                        _currentUpgradeTask := null;
                        ignore Timer.setTimer<system>(#seconds (0), _execUpgrade);
                    };
                } catch (_) {
                    _upgradeFailedPoolList := List.push(task.poolData, _upgradeFailedPoolList);
                    _currentUpgradeTask := null;
                    if (null != _setNextUpgradeTask()) { ignore Timer.setTimer<system>(#seconds (0), _execUpgrade); };
                };
            }; 
            case (_) {
                if (null != _setNextUpgradeTask()) { ignore Timer.setTimer<system>(#seconds (0), _execUpgrade); };
            };  
        };
    };

    // --------------------------- Version Control      -------------------------------
    private var _version : Text = "3.5.0";
    public query func getVersion() : async Text { _version };
    
    system func preupgrade() {
        _feeTickSpacingEntries := Iter.toArray(_feeTickSpacingMap.entries());
        _principalPasscodes := Iter.toArray(_principalPasscodeMap.entries());
        _poolUpgradeTaskHis := Iter.toArray(_poolUpgradeTaskHisMap.entries());
        _poolDataState := _poolDataService.getState();
    };

    system func postupgrade() {
        _feeTickSpacingEntries := [];
        _principalPasscodes := [];
        _poolUpgradeTaskHis := [];
    };

    system func inspect({
        arg : Blob;
        caller : Principal;
        msg : Types.SwapFactoryMsg;
    }) : Bool {
        return switch (msg) {
            // Controller
            case (#clearRemovedPool _)                   { _hasPermission(caller) };
            case (#removePool _)                         { _hasPermission(caller) };
            case (#removePoolErrorTransferLog _)         { _hasPermission(caller) };
            case (#upgradePoolTokenStandard _)           { _hasPermission(caller) };
            case (#addPoolControllers _)                 { _hasPermission(caller) };
            case (#removePoolControllers _)              { _hasPermission(caller) };
            case (#setPoolAdmins _)                      { _hasPermission(caller) };
            case (#setBackupCid _)                       { _hasPermission(caller) };
            case (#setPoolAvailable _)                   { _hasPermission(caller) };
            case (#setUpgradePoolList _)                 { _hasPermission(caller) };
            case (#batchAddPoolControllers _)            { _hasPermission(caller) };
            case (#batchRemovePoolControllers _)         { _hasPermission(caller) };
            case (#batchSetPoolAdmins _)                 { _hasPermission(caller) };
            // Anyone
            case (_)                                   { true };
        };
    };

};
