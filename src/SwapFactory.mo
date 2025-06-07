import Array "mo:base/Array";
import Bool "mo:base/Bool";
import Buffer "mo:base/Buffer";
import Blob "mo:base/Blob";
import Cycles "mo:base/ExperimentalCycles";
import Error "mo:base/Error";
import Hash "mo:base/Hash";
import HashMap "mo:base/HashMap";
import Int "mo:base/Int";
import Iter "mo:base/Iter";
import List "mo:base/List";
import Nat "mo:base/Nat";
import Timer "mo:base/Timer";
import Prim "mo:⛔";
import Order "mo:base/Order";
import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Text "mo:base/Text";
import Time "mo:base/Time";
import Option "mo:base/Option";

import SafeUint "mo:commons/math/SafeUint";
import TextUtils "mo:commons/utils/TextUtils";
import IC0Utils "mo:commons/utils/IC0Utils";
import CollectionUtils "mo:commons/utils/CollectionUtils";

import ICRC21 "./components/ICRC21";
import PoolData "./components/PoolData";
import UpgradeTask "./components/UpgradeTask";
import BlockTimestamp "./libraries/BlockTimestamp";
import PoolUtils "./utils/PoolUtils";
import WasmManager "./components/WasmManager";

import ICRCTypes "./ICRCTypes";
import Types "./Types";

