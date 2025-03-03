import Principal "mo:base/Principal";
import Buffer "mo:base/Buffer";
import Array "mo:base/Array";
import Nat "mo:base/Nat";
import HashMap "mo:base/HashMap";
import Result "mo:base/Result";
import Option "mo:base/Option";
import Time "mo:base/Time";
import Error "mo:base/Error";
import Cycles "mo:base/ExperimentalCycles";
import Iter "mo:base/Iter";
import TokenAdapterTypes "mo:token-adapter/Types";
import TokenFactory "mo:token-adapter/TokenFactory";
import AccountUtils "./utils/AccountUtils";
import PoolUtils "./utils/PoolUtils";
import Types "./Types";

actor class PasscodeManager(
    tokenCid : Principal,
    passcodePrice : Nat,
    factoryCid : Principal,
    governanceCid : Principal,
) = this {

    public type Result = {
        #Ok : Text;
        #Err : Text;
    };
    public type DepositArgs = {
        amount : Nat;
        fee : Nat;
    };
    public type WithdrawArgs = {
        fee : Nat;
        amount : Nat;
    };
    public type TokenFrozen = {
        amount : Nat;
        timestamp : Time.Time;
        passcode : { token0 : Principal; token1 : Principal; fee : Nat };
    };
    public type Wallet = {
        balance : Nat;
        frozens : [TokenFrozen];
    };
    public type LogEntry = {
        timestamp : Int;
        caller : Principal;
        message : Text;
        amount : ?Nat; // Optional amount field
    };
    private let TOKEN : TokenAdapterTypes.TokenAdapter = TokenFactory.getAdapter(Principal.toText(tokenCid), "ICRC2");
    private let FACTORY = actor (Principal.toText(factoryCid)) : Types.SwapFactoryActor;
    private stable var _walletArray : [(Principal, Nat)] = [];
    private var _wallet : HashMap.HashMap<Principal, Nat> = HashMap.fromIter(_walletArray.vals(), _walletArray.size(), Principal.equal, Principal.hash);
    private stable var _transferIndex : Nat = 0;

    // Logging related code
    private let MAX_LOGS = 5000;
    private stable var _logsArray : [LogEntry] = [];
    private var _logs : Buffer.Buffer<LogEntry> = Buffer.fromArray<LogEntry>(_logsArray);
    private func _addLog(caller : Principal, message : Text, amount : ?Nat) {
        if (_logs.size() >= MAX_LOGS) {
            ignore _logs.remove(0); // Remove oldest log
        };
        _logs.add({
            timestamp = Time.now();
            caller = caller;
            message = message;
            amount = amount;
        });
    };

    private func _walletDeposit(principal : Principal, amount : Nat) {
        switch (_wallet.get(principal)) {
            case (?bal) {
                _wallet.put(principal, Nat.add(bal, amount));
            };
            case (_) {
                _wallet.put(principal, amount);
            };
        };
    };

    private func _walletWithdraw(principal : Principal, amount : Nat) : Bool {
        switch (_wallet.get(principal)) {
            case (?bal) {
                if (Nat.greaterOrEqual(bal, amount)) {
                    let balance = Nat.sub(bal, amount);
                    if (Nat.equal(balance, 0)) {
                        _wallet.delete(principal);
                    } else {
                        _wallet.put(principal, balance);
                    };
                    return true;
                } else {
                    return false;
                };
            };
            case (_) {
                return false;
            };
        };
    };

    private func _walletBalanceOf(principal : Principal) : Nat {
        switch (_wallet.get(principal)) {
            case (?bal) {
                return bal;
            };
            case (_) { return 0 };
        };
    };

    public shared ({ caller }) func deposit(args : DepositArgs) : async Result.Result<Nat, Types.Error> {
        if (Principal.isAnonymous(caller)) return #err(#InternalError("Illegal anonymous call"));
        var canisterId = Principal.fromActor(this);
        var subaccount : ?Blob = Option.make(AccountUtils.principalToBlob(caller));
        if (Option.isNull(subaccount)) {
            return #err(#InternalError("Subaccount can't be null"));
        };
        if (not (args.amount > 0)) { return #err(#InsufficientFunds) };
        if (not (args.amount > args.fee)) { return #err(#InsufficientFunds) };
        var amount : Nat = Nat.sub(args.amount, args.fee);
        _transferIndex := _transferIndex + 1;
        try {
            switch (await TOKEN.transfer({ from = { owner = canisterId; subaccount = subaccount }; from_subaccount = subaccount; to = { owner = canisterId; subaccount = null }; amount = amount; fee = ?args.fee; memo = Option.make(PoolUtils.natToBlob(_transferIndex)); created_at_time = null })) {
                case (#Ok(_)) {
                    _walletDeposit(caller, amount);
                    return #ok(amount);
                };
                case (#Err(msg)) {
                    return #err(#InternalError(debug_show (msg)));
                };
            };
        } catch (e) {
            let msg : Text = debug_show (Error.message(e));
            return #err(#InternalError(msg));
        };
    };

    public shared ({ caller }) func depositFrom(args : DepositArgs) : async Result.Result<Nat, Types.Error> {
        if (Principal.isAnonymous(caller)) return #err(#InternalError("Illegal anonymous call"));
        var canisterId = Principal.fromActor(this);
        if (Principal.equal(caller, canisterId)) {
            return #err(#InternalError("Caller and canister id can't be the same"));
        };
        _transferIndex := _transferIndex + 1;
        try {
            switch (await TOKEN.transferFrom({ from = { owner = caller; subaccount = null }; to = { owner = canisterId; subaccount = null }; amount = args.amount; fee = ?args.fee; memo = Option.make(PoolUtils.natToBlob(_transferIndex)); created_at_time = null })) {
                case (#Ok(_)) {
                    _walletDeposit(caller, args.amount);
                    return #ok(args.amount);
                };
                case (#Err(msg)) {
                    return #err(#InternalError(debug_show (msg)));
                };
            };
        } catch (e) {
            let msg : Text = debug_show (Error.message(e));
            return #err(#InternalError(msg));
        };
    };

    public shared ({ caller }) func withdraw(args : WithdrawArgs) : async Result.Result<Nat, Types.Error> {
        if (Principal.isAnonymous(caller)) return #err(#InternalError("Illegal anonymous call"));
        if (AccountUtils.isEmptyIdentity(caller)) {
            return #err(#InternalError("Do not accept anonymous calls"));
        };
        var canisterId = Principal.fromActor(this);
        var balance : Nat = _walletBalanceOf(caller);
        if (not (balance > 0)) { return #err(#InsufficientFunds) };
        if (not (args.amount > 0)) {
            return #err(#InternalError("Amount can not be 0"));
        };
        if (args.amount > balance) { return #err(#InsufficientFunds) };
        if (not (args.amount > args.fee)) { return #err(#InsufficientFunds) };
        var amount : Nat = Nat.sub(args.amount, args.fee);
        if (_walletWithdraw(caller, args.amount)) {
            _transferIndex := _transferIndex + 1;
            try {
                switch (await TOKEN.transfer({ from = { owner = canisterId; subaccount = null }; from_subaccount = null; to = { owner = caller; subaccount = null }; amount = amount; fee = ?args.fee; memo = Option.make(PoolUtils.natToBlob(_transferIndex)); created_at_time = null })) {
                    case (#Ok(_)) {
                        return #ok(amount);
                    };
                    case (#Err(msg)) {
                        return #err(#InternalError(debug_show (msg)));
                    };
                };
            } catch (e) {
                let msg : Text = debug_show (Error.message(e));
                return #err(#InternalError(msg));
            };
        } else {
            return #err(#InsufficientFunds);
        };
    };

    public shared ({ caller }) func requestPasscode(token0 : Principal, token1 : Principal, fee : Nat) : async Result.Result<Text, Types.Error> {
        if (Principal.isAnonymous(caller)) return #err(#InternalError("Illegal anonymous call"));
        if (_walletWithdraw(caller, passcodePrice)) {
            let (sortedToken0, sortedToken1) = if (Principal.toText(token0) > Principal.toText(token1)) {
                (token1, token0);
            } else { (token0, token1) };
            try {
                switch (
                    await FACTORY.addPasscode(
                        caller,
                        {
                            token0 = sortedToken0;
                            token1 = sortedToken1;
                            fee = fee;
                        },
                    )
                ) {
                    case (#ok()) {
                        _addLog(
                            caller,
                            "FACTORY.addPasscode " # Principal.toText(sortedToken0) # " " # Principal.toText(sortedToken1) # " " # debug_show (fee) # " ok",
                            ?passcodePrice,
                        );
                        return #ok("ok")
                    };
                    case (#err(msg)) {  
                        _addLog(
                            caller,
                            "FACTORY.addPasscode error: " # debug_show (msg),
                            ?passcodePrice,
                        );
                        _walletDeposit(caller, passcodePrice);
                        return #err(#InternalError(debug_show (msg)));
                    };
                };
            } catch (e) {
                _addLog(
                    caller,
                    "FACTORY.addPasscode error: " # Error.message(e),
                    ?passcodePrice,
                );
                return #err(#InternalError(debug_show (Error.message(e))));
            };
        } else {
            return #err(#InsufficientFunds);
        };
    };

    public shared ({ caller }) func destoryPasscode(token0 : Principal, token1 : Principal, fee : Nat) : async Result.Result<Text, Types.Error> {
        if (Principal.isAnonymous(caller)) return #err(#InternalError("Illegal anonymous call"));
        switch (
            await FACTORY.deletePasscode(
                caller,
                {
                    token0 = token0;
                    token1 = token1;
                    fee = fee;
                },
            )
        ) {
            case (#ok()) {
                _addLog(
                    caller,
                    "FACTORY.deletePasscode " # Principal.toText(token0) # " " # Principal.toText(token1) # " " # debug_show (fee) # " ok",
                    ?passcodePrice,
                );
                _walletDeposit(caller, passcodePrice);
                return #ok("ok");
            };
            case (#err(msg)) {
                _addLog(
                    caller,
                    "FACTORY.deletePasscode error: " # debug_show (msg),
                    ?passcodePrice,
                );
                return #err(#InternalError(debug_show (msg)));
            };
        };
    };

    public shared ({ caller }) func transferValidate(recipient : Principal, value : Nat) : async Result {
        assert (Principal.equal(caller, governanceCid));
        var fee : Nat = await TOKEN.fee();
        var balance : Nat = await TOKEN.balanceOf({
            owner = Principal.fromActor(this);
            subaccount = null;
        });
        if (Principal.equal(recipient, Principal.fromActor(this))) {
            return #Err("Cannot transfer to the current canister.");
        };
        if (value <= fee) {
            return #Err("The transfer amount needs to be greater than fee.");
        };
        if (balance < value) {
            return #Err("The transfer amount needs to be less than balance.");
        };
        return #Ok(debug_show (recipient) # ", " # debug_show (value));
    };

    public shared ({ caller }) func transfer(recipient : Principal, value : Nat) : async Result.Result<Nat, Types.Error> {
        assert (Principal.equal(caller, governanceCid));
        var fee : Nat = await TOKEN.fee();
        var balance : Nat = await TOKEN.balanceOf({
            owner = Principal.fromActor(this);
            subaccount = null;
        });
        if (Principal.equal(recipient, Principal.fromActor(this))) {
            return #err(#InternalError("Can not transfer to the current canister."));
        };
        if (value <= fee) {
            return #err(#InternalError("The transfer amount needs to be greater than fee."));
        };
        if (balance < value) {
            return #err(#InternalError("The transfer amount needs to be less than balance."));
        };
        var amount : Nat = Nat.sub(value, fee);
        try {
            switch (await TOKEN.transfer({ from = { owner = Principal.fromActor(this); subaccount = null }; from_subaccount = null; to = { owner = recipient; subaccount = null }; amount = amount; fee = ?fee; memo = null; created_at_time = null })) {
                case (#Ok(_)) { return #ok(amount) };
                case (#Err(msg)) {
                    return #err(#InternalError(debug_show (msg)));
                };
            };
            return #ok(amount);
        } catch (e) {
            let msg : Text = debug_show (Error.message(e));
            _addLog(
                caller,
                "TOKEN.transfer error: " # Error.message(e),
                ?amount,
            );
            return #err(#InternalError(msg));
        };
    };

    public shared func getCycleInfo() : async Result.Result<Types.CycleInfo, Types.Error> {
        return #ok({
            balance = Cycles.balance();
            available = Cycles.available();
        });
    };

    public query func balanceOf(principal : Principal) : async Nat {
        return _walletBalanceOf(principal);
    };

    public query func balances() : async [(Principal, Nat)] {
        return Iter.toArray(_wallet.entries());
    };

    public query func metadata() : async {
        tokenCid : Principal;
        factoryCid : Principal;
        passcodePrice : Nat;
        governanceCid : Principal;
    } {
        return {
            tokenCid = tokenCid;
            factoryCid = factoryCid;
            passcodePrice = passcodePrice;
            governanceCid = governanceCid;
        };
    };

    public query func getLogs(count : ?Nat) : async [LogEntry] {
        let logs = Buffer.toArray(_logs);
        switch (count) {
            case (null) { logs };
            case (?n) {
                let size = logs.size();
                let start = if (size > n) { size - n } else { 0 };
                Array.tabulate(size - start, func(i : Nat) : LogEntry = logs[start + i]);
            };
        };
    };

    // --------------------------- Version Control ------------------------------------
    private var _version : Text = "3.5.0";
    public query func getVersion() : async Text { _version };

    system func preupgrade() {
        _walletArray := Iter.toArray(_wallet.entries());
        _logsArray := Buffer.toArray(_logs);
    };

    system func postupgrade() {
        _walletArray := [];
        _logsArray := [];
    };
};
