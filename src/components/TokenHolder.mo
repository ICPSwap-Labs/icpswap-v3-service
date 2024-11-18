import Nat "mo:base/Nat";
import Principal "mo:base/Principal";
import HashMap "mo:base/HashMap";
import Iter "mo:base/Iter";
import Types "../Types";
import Func "../utils/Functions";

module TokenHolder {
    type TokenBalance = Types.TokenBalance;
    type Token = Types.Token;
    type BalanceEntry = (Principal, HashMap.HashMap<Token, TokenBalance>);
    type TokenBalanceEntry = (Token, TokenBalance);

    public type AccountBalance = {
        balance0: Nat;
        balance1: Nat;
    };
    public type State = {
        token0: Token;
        token1: Token;
        balances: [(Principal, AccountBalance)];
    };

    public class Service(initState: State) {
        private var _token0: Token = initState.token0;
        private var _token1: Token = initState.token1;
        private var _balances: HashMap.HashMap<Principal, AccountBalance> = HashMap.fromIter<Principal, AccountBalance>(initState.balances.vals(), 100000, Principal.equal, Principal.hash);
        func _isSupported(token: Token): Bool {
            return Func.tokenEqual(_token0, token) or Func.tokenEqual(_token1, token);
        };
        func _setBalance(principal: Principal, balance0: Nat, balance1: Nat) {
            if (balance0 == 0 and balance1 == 0) {
                _balances.delete(principal);
            } else {
                _balances.put(principal, { balance0 = balance0; balance1 = balance1; }: AccountBalance);
            };
        };
        public func getAllBalances(): HashMap.HashMap<Principal, AccountBalance> {
            _balances;
        };
        public func getBalances(account: Principal): AccountBalance {
            return switch(_balances.get(account)) {
                case (?ab) { ab };
                case (_) { {
                    balance0 = 0;
                    balance1 = 0;
                }: AccountBalance };
            };
        };
        public func getBalance(account: Principal, token: Token): Nat {
            if (not _isSupported(token)) {
                return 0;
            };
            return switch(_balances.get(account)) {
                case (?ab) {
                    if (Func.tokenEqual(_token0, token)) {
                        return ab.balance0;
                    } else {
                        return ab.balance1;
                    };
                };
                case (_) { 0 }
            };
        };
        public func swap(principal: Principal, fromToken: Token, fromAmount: Nat, toToken: Token, toAmount: Nat): Bool {
            if (not (_isSupported(fromToken) and _isSupported(toToken))) {
                return false;
            };
            if (withdraw(principal, fromToken, fromAmount)) {
                return deposit(principal, toToken, toAmount);
            } else {
                return false;
            };
        };
        public func deposit(principal: Principal, token: Token, amount: Nat): Bool {
            if (not (_isSupported(token))) {
                return false;
            };
            let (_amount0, _amount1) = if (Func.tokenEqual(_token0, token)) { (amount, 0) } else { (0, amount ) };
            switch(_balances.get(principal)) {
                case (?ab) {
                    _balances.put(principal, { balance0 = ab.balance0 + _amount0; balance1 = ab.balance1 + _amount1; }: AccountBalance);
                };
                case (_) {
                    _balances.put(principal, { balance0 = _amount0; balance1 = _amount1; }: AccountBalance);
                };
            };
            return true;
        };
        public func deposit2(principal: Principal, token0: Token, amount0: Nat, token1: Token, amount1: Nat): Bool {
            if (not (_isSupported(token0) and _isSupported(token1))) {
                return false;
            };
            let (_amount0, _amount1) = if (Func.tokenEqual(_token0, token0)) { (amount0, amount1) } else { (amount1, amount0 ) };
            switch(_balances.get(principal)) {
                case (?ab) {
                    _balances.put(principal, { balance0 = ab.balance0 + amount0; balance1 = ab.balance1 + amount1; }: AccountBalance);
                };
                case (_) {
                    _balances.put(principal, { balance0 = amount0; balance1 = amount1; }: AccountBalance);
                };
            };
            return true;
        };
        public func withdraw(principal: Principal, token: Token, amount: Nat): Bool {
            if (not _isSupported(token)) {
                return false;
            };
            switch(_balances.get(principal)) {
                case (?ab) {
                    let (_amount0, _amount1) = if (Func.tokenEqual(_token0, token)) { (amount, 0) } else { (0, amount ) };
                    if (ab.balance0 < _amount0 or ab.balance1 < _amount1) {
                        return false;
                    };
                    _setBalance(principal, Nat.sub(ab.balance0, _amount0), Nat.sub(ab.balance1, _amount1));
                    return true;
                };
                case (_) { return false; }
            };
        };
        public func withdraw2(principal: Principal, token0: Token, amount0: Nat, token1: Token, amount1: Nat): Bool {
            if (not (_isSupported(token0) and _isSupported(token1))) {
                return false;
            };
            switch(_balances.get(principal)) {
                case (?ab) { // HashMap.HashMap<Token, TokenBalance>
                    let (_amount0, _amount1) = if (Func.tokenEqual(_token0, token0)) { (amount0, amount1) } else { (amount1, amount0) };
                    if (ab.balance0 < _amount0 or ab.balance1 < _amount1) {
                        return false;
                    };
                    _setBalance(principal, Nat.sub(ab.balance0, _amount0), Nat.sub(ab.balance1, _amount1));
                    return true;
                };
                case (_) { return false; }
            };
        };
        public func getState(): State {
            return {
                token0 = _token0;
                token1 = _token1;
                balances = Iter.toArray(_balances.entries());
            };
        };
    }
}