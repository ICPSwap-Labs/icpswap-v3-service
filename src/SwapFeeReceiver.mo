import Text "mo:base/Text";
import Nat "mo:base/Nat";
import Nat64 "mo:base/Nat64";
import Principal "mo:base/Principal";
import Cycles "mo:base/ExperimentalCycles";
import Blob "mo:base/Blob";
import Error "mo:base/Error";
import Debug "mo:base/Debug";
import Result "mo:base/Result";
import HashMap "mo:base/HashMap";
import TrieSet "mo:base/TrieSet";
import Int "mo:base/Int";
import Iter "mo:base/Iter";
import Bool "mo:base/Bool";
import Buffer "mo:base/Buffer";
import Time "mo:base/Time";
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
    ICP : Types.Token,
    ICS : Types.Token,
    governanceCid : Principal,
) = this {

    // --------------------------- Auto Claim ------------------------------------
    private stable var _canisterId : ?Principal = null;
    private stable var _ICPFee : Nat = 0;
    private stable var _ICSFee : Nat = 0;
    private stable var _factoryAct = actor (Principal.toText(factoryCid)) : Types.SwapFactoryActor;
    private stable var _tokenSet = TrieSet.empty<(Types.Token, Bool)>();
    private var _poolMap: HashMap.HashMap<Principal, Types.ClaimedPoolData> = HashMap.HashMap<Principal, Types.ClaimedPoolData>(100, Principal.equal, Principal.hash);
    // sync flag
    private stable var _isSyncing : Bool = false;
    // claim log
    private var _tokenClaimLog : Buffer.Buffer<Types.ReceiverClaimLog> = Buffer.Buffer<Types.ReceiverClaimLog>(0);
    private stable var _tokenClaimLogArray : [Types.ReceiverClaimLog] = [];
    // swap log
    private var _tokenSwapLog : Buffer.Buffer<Types.ReceiverSwapLog> = Buffer.Buffer<Types.ReceiverSwapLog>(0);
    private stable var _tokenSwapLogArray : [Types.ReceiverSwapLog] = [];
    // burn log
    private var _tokenBurnLog : Buffer.Buffer<Types.ReceiverBurnLog> = Buffer.Buffer<Types.ReceiverBurnLog>(0);
    private stable var _tokenBurnLogArray : [Types.ReceiverBurnLog] = [];

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
            switch (await tokenAct.transfer({
                from = { owner = Principal.fromActor(this); subaccount = null }; 
                from_subaccount = null; to = { owner = recipient; subaccount = null }; 
                amount = amount; fee = ?fee; 
                memo = Option.make(Text.encodeUtf8("transfer")); 
                created_at_time = ?Nat64.fromNat(Int.abs(Time.now())); 
            })) {
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
            switch (await tokenAct.transfer({
                from = { owner = Principal.fromActor(this); subaccount = null };
                from_subaccount = null; to = { owner = recipient; subaccount = null }; 
                amount = amount; fee = ?fee; 
                memo = Option.make(Text.encodeUtf8("transferAll")); 
                created_at_time = ?Nat64.fromNat(Int.abs(Time.now())); 
            })) {
                case (#Ok(_)) { return #ok(amount) };
                case (#Err(msg)) { return #err(#InternalError(debug_show (msg))); };
            };
            return #ok(amount);
        } else {
            return #ok(0);
        };
    };

    public shared ({ caller }) func setFees() : async () {
        _checkPermission(caller);
        var ICPAct : TokenAdapterTypes.TokenAdapter = TokenFactory.getAdapter(ICP.address, ICP.standard);
        var ICSAct : TokenAdapterTypes.TokenAdapter = TokenFactory.getAdapter(ICS.address, ICS.standard);
        _ICPFee := await ICPAct.fee();
        _ICSFee := await ICSAct.fee();
    };

    // public shared ({ caller }) func syncPools() : async () {
    //     _checkPermission(caller);
    //     if (_isSyncing) { return; };
    //     ignore _syncPools();
    // };

    public shared ({ caller }) func startAutoSyncPools() : async () {
        _checkPermission(caller);
        ignore _autoSyncPools();
    };

    public shared ({ caller }) func claimPool(poolId: Principal, canisterId: Principal) : async Result.Result<Bool, Types.Error> {
        _checkPermission(caller);
        switch (_poolMap.get(poolId)) {
            case(?data){ return #ok(await _claim(poolId, canisterId, data)); }; case(_) { return #err(#InternalError("No such pool data")); };
        };
    };

    public shared ({ caller }) func swapToICP(token : Types.Token) : async Result.Result<Bool, Types.Error> {
        _checkPermission(caller);
        return #ok(await _swapToICP(token));
    };

    public shared ({ caller }) func swapICPToICS() : async Result.Result<(), Types.Error> {
        _checkPermission(caller);
        ignore _swapICPToICS();
        return #ok();
    };

    public shared ({ caller }) func burnICS() : async Result.Result<(), Types.Error> {
        _checkPermission(caller);
        return #ok(await _burnICS());
    };

    public shared ({ caller }) func getTokenBalance(token : Types.Token) : async Result.Result<Nat, Types.Error> {
        _checkPermission(caller);
        var canisterId = switch (_canisterId) { case(?p){ p }; case(_) { return #err(#InternalError("Uninitialized _canisterId.")); }; };
        var tokenAct : TokenAdapterTypes.TokenAdapter = TokenFactory.getAdapter(token.address, token.standard);
        return #ok(await tokenAct.balanceOf({ owner = canisterId; subaccount = null; }));
    };

    public query func getCanisterId(): async Result.Result<?Principal, Types.Error> {
        return #ok(_canisterId);
    };

    public query func getFees(): async Result.Result<{ICPFee:Nat;ICSFee:Nat;}, Types.Error> {
        return #ok({ICPFee=_ICPFee;ICSFee=_ICSFee;});
    };

    public query func getTokens(): async Result.Result<[(Types.Token, Bool)], Types.Error> {
        return #ok(TrieSet.toArray(_tokenSet));
    };

    public query func getPools(): async Result.Result<[(Principal, Types.ClaimedPoolData)], Types.Error> {
        return #ok(Iter.toArray(_poolMap.entries()));
    };

    public query func getTokenClaimLog(): async Result.Result<[Types.ReceiverClaimLog], Types.Error> {
        return #ok(Buffer.toArray(_tokenClaimLog));
    };

    public query func getTokenSwapLog(): async Result.Result<[Types.ReceiverSwapLog], Types.Error> {
        return #ok(Buffer.toArray(_tokenSwapLog));
    };

    public query func getTokenBurnLog(): async Result.Result<[Types.ReceiverBurnLog], Types.Error> {
        return #ok(Buffer.toArray(_tokenBurnLog));
    };

    public query func getInitArgs() : async Result.Result<{
        factoryCid : Principal;
        ICP : Types.Token;
        ICS : Types.Token;
        governanceCid : Principal;
    }, Types.Error> {
        return #ok({
            factoryCid = factoryCid;
            ICP = ICP;
            ICS = ICS;
            governanceCid : Principal;
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

    private func _tokenSetEqual(t1 : (Types.Token, Bool), t2 : (Types.Token, Bool)) : Bool {
        return Text.equal(t1.0.address, t2.0.address) and Text.equal(t1.0.standard, t2.0.standard);
    };

    private func _addTokenSwapLog(token : Types.Token, amountIn : Nat, amountOut : Nat, errMsg : Text, step : Text, poolId : ?Principal) : () {
        _tokenSwapLog.add({ timestamp = BlockTimestamp.blockTimestamp(); token = token; amountIn = amountIn; amountOut = amountOut; errMsg = errMsg; step = step; poolId = poolId; }); 
    };

    private func _burnICS() : async () {
        var canisterId = switch (_canisterId) { case(?p){ p }; case(_) { return }; };
        var tokenAct : TokenAdapterTypes.TokenAdapter = TokenFactory.getAdapter(ICS.address, ICS.standard);
        var balance : Nat = await tokenAct.balanceOf({ owner = canisterId; subaccount = null; });
        switch (await tokenAct.transfer({
            from = { owner = canisterId; subaccount = null }; from_subaccount = null; 
            to = { owner = governanceCid; subaccount = null }; amount = balance; fee = null; 
            memo = Option.make(Text.encodeUtf8("_burnICS")); 
            created_at_time = ?Nat64.fromNat(Int.abs(Time.now()));
        })) {
            case (#Ok(amount)) { _tokenBurnLog.add({ timestamp = BlockTimestamp.blockTimestamp(); amount = amount; errMsg = ""; }); };
            case (#Err(msg)) { _tokenBurnLog.add({ timestamp = BlockTimestamp.blockTimestamp(); amount = 0; errMsg = debug_show(msg); }); };
        };       
    };

    private func _ICRC1SwapToICP(
        canisterId : Principal,
        poolData : Types.PoolData,
        token : Types.Token, 
        balance : Nat,
        fee : Nat
    ) : async () {
        var tokenAct : TokenAdapterTypes.TokenAdapter = TokenFactory.getAdapter(token.address, token.standard);
        var poolId = poolData.canisterId;
        var poolAct = actor (Principal.toText(poolId)) : Types.SwapPoolActor;
        var transferedAmount = balance - fee;
        switch (await tokenAct.transfer({
            from = { owner = canisterId; subaccount = null }; from_subaccount = null; 
            to = { owner = poolData.canisterId; subaccount = Option.make(AccountUtils.principalToBlob(canisterId)) }; 
            amount = transferedAmount; fee = ?fee; 
            memo = Option.make(Text.encodeUtf8("_ICRC1SwapToICP")); 
            created_at_time = ?Nat64.fromNat(Int.abs(Time.now()));
        })) {
            case (#Ok(_)) {
                _addTokenSwapLog(token, transferedAmount, 0, "", "transfer", ?poolId);
                switch (await poolAct.deposit({ token = token.address; amount = transferedAmount - fee; fee = fee; })) {
                    case (#ok(depositedAmount)) {
                        _addTokenSwapLog(token, depositedAmount, 0, "", "deposit", ?poolId);
                        switch (await poolAct.swap({
                            zeroForOne = if (Functions.tokenEqual(ICP, poolData.token0)) { false } else { true };
                            amountIn = debug_show(depositedAmount);
                            amountOutMinimum = "0";
                        })) {
                            case (#ok(swappedAmount)) {
                                _addTokenSwapLog(token, depositedAmount, swappedAmount, "", "swap", ?poolId);
                                switch (await poolAct.withdraw({ token = ICP.address; fee = _ICPFee; amount = swappedAmount; })) {
                                    case (#ok(withdrawedAmount)) {
                                        _addTokenSwapLog(ICP, 0, withdrawedAmount, "", "withdraw", ?poolId);
                                    };
                                    case (#err(msg)) {
                                        _addTokenSwapLog(ICP, 0, 0, debug_show(msg), "withdraw", ?poolId);
                                    };
                                };
                            };
                            case (#err(msg)) {_addTokenSwapLog(token, depositedAmount, 0, debug_show(msg), "swap", ?poolId);};
                        };
                    };
                    case (#err(msg)) { _addTokenSwapLog(token, transferedAmount, 0, debug_show(msg), "deposit", ?poolId); };
                };
            };
            case (#Err(msg)) { _addTokenSwapLog(token, 0, 0, debug_show(msg), "transfer", ?poolId); };
        };
    };

    private func _commonSwap(
        poolData : Types.PoolData,
        tokenIn : Types.Token, 
        balance : Nat,
        tokenInFee : Nat,
        tokenOut : Types.Token, 
        tokenOutFee : Nat,
    ) : async () {
        var tokenInAct : TokenAdapterTypes.TokenAdapter = TokenFactory.getAdapter(tokenIn.address, tokenIn.standard);
        var poolId = poolData.canisterId;
        var poolAct = actor (Principal.toText(poolId)) : Types.SwapPoolActor;
        var approvedAmount = balance - tokenInFee;
        // todo log this
        switch (await tokenInAct.approve({
            from_subaccount = null; 
            spender = poolData.canisterId; 
            amount = approvedAmount; 
            fee = ?tokenInFee; memo = null; created_at_time = null;
        })) {
            case (#Ok(_)) {
                _addTokenSwapLog(tokenIn, approvedAmount, 0, "", "approve", ?poolId);
                var depositAmount = approvedAmount - tokenInFee * 3;
                switch (await poolAct.depositFrom({ token = tokenIn.address; amount = depositAmount; fee = tokenInFee })) {
                    case (#ok(depositedAmount)) {
                        _addTokenSwapLog(tokenIn, depositedAmount, 0, "", "depositFrom", ?poolId);
                        switch (await poolAct.swap({
                            zeroForOne = if (Functions.tokenEqual(tokenOut, poolData.token0)) { false } else { true };
                            amountIn = debug_show(depositedAmount);
                            amountOutMinimum = "0";
                        })) {
                            case (#ok(swappedAmount)) {
                                _addTokenSwapLog(tokenIn, depositedAmount, swappedAmount, "", "swap", ?poolId);
                                switch (await poolAct.withdraw({ token = tokenOut.address; fee = tokenOutFee; amount = swappedAmount; })) {
                                    case (#ok(withdrawedAmount)) { _addTokenSwapLog(tokenOut, 0, withdrawedAmount, "", "withdraw", ?poolId); };
                                    case (#err(msg)) { _addTokenSwapLog(tokenOut, 0, 0, debug_show(msg), "withdraw", ?poolId); };
                                };
                            };
                            case (#err(msg)) {_addTokenSwapLog(tokenIn, depositedAmount, 0, debug_show(msg), "swap", ?poolId);};
                        };
                    };
                    case (#err(msg)) {_addTokenSwapLog(tokenIn, approvedAmount, 0, debug_show(msg), "depositFrom", ?poolId);};
                };
            };
            case (#Err(msg)) {_addTokenSwapLog(tokenIn, 0, 0, debug_show(msg), "approve", ?poolId);};
        };
    };

    private func _swapICPToICS() : async Bool {
        var canisterId = switch (_canisterId) { case(?p){ p }; case(_) { return false; }; };
        var tokenAct : TokenAdapterTypes.TokenAdapter = TokenFactory.getAdapter(ICP.address, ICP.standard);
        var balance : Nat = await tokenAct.balanceOf({ owner = canisterId; subaccount = null; });
        if (balance <= (_ICPFee * 10)) { return false; };
        switch (await _factoryAct.getPool({ token0 = ICP; token1 = ICS; fee = 3000; })) {
            case (#ok(poolData)) { await _commonSwap(poolData, ICP, balance, _ICPFee, ICS, _ICSFee); return true; };
            case (#err(msg)) { _addTokenSwapLog(ICP, 0, 0, debug_show(msg), "getPool", null); return false; };
        };
    };

    private func _swapToICP(tokenIn : Types.Token) : async Bool {
        var canisterId = switch (_canisterId) { case(?p){ p }; case(_) { return false; }; };
        var tokenAct : TokenAdapterTypes.TokenAdapter = TokenFactory.getAdapter(tokenIn.address, tokenIn.standard);
        var balance : Nat = await tokenAct.balanceOf({ owner = canisterId; subaccount = null; });
        var fee : Nat = await tokenAct.fee();
        if (balance <= (fee * 10)) { return false; };
        switch (await _factoryAct.getPool({ token0 = tokenIn; token1 = ICP; fee = 3000; })) {
            case (#ok(poolData)) {
                if (Text.equal("ICRC1", tokenIn.standard)) {
                    await _ICRC1SwapToICP(canisterId, poolData, tokenIn, balance, fee);
                } else {
                    await _commonSwap(poolData, tokenIn, balance, fee, ICP, _ICPFee);
                };
                true;
            };
            case (#err(msg)) {
                _addTokenSwapLog(tokenIn, 0, 0, debug_show(msg), "getPool", null);
                false;
            };
        };
    };

    private func _claim(poolId: Principal, canisterId: Principal, data: Types.ClaimedPoolData) : async Bool {
        try {
            var poolAct = actor (Principal.toText(poolId)) : Types.SwapPoolActor;
            var balance = { balance0 = 0; balance1 = 0 };
            switch (await poolAct.getUserUnusedBalance(canisterId)) {
                case(#ok(data)) {
                    if (data.balance0 == 0 and data.balance1 == 0) {
                        _tokenClaimLog.add({
                            timestamp = BlockTimestamp.blockTimestamp();
                            amount = 0;
                            poolId = poolId;
                            token = { address = ""; standard = ""; };
                            errMsg = "All balances are 0";
                        });
                        return false;
                    };
                    balance := data;
                }; 
                case(#err(_)) {
                    _tokenClaimLog.add({
                        timestamp = BlockTimestamp.blockTimestamp();
                        amount = 0;
                        poolId = poolId;
                        token = { address = ""; standard = ""; };
                        errMsg = "Get user unused balance failed";
                    });
                    return false;
                };
            };
            var token0Act : TokenAdapterTypes.TokenAdapter = TokenFactory.getAdapter(data.token0.address, data.token0.standard);
            var token1Act : TokenAdapterTypes.TokenAdapter = TokenFactory.getAdapter(data.token1.address, data.token1.standard);
            if (balance.balance0 != 0) {
                var fee : Nat = await token0Act.fee();
                var amount0 : Nat = 0;
                var errMsg0 : Text = "";
                switch (await poolAct.withdraw({token = data.token0.address; fee = fee; amount = balance.balance0;})) {
                    case (#ok(amount)) { amount0 := amount; }; case (#err(msg)) { errMsg0 := debug_show(msg); };
                };
                _tokenClaimLog.add({ timestamp = BlockTimestamp.blockTimestamp(); amount = amount0; poolId = poolId; token = data.token0; errMsg = errMsg0; });
            };
            if (balance.balance1 != 0) {
                var fee : Nat = await token1Act.fee();
                var amount1 : Nat = 0;
                var errMsg1 : Text = "";
                switch (await poolAct.withdraw({token = data.token1.address; fee = fee; amount = balance.balance1;})) {
                    case (#ok(amount)) { amount1 := amount; }; case (#err(msg)) { errMsg1 := debug_show(msg); };
                };
                _tokenClaimLog.add({ timestamp = BlockTimestamp.blockTimestamp(); amount = amount1; poolId = poolId; token = data.token1; errMsg = errMsg1; });
            };
            true;
        } catch (e) {
            let msg: Text = debug_show (Error.message(e));
            _tokenClaimLog.add({ timestamp = BlockTimestamp.blockTimestamp(); amount = 0; poolId = poolId; token = { address = ""; standard = ""; }; errMsg = msg; });
            false;
        };
    };

    private func _syncPools() : async Bool {
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
                true;
            };
            case (#err(_)) { false; };
        };
    };

    private func _autoSwap() : async () {
        label l {
            // swap token to ICP
            for ((token, swapped) in TrieSet.toArray(_tokenSet).vals()) {
                if((not swapped) and (not Text.equal(token.address, ICP.address)) and (not Text.equal(token.address, ICS.address))) {
                    _tokenSet := TrieSet.put<(Types.Token, Bool)>(_tokenSet, (token, true), Functions.tokenHash(token), _tokenSetEqual);
                    try {
                        let _ = await _swapToICP(token);
                    } catch (e) {
                        _addTokenSwapLog(token, 0, 0, "Call _swapToICP failed: " # debug_show (Error.message(e)), "_swapToICP", null);
                    };
                    ignore Timer.setTimer<system>(#nanoseconds (3), _autoSwap);
                    break l;
                };
            };
            // swapping all finished means synchronization ends
            _isSyncing := false;
        };
    };

    private func _autoClaim() : async () {
        var canisterId = switch (_canisterId) { case(?p){ p }; case(_) { return }; };
        label l {
            for ((cid, data) in _poolMap.entries()) {
                if (not data.claimed) {
                    _poolMap.put(cid, { token0 = data.token0; token1 = data.token1; fee = data.fee; claimed = true; });
                    try {
                        let _ = await _claim(cid, canisterId, data);
                    } catch (e) {
                        _tokenClaimLog.add({
                            timestamp = BlockTimestamp.blockTimestamp();
                            amount = 0;
                            poolId = cid;
                            token = { address = ""; standard = ""; };
                            errMsg = "Call _claim failed: " # debug_show (Error.message(e));
                        });
                    };
                    ignore Timer.setTimer<system>(#nanoseconds (3), _autoClaim);
                    break l;
                };
            };
            // ignore Timer.setTimer<system>(#nanoseconds (3), _autoSwap);
        };
    };

    private func _autoSyncPools() : async () {
        if (_isSyncing) { return; };
        if (await _syncPools()) {
            // double check for releasing thread
            if(_isSyncing) { return; };
            _isSyncing := true;
            ignore Timer.setTimer<system>(#nanoseconds (0), _autoClaim); 
        };
    };

    // ignore Timer.recurringTimer<system>(#seconds(604800), _autoSyncPools);

    // --------------------------- Version Control ------------------------------------
    private var _version : Text = "3.5.0";
    public query func getVersion() : async Text { _version };

    system func preupgrade() {
        _tokenClaimLogArray := Buffer.toArray(_tokenClaimLog);
        _tokenSwapLogArray := Buffer.toArray(_tokenSwapLog);
        _tokenBurnLogArray := Buffer.toArray(_tokenBurnLog);
    };

    system func postupgrade() {
        _canisterId := ?Principal.fromActor(this);
        _tokenClaimLog := Buffer.fromArray(_tokenClaimLogArray);
        _tokenSwapLog := Buffer.fromArray(_tokenSwapLogArray);
        _tokenBurnLog := Buffer.fromArray(_tokenBurnLogArray);
        _tokenClaimLogArray := [];
        _tokenSwapLogArray := [];
        _tokenBurnLogArray := [];
    };

    system func inspect({
        arg : Blob;
        caller : Principal;
        msg : Types.SwapFeeReceiverMsg;
    }) : Bool {
        return switch (msg) {
            // Controller
            case (#burnICS _)       { Prim.isController(caller) };
            case (#claim _)         { Prim.isController(caller) };
            case (#claimPool _)     { Prim.isController(caller) };
            case (#setFees _)       { Prim.isController(caller) };
            case (#swapICPToICS _)  { Prim.isController(caller) };
            case (#swapToICP _)     { Prim.isController(caller) };
            case (#syncPools _)     { Prim.isController(caller) };
            case (#transfer _)      { Prim.isController(caller) };
            case (#transferAll _)   { Prim.isController(caller) };
            // Anyone
            case (_) { true };
        };
    };
};
