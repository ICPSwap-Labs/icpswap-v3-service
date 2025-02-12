import Types "../Types";
import HashMap "mo:base/HashMap";
import Option "mo:base/Option";
import Nat "mo:base/Nat";
import Text "mo:base/Text";
import Hash "mo:base/Hash";
import Result "mo:base/Result";
import Error "mo:base/Error";

module {
    public type Account = {
        owner: Principal;
        subaccount: ?Blob;
    };
    public type TransactionStatus = {
        #Created;
        #Processing;
        #Error: TransactionError;
    };
    public type TransactionError = {
        #DepositError: Text;
    };
    public type Transfer = {
        from: Account;
        to: Account;
        fee: ?Nat;
        amount: Nat;
        status: TransferStatus;
    };
    public type TransferStatus = {
        #Created;
        #Processing;
        #Ok: Nat;
        #Err: Text;
    };
    public type Swap = {
        tokenIn: Types.Token;
        tokenOut: Types.Token;
        tokenInAmount: Nat;
        tokenOutAmount: Nat;
    };
    public type SwapTransaction = {
        index: Nat;
        account: Principal;
        tokenIn : Types.Token;
        tokenOut : Types.Token;
        amountIn : Text;
        var amountOut: Text;
        var status: TransactionStatus;
        var deposit: ?Transfer;
        var withdraw: ?Transfer;
        var refund: ?Transfer;
        var swap: ?Swap;
    };
    func hash(n: Nat): Hash.Hash {
      return Text.hash(Nat.toText(n));
    };
    public class Service(initIndex: Nat, initState: [(Nat, SwapTransaction)]) {
        private var _index = initIndex;
        private var _trxMap: HashMap.HashMap<Nat, SwapTransaction> = HashMap.fromIter(initState.vals(), initState.size(), Nat.equal, hash);
    
        public func create(account: Principal, tokenIn: Types.Token, tokenOut: Types.Token, amountIn: Text): Nat {
            let trx: SwapTransaction = {
                index = _index;
                account = account;
                tokenIn = tokenIn;
                tokenOut = tokenOut;
                amountIn = amountIn;
                var amountOut = "0";
                var status = #Created;
                var deposit = null;
                var withdraw = null;
                var refund = null;
                var swap = null;
            };
            _trxMap.put(_index, trx);
            _index += 1;
            return _index - 1;
        };
        public func startDeposit(trxIndex: Nat, from: Account, to: Account, amount: Nat, fee: ?Nat) : Result.Result<(), Text> {
            switch (_trxMap.get(trxIndex)) {
                case (?trx) {
                    trx.deposit := ?{
                        status = #Processing;
                        amount = amount;
                        fee = fee;
                        from = from;
                        to = to;
                    };
                    _trxMap.put(trxIndex, trx);
                    return #ok();
                };
                case (_) {
                    return #err("Transaction not found");
                };
            }
        };
        public func depositSuccess(trxIndex: Nat, index: Nat) : Result.Result<(), Text> {
            switch (_trxMap.get(trxIndex)) {
                case (?trx) {
                    switch (trx.deposit) {
                        case (?deposit) {
                            trx.deposit := ?{
                                status = #Ok(index);
                                amount = deposit.amount;
                                fee = deposit.fee;
                                from = deposit.from;
                                to = deposit.to;
                            };
                            _trxMap.put(trxIndex, trx);
                        };
                        case (_) {
                            return #err("Deposit not found");
                        };
                    };
                    return #ok();
                };
                case (_) {
                    return #err("Transaction not found");
                };
            }
        };
        public func depositError(trxIndex: Nat, error: Text) : Result.Result<(), Text> {
            switch (_trxMap.get(trxIndex)) {
                case (?trx) {
                    switch (trx.deposit) {
                        case (?deposit) {
                            trx.deposit := ?{
                                status = #Err(error);
                                amount = deposit.amount;
                                fee = deposit.fee;
                                from = deposit.from;
                                to = deposit.to;
                            };
                            _trxMap.put(trxIndex, trx);
                        };
                        case (_) {
                            return #err("Deposit not found");
                        };
                    };
                    return #ok();
                };
                case (_) {
                    return #err("Transaction not found");
                };
            }
        };
    };
    
};
