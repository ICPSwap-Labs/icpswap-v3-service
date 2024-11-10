import Principal "mo:base/Principal";
import Cycles "mo:base/ExperimentalCycles";
import Buffer "mo:base/Buffer";
import Result "mo:base/Result";
import Types "./Types";
import Bool "mo:base/Bool";
import Prim "mo:⛔";
import CollectionUtils "mo:commons/utils/CollectionUtils";

shared (initMsg) actor class TrustedCanisterManager(
    governanceCid : ?Principal
) = this {

    private stable var _canisters : [Principal] = [];

    public shared (msg) func addCanister(canister : Principal) : async Bool {
        _checkPermission(msg.caller);
        if (not CollectionUtils.arrayContains(_canisters, canister, Principal.equal)) {
            var buffer: Buffer.Buffer<Principal> = Buffer.Buffer<Principal>(_canisters.size() + 1);
            for (it: Principal in _canisters.vals()) {
                buffer.add(it);
            };
            buffer.add(canister);
            _canisters := Buffer.toArray<Principal>(buffer);
            return true;
        };
        return false;
    };

    public shared (msg) func deleteCanister(canister : Principal) : async Bool {
        _checkPermission(msg.caller);
        _canisters := CollectionUtils.arrayRemove(_canisters, canister, Principal.equal);
        true;
    };

    public query func isCanisterTrusted(canister : Principal) : async Bool {
        if (CollectionUtils.arrayContains(_canisters, canister, Principal.equal)) {
            true;
        } else {
            false;
        };
    };

    public query func getCanisters() : async [Principal] {
        _canisters;
    };

    public shared func getCycleInfo() : async Result.Result<Types.CycleInfo, Types.Error> {
        return #ok({
            balance = Cycles.balance();
            available = Cycles.available();
        });
    };

    private func _checkPermission(caller : Principal) {
        assert (Prim.isController(caller) or (switch (governanceCid) { case (?cid) { Principal.equal(caller, cid) }; case (_) { false } }));
    };

    system func preupgrade() {};

    system func postupgrade() {};
};
