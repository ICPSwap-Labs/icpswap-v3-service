import HashMap "mo:base/HashMap";
import Nat "mo:base/Nat";
import Text "mo:base/Text";
import Hash "mo:base/Hash";
import Result "mo:base/Result";
import Iter "mo:base/Iter";

module {
    public type State = {
        index: Nat;
        trxArray: [(Nat, SwapTransaction)];
    };
    public type Account = {
        owner: Principal;
        subaccount: ?Blob;
    };
    public type TransactionStatus = {
        #Created;
        #Processing;
        #Completed;
        #Error: TransactionError;
    };
    public type TransactionError = {
        #DepositError: Text;
        #SwapError: Text;
        #WithdrawError: Text;
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
        tokenInAmount: Nat;
        tokenOutAmount: Nat;
    };
    public type SwapTransaction = {
        index: Nat;
        account: Principal;
        zeroForOne: Bool;
        amountIn : Text;
        var amountOut: Text;
        var status: TransactionStatus;
        var deposit: ?Transfer;
        var withdraw: ?Transfer;
        var refund: ?Transfer;
        var swap: ?Swap;
    };
    public type ImmutableSwapTransaction = {
        index: Nat;
        account: Principal;
        zeroForOne: Bool;
        amountIn : Text;
        amountOut: Text;
        status: TransactionStatus;
        deposit: ?Transfer;
        withdraw: ?Transfer;
        refund: ?Transfer;
        swap: ?Swap;
    };
    func hash(n: Nat): Hash.Hash { return Text.hash(Nat.toText(n)); };

    public class Service(initIndex: Nat, initTrxArray: [(Nat, SwapTransaction)]) {
        private var _index = initIndex;
        private var _trxMap: HashMap.HashMap<Nat, SwapTransaction> = HashMap.fromIter(initTrxArray.vals(), initTrxArray.size(), Nat.equal, hash);
    
        public func getTrx(trxIndex: Nat) : ?SwapTransaction {
            return _trxMap.get(trxIndex);
        };

        public func getTrxMap() : HashMap.HashMap<Nat, SwapTransaction> {
            return _trxMap;
        };

        public func getState() : { index: Nat; trxArray: [(Nat, SwapTransaction)] } {
            return { index = _index; trxArray = Iter.toArray(_trxMap.entries()); };
        };

        public func setStatus(trxIndex: Nat, status: TransactionStatus) : Result.Result<(), Text> {
            switch (_trxMap.get(trxIndex)) {
                case (?trx) {
                    trx.status := status;
                    _trxMap.put(trxIndex, trx);
                    return #ok();
                };
                case (_) { return #err("Transaction not found"); };
            }
        };

        public func create(account: Principal, zeroForOne: Bool, amountIn: Text): Nat {
            let trx: SwapTransaction = {
                index = _index;
                account = account;
                zeroForOne = zeroForOne;
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
                    trx.deposit := ?{ status = #Processing; amount = amount; fee = fee; from = from; to = to; };
                    _trxMap.put(trxIndex, trx);
                    return #ok();
                };
                case (_) { return #err("Transaction not found"); };
            }
        };

        public func depositSuccess(trxIndex: Nat, index: Nat) : Result.Result<(), Text> {
            switch (_trxMap.get(trxIndex)) {
                case (?trx) {
                    switch (trx.deposit) {
                        case (?deposit) {
                            trx.deposit := ?{ status = #Ok(index); amount = deposit.amount; fee = deposit.fee; from = deposit.from; to = deposit.to; };
                            _trxMap.put(trxIndex, trx);
                        };
                        case (_) { return #err("Deposit not found"); };
                    };
                    return #ok();
                };
                case (_) { return #err("Transaction not found"); };
            }
        };

        public func depositError(trxIndex: Nat, error: Text) : Result.Result<(), Text> {
            switch (_trxMap.get(trxIndex)) {
                case (?trx) {
                    switch (trx.deposit) {
                        case (?deposit) {
                            trx.deposit := ?{ status = #Err(error); amount = deposit.amount; fee = deposit.fee; from = deposit.from; to = deposit.to; };
                            _trxMap.put(trxIndex, trx);
                        };
                        case (_) { return #err("Deposit not found"); };
                    };
                    return #ok();
                };
                case (_) { return #err("Transaction not found"); };
            }
        };

        public func startSwap(trxIndex: Nat, tokenInAmount: Nat) : Result.Result<(), Text> {
            switch (_trxMap.get(trxIndex)) {
                case (?trx) {
                    trx.swap := ?{
                        zeroForOne = trx.zeroForOne;
                        tokenInAmount = tokenInAmount;
                        tokenOutAmount = 0;
                    };
                    _trxMap.put(trxIndex, trx);
                    return #ok();
                };
                case (_) { return #err("Transaction not found"); };
            }
        };

        public func swapSuccess(trxIndex: Nat, tokenOutAmount: Nat) : Result.Result<(), Text> {
            switch (_trxMap.get(trxIndex)) {
                case (?trx) {
                    switch (trx.swap) {
                        case (?swap) {
                            trx.swap := ?{
                                tokenInAmount = swap.tokenInAmount;
                                tokenOutAmount = tokenOutAmount;
                            };
                            trx.amountOut := Nat.toText(tokenOutAmount);
                            _trxMap.put(trxIndex, trx);
                        };
                        case (_) { return #err("Swap not found"); };
                    };
                    return #ok();
                };
                case (_) { return #err("Transaction not found"); };
            }
        };

        public func swapError(trxIndex: Nat, error: Text) : Result.Result<(), Text> {
            switch (_trxMap.get(trxIndex)) {
                case (?trx) {
                    _trxMap.put(trxIndex, trx);
                    return #ok();
                };
                case (_) { return #err("Transaction not found"); };
            }
        };

        public func startWithdraw(trxIndex: Nat, from: Account, to: Account, amount: Nat, fee: ?Nat) : Result.Result<(), Text> {
            switch (_trxMap.get(trxIndex)) {
                case (?trx) {
                    trx.withdraw := ?{ status = #Processing; amount = amount; fee = fee; from = from; to = to; };
                    _trxMap.put(trxIndex, trx);
                    return #ok();
                };
                case (_) { return #err("Transaction not found"); };
            }
        };

        public func withdrawSuccess(trxIndex: Nat, index: Nat) : Result.Result<(), Text> {
            switch (_trxMap.get(trxIndex)) {
                case (?trx) {
                    switch (trx.withdraw) {
                        case (?withdraw) {
                            trx.withdraw := ?{ status = #Ok(index); amount = withdraw.amount; fee = withdraw.fee; from = withdraw.from; to = withdraw.to; };
                            _trxMap.put(trxIndex, trx);
                        };
                        case (_) { return #err("Withdraw not found"); };
                    };
                    return #ok();
                };
                case (_) { return #err("Transaction not found"); };
            }
        };

        public func withdrawError(trxIndex: Nat, error: Text) : Result.Result<(), Text> {
            switch (_trxMap.get(trxIndex)) {
                case (?trx) {
                    switch (trx.withdraw) {
                        case (?withdraw) {
                            trx.withdraw := ?{ status = #Err(error); amount = withdraw.amount; fee = withdraw.fee; from = withdraw.from; to = withdraw.to; };
                            _trxMap.put(trxIndex, trx);
                        };
                        case (_) { return #err("Withdraw not found"); };
                    };
                    return #ok();
                };
                case (_) { return #err("Transaction not found"); };
            }
        };

        public func startRefund(trxIndex: Nat, from: Account, to: Account, amount: Nat, fee: ?Nat) : Result.Result<(), Text> {
            switch (_trxMap.get(trxIndex)) {
                case (?trx) {
                    trx.refund := ?{ status = #Processing; amount = amount; fee = fee; from = from; to = to; };
                    _trxMap.put(trxIndex, trx);
                    return #ok();
                };
                case (_) { return #err("Transaction not found"); };
            }
        };

        public func refundSuccess(trxIndex: Nat, index: Nat) : Result.Result<(), Text> {
            switch (_trxMap.get(trxIndex)) {
                case (?trx) {
                    switch (trx.refund) {
                        case (?refund) {
                            trx.refund := ?{ status = #Ok(index); amount = refund.amount; fee = refund.fee; from = refund.from; to = refund.to; };
                            _trxMap.put(trxIndex, trx);
                        };
                        case (_) { return #err("Refund not found"); };
                    };
                    return #ok();
                };
                case (_) { return #err("Transaction not found"); };
            }
        };

        public func refundError(trxIndex: Nat, error: Text) : Result.Result<(), Text> {
            switch (_trxMap.get(trxIndex)) {
                case (?trx) {
                    switch (trx.refund) {
                        case (?refund) {
                            trx.refund := ?{ status = #Err(error); amount = refund.amount; fee = refund.fee; from = refund.from; to = refund.to; };
                            _trxMap.put(trxIndex, trx);
                        };
                        case (_) { return #err("Refund not found"); };
                    };
                    return #ok();
                };
                case (_) { return #err("Transaction not found"); };
            }
        };
    
    };
    
};
