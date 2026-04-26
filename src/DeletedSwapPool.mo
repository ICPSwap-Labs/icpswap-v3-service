import Nat "mo:base/Nat";
import Buffer "mo:base/Buffer";
import Cycles "mo:base/ExperimentalCycles";
import Principal "mo:base/Principal";
import Error "mo:base/Error";
import Timer "mo:base/Timer";

import Types "./Types";
import TokenAdapterTypes "mo:token-adapter/Types";
import TokenFactory "mo:token-adapter/TokenFactory";
import TokenHolder "./components/TokenHolder";
import PoolUtils "./utils/PoolUtils";

shared (initMsg) actor class DeletedSwapPool(
    token0 : Types.Token,
    token1 : Types.Token,
) = this {

    private stable var _controller: Principal = Principal.fromText("hw447-5yiq7-3pttp-lzs2z-avadx-v7ip6-i4sob-q77eu-x6ra5-nuuk7-7qe");
    private stable var _feeReceiver: Principal = Principal.fromText("cbkxt-gaaaa-aaaag-qcs4a-cai");
    private stable var _cyclesReceiver: Principal = Principal.fromText("pb4qt-haaaa-aaaar-qal2q-cai");

    private stable var _token0 : Types.Token = PoolUtils.sort(token0, token1).0;
    private stable var _token1 : Types.Token = PoolUtils.sort(token0, token1).1;

    private var _token0Act : TokenAdapterTypes.TokenAdapter = TokenFactory.getAdapter(_token0.address, _token0.standard);
    private var _token1Act : TokenAdapterTypes.TokenAdapter = TokenFactory.getAdapter(_token1.address, _token1.standard);

    // Preserved from SwapPool upgrade — contains all user unused balances
    private stable var _tokenHolderState : TokenHolder.State = { token0 = _token0; token1 = _token1; balances = []; };

    // Refund state
    private stable var _refundIndex : Nat = 0;
    private stable var _isRefunding : Bool = false;
    private stable var _refundLog : [Text] = [];
    private var _refundLogBuffer : Buffer.Buffer<Text> = Buffer.fromArray(_refundLog);
    private stable var _failedRefunds : [(Principal, { balance0 : Nat; balance1 : Nat })] = [];
    private var _token0Fee : Nat = 0;
    private var _token1Fee : Nat = 0;

    private type deposit_cycles_args = { canister_id : Principal; };
    private let _ic = actor "aaaaa-aa" : actor { deposit_cycles : (deposit_cycles_args) -> async (); };

    // Step 1: Start refunding user balances one at a time
    public shared ({ caller }) func refundAll() : async Text {
        if (not Principal.equal(caller, _controller)) {
            return "error=Only controller can refund.";
        };
        if (_isRefunding) {
            return "error=Refund already in progress. index=" # Nat.toText(_refundIndex) # "/" # Nat.toText(_tokenHolderState.balances.size());
        };
        let balances = _tokenHolderState.balances;
        if (balances.size() == 0) {
            return "No balances to refund.";
        };
        try { _token0Fee := await _token0Act.fee(); } catch (_) {};
        try { _token1Fee := await _token1Act.fee(); } catch (_) {};
        _refundIndex := 0;
        _isRefunding := true;
        ignore Timer.setTimer<system>(#nanoseconds(0), _processRefund);
        return "Refund started. total=" # Nat.toText(balances.size());
    };

    private func _processRefund() : async () {
        let balances = _tokenHolderState.balances;
        if (_refundIndex >= balances.size()) {
            _isRefunding := false;
            let failedCount = _failedRefunds.size();
            _refundLogBuffer.add("Refund completed. total=" # Nat.toText(balances.size()) # " failed=" # Nat.toText(failedCount));
            return;
        };
        let (user, ab) = balances[_refundIndex];
        var r0 : Nat = 0;
        var r1 : Nat = 0;
        var err0 : Text = "";
        var err1 : Text = "";
        // Track remaining balance for this user after refund attempts
        var remaining0 : Nat = ab.balance0;
        var remaining1 : Nat = ab.balance1;

        if (ab.balance0 > _token0Fee) {
            let amount0 = ab.balance0 - _token0Fee;
            try {
                switch (await _token0Act.transfer({
                    from = { owner = Principal.fromActor(this); subaccount = null };
                    from_subaccount = null;
                    to = { owner = user; subaccount = null };
                    amount = amount0;
                    fee = ?_token0Fee;
                    memo = null;
                    created_at_time = null;
                })) {
                    case (#Ok(_)) { r0 := amount0; remaining0 := 0; };
                    case (#Err(msg)) { err0 := debug_show(msg); };
                };
            } catch (e) { err0 := Error.message(e); };
        } else { remaining0 := 0; };

        if (ab.balance1 > _token1Fee) {
            let amount1 = ab.balance1 - _token1Fee;
            try {
                switch (await _token1Act.transfer({
                    from = { owner = Principal.fromActor(this); subaccount = null };
                    from_subaccount = null;
                    to = { owner = user; subaccount = null };
                    amount = amount1;
                    fee = ?_token1Fee;
                    memo = null;
                    created_at_time = null;
                })) {
                    case (#Ok(_)) { r1 := amount1; remaining1 := 0; };
                    case (#Err(msg)) { err1 := debug_show(msg); };
                };
            } catch (e) { err1 := Error.message(e); };
        } else { remaining1 := 0; };

        // If any token failed to refund, preserve the remaining balance
        if (remaining0 > 0 or remaining1 > 0) {
            _failedRefunds := _appendFailedRefund(_failedRefunds, user, remaining0, remaining1);
        };

        _refundLogBuffer.add("["  # Nat.toText(_refundIndex) # "] user=" # Principal.toText(user)
            # " refunded0=" # Nat.toText(r0)
            # " refunded1=" # Nat.toText(r1)
            # (if (err0 != "") { " err0=" # err0 } else { "" })
            # (if (err1 != "") { " err1=" # err1 } else { "" }));

        _refundIndex += 1;
        ignore Timer.setTimer<system>(#nanoseconds(500_000_000), _processRefund);
    };

    private func _appendFailedRefund(
        arr : [(Principal, { balance0 : Nat; balance1 : Nat })],
        user : Principal, balance0 : Nat, balance1 : Nat
    ) : [(Principal, { balance0 : Nat; balance1 : Nat })] {
        let buf = Buffer.fromArray<(Principal, { balance0 : Nat; balance1 : Nat })>(arr);
        buf.add((user, { balance0 = balance0; balance1 = balance1 }));
        Buffer.toArray(buf);
    };

    // Retry failed refunds
    public shared ({ caller }) func retryFailedRefunds() : async Text {
        if (not Principal.equal(caller, _controller)) {
            return "error=Only controller can retry refunds.";
        };
        if (_isRefunding) {
            return "error=Refund still in progress. Wait for completion.";
        };
        if (_failedRefunds.size() == 0) {
            return "No failed refunds to retry.";
        };
        // Move failed refunds into balances and restart
        _tokenHolderState := { token0 = _token0; token1 = _token1; balances = _failedRefunds; };
        _failedRefunds := [];
        _refundIndex := 0;
        _isRefunding := true;
        try { _token0Fee := await _token0Act.fee(); } catch (_) {};
        try { _token1Fee := await _token1Act.fee(); } catch (_) {};
        ignore Timer.setTimer<system>(#nanoseconds(0), _processRefund);
        return "Retry started. total=" # Nat.toText(_tokenHolderState.balances.size());
    };

    // Query: view failed refunds
    public query ({ caller }) func getFailedRefunds() : async [(Principal, { balance0 : Nat; balance1 : Nat })] {
        assert(Principal.equal(caller, _controller));
        _failedRefunds;
    };

    // Step 2: Transfer remaining tokens to fee receiver
    public shared ({ caller }) func transferAll() : async Text {
        if (not Principal.equal(caller, _controller)) {
            return "error=Only controller can transfer all tokens.";
        };
        if (_isRefunding) {
            return "error=Refund still in progress. Wait for completion.";
        };
        if (_failedRefunds.size() > 0) {
            return "error=Failed refunds pending (" # Nat.toText(_failedRefunds.size()) # " users). Retry or resolve before transferAll.";
        };
        var token0_transferred : Nat = 0;
        var token1_transferred : Nat = 0;
        var token0_error : Text = "";
        var token1_error : Text = "";
        try {
            var value0 : Nat = await _token0Act.balanceOf({ owner = Principal.fromActor(this); subaccount = null; });
            var fee0 : Nat = await _token0Act.fee();
            if (value0 > 2 * fee0) {
                var amount0 : Nat = Nat.sub(value0, fee0);
                switch (await _token0Act.transfer({ from = { owner = Principal.fromActor(this); subaccount = null }; from_subaccount = null; to = { owner = _feeReceiver; subaccount = null }; amount = amount0; fee = ?fee0; memo = null; created_at_time = null })) {
                    case (#Ok(_)) { token0_transferred := amount0; };
                    case (#Err(msg)) { token0_error := debug_show(msg); };
                };
            };
        } catch (e) {
            token0_error := Error.message(e);
        };
        try {
            var value1 : Nat = await _token1Act.balanceOf({ owner = Principal.fromActor(this); subaccount = null; });
            var fee1 : Nat = await _token1Act.fee();
            if (value1 > 2 * fee1) {
                var amount1 : Nat = Nat.sub(value1, fee1);
                switch (await _token1Act.transfer({ from = { owner = Principal.fromActor(this); subaccount = null }; from_subaccount = null; to = { owner = _feeReceiver; subaccount = null }; amount = amount1; fee = ?fee1; memo = null; created_at_time = null })) {
                    case (#Ok(_)) { token1_transferred := amount1; };
                    case (#Err(msg)) { token1_error := debug_show(msg); };
                };
            };
        } catch (e) {
            token1_error := Error.message(e);
        };
        var r = "token0_transferred=" # Nat.toText(token0_transferred) # " token1_transferred=" # Nat.toText(token1_transferred);
        if (token0_error != "") { r := r # " token0_error=" # token0_error; };
        if (token1_error != "") { r := r # " token1_error=" # token1_error; };
        return r;
    };

    // Step 3: Recycle cycles
    public shared ({ caller }) func recycle() : async Text {
        if (not Principal.equal(caller, _controller)) {
            return "error=Only controller can recycle cycles.";
        };
        if (_isRefunding) {
            return "error=Refund still in progress. Wait for completion.";
        };
        if (_failedRefunds.size() > 0) {
            return "error=Failed refunds pending (" # Nat.toText(_failedRefunds.size()) # " users). Resolve before recycling.";
        };
        let balance = Cycles.balance();
        if (balance > 1000000000000) {
            let to_recycle = balance - 50000000000;
            Cycles.add<system>(to_recycle);
            await _ic.deposit_cycles({ canister_id = _cyclesReceiver; });
            return "cycles_recycled=" # Nat.toText(to_recycle) # " cycles_remaining=50000000000";
        };
        return "cycles_recycled=0 cycles_remaining=" # Nat.toText(balance);
    };

    // Query: refund progress
    public query func getRefundStatus() : async { isRefunding : Bool; index : Nat; total : Nat } {
        { isRefunding = _isRefunding; index = _refundIndex; total = _tokenHolderState.balances.size(); };
    };

    // Query: view remaining user balances (controller only)
    public query ({ caller }) func getRemainingBalances() : async [(Principal, { balance0 : Nat; balance1 : Nat })] {
        assert(Principal.equal(caller, _controller));
        _tokenHolderState.balances;
    };

    // Query: view refund log (controller only)
    public query ({ caller }) func getRefundLog() : async [Text] {
        assert(Principal.equal(caller, _controller));
        Buffer.toArray(_refundLogBuffer);
    };

    public shared func getCycleInfo() : async { balance : Nat; available : Nat } {
        { balance = Cycles.balance(); available = Cycles.available(); };
    };

    system func preupgrade() {
        _refundLog := Buffer.toArray(_refundLogBuffer);
    };

    system func postupgrade() {
        _refundLogBuffer := Buffer.fromArray(_refundLog);
        _refundLog := [];
        // Resume refunding if interrupted by upgrade — refresh fee cache first
        if (_isRefunding) {
            ignore Timer.setTimer<system>(#nanoseconds(0), func() : async () {
                try { _token0Fee := await _token0Act.fee(); } catch (_) {};
                try { _token1Fee := await _token1Act.fee(); } catch (_) {};
                await _processRefund();
            });
        };
    };
};
