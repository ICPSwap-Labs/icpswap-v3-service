import Blob "mo:base/Blob";
import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Types "./Types";
import CanisterUtils "./CanisterUtils";
import Arg "mo:candid/Arg";
import Type "mo:candid/Type";
import CandidEncoder "mo:candid/Encoder";

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

    public shared(msg) func upgrade_pool(swap_pool_wasm : Blob) : async UpgradeResult {
        _swap_pool_wasm := swap_pool_wasm;
        await exec_upgrade();
        #Success
    };

    private func exec_upgrade() : async () {
        let argToken0 : Arg.Arg = {
            type_ = #record([
                {
                    tag = #name("address");
                    type_ = #text;
                },
                {
                    tag = #name("standard");
                    type_ = #text;
                }
            ]);
            value = #record([
                {
                    tag = #name("address");
                    value = #text("ryjl3-tyaaa-aaaaa-aaaba-cai");
                },
                {
                    tag = #name("standard");
                    value = #text("ICRC-1");
                }
            ]);
        };
        let argToken1 : Arg.Arg = {
            type_ = #record([
                {
                    tag = #name("address");
                    type_ = #text;
                },
                {
                    tag = #name("standard");
                    type_ = #text;
                }
            ]);
            value = #record([
                {
                    tag = #name("address");
                    value = #text("ryjl3-tyaaa-aaaaa-aaaba-cai");
                },
                {
                    tag = #name("standard");
                    value = #text("ICRC-1");
                }
            ]);
        };
        let argInfoCid : Arg.Arg = {
            type_ = #principal;
            value = #principal(Principal.fromText("ry2wr-pqaaa-aaaah-adxla-cai"));
        };
        let argFeeReceiverCid : Arg.Arg = {
            type_ = #principal;
            value = #principal(Principal.fromText("ry2wr-pqaaa-aaaah-adxla-cai"));
        };
        let argBlob : Blob = CandidEncoder.encode([argToken0, argToken1, argInfoCid, argFeeReceiverCid]);
        await CanisterUtils.CanisterUtils().upgradeCode(Principal.fromText("azzrm-liaaa-aaaah-adymq-cai"), argBlob, _swap_pool_wasm);
    };
    
    system func preupgrade() {
    };

    system func postupgrade() {
    };

};
