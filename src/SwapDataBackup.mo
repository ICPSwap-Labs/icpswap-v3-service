import HashMap "mo:base/HashMap";
import Iter "mo:base/Iter";
import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Text "mo:base/Text";
import Prim "mo:⛔";
import Types "./Types";

shared (initMsg) actor class SwapDataBackup(
    factoryCid : Principal,
) = this {

    // Store pool backup data
    public type PoolBackupData = {
        isDone : Bool;
        isFailed : Bool;
        errorMsg : Text;
        metadata : ?Types.PoolMetadata;
        allTokenBalances : ?[(Principal, { balance0 : Nat; balance1 : Nat; })];
        positions : ?[Types.PositionInfoWithId];
        ticks : ?[Types.TickInfoWithId]; 
        tickBitmaps : ?[(Int, Nat)];
        tokenAmountState : ?{
            token0Amount : Nat;
            token1Amount : Nat;
            swapFee0Repurchase : Nat;
            swapFee1Repurchase : Nat;
            swapFeeReceiver : Text;
        };
        userPositions : ?[Types.UserPositionInfoWithId];
        userPositionIds : ?[(Text, [Nat])];
        feeGrowthGlobal : ?{ feeGrowthGlobal0X128 : Nat; feeGrowthGlobal1X128 : Nat; };
    };

    private stable var _poolBackupEntries : [(Principal, PoolBackupData)] = [];
    private var _poolBackupMap : HashMap.HashMap<Principal, PoolBackupData> = HashMap.fromIter(_poolBackupEntries.vals(), 0, Principal.equal, Principal.hash);

    // Query backup data for a specific pool
    public query func getPoolBackup(poolCid: Principal) : async Result.Result<PoolBackupData, Types.Error> {
        switch(_poolBackupMap.get(poolCid)) {
            case (?data) { #ok(data) };
            case null { #err(#InternalError("No backup data found for pool " # Principal.toText(poolCid))) };
        }
    };

    // Query all pool backups
    public query func getAllPoolBackups() : async Result.Result<[(Principal, PoolBackupData)], Types.Error> {
        #ok(Iter.toArray(_poolBackupMap.entries()))
    };

    public shared (msg) func backup(poolCid: Principal) : async Result.Result<(), Types.Error> {
        _checkPermission(msg.caller);
        // ----- backup -----
        var poolAct = actor (Principal.toText(poolCid)) : Types.SwapPoolActor;
        let metadata = switch (await poolAct.metadata()) {
            case (#ok(metadata)) { metadata };
            case (#err(code)) { 
                _poolBackupMap.put(poolCid, { isDone = false; isFailed = true; errorMsg = "Get pool metadata failed: " # debug_show (code); metadata = null; allTokenBalances = null; positions = null; ticks = null; tickBitmaps = null; tokenAmountState = null; userPositions = null; userPositionIds = null; feeGrowthGlobal = null; }); 
                return #err(#InternalError("Get pool metadata failed: " # debug_show (code))); 
            };
        };
        let allTokenBalances = switch (await poolAct.allTokenBalance(0,0)) {
            case (#ok(paged)) {
                switch (await poolAct.allTokenBalance(0,paged.totalElements)) {
                    case (#ok(all)) { all.content; };
                    case (#err(code)) {
                        _poolBackupMap.put(poolCid, { isDone = false; isFailed = true; errorMsg = "Get all token balance failed: " # debug_show (code); metadata = null; allTokenBalances = null; positions = null; ticks = null; tickBitmaps = null; tokenAmountState = null; userPositions = null; userPositionIds = null; feeGrowthGlobal = null; }); 
                        return #err(#InternalError("Get all token balance failed: " # debug_show (code))); 
                    };
                };
            };
            case (#err(code)) { return #err(#InternalError("Get all token balance failed: " # debug_show (code))); };
        };
        let positions = switch (await poolAct.getPositions(0,0)) {
            case (#ok(paged)) {
                switch (await poolAct.getPositions(0,paged.totalElements)) {
                    case (#ok(all)) { all.content; };
                    case (#err(code)) {
                        _poolBackupMap.put(poolCid, { isDone = false; isFailed = true; errorMsg = "Get positions failed: " # debug_show (code); metadata = null; allTokenBalances = null; positions = null; ticks = null; tickBitmaps = null; tokenAmountState = null; userPositions = null; userPositionIds = null; feeGrowthGlobal = null; }); 
                        return #err(#InternalError("Get positions failed: " # debug_show (code))); 
                    };
                };
            };
            case (#err(code)) {
                _poolBackupMap.put(poolCid, { isDone = false; isFailed = true; errorMsg = "Get positions failed: " # debug_show (code); metadata = null; allTokenBalances = null; positions = null; ticks = null; tickBitmaps = null; tokenAmountState = null; userPositions = null; userPositionIds = null; feeGrowthGlobal = null; }); 
                return #err(#InternalError("Get positions failed: " # debug_show (code))); 
            };
        };
        let ticks = switch (await poolAct.getTicks(0,0)) {
            case (#ok(paged)) {
                switch (await poolAct.getTicks(0,paged.totalElements)) {
                    case (#ok(all)) { all.content; };
                    case (#err(code)) {
                        _poolBackupMap.put(poolCid, { isDone = false; isFailed = true; errorMsg = "Get ticks failed: " # debug_show (code); metadata = null; allTokenBalances = null; positions = null; ticks = null; tickBitmaps = null; tokenAmountState = null; userPositions = null; userPositionIds = null; feeGrowthGlobal = null; }); 
                        return #err(#InternalError("Get ticks failed: " # debug_show (code))); 
                    };
                };
            };
            case (#err(code)) {
                _poolBackupMap.put(poolCid, { isDone = false; isFailed = true; errorMsg = "Get ticks failed: " # debug_show (code); metadata = null; allTokenBalances = null; positions = null; ticks = null; tickBitmaps = null; tokenAmountState = null; userPositions = null; userPositionIds = null; feeGrowthGlobal = null; }); 
                return #err(#InternalError("Get ticks failed: " # debug_show (code))); 
            };
        };
        let tickBitmaps = switch (await poolAct.getTickBitmaps()) {
            case (#ok(data)) { data };
            case (#err(code)) {
                _poolBackupMap.put(poolCid, { isDone = false; isFailed = true; errorMsg = "Get tick bitmaps failed: " # debug_show (code); metadata = null; allTokenBalances = null; positions = null; ticks = null; tickBitmaps = null; tokenAmountState = null; userPositions = null; userPositionIds = null; feeGrowthGlobal = null; }); 
                return #err(#InternalError("Get tick bitmaps failed: " # debug_show (code))); 
            };
        };
        let tokenAmountState = switch (await poolAct.getTokenAmountState()) {
            case (#ok(data)) { data; };
            case (#err(code)) { return #err(#InternalError("Get token amount state failed: " # debug_show (code))); };
        };
        let userPositions = switch (await poolAct.getUserPositions(0,0)) {
            case (#ok(paged)) {
                switch (await poolAct.getUserPositions(0,paged.totalElements)) {
                    case (#ok(all)) { all.content; };
                    case (#err(code)) {
                        _poolBackupMap.put(poolCid, { isDone = false; isFailed = true; errorMsg = "Get user positions failed: " # debug_show (code); metadata = null; allTokenBalances = null; positions = null; ticks = null; tickBitmaps = null; tokenAmountState = null; userPositions = null; userPositionIds = null; feeGrowthGlobal = null; }); 
                        return #err(#InternalError("Get user positions failed: " # debug_show (code))); 
                    };
                };
            };
            case (#err(code)) {
                _poolBackupMap.put(poolCid, { isDone = false; isFailed = true; errorMsg = "Get user positions failed: " # debug_show (code); metadata = null; allTokenBalances = null; positions = null; ticks = null; tickBitmaps = null; tokenAmountState = null; userPositions = null; userPositionIds = null; feeGrowthGlobal = null; }); 
                return #err(#InternalError("Get user positions failed: " # debug_show (code))); 
            };
        };
        let userPositionIds = switch (await poolAct.getUserPositionIds()) {
            case (#ok(data)) { data };
            case (#err(code)) {
                _poolBackupMap.put(poolCid, { isDone = false; isFailed = true; errorMsg = "Get user position ids failed: " # debug_show (code); metadata = null; allTokenBalances = null; positions = null; ticks = null; tickBitmaps = null; tokenAmountState = null; userPositions = null; userPositionIds = null; feeGrowthGlobal = null; }); 
                return #err(#InternalError("Get user position ids failed: " # debug_show (code))); 
            };
        };
        let feeGrowthGlobal = switch (await poolAct.getFeeGrowthGlobal()) {
            case (#ok(data)) { data };
            case (#err(code)) {
                _poolBackupMap.put(poolCid, { isDone = false; isFailed = true; errorMsg = "Get fee growth global failed: " # debug_show (code); metadata = null; allTokenBalances = null; positions = null; ticks = null; tickBitmaps = null; tokenAmountState = null; userPositions = null; userPositionIds = null; feeGrowthGlobal = null; }); 
                return #err(#InternalError("Get fee growth global failed: " # debug_show (code))); 
            };
        };
        // after version 3.5.0
        // todo backup getLimitOrderAvailabilityState, getLimitOrders, getLimitOrderStack 
        _poolBackupMap.put(poolCid, {
            isDone = true; isFailed = false; errorMsg = ""; 
            metadata = ?metadata; allTokenBalances = ?allTokenBalances; positions = ?positions; ticks = ?ticks; 
            tickBitmaps = ?tickBitmaps; tokenAmountState = ?tokenAmountState; userPositions = ?userPositions; 
            userPositionIds = ?userPositionIds; feeGrowthGlobal = ?feeGrowthGlobal;
        });
        return #ok();
    };

    public query func isBackupDone(poolCid : Principal) : async Result.Result<Bool, Types.Error> {
        switch (_poolBackupMap.get(poolCid)) {
            case (?backup) {
                if (backup.isFailed) {
                    return #err(#InternalError(backup.errorMsg));
                };
                #ok(backup.isDone);
            };
            case (_) {
                #err(#InternalError("No backup data found for pool " # Principal.toText(poolCid)));
            };
        };
    };

    public shared ({ caller }) func removeBackupData(poolCid : Principal) : async Result.Result<(), Types.Error> {
        _checkPermission(caller);
        switch (_poolBackupMap.get(poolCid)) {
            case (?_) {
                _poolBackupMap.delete(poolCid);
                #ok();
            };
            case (_) {
                #err(#InternalError("No backup data found for pool " # Principal.toText(poolCid)));
            };
        };
    };

    public shared ({ caller }) func clearAllBackupData() : async Result.Result<(), Types.Error> {
        _checkPermission(caller);
        _poolBackupMap := HashMap.HashMap<Principal, PoolBackupData>(0, Principal.equal, Principal.hash);
        #ok();
    };

    public query func getBackupData(poolCid : Principal) : async Result.Result<PoolBackupData, Types.Error> {
        switch (_poolBackupMap.get(poolCid)) {
            case (?backup) {
                if (backup.isFailed) {
                    return #err(#InternalError(backup.errorMsg));
                };
                #ok(backup);
            };
            case (_) {
                #err(#InternalError("No backup data found for pool " # Principal.toText(poolCid)));
            };
        };
    };
        
    // public shared (msg) func recoverPool() : async Result.Result<Types.PoolData, Types.Error> {
    //     // ----- recover -----
    //     var tickSpacing = switch (_feeTickSpacingMap.get(metadata.fee)) {
    //         case (?feeAmountTickSpacingFee) { feeAmountTickSpacingFee };
    //         case (_) { return "TickSpacing cannot be 0"; };
    //     };
    //     Cycles.add<system>(_initCycles);
    //     let pool = await SwapPoolRecover.SwapPoolRecover(
    //         metadata.token0, 
    //         metadata.token1, 
    //         infoCid, 
    //         feeReceiverCid, 
    //         trustedCanisterManagerCid
    //     );
    //     await pool.init(
    //         metadata.fee, 
    //         tickSpacing,
    //         SafeUint.Uint160(metadata.sqrtPriceX96).val()
    //     );
    //     await IC0Utils.update_settings_add_controller(Principal.fromActor(pool), [initMsg.caller]);
    //     await _infoAct.addClient(Principal.fromActor(pool));
        
    //     await pool.recoverUserPositions(userPositions);
    //     await pool.recoverPositions(positions);
    //     await pool.recoverTickBitmaps(tickBitmaps);
    //     await pool.recoverTicks(ticks);
    //     await pool.recoverUserPositionIds(userPositionIds);
    //     await pool.resetPositionTickService();
    //     await pool.recoverMetadata(metadata, feeGrowthGlobal);

    //     return Principal.toText(Principal.fromActor(pool));
    // };

    private func _checkPermission(caller : Principal) {
        assert(_hasPermission(caller));
    };

    private func _hasPermission(caller: Principal): Bool {
        return Prim.isController(caller) or Principal.equal(caller, factoryCid);
    };

    // --------------------------- Version Control      -------------------------------
    private var _version : Text = "3.5.0";
    public query func getVersion() : async Text { _version };

    system func preupgrade() {
        _poolBackupEntries := Iter.toArray(_poolBackupMap.entries());
    };

    system func postupgrade() {
        _poolBackupEntries := [];
    };
};
