import Blob "mo:base/Blob";
import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Types "./Types";
import CanisterUtils "./CanisterUtils";

shared (initMsg) actor class SwapFactoryTest() = this {

    public type UpgradeResult = {
        #Success;
        #InternalError;
    };

    public type UpgradeArg = {
        wasm : Blob;
        pools : [UpgradePoolArg];
    };

    public type UpgradePoolArg = {
        poolId : Principal;
        arg : Blob;
    };

    // --------------------------- upgrade pool      -------------------------------

    private stable var _swap_pool_wasm : Blob = Blob.fromArray([]);

    public query func _get_swap_pool_wasm() : async Blob { _swap_pool_wasm };

    public query func get_pools() : async Result.Result<[Types.PoolData], Types.Error> { 
        #ok([
            {
                key = "";
                token0 = {
                    address = "ryjl3-tyaaa-aaaaa-aaaba-cai";
                    standard = "ICRC-1";
                };
                token1 = {
                    address = "ryjl3-tyaaa-aaaaa-aaaba-cai";
                    standard = "ICRC-1";
                };
                canisterId = Principal.fromText("aq22q-5aaaa-aaaah-adyna-cai");
                fee = 3000;
                tickSpacing = 1;
            }
        ])
    };

    public shared(msg) func upgrade_pool(arg : UpgradeArg) : async UpgradeResult {
        _swap_pool_wasm := arg.wasm;
        await exec_upgrade(arg.pools);
        #Success
    };

    private func exec_upgrade(pools : [UpgradePoolArg]) : async () {
        for (pool in pools.vals()) {
            await CanisterUtils.CanisterUtils().upgradeCode(pool.poolId, pool.arg, _swap_pool_wasm);
        };
    };
    
    system func preupgrade() {
    };

    system func postupgrade() {
    };

};
