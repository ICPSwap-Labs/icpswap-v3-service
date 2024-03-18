import Text "mo:base/Text";
import Nat "mo:base/Nat";
import Nat8 "mo:base/Nat8";
import Int "mo:base/Int";
import Hash "mo:base/Hash";
import List "mo:base/List";
import Principal "mo:base/Principal";
import Cycles "mo:base/ExperimentalCycles";
import Time "mo:base/Time";
import Timer "mo:base/Timer";
import Float "mo:base/Float";
import Debug "mo:base/Debug";
import Blob "mo:base/Blob";
import Buffer "mo:base/Buffer";
import HashMap "mo:base/HashMap";
import Error "mo:base/Error";
import Iter "mo:base/Iter";
import Option "mo:base/Option";
import Result "mo:base/Result";
import TokenAdapterTypes "mo:token-adapter/Types";
import TokenFactory "mo:token-adapter/TokenFactory";
import Types "./Types";
import AccountUtils "./utils/AccountUtils";
import Prim "mo:⛔";
import CollectionUtils "mo:commons/utils/CollectionUtils";

shared (initMsg) actor class SwapAgent(
    token0 : Types.Token,
    token1 : Types.Token,
    poolCid : Principal,
    governanceCid : Principal,
) = this {

    private let _poolAct = actor (Principal.toText(poolCid)) : Types.SwapPoolActor;
    private let _token0Act = TokenFactory.getAdapter(token0.address, token0.standard);
    private let _token1Act = TokenFactory.getAdapter(token1.address, token1.standard);

    public shared (msg) func transferToPoolSubAccount(token : Types.Token, amount : Nat, fee : Nat) : async Result.Result<Nat, Types.Error> {
        _checkAdminPermission(msg.caller);
        try {
            var canisterId = Principal.fromActor(this);
            var subaccount : ?Blob = Option.make(AccountUtils.principalToBlob(canisterId));
            let tokenAct = if (Text.equal("ICRC1", token.standard)) {
                if (Text.equal(token.address, token0.address)) { _token0Act }
                else if (Text.equal(token.address, token1.address)) { _token1Act }
                else { return #err(#InternalError("Invalid token address.")); };
            } else { return #err(#InternalError("Invalid token standard.")); };
            switch (await tokenAct.transfer({
                from = { owner = canisterId; subaccount = null }; 
                from_subaccount = null; 
                to = { owner = poolCid; subaccount = subaccount }; 
                amount = amount; fee = ?fee; 
                memo = null; created_at_time = null
             })) {
                case (#Ok(index)) { return #ok(index); };
                case (#Err(msg)) { return #err(#InternalError(debug_show (msg))); };
            };
        } catch (e) {
            return #err(#InternalError(debug_show (Error.message(e))));
        };
    };

    public shared (msg) func deposit(args : Types.DepositArgs) : async Result.Result<Nat, Types.Error> {
        _checkAdminPermission(msg.caller);
        await _poolAct.deposit(args);
    };

    public shared (msg) func approveToPool(token : Types.Token, amount : Nat, fee : Nat) : async Result.Result<Nat, Types.Error> {
        _checkAdminPermission(msg.caller);
        try {
            var canisterId = Principal.fromActor(this);
            let tokenAct = if (_checkApprovableStandard(token.standard)) {
                if (Text.equal(token.address, token0.address)) { _token0Act }
                else if (Text.equal(token.address, token1.address)) { _token1Act }
                else { return #err(#InternalError("Invalid token address.")); };
            } else { return #err(#InternalError("Invalid token standard.")); };
            switch (await tokenAct.approve({
                from_subaccount = null;
                spender = poolCid;
                amount = amount;
                fee = ?fee;
                memo = null;
                created_at_time = null;
             })) {
                case (#Ok(index)) { return #ok(index); };
                case (#Err(msg)) { return #err(#InternalError(debug_show (msg))); };
            };
        } catch (e) {
            return #err(#InternalError(debug_show (Error.message(e))));
        };
    };

    public shared (msg) func depositFrom(args : Types.DepositArgs) : async Result.Result<Nat, Types.Error> {
        _checkAdminPermission(msg.caller);
        await _poolAct.depositFrom(args);
    };

    public shared (msg) func withdraw(args : Types.WithdrawArgs) : async Result.Result<Nat, Types.Error> {
        _checkAdminPermission(msg.caller);
        await _poolAct.withdraw(args);
    };

    public shared (msg) func transferToGovernanceCid(token : Types.Token, amount : Nat, fee : Nat) : async Result.Result<Nat, Types.Error> {
        _checkAdminPermission(msg.caller);
        try {
            var canisterId = Principal.fromActor(this);
            let tokenAct = if (Text.equal(token.address, token0.address)) { _token0Act }
            else if (Text.equal(token.address, token1.address)) { _token1Act }
            else { return #err(#InternalError("Invalid token address.")); };
            switch (await tokenAct.transfer({
                from = { owner = canisterId; subaccount = null }; 
                from_subaccount = null; 
                to = { owner = governanceCid; subaccount = null }; 
                amount = amount; fee = ?fee; 
                memo = null; created_at_time = null
             })) {
                case (#Ok(index)) { return #ok(index); };
                case (#Err(msg)) { return #err(#InternalError(debug_show (msg))); };
            };
        } catch (e) {
            return #err(#InternalError(debug_show (Error.message(e))));
        };
    };

    public shared (msg) func mint(args : Types.MintArgs) : async Result.Result<Nat, Types.Error> {
        _checkAdminPermission(msg.caller);
        await _poolAct.mint(args);
    };

    public shared (msg) func increaseLiquidity(args : Types.IncreaseLiquidityArgs) : async Result.Result<Nat, Types.Error> {
        _checkAdminPermission(msg.caller);
        await _poolAct.increaseLiquidity(args);
    };
    
    public shared (msg) func decreaseLiquidity(args : Types.DecreaseLiquidityArgs) : async Result.Result<{ amount0 : Nat; amount1 : Nat }, Types.Error> {
        _checkAdminPermission(msg.caller);
        await _poolAct.decreaseLiquidity(args);
    };
    
    public shared (msg) func claim(args : Types.ClaimArgs) : async Result.Result<{ amount0 : Nat; amount1 : Nat }, Types.Error> {
        _checkAdminPermission(msg.caller);
        await _poolAct.claim(args);
    };
    
    public shared (msg) func swap(args : Types.SwapArgs) : async Result.Result<Nat, Types.Error> {
        _checkAdminPermission(msg.caller);
        await _poolAct.swap(args);
    };

    public shared (msg) func getUnusedBalance() : async Result.Result<{ balance0 : Nat; balance1 : Nat }, Types.Error> {
        await _poolAct.getUserUnusedBalance(Principal.fromActor(this));
    };

    public query func getInitArgs() : async Result.Result<{ token0 : Types.Token; token1 : Types.Token; poolCid : Principal; governanceCid : Principal }, Types.Error> {
        #ok({
            token0 = token0;
            token1 = token1;
            poolCid = poolCid;
            governanceCid = governanceCid;
        });
    };

    public query func getCycleInfo() : async Result.Result<Types.CycleInfo, Types.Error> {
        return #ok({
            balance = Cycles.balance();
            available = Cycles.available();
        });
    };

    private func _checkApprovableStandard(standard : Text) : Bool {
        if (
            Text.notEqual(standard, "DIP20") 
            and Text.notEqual(standard, "DIP20-WICP") 
            and Text.notEqual(standard, "DIP20-XTC") 
            and Text.notEqual(standard, "EXT") 
            and Text.notEqual(standard, "ICRC2") 
            and Text.notEqual(standard, "ICRC3") 
            and Text.notEqual(standard, "ICP")
        ) {
            return false;
        };
        return true;
    };

    // --------------------------- ACL ------------------------------------
    private stable var _admins : [Principal] = [];
    public shared (msg) func setAdmins(admins : [Principal]) : async () {
        _checkControllerPermission(msg.caller);
        _admins := admins;
    };
    public query (msg) func getAdmins() : async [Principal] {
        return _admins;
    };
    private func _checkControllerPermission(caller: Principal) {
        assert(Prim.isController(caller));
    };
    private func _checkAdminPermission(caller: Principal) {
        assert(
            CollectionUtils.arrayContains<Principal>(_admins, caller, Principal.equal) 
            or 
            Principal.equal(caller, governanceCid)
            or 
            Prim.isController(caller)
        );
    };

    // --------------------------- LIFE CYCLE -----------------------------------
    system func preupgrade() {};

    system func postupgrade() {};
};