shared (initMsg) actor class SwapFactory(
    infoCid : Principal,
    feeReceiverCid : Principal,
    passcodeManagerCid : Principal,
    trustedCanisterManagerCid : Principal,
    backupCid : Principal,
    governanceCid : ?Principal,
    positionIndexCid : Principal
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

    /**
        make sure the version is not the same as the previous one and same as the new version of SwapPool
    **/
    private var _nextPoolVersion : Text = "3.6.0";
    // upgrade task
    private stable var _backupAct = actor (Principal.toText(backupCid)) : Types.SwapDataBackupActor;
    private stable var _currentUpgradeTask : ?Types.PoolUpgradeTask = null;
    private stable var _pendingUpgradePoolList = List.nil<Types.PoolUpgradeTask>();
    private stable var _upgradeFailedPoolList = List.nil<Types.FailedPoolInfo>();
    // upgrade history
    private stable var _poolUpgradeTaskHis : [(Principal, [Types.PoolUpgradeTask])] = [];
    private var _poolUpgradeTaskHisMap : HashMap.HashMap<Principal, [Types.PoolUpgradeTask]> = HashMap.fromIter(_poolUpgradeTaskHis.vals(), 0, Principal.equal, Principal.hash);
    // create pool records
    private stable var _createPoolRecords: List.List<Types.CreatePoolRecord> = List.nil<Types.CreatePoolRecord>();
    // position index
    private stable var _positionIndexAct = actor (Principal.toText(positionIndexCid)) : Types.PositionIndexActor;

    // Add WasmManager state
    private stable var _isWasmActive = false;
    private stable var _activeWasmBlob = Blob.fromArray([]);
    private var _wasmManager = WasmManager.Service(_activeWasmBlob);

    public shared (msg) func createPool(args : Types.CreatePoolArgs) : async Result.Result<Types.PoolData, Types.Error> {
        if (not _isWasmActive) { return #err(#InternalError("Wasm of SwapPool is not ready yet, please contact the administrator.")); };
        if (not _validatePasscode(msg.caller, args)) { return #err(#InternalError("Please pay the fee for creating SwapPool.")); };
        if (Text.equal(args.token0.address, args.token1.address)) { return #err(#InternalError("Can not use the same token")); };
        if (not _checkStandard(args.token0.standard)) { return #err(#UnsupportedToken("Wrong token0 standard.")); };
        if (not _checkStandard(args.token1.standard)) { return #err(#UnsupportedToken("Wrong token1 standard.")); };
        let installer: ?InstallerFunc = _getInstallFunc(args.subnet);
        let installFunc : InstallerFunc = switch (installer) {
            case (?_installer) { _installer };
            case (_) { return #err(#InternalError("Installer not found")); };
        };
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
                    let passcode = { token0 = Principal.fromText(token0.address); token1 = Principal.fromText(token1.address); fee = args.fee; };
                    if(not _deletePasscode(msg.caller, passcode)) { return #err(#InternalError("Passcode is not existed.")); };

                    let pool: Types.SwapPoolActor = await installFunc(token0, token1, infoCid, feeReceiverCid, trustedCanisterManagerCid, positionIndexCid);
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

                    // Add creation record
                    _addCreatePoolRecord({
                        caller = msg.caller;
                        poolId = ?Principal.fromActor(pool);
                        timestamp = Time.now();
                        token0 = token0;
                        token1 = token1;
                        fee = args.fee;
                        status = "success";
                        err = null;
                    });

                    poolData;
                } catch (e) {
                    // Rollback passcode if pool creation fails
                    _rollbackPasscode(msg.caller, { token0 = Principal.fromText(token0.address); token1 = Principal.fromText(token1.address); fee = args.fee; });
                    _addCreatePoolRecord({
                        caller = msg.caller;
                        poolId = null;
                        timestamp = Time.now();
                        token0 = token0;
                        token1 = token1;
                        fee = args.fee;
                        status = "failed";
                        err = ?Error.message(e);
                    });
                    return #err(#InternalError("Create pool failed: " # Error.message(e)));
                };
            };
        };

        _unlock();

        // update pool ids
        ignore Timer.setTimer<system>(#nanoseconds (0), func() : async () { await _positionIndexAct.updatePoolIds(); });
        
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

    /// get pool by token addresses and fee.
    public query func getPool(args : Types.GetPoolArgs) : async Result.Result<Types.PoolData, Types.Error> {
        let poolKey : Text = PoolUtils.getPoolKey(args.token0, args.token1, args.fee);
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
        positionIndexCid : Principal;
    }, Types.Error> {
        #ok({
            infoCid = infoCid;
            feeReceiverCid = feeReceiverCid;
            passcodeManagerCid = passcodeManagerCid;
            trustedCanisterManagerCid = trustedCanisterManagerCid;
            backupCid = backupCid;
            governanceCid = governanceCid;  
            positionIndexCid = positionIndexCid;
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

    public query func getCreatePoolRecords() : async [Types.CreatePoolRecord] {
        return List.toArray(_createPoolRecords);
    };

    public query func getCreatePoolRecordsByCaller(caller: Principal) : async [Types.CreatePoolRecord] {
        return List.toArray(List.filter(_createPoolRecords, func(record: Types.CreatePoolRecord) : Bool {
            Principal.equal(record.caller, caller)
        }));
    };
    
    public query func getPendingUpgradePoolList() : async Result.Result<[Types.PoolUpgradeTask], Types.Error> {
        return #ok(List.toArray(_pendingUpgradePoolList));
    };

    public query func getCurrentUpgradeTask() : async Result.Result<?Types.PoolUpgradeTask, Types.Error> {
        return #ok(_currentUpgradeTask);
    };

    public query func getPoolUpgradeTaskHisList() : async Result.Result<[(Principal, [Types.PoolUpgradeTask])], Types.Error> {
        return #ok(Iter.toArray(_poolUpgradeTaskHisMap.entries()));
    };

    public query func getPoolUpgradeTaskHis(poolCid: Principal) : async Result.Result<[Types.PoolUpgradeTask], Types.Error> {
        switch (_poolUpgradeTaskHisMap.get(poolCid)) { case (?list) { return #ok(list); }; case (_) { return #ok([]); }; };
    };

    public query func getUpgradeFailedPoolList() : async Result.Result<[Types.FailedPoolInfo], Types.Error> {
        return #ok(List.toArray(_upgradeFailedPoolList));
    };

    public query func getNextPoolVersion() : async Text {
        _nextPoolVersion;
    };

    public query func getWasmActiveStatus() : async Bool {
        _isWasmActive;
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
        "https://bplw4-cqaaa-aaaag-qcb7q-cai.icp0.io",
        "https://oisy.com"
    ];
    public shared(msg) func setIcrc28TrustedOrigins(origins: [Text]) : async Result.Result<Bool, Types.Error> {
        _checkAdminPermission(msg.caller);
        _icrc28_trusted_origins := origins;
        return #ok(true);
    };
    public func icrc28_trusted_origins() : async ICRCTypes.Icrc28TrustedOriginsResponse {
        return {trusted_origins = _icrc28_trusted_origins};
    };
    public query func icrc10_supported_standards() : async [{ url : Text; name : Text }] {
        ICRC21.icrc10_supported_standards();
    };
    public shared func icrc21_canister_call_consent_message(request : ICRCTypes.Icrc21ConsentMessageRequest) : async ICRCTypes.Icrc21ConsentMessageResponse {
        return ICRC21.icrc21_canister_call_consent_message(request);
    };

    public shared func getCycleInfo() : async Result.Result<Types.CycleInfo, Types.Error> {
        return #ok({
            balance = Cycles.balance();
            available = Cycles.available();
        });
    };

    // ---------------        Factory Admin Functions              ----------------------

    public shared (msg) func upgradePoolTokenStandard(poolCid : Principal, tokenCid : Principal) : async Result.Result<Text, Types.Error> {
        _checkAdminPermission(msg.caller);
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

    public shared(msg) func retryAllFailedUpgrades() : async Result.Result<(), Types.Error> {
        _checkAdminPermission(msg.caller);
        // Check if there are any pending upgrades
        if (List.size(_pendingUpgradePoolList) > 0) { 
            return #err(#InternalError("Cannot retry failed upgrades while there are pending upgrades")); 
        };
        // Check if there's a current upgrade task running
        switch(_currentUpgradeTask) {
            case (?_) { return #err(#InternalError("Cannot retry failed upgrades while there is an upgrade in progress")); };
            case (null) {};
        };
        // Move all failed tasks to pending list
        var failedList = _upgradeFailedPoolList;
        _upgradeFailedPoolList := List.nil<Types.FailedPoolInfo>();
        // Add each failed task to pending list
        label addTasks while (not List.isNil(failedList)) {
            let (failedInfoOpt, remainingList) = List.pop(failedList);
            failedList := remainingList;
            switch(failedInfoOpt) {
                case (?failedInfo) { _pendingUpgradePoolList := List.push(failedInfo.task, _pendingUpgradePoolList); };
                case (null) {};
            };
        };
        // If we added any tasks, start the upgrade process
        if (not List.isNil(_pendingUpgradePoolList)) {
            ignore Timer.setTimer<system>(#seconds (0), _execUpgrade);
        };
        #ok();
    };

    public shared (msg) func clearPoolUpgradeTaskHis() : async () {
        _checkAdminPermission(msg.caller);
        _poolUpgradeTaskHis := [];
        _poolUpgradeTaskHisMap := HashMap.fromIter(_poolUpgradeTaskHis.vals(), 0, Principal.equal, Principal.hash);
    };

    public shared (msg) func clearUpgradeFailedPoolList() : async () {
        _checkAdminPermission(msg.caller);
        _upgradeFailedPoolList := List.nil<Types.FailedPoolInfo>();
    };

    public shared (msg) func batchSetPoolIcrc28TrustedOrigins(poolCids : [Principal], origins : [Text]) : async Result.Result<(), Types.Error> {
        _checkAdminPermission(msg.caller);
        for (poolCid in poolCids.vals()) {
            var poolAct = actor (Principal.toText(poolCid)) : Types.SwapPoolActor;
            try {
                switch(await poolAct.setIcrc28TrustedOrigins(origins)) {
                    case (#ok(_)) { };
                    case (#err(e)) { return #err(#InternalError("Failed to set ICRC28 trusted origins for " # Principal.toText(poolCid) # ": " # debug_show(e))); };
                };
            } catch (e) {
                return #err(#InternalError("Failed to set ICRC28 trusted origins for " # Principal.toText(poolCid) # ": " # Error.message(e)));
            };
        };
        return #ok();
    };

    // ---------------       Factory Governance Functions              ----------------------

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
        if (not _isWasmActive) { return #err(#InternalError("Wasm is not active")); };
        if (Array.size(args.poolIds) == 0) { return #err(#InternalError("The number of canisters to be upgraded cannot be set to 0")); };
        if (Array.size(args.poolIds) > 500) { return #err(#InternalError("The number of canisters to be upgraded cannot be set to more than 500")); };
        
        // check if task map is empty
        if (List.size(_pendingUpgradePoolList) > 0) { return #err(#InternalError("Please wait until the upgrade task list is empty")); };
        // clear the upgrade task history
        _poolUpgradeTaskHis := [];
        _poolUpgradeTaskHisMap := HashMap.fromIter(_poolUpgradeTaskHis.vals(), 0, Principal.equal, Principal.hash);
        for (poolId in args.poolIds.vals()) {
            label poolLoop {
                for ((poolKey, pooldata) in _poolDataService.getPools().entries()) {
                    if (Principal.equal(poolId, pooldata.canisterId)) {
                        let newTask : Types.PoolUpgradeTask = {
                            poolData = pooldata;
                            moduleHashBefore = null;
                            moduleHashAfter = null;
                            backup = { timestamp = 0; isDone = false; isSent = false; retryCount = 0; };
                            turnOffAvailable = { timestamp = 0; isDone = false; };
                            stop = { timestamp = 0; isDone = false; };
                            upgrade = { timestamp = 0; isDone = false; };
                            start = { timestamp = 0; isDone = false; };
                            turnOnAvailable = { timestamp = 0; isDone = false; };
                        };
                        _pendingUpgradePoolList := List.push(newTask, _pendingUpgradePoolList);
                        break poolLoop; // Break after finding and processing the matching pool
                    };
                };
            };
        };
        ignore Timer.setTimer<system>(#seconds (10), _execUpgrade);
        return #ok();
    };

    public shared (msg) func batchClearRemovedPool(poolCids : [Principal]) : async () {
        _checkPermission(msg.caller);
        for (poolCid in poolCids.vals()) { await _addCanisterControllers(poolCid, [feeReceiverCid]); };
        for (poolCid in poolCids.vals()) { ignore _poolDataService.deletePool(Principal.toText(poolCid)); };
    };

    // ---------------        Pool Governance Functions        ----------------------

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
            await _addCanisterControllers(poolCid, controllers);
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

    public shared (msg) func batchAddInstallerControllers(controllers : [Principal]) : async () {
        _checkPermission(msg.caller);
        for (poolInstaller in _poolInstallers.vals()) {
            await _addCanisterControllers(poolInstaller.canisterId, controllers);
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

    private func _addCreatePoolRecord(record: Types.CreatePoolRecord) {
        _createPoolRecords := List.push<Types.CreatePoolRecord>(record, _createPoolRecords);
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

    private func _addCanisterControllers(canisterCid : Principal, controllers : [Principal]) : async () {
         await IC0Utils.update_settings_add_controller(canisterCid, controllers);
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
        
            // Compare versions
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
        } catch (e) {
            throw Error.reject("Failed to get version: " # Error.message(e));
        };
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

    private func _rollbackPasscode(principal: Principal, passcode: Types.Passcode) {
        switch (_principalPasscodeMap.get(principal)) {
            case (?passcodes) {
                // Check if passcode already exists
                if (CollectionUtils.arrayContains<Types.Passcode>(passcodes, passcode, _passcodeEqual)) {
                    return;
                };
                var passcodeList : List.List<Types.Passcode> = List.fromArray(passcodes);
                passcodeList := List.push(passcode, passcodeList);
                _principalPasscodeMap.put(principal, List.toArray(passcodeList));
            };
            case (_) {
                var passcodeList = List.nil<Types.Passcode>();
                passcodeList := List.push(passcode, passcodeList);
                _principalPasscodeMap.put(principal, List.toArray(passcodeList));
            };
        };
    };

    private func _passcodeEqual(p1 : Types.Passcode, p2 : Types.Passcode) : Bool { 
        Principal.equal(p1.token0, p2.token0) and  Principal.equal(p1.token1, p2.token1) and Nat.equal(p1.fee, p2.fee)
    };
    
    private func _checkStandard(standard : Text) : Bool {
        let supportedStandards = [
            "DIP20",
            "DIP20-WICP",
            "DIP20-XTC",
            "EXT",
            "ICRC1",
            "ICRC2",
            "ICP"
        ];
        return Option.isSome(Array.find<Text>(supportedStandards, func(s) = Text.equal(s, standard)));
    };

    private func _setNextUpgradeTask() : ?Types.PoolUpgradeTask {
        let (task, list) = List.pop(_pendingUpgradePoolList);
        _pendingUpgradePoolList := list;
        switch (task) {
            case (?t) {
                _currentUpgradeTask := ?t;
                _currentUpgradeTask;
            };
            case (_) { null };
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
                    if (not task.backup.isDone) {
                        if (not task.backup.isSent) {
                            try {
                                // check if the pool version is outdated
                                let isVersionOutdated = await _checkPoolVersion(task.poolData.canisterId);
                                if (not isVersionOutdated) {
                                    // Add task to history since it's already up to date
                                    let timestamp = BlockTimestamp.blockTimestamp();
                                    _addTaskHis({
                                        poolData = task.poolData;
                                        moduleHashBefore = task.moduleHashBefore;
                                        moduleHashAfter = task.moduleHashAfter;
                                        backup = { timestamp = timestamp; isDone = true; isSent = false; retryCount = 0; };
                                        turnOffAvailable = { timestamp = timestamp; isDone = true; };
                                        stop = { timestamp = timestamp; isDone = true; };
                                        upgrade = { timestamp = timestamp; isDone = true; };
                                        start = { timestamp = timestamp; isDone = true; };
                                        turnOnAvailable = { timestamp = timestamp; isDone = true; };
                                    });
                                    _currentUpgradeTask := null;
                                    if (null != _setNextUpgradeTask()) { 
                                        ignore Timer.setTimer<system>(#seconds (0), _execUpgrade); 
                                    };
                                    return;
                                };
                            } catch (e) {
                                // If version check fails, add to failed list
                                _upgradeFailedPoolList := List.push({
                                    task = task;
                                    timestamp = BlockTimestamp.blockTimestamp();
                                    errorMsg = Error.message(e);
                                }, _upgradeFailedPoolList);
                                _currentUpgradeTask := null;
                                if (null != _setNextUpgradeTask()) { 
                                    ignore Timer.setTimer<system>(#seconds (0), _execUpgrade); 
                                };
                                return;
                            };
                            
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
                                            _upgradeFailedPoolList := List.push({
                                                task = task;
                                                timestamp = BlockTimestamp.blockTimestamp();
                                                errorMsg = "Backup failed";
                                            }, _upgradeFailedPoolList);
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
                                case (#err(msg)) {
                                    _upgradeFailedPoolList := List.push({
                                        task = task;
                                        timestamp = BlockTimestamp.blockTimestamp();
                                        errorMsg = "Check backup status failed: " # debug_show(msg);
                                    }, _upgradeFailedPoolList);
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
                        var currentTask = await UpgradeTask.stepUpgrade(task, infoCid, feeReceiverCid, trustedCanisterManagerCid, positionIndexCid, _wasmManager.getActiveWasm());
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
                } catch (e) {
                    _upgradeFailedPoolList := List.push({
                        task = task;
                        timestamp = BlockTimestamp.blockTimestamp();
                        errorMsg = Error.message(e);
                    }, _upgradeFailedPoolList);
                    _currentUpgradeTask := null;
                    if (null != _setNextUpgradeTask()) { ignore Timer.setTimer<system>(#seconds (0), _execUpgrade); };
                };
            }; 
            case (_) {
                if (null != _setNextUpgradeTask()) { ignore Timer.setTimer<system>(#seconds (0), _execUpgrade); };
            };
        };
    };

    // --------------------------------        Pool Installer Functions        ---------------------------------------

    private stable var _installerModuleHash : ?Blob = null;
    public shared ({ caller}) func setInstallerModuleHash(moduleHash : Blob) : async () {
        _checkPermission(caller);
        _installerModuleHash := ?moduleHash;
    };
    public query func getInstallerModuleHash() : async ?Blob { _installerModuleHash; };

    private func _validateInstaller(installer: Types.PoolInstaller) : async { #Ok : Text; #Err : Text; } {
        let status = await IC0Utils.canister_status(installer.canisterId);
        let controllers = status.settings.controllers;
        let moduleHash = status.module_hash;
        // Check controllers
        if (controllers.size() != 2 or (
            switch(governanceCid) {
                case (?gCid) {
                    let hasGovAndFactory = Array.sort(controllers, Principal.compare) == Array.sort([gCid, Principal.fromActor(this)], Principal.compare);
                    not hasGovAndFactory
                };
                case (null) { true }; // If no governanceCid, condition fails
            }
        )) {
            return #Err("Installer " # Principal.toText(installer.canisterId) # " must have exactly two controllers: governanceCid and factoryCid");
        };

        // Check moduleHash
        switch (_installerModuleHash) {
            case (?expectedHash) {
                switch (moduleHash) {
                    case (?actualHash) {
                        if (not Blob.equal(actualHash, expectedHash)) {
                            return #Err("Installer " # Principal.toText(installer.canisterId) # " has incorrect module hash");
                        };
                    };
                    case (null) { return #Err("Installer " # Principal.toText(installer.canisterId) # " has no module hash"); };
                };
            };
            case (null) { return #Err("No installer module hash has been set"); };
        };
        
        return #Ok("Valid installer");
    };
    public shared ({ caller }) func addPoolInstallersValidate(installers : [Types.PoolInstaller]) : async { #Ok : Text; #Err : Text; } {
        _checkPermission(caller);
        for (installer in installers.vals()) {
            switch (await _validateInstaller(installer)) {
                case (#Err(msg)) { return #Err(msg); };
                case (_) {};
            };
        };
        return #Ok(debug_show (installers));
    };
    public shared ({ caller }) func removePoolInstallerValidate(canisterId : Principal) : async { #Ok : Text; #Err : Text; } {
        _checkPermission(caller);
        for (installer in _poolInstallers.vals()) {
            if (Principal.equal(installer.canisterId, canisterId)) {
                return #Ok(debug_show (canisterId));
            };
        };
        return #Err("Pool installer " # Principal.toText(canisterId) # " not found");
    };
    public shared ({ caller }) func setInstallerModuleHashValidate(moduleHash : Blob) : async { #Ok : Text; #Err : Text; } {
        _checkPermission(caller);
        // Validate moduleHash is not empty
        if (Blob.toArray(moduleHash).size() == 0) { return #Err("Module hash cannot be empty"); };
        // Validate moduleHash size (should be 32 bytes for SHA-256)
        if (Blob.toArray(moduleHash).size() != 32) { return #Err("Invalid module hash size. Expected 32 bytes"); };
        return #Ok(debug_show(moduleHash));
    };
    
    private stable var _poolInstallers : [Types.PoolInstaller] = [];
    private type Installer = {
        #External : Types.SwapPoolInstaller;
        #Local;
    };
    private type InstallerFunc = (Types.Token, Types.Token, Principal, Principal, Principal, Principal) -> async Types.SwapPoolActor;
    private func _getInstallFunc(subnet: ?Text) : ?InstallerFunc {
        switch (_getInstaller(subnet)) {
            case (?#External(act)) {
                let fun = func _actInstall(token0: Types.Token, token1: Types.Token, infoCid: Principal, feeReceiverCid: Principal, trustedCanisterManagerCid: Principal, positionIndexCid: Principal) : async Types.SwapPoolActor {
                    let canisterId: Principal = await act.install(token0, token1, infoCid, feeReceiverCid, trustedCanisterManagerCid, positionIndexCid);
                    return actor(Principal.toText(canisterId)) : Types.SwapPoolActor;
                };
                return Option.make(fun);
            };
            case (?#Local) {
                let fun = func (token0: Types.Token, token1: Types.Token, infoCid: Principal, feeReceiverCid: Principal, trustedCanisterManagerCid: Principal, positionIndexCid: Principal) : async Types.SwapPoolActor {
                    Cycles.add<system>(_initCycles);
                    let createCanisterResult = await IC0Utils.create_canister(null, null, _initCycles);
                    let canisterId = createCanisterResult.canister_id;
                    await IC0Utils.deposit_cycles(canisterId, _initCycles);
                    await IC0Utils.install_code(canisterId, to_candid(token0, token1, infoCid, feeReceiverCid, trustedCanisterManagerCid, positionIndexCid), _wasmManager.getActiveWasm(), #install);
                    return actor(Principal.toText(canisterId)) : Types.SwapPoolActor;
                };
                return Option.make(fun);
            };
            case (_) { null };  
        };
    };
    private func _getInstaller(subnet: ?Text) : ?Installer {
        switch (subnet) {
            case (?_subnet) {
                let installer = Array.find<Types.PoolInstaller>(_poolInstallers, func(installer : Types.PoolInstaller) : Bool { installer.subnet == _subnet });
                return switch (installer) { 
                    case (?_installer) { Option.make(#External(actor(Principal.toText(_installer.canisterId)): Types.SwapPoolInstaller)) }; 
                    case (_) { null }; 
                };
            };
            case (_) {
                if (_poolInstallers.size() == 0) {
                    return Option.make(#Local);
                } else {
                    return Option.make(#External(actor(Principal.toText(_poolInstallers[0].canisterId)) : Types.SwapPoolInstaller));
                };
            };
        };
    };
   
    public shared({caller}) func addPoolInstallers(installers : [Types.PoolInstaller]) : async () {
        _checkPermission(caller);
        let buffer: Buffer.Buffer<Types.PoolInstaller> = Buffer.Buffer<Types.PoolInstaller>(0);
        for (installer in installers.vals()) {
            switch(await _validateInstaller(installer)) {
                case (#Ok(_)) { buffer.add(installer); }; 
                case (#Err(err)) { throw Error.reject(err); };
            };
        };
        _poolInstallers := Array.sort<Types.PoolInstaller>(Buffer.toArray(buffer), func(a: Types.PoolInstaller, b: Types.PoolInstaller) : Order.Order {
            if (a.weight > b.weight) { #less }
            else if (a.weight < b.weight) { #greater }
            else { #equal }
        });
    };
    public shared({caller}) func removePoolInstaller(canisterId : Principal) : async () {
        _checkPermission(caller);
        _poolInstallers := Array.filter<Types.PoolInstaller>(_poolInstallers, func(installer : Types.PoolInstaller) : Bool { not Principal.equal(installer.canisterId, canisterId) });
    };
    public query func getPoolInstallers() : async [Types.PoolInstaller] { _poolInstallers };
    
    // --------------------------- WasmManager Functions -------------------------------
    
    public shared (msg) func uploadWasmChunk(chunk : [Nat8]) : async Nat {
        _checkAdminPermission(msg.caller);
        _wasmManager.uploadChunk(chunk);
    };

    public shared (msg) func combineWasmChunks() : async () {
        _checkAdminPermission(msg.caller);
        _wasmManager.combineChunks();
    };

    public shared (msg) func activateWasm() : async () {
        _checkAdminPermission(msg.caller);
        _wasmManager.activateWasm();
        _activeWasmBlob := _wasmManager.getActiveWasm();
        _isWasmActive := true;
    };

    public shared (msg) func setWasmActive(isActive : Bool) : async () {
        _checkAdminPermission(msg.caller);
        _isWasmActive := isActive;
    };

    public shared (msg) func clearChunks() : async () {
        _checkAdminPermission(msg.caller);
        _wasmManager.clearChunks();
    };

    public query func getStagingWasm() : async Blob {
        _wasmManager.getStagingWasm();
    };

    public query func getActiveWasm() : async Blob {
        _wasmManager.getActiveWasm();
    };

    // --------------------------- ACL ------------------------------------

    private stable var _admins : [Principal] = [];
    public shared (msg) func setAdmins(admins : [Principal]) : async () {
        _checkPermission(msg.caller);
        for (admin in admins.vals()) {
            if (Principal.isAnonymous(admin)) {
                throw Error.reject("Anonymous principals cannot be pool admins");
            };
        };
        _admins := admins;
    };
    public query func getAdmins(): async [Principal] {
        return _admins;
    };
    private func _checkAdminPermission(caller: Principal) {
        assert(not Principal.isAnonymous(caller));
        assert(CollectionUtils.arrayContains<Principal>(_admins, caller, Principal.equal) or _hasPermission(caller));
    };
    private func _checkPermission(caller : Principal) {
        assert(_hasPermission(caller));
    };
    private func _hasPermission(caller: Principal): Bool {
        return Prim.isController(caller) or (switch (governanceCid) {case (?cid) { Principal.equal(caller, cid) }; case (_) { false };});
    };

    // --------------------------- Version Control      -------------------------------
    private var _version : Text = "3.6.0";
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
            case (#setUpgradePoolList _)                 { _hasPermission(caller) };
            case (#setAdmins _)                          { _hasPermission(caller) };
            case (#setIcrc28TrustedOrigins _)            { _hasPermission(caller) };
            case (#batchAddPoolControllers _)            { _hasPermission(caller) };
            case (#batchAddInstallerControllers _)       { _hasPermission(caller) };
            case (#batchRemovePoolControllers _)         { _hasPermission(caller) };
            case (#batchSetPoolAdmins _)                 { _hasPermission(caller) };
            case (#batchRemovePools _)                   { _hasPermission(caller) };
            case (#batchClearRemovedPool _)              { _hasPermission(caller) };
            case (#batchSetPoolAvailable _)              { _hasPermission(caller) };
            case (#batchSetPoolLimitOrderAvailable _)    { _hasPermission(caller) };
            case (#setInstallerModuleHash _)             { _hasPermission(caller) };
            case (#addPoolInstallers _)                  { _hasPermission(caller) };
            case (#removePoolInstaller _)                { _hasPermission(caller) };
            // Admin
            case (#upgradePoolTokenStandard _)           { CollectionUtils.arrayContains<Principal>(_admins, caller, Principal.equal) or _hasPermission(caller) };
            case (#retryAllFailedUpgrades _)             { CollectionUtils.arrayContains<Principal>(_admins, caller, Principal.equal) or _hasPermission(caller) };
            case (#clearPoolUpgradeTaskHis _)            { CollectionUtils.arrayContains<Principal>(_admins, caller, Principal.equal) or _hasPermission(caller) };
            case (#clearUpgradeFailedPoolList _)         { CollectionUtils.arrayContains<Principal>(_admins, caller, Principal.equal) or _hasPermission(caller) };
            case (#batchSetPoolIcrc28TrustedOrigins _)   { CollectionUtils.arrayContains<Principal>(_admins, caller, Principal.equal) or _hasPermission(caller) };
            case (#uploadWasmChunk _)                    { CollectionUtils.arrayContains<Principal>(_admins, caller, Principal.equal) or _hasPermission(caller) };
            case (#combineWasmChunks _)                  { CollectionUtils.arrayContains<Principal>(_admins, caller, Principal.equal) or _hasPermission(caller) };
            case (#activateWasm _)                       { CollectionUtils.arrayContains<Principal>(_admins, caller, Principal.equal) or _hasPermission(caller) };
            // Anyone
            case (_)                                     { true };
        };
    };
};
