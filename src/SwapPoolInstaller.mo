import Result "mo:base/Result";
import Principal "mo:base/Principal";
import Cycles "mo:base/ExperimentalCycles";
import Types "./Types";
import IC0Utils "mo:commons/utils/IC0Utils";
import SwapPool "./SwapPool";
import Prim "mo:⛔";

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
    private func _hasPermission(caller: Principal): Bool {
        return Prim.isController(caller) or Principal.equal(caller, factoryId) or Principal.equal(caller, governanceId);
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
        let _ = await (system SwapPool.SwapPool)(#install canisterId)(token0, token1, infoCid, feeReceiverCid, trustedCanisterManagerCid, positionIndexCid);
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
    
    // --------------------------- Version Control      -------------------------------
    private var _version : Text = "3.6.0";
    public query func getVersion() : async Text { _version };
    
    system func preupgrade() {
    };
    system func postupgrade() {
    };
}
