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
import Buffer "mo:base/Buffer";
import Timer "mo:base/Timer";
import Option "mo:base/Option";
import Prim "mo:⛔";
import Types "./Types";
import AccountUtils "./utils/AccountUtils";
import Functions "./utils/Functions";
import TokenAdapterTypes "mo:token-adapter/Types";
import TokenFactory "mo:token-adapter/TokenFactory";
import BlockTimestamp "./libraries/BlockTimestamp";

shared (initMsg) actor class SwapFeeReceiver(
    factoryCid : Principal,
    // ICP : Types.Token,
    // ICS : Types.Token,
) = this {

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

    public query func getCanisterId(): async Result.Result<?Principal, Types.Error> {
        return #ok(_canisterId);
    };

    public query func getTokens(): async Result.Result<[(Types.Token, Bool)], Types.Error> {
        return #ok(TrieSet.toArray(_tokenSet));
    };

    public query func getPools(): async Result.Result<[(Principal, Types.ClaimedPoolData)], Types.Error> {
        return #ok(Iter.toArray(_poolMap.entries()));
    };

    public query func getInitArgs() : async Result.Result<{
        factoryCid : Principal;
        // ICP : Types.Token;
        // ICS : Types.Token;
    }, Types.Error> {
        return #ok({
            factoryCid = factoryCid;
            // ICP = ICP;
            // ICS = ICS;
        });
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
    private stable var _tokenSet = TrieSet.empty<(Types.Token, Bool)>();
    private var _poolMap: HashMap.HashMap<Principal, Types.ClaimedPoolData> = HashMap.HashMap<Principal, Types.ClaimedPoolData>(100, Principal.equal, Principal.hash);
    // claim log
    var tokenClaimLog : Buffer.Buffer<Types.ReceiverClaimLog> = Buffer.Buffer<Types.ReceiverClaimLog>(0);
    // swap log

    private func _tokenSetEqual(t1 : (Types.Token, Bool), t2 : (Types.Token, Bool)) : Bool {
        return Text.equal(t1.0.address, t2.0.address) and Text.equal(t1.0.standard, t2.0.standard);
    };

    private func _syncPools() : async () {
        switch (await _factoryAct.getPools()) {
            case (#ok(pools)) {
                _poolMap := HashMap.HashMap<Principal, Types.ClaimedPoolData>(pools.size(), Principal.equal, Principal.hash);
                _tokenSet := TrieSet.empty<(Types.Token, Bool)>();
                for (it in pools.vals()) {
                    _poolMap.put(it.canisterId, {
                        token0 = it.token0;
                        token1 = it.token1;
                        fee = it.fee;
                        claimed = false;
                    });
                    _tokenSet := TrieSet.put<(Types.Token, Bool)>(_tokenSet, (it.token0, false), Functions.tokenHash(it.token0), _tokenSetEqual);
                    _tokenSet := TrieSet.put<(Types.Token, Bool)>(_tokenSet, (it.token1, false), Functions.tokenHash(it.token1), _tokenSetEqual);
                };
                ignore Timer.setTimer<system>(#nanoseconds (0), _autoClaim);
            };
            case (#err(_)) {
            };
        };
    };

    private func _autoClaim() : async () {
        var canisterId = switch (_canisterId) { case(?p){ p }; case(_) { return }; };
        label l {
            for ((cid, data) in _poolMap.entries()) {
                if (not data.claimed) {
                    _poolMap.put(cid, {
                        token0 = data.token0;
                        token1 = data.token1;
                        fee = data.fee;
                        claimed = true;
                    });
                    var poolAct = actor (Principal.toText(cid)) : Types.SwapPoolActor;
                    var balance = switch (await poolAct.getUserUnusedBalance(canisterId)) {
                        case(#ok(data)) { data }; case(#err(_)) { ignore Timer.setTimer<system>(#nanoseconds (0), _autoClaim); return };
                    };
                    var token0Act : TokenAdapterTypes.TokenAdapter = TokenFactory.getAdapter(data.token0.address, data.token0.standard);
                    var token1Act : TokenAdapterTypes.TokenAdapter = TokenFactory.getAdapter(data.token1.address, data.token1.standard);
                    if (balance.balance0 != 0) {
                        var fee : Nat = await token0Act.fee();
                        var amount0 : Nat = 0;
                        var errMsg0 : ?Types.Error = null;
                        switch (await poolAct.withdraw({token = data.token0.address; fee = fee; amount = balance.balance0;})) {
                            case (#ok(amount)) { amount0:=amount; }; case (#err(msg)) { errMsg0:=?msg; };
                        };
                        tokenClaimLog.add({ timestamp = BlockTimestamp.blockTimestamp(); amount = amount0; poolId = cid; token = data.token0; errMsg = errMsg0; });
                    };
                    if (balance.balance1 != 0) {
                        var fee : Nat = await token1Act.fee();
                        var amount1 : Nat = 0;
                        var errMsg1 : ?Types.Error = null;
                        switch (await poolAct.withdraw({token = data.token1.address; fee = fee; amount = balance.balance1;})) {
                            case (#ok(amount)) { amount1:=amount; }; case (#err(msg)) { errMsg1:=?msg; };
                        };
                        tokenClaimLog.add({ timestamp = BlockTimestamp.blockTimestamp(); amount = amount1; poolId = cid; token = data.token1; errMsg = errMsg1; });
                    };
                    ignore Timer.setTimer<system>(#nanoseconds (0), _autoClaim);
                    break l;
                };
            };
        };
    };

    // private func _autoSwap() : async () {
    //     var canisterId = switch (_canisterId) { case(?p){ p }; case(_) { return }; };
    //     label l {
    //         for ((token, swapped) in TrieSet.toArray(_tokenSet).vals()) {
    //             if(not swapped) {
    //                 var tokenAct : TokenAdapterTypes.TokenAdapter = TokenFactory.getAdapter(token.address, token.standard);
    //                 var balance : Nat = await tokenAct.balanceOf({ owner = canisterId; subaccount = null; });
    //                 var fee : Nat = await tokenAct.fee();
    //                 if (balance <= (fee * 3)) {
    //                     ignore Timer.setTimer<system>(#nanoseconds (0), _autoSwap);
    //                     break l;
    //                 }
    //                 // burn ICS
    //                 else if (Functions.tokenEqual(token, ICS)) {
    //                     // switch (await tokenAct.transfer({
    //                     //     from = { owner = Principal.fromActor(this); subaccount = null }; from_subaccount = null; 
    //                     //     to = { owner = recipient; subaccount = null }; amount = amount; fee = ?fee; memo = null; created_at_time = null;
    //                     // })) {
    //                     //     case (#Ok(_)) { return #ok(amount) };
    //                     //     case (#Err(msg)) { return #err(#InternalError(debug_show (msg))); };
    //                     // };
    //                     // ignore Timer.setTimer<system>(#nanoseconds (0), _autoClaim);
    //                 }
    //                 // swap ICP to ICS
    //                 else if (Functions.tokenEqual(token, ICP)) {
    //                     switch (await _factoryAct.getPool({ token0 = token; token1 = ICS; fee = 3000; })) {
    //                         case (#ok(poolData)) {
    //                             if (Text.equal("ICRC1", token.standard)) {
    //                                 await _ICRC1Swap(canisterId, poolData, token, balance, fee);
    //                             } else {
    //                                 await _commonSwap(poolData, token, balance, fee);
    //                             };
    //                         };
    //                         case (#err(_)) {};
    //                     };
    //                     ignore Timer.setTimer<system>(#nanoseconds (0), _autoClaim);
    //                 }
    //                 // swap token to ICP
    //                 else {
    //                     switch (await _factoryAct.getPool({ token0 = token; token1 = ICP; fee = 3000; })) {
    //                         case (#ok(poolData)) {
    //                             if (Text.equal("ICRC1", token.standard)) {
    //                                 await _ICRC1Swap(canisterId, poolData, token, balance, fee);
    //                             } else {
    //                                 await _commonSwap(poolData, token, balance, fee);
    //                             };
    //                         };
    //                         case (#err(_)) {};
    //                     };
    //                     ignore Timer.setTimer<system>(#nanoseconds (0), _autoClaim);
    //                 };
    //                 _tokenSet := TrieSet.put<(Types.Token, Bool)>(_tokenSet, (token, true), Functions.tokenHash(token), _tokenSetEqual);
    //             };
    //         };
    //     };
    // };

    // private func _ICRC1Swap(
    //     canisterId : Principal,
    //     poolData : Types.PoolData,
    //     token : Types.Token, 
    //     balance : Nat,
    //     fee : Nat
    // ) : async () {
    //     var tokenAct : TokenAdapterTypes.TokenAdapter = TokenFactory.getAdapter(token.address, token.standard);
    //     var poolAct = actor (Principal.toText(poolData.canisterId)) : Types.SwapPoolActor;
    //     switch (await tokenAct.transfer({
    //         from = { owner = Principal.fromActor(this); subaccount = null }; from_subaccount = null; 
    //         to = { owner = poolData.canisterId; subaccount = Option.make(AccountUtils.principalToBlob(canisterId)) }; 
    //         amount = balance - fee; fee = ?fee; memo = null; created_at_time = null;
    //     })) {
    //         case (#Ok(transferedAmount)) {
    //             switch (await poolAct.deposit({ token = token.address; amount = transferedAmount - fee; fee = fee; })) {
    //                 case (#ok(depositedAmount)) {
    //                     switch (await poolAct.swap({
    //                         zeroForOne = if (Functions.tokenEqual(ICP, poolData.token0)) { false } else { true };
    //                         amountIn = debug_show(depositedAmount - fee);
    //                         amountOutMinimum = "0";
    //                     })) {
    //                         case (#ok(swappedAmount)) {
    //                             switch (await poolAct.withdraw({ token = token.address; fee = fee; amount = swappedAmount; })) {
    //                                 case (#ok(withdrawedAmount)) {};
    //                                 case (#err(_)) {};
    //                             };
    //                         };
    //                         case (#err(_)) {};
    //                     };
    //                 };
    //                 case (#err(_)) {};
    //             };
    //         };
    //         case (#Err(msg)) {};
    //     };
    // };

    // private func _commonSwap(
    //     poolData : Types.PoolData,
    //     token : Types.Token, 
    //     balance : Nat,
    //     fee : Nat
    // ) : async () {
    //     var tokenAct : TokenAdapterTypes.TokenAdapter = TokenFactory.getAdapter(token.address, token.standard);
    //     var poolAct = actor (Principal.toText(poolData.canisterId)) : Types.SwapPoolActor;
    //     switch (await tokenAct.approve({
    //         from_subaccount = null; 
    //         spender = poolData.canisterId; 
    //         amount = balance - fee; 
    //         fee = ?fee; memo = null; created_at_time = null;
    //     })) {
    //         case (#Ok(approvedAmount)) {
    //             switch (await poolAct.depositFrom({ token = token.address; amount = approvedAmount - fee; fee = fee })) {
    //                 case (#ok(depositedAmount)) {
    //                     switch (await poolAct.swap({
    //                         zeroForOne = if (Functions.tokenEqual(ICP, poolData.token0)) { false } else { true };
    //                         amountIn = debug_show(depositedAmount - fee);
    //                         amountOutMinimum = "0";
    //                     })) {
    //                         case (#ok(swappedAmount)) {
    //                             switch (await poolAct.withdraw({ token = token.address; fee = fee; amount = swappedAmount; })) {
    //                                 case (#ok(withdrawedAmount)) {};
    //                                 case (#err(_)) {};
    //                             };
    //                         };
    //                         case (#err(_)) {};
    //                     };
    //                 };
    //                 case (#err(msg)) { };
    //             };
    //         };
    //         case (#Err(msg)) { };
    //     };
    // };

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
