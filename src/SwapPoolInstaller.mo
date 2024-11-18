import Result "mo:base/Result";
import Principal "mo:base/Principal";
import Cycles "mo:base/ExperimentalCycles";
import Types "./Types";
import IC0Utils "mo:commons/utils/IC0Utils";
import SwapPool "./SwapPool";
import Prim "mo:⛔";
import Debug "mo:base/Debug";

actor class SwapPoolInstaller(
    factoryId: Principal,
    governanceId: Principal
) = this {
    public type Error = {
        #Unauthorized;
    };
    private stable var _initCycles : Nat = 1860000000000;
    private func _hasPermission(caller: Principal): Bool {
        return Prim.isController(caller) or Principal.equal(caller, factoryId) or Principal.equal(caller, governanceId);
    };

    public func install(token0: Types.Token, token1: Types.Token, infoCid: Principal, feeReceiverCid: Principal, trustedCanisterManagerCid: Principal) : async Principal {
        Cycles.add<system>(_initCycles);
        let act = await SwapPool.SwapPool(token0, token1, infoCid, feeReceiverCid, trustedCanisterManagerCid);
        let canisterId = Principal.fromActor(act);
        await IC0Utils.update_settings_add_controller(canisterId, [factoryId]);
        return canisterId;
    };
    public shared func getCycleInfo() : async Result.Result<Types.CycleInfo, Types.Error> {
        return #ok({
            balance = Cycles.balance();
            available = Cycles.available();
        });
    };
    
    system func preupgrade() {
    };
    system func postupgrade() {
    };
}
