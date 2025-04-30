import Blob "mo:base/Blob";
import Error "mo:base/Error";
import Result "mo:base/Result";
import Principal "mo:base/Principal";
import Cycles "mo:base/ExperimentalCycles";
// import Debug "mo:base/Debug";
import Prim "mo:⛔";

import CollectionUtils "mo:commons/utils/CollectionUtils";
import IC0Utils "mo:commons/utils/IC0Utils";

import Types "./Types";
import WasmManager "./components/WasmManager";

actor class SwapPoolInstaller(
    factoryId: Principal,
    governanceId: Principal,
    positionIndexCid: Principal
) = this {
    public type Error = {
        #Unauthorized;
    };
    private stable var _initCycles : Nat = 1860000000000;
    private stable var _initTopUpCycles : Nat = 500000000000;

    private stable var _activeWasmBlob = Blob.fromArray([]);
    private var _wasmManager = WasmManager.Service(_activeWasmBlob);
    private stable var _admins : [Principal] = [];

    private func _hasPermission(caller: Principal): Bool {
        return Prim.isController(caller) or Principal.equal(caller, factoryId) or Principal.equal(caller, governanceId);
    };

    private func _checkAdminPermission(caller: Principal) {
        assert(not Principal.isAnonymous(caller));
        assert(CollectionUtils.arrayContains<Principal>(_admins, caller, Principal.equal) or _hasPermission(caller));
    };

    public shared ({ caller }) func install(
        token0: Types.Token, 
        token1: Types.Token, 
        infoCid: Principal, 
        feeReceiverCid: Principal, 
        trustedCanisterManagerCid: Principal,
        positionIndexCid: Principal
    ) : async Principal {
        assert (_hasPermission(caller));
        let createCanisterResult = await IC0Utils.create_canister(null, null, _initCycles);
        let canisterId = createCanisterResult.canister_id;
        await IC0Utils.deposit_cycles(canisterId, _initTopUpCycles);
        // let _ = await (system SwapPool.SwapPool)(#install canisterId)(token0, token1, infoCid, feeReceiverCid, trustedCanisterManagerCid, positionIndexCid);
        await IC0Utils.install_code(canisterId, to_candid(token0, token1, infoCid, feeReceiverCid, trustedCanisterManagerCid, positionIndexCid), _wasmManager.getActiveWasm(), #install);
        await IC0Utils.update_settings_add_controller(canisterId, [factoryId, governanceId]);
        return canisterId;
    };

    public shared func getStatus() : async { controllers: [Principal]; moduleHash: ?Blob } {
        let status = await IC0Utils.canister_status(Principal.fromActor(this));
        let controllers = status.settings.controllers;
        let moduleHash = status.module_hash;
        return {
            controllers = controllers;
            moduleHash = moduleHash;
        };
    };

    public query func getInitArgs() : async Result.Result<{ factoryId: Principal; governanceId: Principal; positionIndexCid: Principal; }, Types.Error> {
        return #ok({
            factoryId = factoryId;
            governanceId = governanceId;
            positionIndexCid = positionIndexCid;
        });
    };

    public shared func getCycleInfo() : async Result.Result<Types.CycleInfo, Types.Error> {
        return #ok({
            balance = Cycles.balance();
            available = Cycles.available();
        });
    };

    // --------------------------- Admin Management Functions -------------------------------
    public shared (msg) func setAdmins(admins : [Principal]) : async () {
        assert(_hasPermission(msg.caller));
        for (admin in admins.vals()) {
            if (Principal.isAnonymous(admin)) {
                throw Error.reject("Anonymous principals cannot be admins");
            };
        };
        _admins := admins;
    };

    public query func getAdmins(): async [Principal] {
        return _admins;
    };

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
    
    // --------------------------- Version Control      -------------------------------
    private var _version : Text = "3.6.0";
    public query func getVersion() : async Text { _version };
    
    system func preupgrade() {
    };
    system func postupgrade() {
    };
}
