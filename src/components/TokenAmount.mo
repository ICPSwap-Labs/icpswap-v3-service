import Principal "mo:base/Principal";
import Int "mo:base/Int";
import Hash "mo:base/Hash";
import HashMap "mo:base/HashMap";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";
import Types "../Types";

module TokenAmount {

    public type State = {
        tokenAmount0 : Nat;
        tokenAmount1 : Nat;
        swapFee0Repurchase : Nat;
        swapFee1Repurchase : Nat;
        withdrawErrorLogIndex : Nat;
        withdrawErrorLog : [(Nat, Types.WithdrawErrorLog)];
    };
    public class Service(initState : State) {
        private var _swapFee0Repurchase : Nat = initState.swapFee0Repurchase;
        private var _swapFee1Repurchase : Nat = initState.swapFee1Repurchase;
        private var _tokenAmount0 : Nat = initState.tokenAmount0;
        private var _tokenAmount1 : Nat = initState.tokenAmount1;
        private var _withdrawErrorLogIndex: Nat = initState.withdrawErrorLogIndex;
        private var _withdrawErrorLog : HashMap.HashMap<Nat, Types.WithdrawErrorLog> = HashMap.fromIter(initState.withdrawErrorLog.vals(), 0, Nat.equal, Hash.hash);

        public func getSwapFee0Repurchase() : Nat {
            return _swapFee0Repurchase;
        };
        public func setSwapFee0Repurchase(swapFee0Repurchase : Nat) : () {
            _swapFee0Repurchase := swapFee0Repurchase;
        };
        public func getSwapFee1Repurchase() : Nat {
            return _swapFee1Repurchase;
        };
        public func setSwapFee1Repurchase(swapFee1Repurchase : Nat) : () {
            _swapFee1Repurchase := swapFee1Repurchase;
        };
        public func getTokenAmount0() : Nat {
            return _tokenAmount0;
        };
        public func setTokenAmount0(tokenAmount0 : Nat) : () {
            _tokenAmount0 := tokenAmount0;
        };
        public func getTokenAmount1() : Nat {
            return _tokenAmount1;
        };
        public func setTokenAmount1(tokenAmount1 : Nat) : () {
            _tokenAmount1 := tokenAmount1;
        };
        public func addWithdrawErrorLog(user: Principal, token : Types.Token, time: Int, amount: Nat) : Nat {
            var index = _withdrawErrorLogIndex;
            _withdrawErrorLog.put(index, {
                user = user;
                token = token;
                time = time;
                amount = amount;
            });
            _withdrawErrorLogIndex += 1;
            return index;
        };
        public func removeWithdrawErrorLog(index: Nat) : () {
            ignore _withdrawErrorLog.remove(index);
        };
        public func getWithdrawErrorLog() : HashMap.HashMap<Nat, Types.WithdrawErrorLog> {
            return _withdrawErrorLog;
        };

        public func getState() : State {
            return {
                swapFee0Repurchase = _swapFee0Repurchase;
                swapFee1Repurchase = _swapFee1Repurchase;
                tokenAmount0 = _tokenAmount0;
                tokenAmount1 = _tokenAmount1;
                withdrawErrorLogIndex = _withdrawErrorLogIndex;
                withdrawErrorLog = Iter.toArray(_withdrawErrorLog.entries());
            };
        };
    };
};
