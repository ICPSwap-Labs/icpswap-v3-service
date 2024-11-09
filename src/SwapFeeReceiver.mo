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
    private stable var _tokenSet = TrieSet.empty<(Types.Token, Bool)>();
    private var _poolMap: HashMap.HashMap<Principal, Types.ClaimedPoolData> = HashMap.HashMap<Principal, Types.ClaimedPoolData>(100, Principal.equal, Principal.hash);
    // sync flag
    private stable var _isSyncing : Bool = false;
    // last sync time
    private stable var _lastSyncTime : Nat = 0;
    // claim log
    private var _tokenClaimLog : Buffer.Buffer<Types.ReceiverClaimLog> = Buffer.Buffer<Types.ReceiverClaimLog>(0);
    private stable var _tokenClaimLogArray : [Types.ReceiverClaimLog] = [];
    // swap log
    private var _tokenSwapLog : Buffer.Buffer<Types.ReceiverSwapLog> = Buffer.Buffer<Types.ReceiverSwapLog>(0);
    private stable var _tokenSwapLogArray : [Types.ReceiverSwapLog] = [];
    // burn log
    private var _tokenBurnLog : Buffer.Buffer<Types.ReceiverBurnLog> = Buffer.Buffer<Types.ReceiverBurnLog>(0);
    private stable var _tokenBurnLogArray : [Types.ReceiverBurnLog] = [];

    private stable var _locked : Bool = false;
    private func _acquireLock() : Bool {
        if (_locked) { return false; };
        _locked := true;
        true;
    };
    private func _releaseLock() { _locked := false; };

    // Track active timers
    private var _activeTimers : Buffer.Buffer<Timer.TimerId> = Buffer.Buffer(0);
    private func _scheduleRetry(delay: Nat, operation: () -> async ()) : async () {
        let timerId = Timer.setTimer<system>(#seconds(delay), func() : async () {
            try {
                await operation();
            } catch (e) {
            // Log error but don't reschedule to avoid infinite retry loops
                Debug.print("Retry operation failed: " # Error.message(e));
            };
        });
        _activeTimers.add(timerId);
    };
    // Clean up function remains the same
    private func _cleanupTimers() {
        for (timerId in _activeTimers.vals()) { Timer.cancelTimer(timerId); };
        _activeTimers.clear();
    };

    private var _factoryAct = actor (Principal.toText(factoryCid)) : Types.SwapFactoryActor;

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

    public shared ({ caller }) func setCanisterId() : async () {
        _checkPermission(caller);
        _canisterId := ?Principal.fromActor(this);
    };

    public shared ({ caller }) func startAutoSyncPools() : async () {
        _checkPermission(caller);
        ignore _autoSyncPools();
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

    public shared func getBaseBalances() : async Result.Result<{ ICP:Nat; ICS:Nat; }, Types.Error> {
        var canisterId = switch (_canisterId) { case(?p){ p }; case(_) { return #err(#InternalError("Uninitialized _canisterId.")); }; };
        var ICPAct : TokenAdapterTypes.TokenAdapter = TokenFactory.getAdapter(ICP.address, ICP.standard);
        var ICSAct : TokenAdapterTypes.TokenAdapter = TokenFactory.getAdapter(ICS.address, ICS.standard);
        return #ok({
            ICP = await ICPAct.balanceOf({ owner = canisterId; subaccount = null; });
            ICS = await ICSAct.balanceOf({ owner = canisterId; subaccount = null; });
        });
    };

    public query func getCanisterId(): async Result.Result<?Principal, Types.Error> {
        return #ok(_canisterId);
    };

    public query func getSyncingStatus(): async Result.Result<{ isSyncing:Bool; lastSyncTime : Nat; swapProgress:Text; }, Types.Error> {
        var count = 0;
        var total = 0;
        for ((token, swapped) in TrieSet.toArray(_tokenSet).vals()) {
            if (swapped) { count := count + 1; };
            total := total + 1;
        };
        return #ok({ isSyncing = _isSyncing; lastSyncTime = _lastSyncTime; swapProgress = debug_show(count) # "/" # debug_show(total); });
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
        try {
            var canisterId = switch (_canisterId) { case(?p){ p }; case(_) { return }; };
            var tokenAct : TokenAdapterTypes.TokenAdapter = TokenFactory.getAdapter(ICS.address, ICS.standard);
            var balance : Nat = await tokenAct.balanceOf({ owner = canisterId; subaccount = null; });
            switch (await tokenAct.transfer({
                from = { owner = canisterId; subaccount = null }; 
                from_subaccount = null; 
                to = { owner = governanceCid; subaccount = null }; 
                amount = balance; 
                fee = null; 
                memo = Option.make(Text.encodeUtf8("_burnICS")); 
                created_at_time = ?Nat64.fromNat(Int.abs(Time.now()));
            })) {
                case (#Ok(amount)) { _tokenBurnLog.add({ timestamp = BlockTimestamp.blockTimestamp(); amount = amount; errMsg = ""; }); };
                case (#Err(msg)) { _tokenBurnLog.add({ timestamp = BlockTimestamp.blockTimestamp(); amount = 0; errMsg = debug_show(msg); }); };
            };       
        } catch (e) {
            _tokenBurnLog.add({ 
                timestamp = BlockTimestamp.blockTimestamp(); 
                amount = 0; 
                errMsg = "_burnICS failed: " # debug_show (Error.message(e));
            });
            // Retry after 1 hour
            ignore Timer.setTimer<system>(#seconds(3600), _burnICS);
        };
    };

    private func _ICRC1SwapToICP(
        canisterId : Principal,
        poolData : Types.PoolData,
        token : Types.Token, 
        balance : Nat,
        fee : Nat
    ) : async () {
        // Check and acquire lock
        assert(_acquireLock());
        try {
            var tokenAct : TokenAdapterTypes.TokenAdapter = TokenFactory.getAdapter(token.address, token.standard);
            var poolId = poolData.canisterId;
            var poolAct = actor (Principal.toText(poolId)) : Types.SwapPoolActor;
            // Calculate amounts before external calls
            var transferedAmount = balance - fee;
            // First external call - transfer
            switch (await tokenAct.transfer({
                from = { owner = canisterId; subaccount = null }; 
                from_subaccount = null; 
                to = { owner = poolData.canisterId; subaccount = Option.make(AccountUtils.principalToBlob(canisterId)) }; 
                amount = transferedAmount; 
                fee = ?fee; 
                memo = Option.make(Text.encodeUtf8("_ICRC1SwapToICP")); 
                created_at_time = ?Nat64.fromNat(Int.abs(Time.now()));
            })) {
                case (#Ok(_)) {
                    _addTokenSwapLog(token, transferedAmount, 0, "", "transfer", ?poolId);
                    // Second external call - deposit
                    switch (await poolAct.deposit({ token = token.address; amount = transferedAmount - fee; fee = fee; })) {
                        case (#ok(depositedAmount)) {
                            _addTokenSwapLog(token, depositedAmount, 0, "", "deposit", ?poolId);
                            // Third external call - swap
                            switch (await poolAct.swap({
                                zeroForOne = if (Functions.tokenEqual(ICP, poolData.token0)) { false } else { true };
                                amountIn = debug_show(depositedAmount);
                                amountOutMinimum = "0";
                            })) {
                                case (#ok(swappedAmount)) {
                                    _addTokenSwapLog(token, depositedAmount, swappedAmount, "", "swap", ?poolId);
                                    // Check if swapped amount is worth withdrawing
                                    if (swappedAmount <= _ICPFee) {
                                        _addTokenSwapLog(ICP, 0, 0, "Skip: swappedAmount less than _ICPFee", "withdraw", ?poolId);
                                        _releaseLock();
                                        return;
                                    };
                                    // Final external call - withdraw
                                    switch (await poolAct.withdraw({ token = ICP.address; fee = _ICPFee; amount = swappedAmount; })) {
                                        case (#ok(withdrawedAmount)) { _addTokenSwapLog(ICP, 0, withdrawedAmount, "", "withdraw", ?poolId); };
                                        case (#err(msg)) { _addTokenSwapLog(ICP, 0, 0, debug_show(msg), "withdraw", ?poolId); };
                                    };
                                };
                                case (#err(msg)) { _addTokenSwapLog(token, depositedAmount, 0, debug_show(msg), "swap", ?poolId); };
                            };
                        };
                        case (#err(msg)) { _addTokenSwapLog(token, transferedAmount, 0, debug_show(msg), "deposit", ?poolId); };
                    };
                };
                case (#Err(msg)) { 
                    _addTokenSwapLog(token, 0, 0, debug_show(msg), "transfer", ?poolId); 
                };
            };
        } catch (e) {
            // Log any unexpected errors
            _addTokenSwapLog(token, 0, 0, "_ICRC1SwapToICP failed: " # debug_show(Error.message(e)), "ICRC1SwapToICP", ?poolData.canisterId );
        } finally {
            // Always release the lock, even if an error occurred
            _releaseLock();
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
        // Check and acquire lock
        assert(_acquireLock());
        try {
            // Safety checks for calculations
            if (balance <= tokenInFee) {
                _addTokenSwapLog(tokenIn, 0, 0, "Insufficient balance for fee", "validation", ?poolData.canisterId);
                return;
            };
            if (balance <= (tokenInFee * 4)) {  // Need at least 4x fee for the operations
                _addTokenSwapLog(tokenIn, 0, 0, "Insufficient balance for operations", "validation", ?poolData.canisterId);
                return;
            };
            // Calculate amounts before any external calls
            var approvedAmount = balance - tokenInFee;
            var depositAmount = approvedAmount - tokenInFee * 3;
            var tokenInAct : TokenAdapterTypes.TokenAdapter = TokenFactory.getAdapter(tokenIn.address, tokenIn.standard);
            var poolId = poolData.canisterId;
            var poolAct = actor (Principal.toText(poolId)) : Types.SwapPoolActor;
            // First external call - approve
            switch (await tokenInAct.approve({
                from_subaccount = null; 
                spender = poolData.canisterId; 
                amount = approvedAmount; 
                fee = ?tokenInFee; 
                memo = null; 
                created_at_time = null;
            })) {
                case (#Ok(_)) {
                    _addTokenSwapLog(tokenIn, approvedAmount, 0, "", "approve", ?poolId);
                    // Second external call - depositFrom
                    switch (await poolAct.depositFrom({ token = tokenIn.address; amount = depositAmount; fee = tokenInFee; })) {
                        case (#ok(depositedAmount)) {
                            _addTokenSwapLog(tokenIn, depositedAmount, 0, "", "depositFrom", ?poolId);
                            // Third external call - swap
                            switch (await poolAct.swap({
                                zeroForOne = if (Functions.tokenEqual(tokenOut, poolData.token0)) { false } else { true };
                                amountIn = debug_show(depositedAmount);
                                amountOutMinimum = "0";
                            })) {
                                case (#ok(swappedAmount)) {
                                    _addTokenSwapLog(tokenIn, depositedAmount, swappedAmount, "", "swap", ?poolId);
                                    // Check minimum amount for tokenOut if it's ICP
                                    if (Functions.tokenEqual(tokenOut, ICP) and swappedAmount <= _ICPFee) {
                                        _addTokenSwapLog(tokenOut, 0, 0, "Skip: swappedAmount less than _ICPFee", "withdraw", ?poolId);
                                        _releaseLock();
                                        return;
                                    };
                                    // Final external call - withdraw
                                    switch (await poolAct.withdraw({ token = tokenOut.address; fee = tokenOutFee; amount = swappedAmount; })) {
                                        case (#ok(withdrawedAmount)) { _addTokenSwapLog(tokenOut, 0, withdrawedAmount, "", "withdraw", ?poolId);  };
                                        case (#err(msg)) { _addTokenSwapLog(tokenOut, 0, 0, debug_show(msg), "withdraw", ?poolId); };
                                    };
                                };
                                case (#err(msg)) { _addTokenSwapLog(tokenIn, depositedAmount, 0, debug_show(msg), "swap", ?poolId); };
                            };
                        };
                        case (#err(msg)) { _addTokenSwapLog(tokenIn, approvedAmount, 0, debug_show(msg), "depositFrom", ?poolId); };
                    };
                };
                case (#Err(msg)) { _addTokenSwapLog(tokenIn, 0, 0, debug_show(msg), "approve", ?poolId); };
            };
        } catch (e) {
            // Log any unexpected errors
            _addTokenSwapLog(tokenIn, 0, 0, "_commonSwap failed: " # debug_show(Error.message(e)), "commonSwap", ?poolData.canisterId);
        } finally {
            // Always release the lock, even if an error occurred
            _releaseLock();
        };
    };

    private func _swapICPToICS() : async () {
        try {
            var canisterId = switch (_canisterId) { 
                case(?p){ p };
                case(_) {
                    _addTokenSwapLog( ICP, 0, 0, "_swapICPToICS failed: Uninitialized canisterId", "swapICPToICS", null);
                    return;
                }; 
            };
            var tokenAct : TokenAdapterTypes.TokenAdapter = TokenFactory.getAdapter(ICP.address, ICP.standard);
            var balance : Nat = await tokenAct.balanceOf({ owner = canisterId; subaccount = null; });
            if (balance <= (_ICPFee * 10)) { return; };
            switch (await _factoryAct.getPool({ token0 = ICP; token1 = ICS; fee = 3000; })) {
                case (#ok(poolData)) { 
                    await _commonSwap(poolData, ICP, balance, _ICPFee, ICS, _ICSFee); 
                    ignore Timer.setTimer<system>(#nanoseconds (1), _burnICS);
                    return; 
                };
                case (#err(msg)) { 
                    _addTokenSwapLog(ICP, 0, 0, debug_show(msg), "getPool", null); 
                    return; 
                };
            };
        } catch (e) {
            _addTokenSwapLog(ICP, 0, 0, "_swapICPToICS failed: " # debug_show (Error.message(e)), "swapICPToICS", null);
            // Retry after 1 hour
            ignore Timer.setTimer<system>(#seconds(3600), _swapICPToICS);
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
                // clear history
                _tokenClaimLog := Buffer.Buffer<Types.ReceiverClaimLog>(0);
                _tokenSwapLog := Buffer.Buffer<Types.ReceiverSwapLog>(0);
                true;
            };
            case (#err(_)) { false; };
        };
    };

    private func _autoSwap() : async () {
        try {
            for ((token, swapped) in TrieSet.toArray(_tokenSet).vals()) {
                if((not swapped) and (not Text.equal(token.address, ICP.address)) and (not Text.equal(token.address, ICS.address))) {
                    _tokenSet := TrieSet.put<(Types.Token, Bool)>(_tokenSet, (token, true), Functions.tokenHash(token), _tokenSetEqual);
                    try {
                        let _ = await _swapToICP(token);
                    } catch (e) {
                        _addTokenSwapLog(token, 0, 0, "Call _swapToICP failed: " # debug_show (Error.message(e)), "_swapToICP", null);
                    };
                    ignore Timer.setTimer<system>(#nanoseconds (1), _autoSwap);
                    return;
                };
            };
            _isSyncing := false;
            ignore Timer.setTimer<system>(#nanoseconds (1), _swapICPToICS);
        } catch (e) {
            _addTokenSwapLog(
                { address = ""; standard = ""; },
                0,
                0,
                "_autoSwap failed: " # debug_show (Error.message(e)),
                "autoSwap",
                null
            );
            // Retry after 1 hour
            ignore Timer.setTimer<system>(#seconds(3600), _autoSwap);
        };
    };

    private func _autoClaim() : async () {
        try {
            var canisterId = switch (_canisterId) { case(?p){ p }; case(_) { return }; };
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
                    ignore Timer.setTimer<system>(#nanoseconds (1), _autoClaim);
                    return;
                };
            };
            ignore Timer.setTimer<system>(#nanoseconds (2), _autoSwap);
        } catch (e) {
            _tokenClaimLog.add({
                timestamp = BlockTimestamp.blockTimestamp();
                amount = 0;
                poolId = Principal.fromText("aaaaa-aa");  // default principal
                token = { address = ""; standard = ""; };
                errMsg = "_autoClaim failed: " # debug_show (Error.message(e));
            });
            // Retry after 1 hour
            ignore Timer.setTimer<system>(#seconds(3600), _autoClaim);
        };
    };

    private func _autoSyncPools() : async () {
        try {
            if (_isSyncing) { return; };
            if (await _syncPools()) {
                if(_isSyncing) { return; };
                _isSyncing := true;
                _lastSyncTime := BlockTimestamp.blockTimestamp();
                ignore Timer.setTimer<system>(#nanoseconds (0), _autoClaim); 
            };
        } catch (e) {
            // Log error and retry after delay
            _tokenSwapLog.add({
                timestamp = BlockTimestamp.blockTimestamp();
                token = { address = ""; standard = ""; };
                amountIn = 0;
                amountOut = 0;
                errMsg = "_autoSyncPools failed: " # debug_show(Error.message(e));
                step = "autoSync";
                poolId = null;
            });
            // Use _scheduleRetry instead of direct Timer.setTimer
            await _scheduleRetry(3600, _autoSyncPools);
        };
    };

    // auto claim every 7 days
    let _claimSwapFeeRepurchasePerWeek = Timer.recurringTimer<system>(#seconds(604800), _autoSyncPools);

    // --------------------------- Version Control ------------------------------------
    private var _version : Text = "3.5.0";
    public query func getVersion() : async Text { _version };

    system func preupgrade() {
        _tokenClaimLogArray := Buffer.toArray(_tokenClaimLog);
        _tokenSwapLogArray := Buffer.toArray(_tokenSwapLog);
        _tokenBurnLogArray := Buffer.toArray(_tokenBurnLog);
        _cleanupTimers();
    };

    system func postupgrade() {
        _canisterId := ?Principal.fromActor(this);
        _tokenClaimLog := Buffer.fromArray(_tokenClaimLogArray);
        _tokenSwapLog := Buffer.fromArray(_tokenSwapLogArray);
        _tokenBurnLog := Buffer.fromArray(_tokenBurnLogArray);
        _tokenClaimLogArray := [];
        _tokenSwapLogArray := [];
        _tokenBurnLogArray := [];
        _locked := false;
    };

    system func inspect({
        arg : Blob;
        caller : Principal;
        msg : Types.SwapFeeReceiverMsg;
    }) : Bool {
        return switch (msg) {
            // Controller
            case (#burnICS _)            { Prim.isController(caller) };
            case (#claim _)              { Prim.isController(caller) };
            case (#setFees _)            { Prim.isController(caller) };
            case (#setCanisterId _)      { Prim.isController(caller) };
            case (#startAutoSyncPools _) { Prim.isController(caller) };
            case (#swapICPToICS _)       { Prim.isController(caller) };
            case (#swapToICP _)          { Prim.isController(caller) };
            case (#transfer _)           { Prim.isController(caller) };
            case (#transferAll _)        { Prim.isController(caller) };
            // Anyone
            case (_) { true };
        };
    };
};
