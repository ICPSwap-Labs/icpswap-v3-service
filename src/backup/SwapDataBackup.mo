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
import PoolUtils "../utils/PoolUtils";
import PoolData "../components/PoolData";
import UpgradeTask "../components/UpgradeTask";
import SwapPool "../SwapPool";
import SwapPoolRecover "./SwapPoolRecover";
import Types "../Types";

shared (initMsg) actor class SwapDataBackup(
    infoCid : Principal,
    feeReceiverCid : Principal,
    trustedCanisterManagerCid : Principal,
) = this {

    private var _infoAct = actor (Principal.toText(infoCid)) : Types.TxStorage;

    /// configuration items
    private stable var _initCycles : Nat = 1860000000000;
    private stable var _feeTickSpacingEntries : [(Nat, Int)] = [(500, 10), (3000, 60), (10000, 200)];
    private var _feeTickSpacingMap : HashMap.HashMap<Nat, Int> = HashMap.fromIter<Nat, Int>(_feeTickSpacingEntries.vals(), 10, Nat.equal, Hash.hash);
    
    public shared (msg) func backupAndRecoverPool(poolCid: Principal) : async Text {
        // ----- backup -----
        var poolAct = actor (Principal.toText(poolCid)) : Types.SwapPoolActor;
        let metadata = switch (await poolAct.metadata()) {
            case (#ok(metadata)) { metadata };
            case (#err(code)) { return "Get pool metadata failed: " # debug_show (code); };
        };
        // let allTokenBalances = switch (await poolAct.allTokenBalance(0,0)) {
        //     case (#ok(paged)) {
        //         switch (await poolAct.allTokenBalance(0,paged.totalElements)) {
        //             case (#ok(all)) { all.content; };
        //             case (#err(code)) { return #err(#InternalError("Get all token balance failed: " # debug_show (code))); };
        //         };
        //     };
        //     case (#err(code)) { return #err(#InternalError("Get all token balance failed: " # debug_show (code))); };
        // };
        let positions = switch (await poolAct.getPositions(0,0)) {
            case (#ok(paged)) {
                switch (await poolAct.getPositions(0,paged.totalElements)) {
                    case (#ok(all)) { all.content; };
                    case (#err(code)) { return "Get positions failed: " # debug_show (code); };
                };
            };
            case (#err(code)) { return "Get positions failed: " # debug_show (code); };
        };
        let ticks = switch (await poolAct.getTicks(0,0)) {
            case (#ok(paged)) {
                switch (await poolAct.getTicks(0,paged.totalElements)) {
                    case (#ok(all)) { all.content; };
                    case (#err(code)) { return "Get ticks failed: " # debug_show (code); };
                };
            };
            case (#err(code)) { return "Get ticks failed: " # debug_show (code); };
        };
        let tickBitmaps = switch (await poolAct.getTickBitmaps()) {
            case (#ok(data)) { data };
            case (#err(code)) { return "Get user position ids failed: " # debug_show (code); };
        };
        // let tokenAmountState = switch (await poolAct.getTokenAmountState()) {
        //     case (#ok(data)) { data; };
        //     case (#err(code)) { return #err(#InternalError("Get token amount state failed: " # debug_show (code))); };
        // };
        let userPositions = switch (await poolAct.getUserPositions(0,0)) {
            case (#ok(paged)) {
                switch (await poolAct.getUserPositions(0,paged.totalElements)) {
                    case (#ok(all)) { all.content; };
                    case (#err(code)) { return "Get user positions failed: " # debug_show (code); };
                };
            };
            case (#err(code)) { return "Get user positions failed: " # debug_show (code); };
        };
        let userPositionIds = switch (await poolAct.getUserPositionIds()) {
            case (#ok(data)) { data };
            case (#err(code)) { return "Get user position ids failed: " # debug_show (code); };
        };
        let feeGrowthGlobal = switch (await poolAct.getFeeGrowthGlobal()) {
            case (#ok(data)) { data };
            case (#err(code)) { return "Get fee growth global failed: " # debug_show (code); };
        };
        // after version 3.5.0
        // todo backup getLimitOrderAvailabilityState, getLimitOrders, getLimitOrderStack 

        // ----- recover -----
        var tickSpacing = switch (_feeTickSpacingMap.get(metadata.fee)) {
            case (?feeAmountTickSpacingFee) { feeAmountTickSpacingFee };
            case (_) { return "TickSpacing cannot be 0"; };
        };
        Cycles.add<system>(_initCycles);
        let pool = await SwapPoolRecover.SwapPoolRecover(
            metadata.token0, 
            metadata.token1, 
            infoCid, 
            feeReceiverCid, 
            trustedCanisterManagerCid
        );
        await pool.init(
            metadata.fee, 
            tickSpacing,
            SafeUint.Uint160(metadata.sqrtPriceX96).val()
        );
        await IC0Utils.update_settings_add_controller(Principal.fromActor(pool), [initMsg.caller]);
        await _infoAct.addClient(Principal.fromActor(pool));
        
        await pool.recoverUserPositions(userPositions);
        await pool.recoverPositions(positions);
        await pool.recoverTickBitmaps(tickBitmaps);
        await pool.recoverTicks(ticks);
        await pool.recoverUserPositionIds(userPositionIds);
        await pool.resetPositionTickService();
        await pool.recoverMetadata(metadata, feeGrowthGlobal);


        return Principal.toText(Principal.fromActor(pool));
    };
    
    // public shared (msg) func recoverPool() : async Result.Result<Types.PoolData, Types.Error> {
    // };

    // --------------------------- Version Control      -------------------------------
    private var _version : Text = "3.5.0";
    public query func getVersion() : async Text { _version };
    
    system func preupgrade() {
        _feeTickSpacingEntries := Iter.toArray(_feeTickSpacingMap.entries());
    };

    system func postupgrade() {
        _feeTickSpacingEntries := [];
    };

};
