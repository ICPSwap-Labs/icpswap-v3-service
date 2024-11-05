import HashMap "mo:base/HashMap";
import Iter "mo:base/Iter";
import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Text "mo:base/Text";
import Prim "mo:⛔";
import Types "./Types";

shared (initMsg) actor class SwapDataBackup(
    factoryCid : Principal,
    governanceCid : ?Principal,
) = this {

    // Store pool backup data
    public type PoolBackupData = {
        isDone : Bool;
        isFailed : Bool;
        errorMsg : Text;
        metadata : Types.PoolMetadata;
        allTokenBalances : [(Principal, { balance0 : Nat; balance1 : Nat; })];
        positions : [Types.PositionInfoWithId];
        ticks : [Types.TickInfoWithId]; 
        tickBitmaps : [(Int, Nat)];
        tokenAmountState : {
            token0Amount : Nat;
            token1Amount : Nat;
            swapFee0Repurchase : Nat;
            swapFee1Repurchase : Nat;
            swapFeeReceiver : Text;
        };
        userPositions : [Types.UserPositionInfoWithId];
        userPositionIds : [(Text, [Nat])];
        feeGrowthGlobal : { feeGrowthGlobal0X128 : Nat; feeGrowthGlobal1X128 : Nat; };
        limitOrders : { lowerLimitOrders : [(Types.LimitOrderKey, Types.LimitOrderValue)]; upperLimitOrders : [(Types.LimitOrderKey, Types.LimitOrderValue)]; };
        limitOrderStack : [(Types.LimitOrderKey, Types.LimitOrderValue)];
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
                return #err(_setBackupError(poolCid, "Get metadata failed: " # debug_show(code)));
            };
        };
        let allTokenBalances = switch (await poolAct.allTokenBalance(0,0)) {
            case (#ok(paged)) {
                switch (await poolAct.allTokenBalance(0,paged.totalElements)) {
                    case (#ok(all)) { all.content; };
                    case (#err(code)) {
                        return #err(_setBackupError(poolCid, "Get all token balance failed: " # debug_show(code)));
                    };
                };
            };
            case (#err(code)) {
                return #err(_setBackupError(poolCid, "Get all token balance failed: " # debug_show(code)));
            };
        };
        let positions = switch (await poolAct.getPositions(0,0)) {
            case (#ok(paged)) {
                switch (await poolAct.getPositions(0,paged.totalElements)) {
                    case (#ok(all)) { all.content; };
                    case (#err(code)) {
                        return #err(_setBackupError(poolCid, "Get positions failed: " # debug_show(code)));
                    };
                };
            };
            case (#err(code)) {
                return #err(_setBackupError(poolCid, "Get positions failed: " # debug_show(code)));
            };
        };
        let ticks = switch (await poolAct.getTicks(0,0)) {
            case (#ok(paged)) {
                switch (await poolAct.getTicks(0,paged.totalElements)) {
                    case (#ok(all)) { all.content; };
                    case (#err(code)) {
                        return #err(_setBackupError(poolCid, "Get ticks failed: " # debug_show(code)));
                    };
                };
            };
            case (#err(code)) {
                return #err(_setBackupError(poolCid, "Get ticks failed: " # debug_show(code)));
            };
        };
        let tokenAmountState = switch (await poolAct.getTokenAmountState()) {
            case (#ok(data)) { data; };
            case (#err(code)) { 
                return #err(_setBackupError(poolCid, "Get token amount state failed: " # debug_show(code)));
            };
        };
        let userPositions = switch (await poolAct.getUserPositions(0,0)) {
            case (#ok(paged)) {
                switch (await poolAct.getUserPositions(0,paged.totalElements)) {
                    case (#ok(all)) { all.content; };
                    case (#err(code)) {
                        return #err(_setBackupError(poolCid, "Get user positions failed: " # debug_show(code)));
                    };
                };
            };
            case (#err(code)) {
                return #err(_setBackupError(poolCid, "Get user positions failed: " # debug_show(code)));
            };
        };
        let userPositionIds = switch (await poolAct.getUserPositionIds()) {
            case (#ok(data)) { data };
            case (#err(code)) { return #err(_setBackupError(poolCid, "Get user position ids failed: " # debug_show(code))); };
        };

        // after version 3.5.0
        // let initArgs = switch (await poolAct.getInitArgs()) {
        //     case (#ok(data)) { data };
        //     case (#err(code)) { return #err(_setBackupError(poolCid, "Get init args failed: " # debug_show(code))); };
        // };
        // let tickBitmaps = switch (await poolAct.getTickBitmaps()) {
        //     case (#ok(data)) { data };
        //     case (#err(code)) { return #err(_setBackupError(poolCid, "Get tick bitmaps failed: " # debug_show(code))); };
        // };
        // let feeGrowthGlobal = switch (await poolAct.getFeeGrowthGlobal()) {
        //     case (#ok(data)) { data };
        //     case (#err(code)) { return #err(_setBackupError(poolCid, "Get fee growth global failed: " # debug_show(code))); };
        // };
        // let limitOrders = switch (await poolAct.getLimitOrders()) {
        //     case (#ok(data)) { data };
        //     case (#err(code)) {  return #err(_setBackupError(poolCid, "Get limit orders failed: " # debug_show(code))); };
        // };
        // let limitOrderStack = switch (await poolAct.getLimitOrderStack()) {
        //     case (#ok(data)) { data };
        //     case (#err(code)) { return #err(_setBackupError(poolCid, "Get limit order stack failed: " # debug_show(code))); };
        // };
        // _poolBackupMap.put(poolCid, {
        //     isDone = true;
        //     isFailed = false;
        //     errorMsg = "";
        //     metadata = metadata;
        //     allTokenBalances = allTokenBalances;
        //     positions = positions;
        //     ticks = ticks;
        //     tickBitmaps = tickBitmaps;
        //     tokenAmountState = tokenAmountState;
        //     userPositions = userPositions;
        //     userPositionIds = userPositionIds;
        //     feeGrowthGlobal = feeGrowthGlobal;
        //     limitOrders = limitOrders;
        //     limitOrderStack = limitOrderStack;
        // });
        _poolBackupMap.put(poolCid, {
            isDone = true;
            isFailed = false;
            errorMsg = "";
            metadata = metadata;
            allTokenBalances = allTokenBalances;
            positions = positions;
            ticks = ticks;
            tokenAmountState = tokenAmountState;
            userPositions = userPositions;
            userPositionIds = userPositionIds;
            tickBitmaps = [];
            feeGrowthGlobal = { feeGrowthGlobal0X128 = 0; feeGrowthGlobal1X128 = 0; };
            limitOrders = { lowerLimitOrders = []; upperLimitOrders = []; };
            limitOrderStack = [];
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

    // Add this helper function near the top of the class
    private func _setBackupError(poolCid: Principal, errorMsg: Text) : Types.Error {
        let errorData : PoolBackupData = {
            isDone = false;
            isFailed = true;
            errorMsg = errorMsg;
            metadata = {
                token0 = { address = ""; standard = "" };
                token1 = { address = ""; standard = "" };
                fee = 0;
                tickSpacing = 0;
                sqrtPriceX96 = 0;
                key = "";
                liquidity = 0;
                maxLiquidityPerTick = 0;
                nextPositionId = 0;
                tick = 0;
            };
            allTokenBalances = [];
            positions = [];
            ticks = [];
            tickBitmaps = [];
            tokenAmountState = {
                token0Amount = 0;
                token1Amount = 0;
                swapFee0Repurchase = 0;
                swapFee1Repurchase = 0;
                swapFeeReceiver = "";
            };
            userPositions = [];
            userPositionIds = [];
            feeGrowthGlobal = {
                feeGrowthGlobal0X128 = 0;
                feeGrowthGlobal1X128 = 0;
            };
            limitOrders = { lowerLimitOrders = []; upperLimitOrders = []; };
            limitOrderStack = [];
        };
        _poolBackupMap.put(poolCid, errorData);
        #InternalError(errorMsg);
    };


    private func _checkPermission(caller : Principal) {
        assert(_hasPermission(caller));
    };

    private func _hasPermission(caller: Principal): Bool {
        return Prim.isController(caller) or Principal.equal(caller, factoryCid) or (switch (governanceCid) {case (?cid) { Principal.equal(caller, cid) }; case (_) { false };});
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
