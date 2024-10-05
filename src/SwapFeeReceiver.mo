import Text "mo:base/Text";
import Nat "mo:base/Nat";
import Principal "mo:base/Principal";
import Cycles "mo:base/ExperimentalCycles";
import Blob "mo:base/Blob";
import Result "mo:base/Result";
import HashMap "mo:base/HashMap";
import TrieSet "mo:base/TrieSet";
import Iter "mo:base/Iter";
import Bool "mo:base/Bool";
import Timer "mo:base/Timer";
import Prim "mo:⛔";
import Types "./Types";
import Functions "./utils/Functions";
import TokenAdapterTypes "mo:token-adapter/Types";
import TokenFactory "mo:token-adapter/TokenFactory";

shared (initMsg) actor class SwapFeeReceiver(factoryCid : Principal) = this {

    private func _checkStandard(standard : Text) : Bool {
        if (
            Text.notEqual(standard, "DIP20") 
            and Text.notEqual(standard, "DIP20-WICP") 
            and Text.notEqual(standard, "DIP20-XTC") 
            and Text.notEqual(standard, "EXT") 
            and Text.notEqual(standard, "ICRC1") 
            and Text.notEqual(standard, "ICRC2") 
            and Text.notEqual(standard, "ICRC3") 
            and Text.notEqual(standard, "ICP")
        ) {
            return false;
        };
        return true;
    };

    public shared ({ caller }) func claim(pool : Principal, token : Types.Token, amount : Nat) : async Result.Result<Nat, Types.Error> {
        _checkPermission(caller);
        var tokenAct : TokenAdapterTypes.TokenAdapter = TokenFactory.getAdapter(token.address, token.standard);
        var poolAct = actor (Principal.toText(pool)) : Types.SwapPoolActor;
        var fee : Nat = await tokenAct.fee();
        switch (await poolAct.withdraw({token = token.address; fee = fee; amount = amount;})) {
            case (#ok(amount)) { return #ok(amount) };
            case (#err(msg)) { return #err(#InternalError(debug_show (msg))); };
        };
    };

    public shared ({ caller }) func transfer(token : Types.Token, recipient : Principal, value : Nat) : async Result.Result<Nat, Types.Error> {
        _checkPermission(caller);
        if (not _checkStandard(token.standard)) { return #err(#UnsupportedToken("Wrong token standard.")); };
        var tokenAct : TokenAdapterTypes.TokenAdapter = TokenFactory.getAdapter(token.address, token.standard);
        var fee : Nat = await tokenAct.fee();
        if (value > fee) {
            var amount : Nat = Nat.sub(value, fee);
            switch (await tokenAct.transfer({ from = { owner = Principal.fromActor(this); subaccount = null }; from_subaccount = null; to = { owner = recipient; subaccount = null }; amount = amount; fee = ?fee; memo = null; created_at_time = null })) {
                case (#Ok(_)) { return #ok(amount) };
                case (#Err(msg)) { return #err(#InternalError(debug_show (msg))); };
            };
            return #ok(amount);
        } else {
            return #ok(0);
        };
    };

    public shared ({ caller }) func transferAll(token : Types.Token, recipient : Principal) : async Result.Result<Nat, Types.Error> {
        _checkPermission(caller);
        if (not _checkStandard(token.standard)) { return #err(#UnsupportedToken("Wrong token standard.")); };
        var tokenAct : TokenAdapterTypes.TokenAdapter = TokenFactory.getAdapter(token.address, token.standard);
        var value : Nat = await tokenAct.balanceOf({ owner = Principal.fromActor(this); subaccount = null; });
        var fee : Nat = await tokenAct.fee();
        if (value > fee) {
            var amount : Nat = Nat.sub(value, fee);
            switch (await tokenAct.transfer({ from = { owner = Principal.fromActor(this); subaccount = null }; from_subaccount = null; to = { owner = recipient; subaccount = null }; amount = amount; fee = ?fee; memo = null; created_at_time = null })) {
                case (#Ok(_)) { return #ok(amount) };
                case (#Err(msg)) { return #err(#InternalError(debug_show (msg))); };
            };
            return #ok(amount);
        } else {
            return #ok(0);
        };
    };

    public shared func getCycleInfo() : async Result.Result<Types.CycleInfo, Types.Error> {
        return #ok({
            balance = Cycles.balance();
            available = Cycles.available();
        });
    };

    private func _checkPermission(caller: Principal) {
        assert(Prim.isController(caller));
    };

    // --------------------------- Auto Claim ------------------------------------
    private stable var _canisterId : ?Principal = null;
    private stable var _factoryAct = actor (Principal.toText(factoryCid)) : Types.SwapFactoryActor;
    private stable var _tokenSet = TrieSet.empty<Types.Token>();
    private var _poolMap: HashMap.HashMap<Principal, Types.ClaimedPoolData> = HashMap.HashMap<Principal, Types.ClaimedPoolData>(100, Principal.equal, Principal.hash);
    private func _syncPools() : async () {
        switch (await _factoryAct.getPools()) {
            case (#ok(pools)) {
                _poolMap := HashMap.HashMap<Principal, Types.ClaimedPoolData>(pools.size(), Principal.equal, Principal.hash);
                _tokenSet := TrieSet.empty<Types.Token>();
                for (it in pools.vals()) {
                    _poolMap.put(it.canisterId, {
                        token0 = it.token0;
                        token1 = it.token1;
                        fee = it.fee;
                        claimed = false;
                    });
                    _tokenSet := TrieSet.put<Types.Token>(_tokenSet, it.token0, Functions.tokenHash(it.token0), Functions.tokenEqual);
                    _tokenSet := TrieSet.put<Types.Token>(_tokenSet, it.token1, Functions.tokenHash(it.token1), Functions.tokenEqual);
                };
                // ignore Timer.setTimer<system>(#nanoseconds (0), _autoClaim);
            };
            case (#err(_)) {
            };
        };
    };
    // private func _autoClaim() : async () {
    //     var canisterId = switch (_canisterId) { case(?p){ p }; case(_) { return }; };
    //     label l {
    //         for ((id, data) in _poolMap.entries()) {
    //             if (not data.claimed) {
    //                 _poolMap.put(id, {
    //                     token0 = data.token0;
    //                     token1 = data.token1;
    //                     fee = data.fee;
    //                     claimed = true;
    //                 });
    //                 var poolAct = actor (Principal.toText(id)) : Types.SwapPoolActor;
    //                 var balance = switch (await poolAct.getUserUnusedBalance(canisterId)) {
    //                     case(#ok(data)) { data }; 
    //                     case(#err(_)) { ignore Timer.setTimer<system>(#nanoseconds (0), _autoClaim); return };
    //                 };
    //                 if (balance.balance0 != 0) {
    //                     var tokenAct : TokenAdapterTypes.TokenAdapter = TokenFactory.getAdapter(data.token0.address, data.token0.standard);
    //                     var fee : Nat = await tokenAct.fee();
    //                     // TODO: add log
    //                     switch (await poolAct.withdraw({token = data.token0.address; fee = fee; amount = balance.balance0;})) {
    //                         case (#ok(amount)) {  };
    //                         case (#err(msg)) {  };
    //                     };
    //                 };
    //                 if (balance.balance1 != 0) {
    //                     var tokenAct : TokenAdapterTypes.TokenAdapter = TokenFactory.getAdapter(data.token1.address, data.token1.standard);
    //                     var fee : Nat = await tokenAct.fee();
    //                     // TODO: add log
    //                     switch (await poolAct.withdraw({token = data.token0.address; fee = fee; amount = balance.balance0;})) {
    //                         case (#ok(amount)) {  };
    //                         case (#err(msg)) {  };
    //                     };
    //                 };
    //                 ignore Timer.setTimer<system>(#nanoseconds (0), _autoClaim);
    //                 break l;
    //             };
    //         };
    //     };
    // };
    public query func getCanisterId(): async Result.Result<?Principal, Types.Error> {
        return #ok(_canisterId);
    };
    public query func getTokens(): async Result.Result<[Types.Token], Types.Error> {
        return #ok(TrieSet.toArray(_tokenSet));
    };
    public query func getPools(): async Result.Result<[(Principal, Types.ClaimedPoolData)], Types.Error> {
        return #ok(Iter.toArray(_poolMap.entries()));
    };

    // --------------------------- Version Control ------------------------------------
    private var _version : Text = "3.5.0";
    public query func getVersion() : async Text { _version };

    system func preupgrade() {};

    system func postupgrade() {
        _canisterId := ?Principal.fromActor(this);
    };

    system func inspect({
        arg : Blob;
        caller : Principal;
        msg : Types.SwapFeeReceiverMsg;
    }) : Bool {
        return switch (msg) {
            // Controller
            case (#claim _) { Prim.isController(caller) };
            case (#transfer _) { Prim.isController(caller) };
            case (#transferAll _) { Prim.isController(caller) };
            // Anyone
            case (_) { true };
        };
    };
};
