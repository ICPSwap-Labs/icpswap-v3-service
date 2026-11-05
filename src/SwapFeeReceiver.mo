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
import Array "mo:base/Array";
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

    private var _deploymentTime : Nat = BlockTimestamp.blockTimestamp();

    // --------------------------- Debug Log Buffer ------------------------------------
    private let _MAX_DEBUG_LOGS : Nat = 1000;
    private stable var _debugLogArray : [Text] = [];
    private var _debugLog : Buffer.Buffer<Text> = Buffer.Buffer<Text>(0);
    private var _debugLogWriteIndex : Nat = 0;
    private func _log(msg : Text) {
        let entry = Nat.toText(BlockTimestamp.blockTimestamp()) # " " # msg;
        if (_debugLog.size() < _MAX_DEBUG_LOGS) {
            _debugLog.add(entry);
        } else {
            _debugLog.put(_debugLogWriteIndex % _MAX_DEBUG_LOGS, entry);
        };
        _debugLogWriteIndex += 1;
    };
    public query ({ caller }) func getDebugLog(count : ?Nat) : async [Text] {
        _checkPermission(caller);
        let size = _debugLog.size();
        if (size == 0) { return []; };
        let n = switch (count) { case (null) { size }; case (?c) { if (c > size) { size } else { c }; }; };
        if (size < _MAX_DEBUG_LOGS) {
            let start = if (size > n) { size - n } else { 0 };
            Array.tabulate(size - start, func(i : Nat) : Text = _debugLog.get(start + i));
        } else {
            Array.tabulate(n, func(i : Nat) : Text {
                _debugLog.get((_debugLogWriteIndex + _MAX_DEBUG_LOGS - n + i) % _MAX_DEBUG_LOGS);
            });
        };
    };

    // --------------------------- Auto Claim ------------------------------------
    private stable var _canisterId : ?Principal = null;
    private stable var _ICPFee : Nat = 0;
    private stable var _ICSFee : Nat = 0;
    private stable var _lastSyncTime : Nat = 0;
    private stable var _lastICPPoolClaimTime : Nat = 0;
    private stable var _lastNoICPPoolClaimTime : Nat = 0;
    // Set during chunked claim (one pool per message); used when the cycle completes to update *_last*PoolClaimTime.
    private stable var _claimCycleHadICP : Bool = false;
    private stable var _claimCycleHadNoICP : Bool = false;
    private stable var _icpPoolClaimInterval : Nat = 2592000; // Default 30 days in seconds
    private stable var _noIcpPoolClaimInterval : Nat = 15552000; // Default 180 days in seconds
    private stable var _autoSwapToIcsEnabled : Bool = false;
    private stable var _autoBurnIcsEnabled : Bool = false;

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

    private stable var _locked : Bool = false;
    private func _acquireLock() : Bool {
        if (_locked) { return false; };
        _locked := true;
        true;
    };
    private func _releaseLock() { _locked := false; };

    // --------------------------- Swap Price Protection ------------------------------------
    private let _BPS_DENOMINATOR : Nat = 10000;
    private let _POOL_FEE_DENOMINATOR : Nat = 1000000;
    private let _SWAP_POOL_FEE : Nat = 3000;
    // amountOutMinimum = quote * (1 - slippage); guards the window between quote and swap.
    private stable var _swapSlippageBps : Nat = 500;
    // Skip the swap when the quote is worse than the reference spot price by more than this.
    private stable var _maxPriceDeviationBps : Nat = 1000;
    // Delay between the end of the claim phase (where reference prices are taken) and the swap phase,
    // so that a manipulated price has to be held against arbitrage for at least this long.
    private stable var _swapDelaySeconds : Nat = 1800;
    private stable var _refPriceMaxAgeSeconds : Nat = 86400;
    private var _refPriceMap : HashMap.HashMap<Principal, { sqrtPriceX96 : Nat; timestamp : Nat }> = HashMap.HashMap<Principal, { sqrtPriceX96 : Nat; timestamp : Nat }>(100, Principal.equal, Principal.hash);

    private func _snapshotReferencePrice(poolId : Principal, poolAct : Types.SwapPoolActor, data : Types.ClaimedPoolData) : async () {
        if (data.fee != _SWAP_POOL_FEE or not _poolHasICP(data)) { return };
        try {
            switch (await poolAct.metadata()) {
                case (#ok(metadata)) {
                    _refPriceMap.put(poolId, { sqrtPriceX96 = metadata.sqrtPriceX96; timestamp = BlockTimestamp.blockTimestamp() });
                };
                case (#err(msg)) {
                    _log("[WARN][_snapshotReferencePrice] metadata failed pool=" # Principal.toText(poolId) # " err=" # debug_show(msg));
                };
            };
        } catch (e) {
            _log("[WARN][_snapshotReferencePrice] metadata threw pool=" # Principal.toText(poolId) # " err=" # Error.message(e));
        };
    };

    // Output at the given spot price after the pool fee, ignoring price impact.
    private func _spotAmountOut(sqrtPriceX96 : Nat, amountIn : Nat, zeroForOne : Bool, poolFee : Nat) : Nat {
        if (sqrtPriceX96 == 0 or poolFee >= _POOL_FEE_DENOMINATOR) { return 0 };
        let amountInLessFee = amountIn * (_POOL_FEE_DENOMINATOR - poolFee) / _POOL_FEE_DENOMINATOR;
        let priceX192 = sqrtPriceX96 * sqrtPriceX96;
        let q192 : Nat = 2 ** 192;
        if (zeroForOne) { amountInLessFee * priceX192 / q192 } else { amountInLessFee * q192 / priceX192 };
    };

    type MinOutMode = {
        // Quote, checked against the claim-time reference price, minus _swapSlippageBps.
        #reference;
        // Quote minus the given slippage bps, without the reference price check.
        #quote : Nat;
        // Caller-supplied amountOutMinimum; 0 means no limit.
        #fixed : Nat;
    };

    // Returns the amountOutMinimum to use for swapping `amountIn`, or an error when the swap must be skipped.
    private func _resolveAmountOutMinimum(mode : MinOutMode, poolData : Types.PoolData, poolAct : Types.SwapPoolActor, zeroForOne : Bool, amountIn : Nat) : async Result.Result<Nat, Text> {
        let ref = switch (mode) {
            case (#fixed(amount)) { return #ok(amount) };
            case (#quote(_)) { null };
            case (#reference) {
                switch (_refPriceMap.get(poolData.canisterId)) {
                    case (?r) {
                        if (BlockTimestamp.blockTimestamp() > r.timestamp + _refPriceMaxAgeSeconds) {
                            return #err("reference price is stale, taken at " # Nat.toText(r.timestamp));
                        };
                        ?r;
                    };
                    case (null) { return #err("no reference price for pool") };
                };
            };
        };
        let quoted = switch (await poolAct.quote({ zeroForOne = zeroForOne; amountIn = Nat.toText(amountIn); amountOutMinimum = "0"; })) {
            case (#ok(amount)) { amount };
            case (#err(msg)) { return #err("quote failed: " # debug_show(msg)) };
        };
        switch (ref) {
            case (?r) {
                let refAmountOut = _spotAmountOut(r.sqrtPriceX96, amountIn, zeroForOne, poolData.fee);
                if (quoted * _BPS_DENOMINATOR < refAmountOut * (_BPS_DENOMINATOR - _maxPriceDeviationBps)) {
                    return #err("quote " # Nat.toText(quoted) # " deviates more than " # Nat.toText(_maxPriceDeviationBps)
                        # " bps from reference " # Nat.toText(refAmountOut));
                };
            };
            case (null) {};
        };
        let slippageBps = switch (mode) { case (#quote(bps)) { bps }; case (_) { _swapSlippageBps } };
        let amountOutMinimum = quoted * (_BPS_DENOMINATOR - slippageBps) / _BPS_DENOMINATOR;
        if (amountOutMinimum == 0) { return #err("amountOutMinimum is 0") };
        #ok(amountOutMinimum);
    };

    private var _isForceSwapping : Bool = false;
    private var _forceSwapQueue : [{ token : Types.Token; reclaimPool : ?Principal }] = [];
    private var _forceSwapIndex : Nat = 0;
    private var _forceSwapMode : MinOutMode = #fixed(0);

    private func _scaleAmountOutMinimum(amountOutMinimum : Nat, actualAmountIn : Nat, quotedAmountIn : Nat) : Nat {
        if (actualAmountIn == quotedAmountIn or quotedAmountIn == 0) { return amountOutMinimum };
        amountOutMinimum * actualAmountIn / quotedAmountIn;
    };

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

    public shared ({ caller }) func forceAutoClaim() : async Result.Result<(), Types.Error> {
        _checkPermission(caller);
        if (_isForceSwapping) { return #err(#InternalError("Force swap queue is running")); };
        // _syncPools resets pool, token, swap log and reference price state, so it must not run mid-cycle.
        if (_isSyncing) { return #err(#InternalError("Already syncing")); };
        try {
            // First sync pools to get latest pool list
            if (await _syncPools()) {
                if (_isSyncing) { return #err(#InternalError("Already syncing")); };
                _isSyncing := true;
                let currentTime = BlockTimestamp.blockTimestamp();
                _lastSyncTime := currentTime;
                // Force claim all pools by calling _forceAutoClaim
                ignore Timer.setTimer<system>(#nanoseconds (0), _forceAutoClaim);
                return #ok();
            } else {
                return #err(#InternalError("Failed to sync pools"));
            };
        } catch (e) {
            return #err(#InternalError("forceAutoClaim failed: " # Error.message(e)));
        };
    };

    public shared ({ caller }) func swapToICP(token : Types.Token) : async Result.Result<Bool, Types.Error> {
        _checkPermission(caller);
        return #ok(await _swapToICP(token, #reference));
    };

    public shared ({ caller }) func swapICPToICS() : async Result.Result<(), Types.Error> {
        _checkPermission(caller);
        await _swapICPToICS();
        return #ok();
    };

    // Bypasses the reference price check and uses the given amountOutMinimum (0 means no limit).
    public shared ({ caller }) func forceSwapToICP(token : Types.Token, amountOutMinimum : Nat) : async Result.Result<Bool, Types.Error> {
        _checkPermission(caller);
        return #ok(await _swapToICP(token, #fixed(amountOutMinimum)));
    };

    // Bypasses the reference price check and uses the given amountOutMinimum (0 means no limit).
    public shared ({ caller }) func forceSwapICPToICS(amountOutMinimum : Nat) : async Result.Result<(), Types.Error> {
        _checkPermission(caller);
        await _swapICPToICSWith(#fixed(amountOutMinimum));
        return #ok();
    };

    // Re-runs token -> ICP swaps that were skipped or failed in the current cycle, one token per message.
    // slippageBps = null means no amountOutMinimum; ?bps means quote * (1 - bps), without the reference price check.
    public shared ({ caller }) func forceSwapSkippedTokens(slippageBps : ?Nat) : async Result.Result<[Types.Token], Types.Error> {
        _checkPermission(caller);
        if (_isSyncing) { return #err(#InternalError("Auto claim/swap cycle is running")); };
        if (_isForceSwapping) { return #err(#InternalError("Force swap queue is already running")); };
        if (_locked) { return #err(#InternalError("Another swap is in progress")); };
        let mode : MinOutMode = switch (slippageBps) {
            case (null) { #fixed(0) };
            case (?bps) {
                if (bps > 5000) { return #err(#InternalError("slippageBps must be at most 5000")); };
                #quote(bps);
            };
        };
        _forceSwapQueue := _collectPendingSwapTokens();
        _forceSwapIndex := 0;
        _forceSwapMode := mode;
        if (_forceSwapQueue.size() == 0) { return #ok([]); };
        _isForceSwapping := true;
        ignore Timer.setTimer<system>(#nanoseconds (0), _processForceSwapQueue);
        return #ok(Array.map<{ token : Types.Token; reclaimPool : ?Principal }, Types.Token>(_forceSwapQueue, func(item) { item.token }));
    };

    public query func getForceSwapStatus() : async Result.Result<{ isRunning : Bool; processed : Nat; total : Nat; }, Types.Error> {
        return #ok({ isRunning = _isForceSwapping; processed = _forceSwapIndex; total = _forceSwapQueue.size(); });
    };

    public shared ({ caller }) func burnICS() : async Result.Result<(), Types.Error> {
        _checkPermission(caller);
        return #ok(await _burnICS());
    };

    public shared ({ caller }) func swapWithoutDeposit(
        pool : Principal,
        zeroForOne : Bool,
        amountIn : Text,
        amountOutMinimum : Text
    ) : async Result.Result<Nat, Types.Error> {
        _checkPermission(caller);
        try {
            var poolAct = actor (Principal.toText(pool)) : Types.SwapPoolActor;
            switch (await poolAct.swap({
                zeroForOne = zeroForOne;
                amountIn = amountIn;
                amountOutMinimum = amountOutMinimum;
            })) {
                case (#ok(swappedAmount)) { return #ok(swappedAmount); };
                case (#err(msg)) { return #err(#InternalError(debug_show(msg))); };
            };
        } catch (e) {
            return #err(#InternalError("swapWithoutDeposit failed: " # Error.message(e)));
        };
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

    public query func getSyncingStatus(): async Result.Result<{ 
        isSyncing : Bool; 
        lastSyncTime : Nat; 
        lastICPPoolClaimTime : Nat;
        lastNoICPPoolClaimTime : Nat;
        swapProgress : Text;
        claimProgress : Text; 
    }, Types.Error> {
        var swapCount = 0;
        var swapTotal = 0;
        for ((token, swapped) in TrieSet.toArray(_tokenSet).vals()) {
            if (swapped) { swapCount := swapCount + 1; };
            swapTotal := swapTotal + 1;
        };

        var claimCount = 0;
        var claimTotal = 0;
        for ((_, data) in _poolMap.entries()) {
            if (data.claimed) { claimCount := claimCount + 1; };
            claimTotal := claimTotal + 1;
        };

        return #ok({ 
            isSyncing = _isSyncing; 
            lastSyncTime = _lastSyncTime; 
            lastICPPoolClaimTime = _lastICPPoolClaimTime;
            lastNoICPPoolClaimTime = _lastNoICPPoolClaimTime;
            swapProgress = debug_show(swapCount) # "/" # debug_show(swapTotal);
            claimProgress = debug_show(claimCount) # "/" # debug_show(claimTotal);
        });
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
            if (balance == 0) { return; };
            switch (await tokenAct.transfer({
                from = { owner = canisterId; subaccount = null };
                from_subaccount = null;
                to = { owner = governanceCid; subaccount = null };
                amount = balance;
                fee = null;
                memo = Option.make(Text.encodeUtf8("_burnICS"));
                created_at_time = ?Nat64.fromNat(Int.abs(Time.now()));
            })) {
                case (#Ok(_)) { _tokenBurnLog.add({ timestamp = BlockTimestamp.blockTimestamp(); amount = balance; errMsg = ""; }); };
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
        fee : Nat,
        minOutMode : MinOutMode,
    ) : async () {
        // Check and acquire lock
        if (not _acquireLock()) {
            _addTokenSwapLog(token, 0, 0, "Skip: another swap holds the lock", "lock", ?poolData.canisterId);
            return;
        };
        try {
            var tokenAct : TokenAdapterTypes.TokenAdapter = TokenFactory.getAdapter(token.address, token.standard);
            var poolId = poolData.canisterId;
            var poolAct = actor (Principal.toText(poolId)) : Types.SwapPoolActor;
            // Calculate amounts before external calls
            var transferedAmount = balance - fee;
            let expectedDepositAmount : Nat = transferedAmount - fee;
            let zeroForOne = if (Functions.tokenEqual(ICP, poolData.token0)) { false } else { true };
            let quotedAmountOutMinimum = switch (await _resolveAmountOutMinimum(minOutMode, poolData, poolAct, zeroForOne, expectedDepositAmount)) {
                case (#ok(amount)) { amount };
                case (#err(msg)) {
                    _addTokenSwapLog(token, expectedDepositAmount, 0, "Skip: " # msg, "priceCheck", ?poolId);
                    _releaseLock();
                    return;
                };
            };
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
                                zeroForOne = zeroForOne;
                                amountIn = debug_show(depositedAmount);
                                amountOutMinimum = Nat.toText(_scaleAmountOutMinimum(quotedAmountOutMinimum, depositedAmount, expectedDepositAmount));
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
                    _addTokenSwapLog(token, 0, 0, debug_show(msg), "transfer", ?poolData.canisterId );
                };
            };
        } catch (e) {
            // Log any unexpected errors
            _addTokenSwapLog(token, 0, 0, "_ICRC1SwapToICP failed: " # debug_show(Error.message(e)), "ICRC1SwapToICP", ?poolData.canisterId );
        };
        // Release lock after everything (success or failure)
        _releaseLock();
    };

    private func _commonSwap(
        poolData : Types.PoolData,
        tokenIn : Types.Token,
        balance : Nat,
        tokenInFee : Nat, 
        tokenOut : Types.Token,
        tokenOutFee : Nat,
        minOutMode : MinOutMode,
    ) : async () {
        // Check and acquire lock
        if (not _acquireLock()) {
            _addTokenSwapLog(tokenIn, 0, 0, "Skip: another swap holds the lock", "lock", ?poolData.canisterId);
            return;
        };
        try {
            // Safety checks for calculations
            if (balance <= tokenInFee) {
                _addTokenSwapLog(tokenIn, 0, 0, "Insufficient balance for fee", "validation", ?poolData.canisterId);
                _releaseLock();
                return;
            };
            if (balance <= (tokenInFee * 4)) {  // Need at least 4x fee for the operations
                _addTokenSwapLog(tokenIn, 0, 0, "Insufficient balance for operations", "validation", ?poolData.canisterId);
                _releaseLock();
                return;
            };
            // Calculate amounts before any external calls
            var approvedAmount = balance - tokenInFee;
            var depositAmount = approvedAmount - tokenInFee * 3;
            var tokenInAct : TokenAdapterTypes.TokenAdapter = TokenFactory.getAdapter(tokenIn.address, tokenIn.standard);
            var poolId = poolData.canisterId;
            var poolAct = actor (Principal.toText(poolId)) : Types.SwapPoolActor;
            let zeroForOne = if (Functions.tokenEqual(tokenOut, poolData.token0)) { false } else { true };
            let quotedAmountOutMinimum = switch (await _resolveAmountOutMinimum(minOutMode, poolData, poolAct, zeroForOne, depositAmount)) {
                case (#ok(amount)) { amount };
                case (#err(msg)) {
                    _addTokenSwapLog(tokenIn, depositAmount, 0, "Skip: " # msg, "priceCheck", ?poolId);
                    _releaseLock();
                    return;
                };
            };
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
                                zeroForOne = zeroForOne;
                                amountIn = debug_show(depositedAmount);
                                amountOutMinimum = Nat.toText(_scaleAmountOutMinimum(quotedAmountOutMinimum, depositedAmount, depositAmount));
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
        };
        // Release lock after everything (success or failure)
        _releaseLock();
    };

    private func _swapICPToICS() : async () {
        await _swapICPToICSWith(#reference);
    };

    private func _swapICPToICSWith(minOutMode : MinOutMode) : async () {
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
            switch (await _factoryAct.getPool({ token0 = ICP; token1 = ICS; fee = _SWAP_POOL_FEE; })) {
                case (#ok(poolData)) {
                    await _commonSwap(poolData, ICP, balance, _ICPFee, ICS, _ICSFee, minOutMode);
                    // Only schedule burn if enabled
                    if (_autoBurnIcsEnabled) {
                        ignore Timer.setTimer<system>(#nanoseconds (1), _burnICS);
                    };
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

    private func _swapToICP(tokenIn : Types.Token, minOutMode : MinOutMode) : async Bool {
        var canisterId = switch (_canisterId) { case(?p){ p }; case(_) { return false; }; };
        var tokenAct : TokenAdapterTypes.TokenAdapter = TokenFactory.getAdapter(tokenIn.address, tokenIn.standard);
        var balance : Nat = await tokenAct.balanceOf({ owner = canisterId; subaccount = null; });
        var fee : Nat = await tokenAct.fee();
        if (balance <= (fee * 10)) { return false; };
        switch (await _factoryAct.getPool({ token0 = tokenIn; token1 = ICP; fee = _SWAP_POOL_FEE; })) {
            case (#ok(poolData)) {
                if (Text.equal("ICRC1", tokenIn.standard)) {
                    await _ICRC1SwapToICP(canisterId, poolData, tokenIn, balance, fee, minOutMode);
                } else {
                    await _commonSwap(poolData, tokenIn, balance, fee, ICP, _ICPFee, minOutMode);
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
            await _snapshotReferencePrice(poolId, poolAct, data);
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
                _refPriceMap := HashMap.HashMap<Principal, { sqrtPriceX96 : Nat; timestamp : Nat }>(100, Principal.equal, Principal.hash);
                _claimCycleHadICP := false;
                _claimCycleHadNoICP := false;
                true;
            };
            case (#err(_)) { false; };
        };
    };

    private func _poolHasICP(data : Types.ClaimedPoolData) : Bool {
        Functions.tokenEqual(data.token0, ICP) or Functions.tokenEqual(data.token1, ICP)
    };

    // Unclaimed pools that are in-scope for this claim cycle.
    // ICP-only cycles intentionally leave non-ICP pools unclaimed; those must not block completion.
    private func _hasUnclaimedPoolInScope(claimNoICP : Bool) : Bool {
        for ((_, data) in _poolMap.entries()) {
            if (not data.claimed) {
                if (_poolHasICP(data) or claimNoICP) { return true };
            };
        };
        false;
    };

    private func _hasUnclaimedPool() : Bool {
        _hasUnclaimedPoolInScope(true)
    };

    // Advance interval timestamps once all in-scope pools for this cycle are done.
    // claimICP / claimNoICP are the *intended* scope of the cycle (not whether any pool was found).
    private func _finalizeClaimIntervalTimestamps(currentTime : Nat, claimICP : Bool, claimNoICP : Bool) {
        if (_hasUnclaimedPoolInScope(claimNoICP)) { return };
        if (claimICP or claimNoICP) {
            _log("[INFO][_finalizeClaim] advanced: claimICP=" # debug_show(claimICP)
                # " claimNoICP=" # debug_show(claimNoICP)
                # " hadICP=" # debug_show(_claimCycleHadICP)
                # " hadNoICP=" # debug_show(_claimCycleHadNoICP)
                # " at=" # Nat.toText(currentTime));
        };
        if (claimICP) { _lastICPPoolClaimTime := currentTime };
        if (claimNoICP) { _lastNoICPPoolClaimTime := currentTime };
        _claimCycleHadICP := false;
        _claimCycleHadNoICP := false;
    };

    private func _autoSwap() : async () {
        try {
            for ((token, swapped) in TrieSet.toArray(_tokenSet).vals()) {
                if((not swapped) and (not Text.equal(token.address, ICP.address)) and (not Text.equal(token.address, ICS.address))) {
                    _tokenSet := TrieSet.put<(Types.Token, Bool)>(_tokenSet, (token, true), Functions.tokenHash(token), _tokenSetEqual);
                    try {
                        let _ = await _swapToICP(token, #reference);
                    } catch (e) {
                        _addTokenSwapLog(token, 0, 0, "Call _swapToICP failed: " # debug_show (Error.message(e)), "_swapToICP", null);
                    };
                    ignore Timer.setTimer<system>(#nanoseconds (1), _autoSwap);
                    return;
                };
            };
            _isSyncing := false;
            _log("[INFO][_autoSwap] done: isSyncing cleared, autoSwapToIcsEnabled="
                # debug_show(_autoSwapToIcsEnabled));

            // Only proceed with auto-swap if enabled
            if (_autoSwapToIcsEnabled) {
                ignore Timer.setTimer<system>(#nanoseconds (1), _swapICPToICS);
            };
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

    // Tokens whose latest token -> ICP attempt in the current swap log did not complete.
    // reclaimPool is set when the tokens were already deposited into the pool and must be withdrawn first.
    private func _collectPendingSwapTokens() : [{ token : Types.Token; reclaimPool : ?Principal }] {
        let pending = HashMap.HashMap<Text, { token : Types.Token; reclaimPool : ?Principal }>(16, Text.equal, Text.hash);
        for (log in _tokenSwapLog.vals()) {
            let address = log.token.address;
            if (address != "" and address != ICP.address and address != ICS.address) {
                let prevReclaimPool = switch (pending.get(address)) { case (?p) { p.reclaimPool }; case (null) { null } };
                if (log.step == "swap") {
                    if (log.errMsg == "") {
                        pending.delete(address);
                    } else {
                        pending.put(address, { token = log.token; reclaimPool = log.poolId });
                    };
                } else if (log.step == "priceCheck" or log.step == "lock" or (log.errMsg != "" and (
                    log.step == "transfer" or log.step == "approve" or log.step == "depositFrom"
                    or log.step == "ICRC1SwapToICP" or log.step == "commonSwap" or log.step == "_swapToICP"
                    or log.step == "forceSwapQueue"
                ))) {
                    pending.put(address, { token = log.token; reclaimPool = prevReclaimPool });
                };
            };
        };
        Iter.toArray(pending.vals());
    };

    private func _processForceSwapQueue() : async () {
        if (_forceSwapIndex >= _forceSwapQueue.size()) {
            _isForceSwapping := false;
            _log("[INFO][_processForceSwapQueue] done: total=" # Nat.toText(_forceSwapQueue.size()));
            return;
        };
        let item = _forceSwapQueue[_forceSwapIndex];
        _forceSwapIndex += 1;
        try {
            switch (item.reclaimPool, _canisterId) {
                case (?poolId, ?canisterId) {
                    switch (_poolMap.get(poolId)) {
                        case (?data) { ignore await _claim(poolId, canisterId, data); };
                        case (null) { _log("[WARN][_processForceSwapQueue] reclaim skipped, pool not in pool map: " # Principal.toText(poolId)); };
                    };
                };
                case (_) {};
            };
            ignore await _swapToICP(item.token, _forceSwapMode);
        } catch (e) {
            _addTokenSwapLog(item.token, 0, 0, "forceSwapSkippedTokens failed: " # debug_show(Error.message(e)), "forceSwapQueue", item.reclaimPool);
        };
        ignore Timer.setTimer<system>(#nanoseconds (1), _processForceSwapQueue);
    };

    // Force claim all pools ignoring time restrictions
    private func _forceAutoClaim() : async () {
        try {
            let currentTime = BlockTimestamp.blockTimestamp();
            _log("[INFO][_forceAutoClaim] tick: now=" # Nat.toText(currentTime));

            var canisterId = switch (_canisterId) {
                case(?p){ p };
                case(_) {
                    _log("[ERROR][_forceAutoClaim] skip: _canisterId uninitialized (call setCanisterId)");
                    _isSyncing := false;
                    return;
                };
            };

            // Force claim all pools (both ICP and non-ICP) ignoring time restrictions
            label claimLoop for ((cid, data) in _poolMap.entries()) {
                if (not data.claimed) {
                    let hasICP = _poolHasICP(data);

                    if (hasICP) {
                        _claimCycleHadICP := true;
                    } else {
                        _claimCycleHadNoICP := true;
                    };

                    _log("[INFO][_forceAutoClaim] claim pool=" # Principal.toText(cid) # " hasICP=" # debug_show(hasICP));
                    _poolMap.put(cid, { token0 = data.token0; token1 = data.token1; fee = data.fee; claimed = true; });
                    try {
                        let _ = await _claim(cid, canisterId, data);
                    } catch (e) {
                        _log("[ERROR][_forceAutoClaim] _claim threw pool=" # Principal.toText(cid) # " err=" # Error.message(e));
                        _tokenClaimLog.add({
                            timestamp = currentTime;
                            amount = 0;
                            poolId = cid;
                            token = { address = ""; standard = ""; };
                            errMsg = "Call _claim failed: " # debug_show (Error.message(e));
                        });
                    };

                    _finalizeClaimIntervalTimestamps(currentTime, true, true);
                    if (not _hasUnclaimedPool()) {
                        _log("[INFO][_forceAutoClaim] all pools claimed; scheduling _autoSwap");
                        ignore Timer.setTimer<system>(#seconds (_swapDelaySeconds), _autoSwap);
                    } else {
                        ignore Timer.setTimer<system>(#nanoseconds (1), _forceAutoClaim);
                    };
                    return;
                };
            };

            _log("[INFO][_forceAutoClaim] no unclaimed pools found; scheduling _autoSwap");
            _finalizeClaimIntervalTimestamps(currentTime, true, true);
            ignore Timer.setTimer<system>(#seconds (_swapDelaySeconds), _autoSwap);
        } catch (e) {
            _log("[ERROR][_forceAutoClaim] exception: " # Error.message(e) # " - retry in 3600s");
            _tokenClaimLog.add({
                timestamp = BlockTimestamp.blockTimestamp();
                amount = 0;
                poolId = Principal.fromText("aaaaa-aa");
                token = { address = ""; standard = ""; };
                errMsg = "_forceAutoClaim failed: " # debug_show (Error.message(e));
            });
            // Retry after 1 hour
            ignore Timer.setTimer<system>(#seconds(3600), _forceAutoClaim);
        };
    };
    
    private func _autoClaim() : async () {
        try {
            let currentTime = BlockTimestamp.blockTimestamp();

            // Check if we should claim ICP pools (30 days interval)
            let shouldClaimICPPools = currentTime >= (_icpPoolClaimInterval + _lastICPPoolClaimTime);

            // Only check non-ICP pools when ICP pools need to be claimed
            // If non-ICP pools haven't been claimed for 180 days, claim all pools together
            let shouldClaimNoICPPools = shouldClaimICPPools and (currentTime >= (_noIcpPoolClaimInterval + _lastNoICPPoolClaimTime));

            _log("[INFO][_autoClaim] tick: now=" # Nat.toText(currentTime)
                # " lastICP=" # Nat.toText(_lastICPPoolClaimTime)
                # " lastNoICP=" # Nat.toText(_lastNoICPPoolClaimTime)
                # " shouldClaimICP=" # debug_show(shouldClaimICPPools)
                # " shouldClaimNoICP=" # debug_show(shouldClaimNoICPPools));

            var canisterId = switch (_canisterId) {
                case(?p){ p };
                case(_) {
                    _log("[ERROR][_autoClaim] skip: _canisterId uninitialized (call setCanisterId)");
                    _isSyncing := false;
                    return;
                };
            };

            // If ICP pools don't need to be claimed, don't process any pools
            if (not shouldClaimICPPools) {
                _log("[INFO][_autoClaim] skip: ICP interval not elapsed remaining="
                    # Nat.toText((_icpPoolClaimInterval + _lastICPPoolClaimTime) - currentTime) # "s");
                _isSyncing := false;
                return;
            };

            label claimLoop for ((cid, data) in _poolMap.entries()) {
                if (not data.claimed) {
                    let hasICP = _poolHasICP(data);

                    if (hasICP) {
                        // Always claim ICP pools when shouldClaimICPPools is true
                        _claimCycleHadICP := true;
                    } else {
                        // For non-ICP pools: only claim if 180 days have passed (checked when ICP pools are claimed)
                        if (not shouldClaimNoICPPools) {
                            continue claimLoop;
                        };
                        _claimCycleHadNoICP := true;
                    };

                    _log("[INFO][_autoClaim] claim pool=" # Principal.toText(cid) # " hasICP=" # debug_show(hasICP));
                    _poolMap.put(cid, { token0 = data.token0; token1 = data.token1; fee = data.fee; claimed = true; });
                    try {
                        let _ = await _claim(cid, canisterId, data);
                    } catch (e) {
                        _log("[ERROR][_autoClaim] _claim threw pool=" # Principal.toText(cid) # " err=" # Error.message(e));
                        _tokenClaimLog.add({
                            timestamp = currentTime;
                            amount = 0;
                            poolId = cid;
                            token = { address = ""; standard = ""; };
                            errMsg = "Call _claim failed: " # debug_show (Error.message(e));
                        });
                    };

                    _finalizeClaimIntervalTimestamps(currentTime, true, shouldClaimNoICPPools);
                    if (not _hasUnclaimedPoolInScope(shouldClaimNoICPPools)) {
                        _log("[INFO][_autoClaim] in-scope pools claimed (claimNoICP="
                            # debug_show(shouldClaimNoICPPools) # "); scheduling _autoSwap");
                        ignore Timer.setTimer<system>(#seconds (_swapDelaySeconds), _autoSwap);
                    } else {
                        ignore Timer.setTimer<system>(#nanoseconds (1), _autoClaim);
                    };
                    return;
                };
            };

            _log("[INFO][_autoClaim] no in-scope unclaimed pools; scheduling _autoSwap");
            _finalizeClaimIntervalTimestamps(currentTime, true, shouldClaimNoICPPools);
            ignore Timer.setTimer<system>(#seconds (_swapDelaySeconds), _autoSwap);
        } catch (e) {
            _log("[ERROR][_autoClaim] exception: " # Error.message(e) # " - retry in 3600s");
            _tokenClaimLog.add({
                timestamp = BlockTimestamp.blockTimestamp();
                amount = 0;
                poolId = Principal.fromText("aaaaa-aa");
                token = { address = ""; standard = ""; };
                errMsg = "_autoClaim failed: " # debug_show (Error.message(e));
            });
            // Retry after 1 hour
            ignore Timer.setTimer<system>(#seconds(3600), _autoClaim);
        };
    };

    private func _autoSyncPools() : async () {
        try {
            let currentTime = BlockTimestamp.blockTimestamp();
            let nextEligible = _lastSyncTime + _icpPoolClaimInterval;
            _log("[INFO][_autoSyncPools] tick: isSyncing=" # debug_show(_isSyncing)
                # " lastSyncTime=" # Nat.toText(_lastSyncTime)
                # " nextEligible=" # Nat.toText(nextEligible)
                # " now=" # Nat.toText(currentTime)
                # " icpInterval=" # Nat.toText(_icpPoolClaimInterval));

            if (_isSyncing) {
                _log("[INFO][_autoSyncPools] skip: already syncing (call resetSyncingFlag if stuck)");
                return;
            };
            if (_isForceSwapping) {
                _log("[INFO][_autoSyncPools] skip: force swap queue is running");
                return;
            };
            if (currentTime < nextEligible) {
                _log("[INFO][_autoSyncPools] skip: interval not elapsed remaining="
                    # Nat.toText(nextEligible - currentTime) # "s");
                return;
            };

            if (await _syncPools()) {
                if (_isSyncing) {
                    _log("[WARN][_autoSyncPools] skip after syncPools: isSyncing flipped true mid-flight");
                    return;
                };
                _isSyncing := true;
                _lastSyncTime := currentTime;
                _log("[INFO][_autoSyncPools] proceed: syncPools ok, scheduled _autoClaim, lastSyncTime="
                    # Nat.toText(currentTime));
                ignore Timer.setTimer<system>(#nanoseconds (0), _autoClaim);
            } else {
                _log("[ERROR][_autoSyncPools] syncPools returned false (factory.getPools failed)");
            };
        } catch (e) {
            _log("[ERROR][_autoSyncPools] exception: " # Error.message(e) # " - retry in 3600s");
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

    public shared ({ caller }) func setIcpPoolClaimInterval(interval: Nat) : async Result.Result<(), Types.Error> {
        _checkPermission(caller);
        if (interval < 3600) { return #err(#InternalError("Interval must be at least 3600 seconds (1 hour)")); };
        _icpPoolClaimInterval := interval;
        return #ok();
    };

    public shared ({ caller }) func setNoIcpPoolClaimInterval(interval: Nat) : async Result.Result<(), Types.Error> {
        _checkPermission(caller);
        if (interval < 3600) { return #err(#InternalError("Interval must be at least 3600 seconds (1 hour)")); };
        _noIcpPoolClaimInterval := interval;
        return #ok();
    };

    public shared ({ caller }) func setAutoSwapToIcsEnabled(enabled: Bool) : async Result.Result<(), Types.Error> {
        _checkPermission(caller);
        _autoSwapToIcsEnabled := enabled;
        return #ok();
    };

    public shared ({ caller }) func setAutoBurnIcsEnabled(enabled: Bool) : async Result.Result<(), Types.Error> {
        _checkPermission(caller);
        _autoBurnIcsEnabled := enabled;
        return #ok();
    };

    public shared ({ caller }) func setSwapProtectionConfig(config : Types.SwapProtectionConfig) : async Result.Result<(), Types.Error> {
        _checkPermission(caller);
        if (config.slippageBps > 5000) { return #err(#InternalError("slippageBps must be at most 5000")); };
        if (config.maxPriceDeviationBps > 5000) { return #err(#InternalError("maxPriceDeviationBps must be at most 5000")); };
        if (config.refPriceMaxAgeSeconds <= config.swapDelaySeconds) {
            return #err(#InternalError("refPriceMaxAgeSeconds must be greater than swapDelaySeconds"));
        };
        _swapSlippageBps := config.slippageBps;
        _maxPriceDeviationBps := config.maxPriceDeviationBps;
        _swapDelaySeconds := config.swapDelaySeconds;
        _refPriceMaxAgeSeconds := config.refPriceMaxAgeSeconds;
        return #ok();
    };

    public query func getSwapProtectionConfig() : async Result.Result<Types.SwapProtectionConfig, Types.Error> {
        return #ok({
            slippageBps = _swapSlippageBps;
            maxPriceDeviationBps = _maxPriceDeviationBps;
            swapDelaySeconds = _swapDelaySeconds;
            refPriceMaxAgeSeconds = _refPriceMaxAgeSeconds;
        });
    };

    public shared ({ caller }) func resetSyncingFlag() : async () {
        _checkPermission(caller);
        _isSyncing := false;
        _isForceSwapping := false;
    };

    public shared ({ caller }) func forceReleaseLock() : async () {
        _checkPermission(caller);
        _releaseLock();
    };

    public query func getConfig() : async Result.Result<{
        icpPoolClaimInterval: Nat;
        noIcpPoolClaimInterval: Nat;
        deploymentTime: Nat;
        autoSwapToIcsEnabled: Bool;
        autoBurnEnabled: Bool;
    }, Types.Error> {
        return #ok({
            icpPoolClaimInterval = _icpPoolClaimInterval;
            noIcpPoolClaimInterval = _noIcpPoolClaimInterval;
            deploymentTime = _deploymentTime;
            autoSwapToIcsEnabled = _autoSwapToIcsEnabled;
            autoBurnEnabled = _autoBurnIcsEnabled;
        });
    };

    private var _claimSwapFeeRepurchaseDaily = Timer.recurringTimer<system>(#seconds(86400), _autoSyncPools); // 24 hours

    // --------------------------- Version Control ------------------------------------
    private var _version : Text = "3.7.0";
    public query func getVersion() : async Text { _version };

    system func preupgrade() {
        _tokenClaimLogArray := Buffer.toArray(_tokenClaimLog);
        _tokenSwapLogArray := Buffer.toArray(_tokenSwapLog);
        _tokenBurnLogArray := Buffer.toArray(_tokenBurnLog);
        let _logSize = _debugLog.size();
        if (_logSize == _MAX_DEBUG_LOGS) {
            _debugLogArray := Array.tabulate<Text>(_logSize, func(i : Nat) : Text {
                _debugLog.get((_debugLogWriteIndex + i) % _MAX_DEBUG_LOGS)
            });
        } else {
            _debugLogArray := Buffer.toArray(_debugLog);
        };
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
        _debugLog := Buffer.fromArray(_debugLogArray);
        _debugLogWriteIndex := _debugLog.size();
        _debugLogArray := [];
        _locked := false;
        _isSyncing := false;
    };

    system func inspect({
        arg : Blob;
        caller : Principal;
        msg : Types.SwapFeeReceiverMsg;
    }) : Bool {
        return switch (msg) {
            // Controller
            case (#burnICS _)                   { Prim.isController(caller) };
            case (#claim _)                     { Prim.isController(caller) };
            case (#forceAutoClaim _)            { Prim.isController(caller) };
            case (#getDebugLog _)               { Prim.isController(caller) };
            case (#setFees _)                   { Prim.isController(caller) };
            case (#setCanisterId _)             { Prim.isController(caller) };
            case (#setIcpPoolClaimInterval _)   { Prim.isController(caller) };
            case (#setNoIcpPoolClaimInterval _) { Prim.isController(caller) };
            case (#setAutoSwapToIcsEnabled _)   { Prim.isController(caller) };
            case (#setAutoBurnIcsEnabled _)     { Prim.isController(caller) };
            case (#startAutoSyncPools _)        { Prim.isController(caller) };
            case (#swapICPToICS _)              { Prim.isController(caller) };
            case (#swapToICP _)                 { Prim.isController(caller) };
            case (#swapWithoutDeposit _)        { Prim.isController(caller) };
            case (#transfer _)                  { Prim.isController(caller) };
            case (#transferAll _)               { Prim.isController(caller) };
            case (#resetSyncingFlag _)          { Prim.isController(caller) };
            case (#forceReleaseLock _)          { Prim.isController(caller) };
            case (#setSwapProtectionConfig _)   { Prim.isController(caller) };
            case (#forceSwapToICP _)            { Prim.isController(caller) };
            case (#forceSwapICPToICS _)         { Prim.isController(caller) };
            case (#forceSwapSkippedTokens _)    { Prim.isController(caller) };
            // Anyone
            case (_) { true };
        };
    };
};
