import Types "./Types";
import Swap "./Swap";
import Deposit "./Deposit";
import Withdraw "./Withdraw";
import AddLiquidity "./AddLiquidity";
import HashMap "mo:base/HashMap";
import Hash "mo:base/Hash";
import Result "mo:base/Result";
import Prim "mo:⛔";
import Time "mo:base/Time";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";
import Blob "mo:base/Blob";
import Debug "mo:base/Debug";
import PoolUtils "../../utils/PoolUtils";
import Refund "Refund";
import DecreaseLiquidity "./DecreaseLiquidity";
import Claim "./Claim";
import TransferPosition "./TransferPosition";

module {
    public type Transaction = Types.Transaction;
    public type Transfer = Types.Transfer;
    public type SwapInfo = Types.SwapInfo;
    public type DepositInfo = Types.DepositInfo;
    public type Error = Text;
    public type Account = Types.Account;
    public type Amount = Types.Amount;
    func _hash(n: Nat) : Hash.Hash { return Prim.natToNat32(n); };
    func _copy(tx: Transaction, action: Types.Action): Transaction {
        return {
            id = tx.id;
            timestamp = tx.timestamp;
            owner = tx.owner;
            canisterId = tx.canisterId;
            action = action;
        };
    };
    public type Fun = (action: Types.Action) -> Result.Result<Types.Action, Types.Error>;
    public class State(
        initialIndex: Nat, 
        initialTransactions: [(Nat, Transaction)]
    ) {
        public var index: Nat = initialIndex;
        public var transactions = HashMap.fromIter<Nat, Transaction>(initialTransactions.vals(), initialTransactions.size(), Nat.equal, _hash);
        public func getTxId() : Nat {
            let id = index;
            index := index + 1;
            return id;
        };

        public func new(owner: Principal, canisterId: Principal, action: Types.Action) : Nat {
            let txId = getTxId();
            transactions.put(txId, {
                id = txId;
                timestamp = Time.now();
                owner = owner;
                canisterId = canisterId;
                action = action;    
            });
            return txId;
        };
        public func get(txId: Nat) : ?Transaction {
            return transactions.get(txId);
        };
        public func update(txId: Nat, fun: Fun) : Result.Result<(), Error> {
            switch (transactions.get(txId)) {
                case null { return #err("TransactionNotFound") };
                case (?tx) {
                    switch (fun(tx.action)) {
                        case (#ok(newAction)) {
                            transactions.put(txId, _copy(tx, newAction));
                            return #ok();
                        };
                        case (#err(error)) { return #err(error) };
                    };
                };
            };
        };

        public func getTransactions(): [Transaction] { return Iter.toArray(transactions.vals()); };
        public func getTransaction(txId: Nat): ?Transaction { return transactions.get(txId); };
        
        // --------------------------- deposit ------------------------------------
        public func startDeposit(owner: Principal, canisterId: Principal, token: Principal, from: Account, to: Account, amount: Nat, fee: Nat): Nat {
            let txId = getTxId();
            let memo = ?PoolUtils.natToBlob(txId);
            transactions.put(txId, {
                id = txId;
                timestamp = Time.now();
                owner = owner;
                canisterId = canisterId;
                action = #Deposit(Deposit.start(token, from, to, amount, fee, memo));
            });
            return txId;
        };
        public func successDeposit(txId: Nat, transferIndex: Nat): Result.Result<(), Error> {
            let tx = switch (transactions.get(txId)) {
                case null { return #err("TransactionNotFound") };
                case (?tx) { tx };
            };
            switch(tx.action) {
                case (#Swap(swap)) {
                    switch(swap.deposit) {
                        case null { return #err("DepositNotFound"); };
                        case (?deposit) {
                            let newDeposit = switch(Deposit.success(deposit, transferIndex)) {
                                case (#ok(deposit)) { deposit };
                                case (#err(error)) { return #err(error) };
                            };
                            var trx = _copy(tx, #Swap({
                                tokenIn = swap.tokenIn;
                                tokenOut = swap.tokenOut;
                                amountIn = swap.amountIn;
                                amountOut = swap.amountOut;
                                deposit = ?newDeposit;
                                withdraw = swap.withdraw;
                                refundToken0 = swap.refundToken0;
                                refundToken1 = swap.refundToken1;
                                status = swap.status;
                            }));
                            transactions.put(txId, trx);
                            return #ok();
                        };
                    };
                };
                case(#Deposit(deposit)) {
                    let newDeposit = switch(Deposit.success(deposit, transferIndex)) { 
                        case (#ok(deposit)) { deposit };
                        case (#err(error)) { return #err(error) };
                    };
                    var trx = _copy(tx, #Deposit(newDeposit));
                    transactions.put(txId, trx);
                    return #ok();               
                };
                case(_) {
                    return #err("InvalidTransaction");
                };
            };
        };
        public func completeDeposit(txId: Nat): Result.Result<(), Error> {
            let tx = switch (transactions.get(txId)) {
                case null { return #err("TransactionNotFound") };
                case (?tx) { tx };
            };
            switch(tx.action) {
                case (#Swap(swap)) {
                    switch(swap.deposit) {
                        case null { return #err("DepositNotFound"); };
                        case (?deposit) {
                            let newDeposit = switch(Deposit.complete(deposit)) {
                                case (#ok(deposit)) { deposit };
                                case (#err(error)) { return #err(error) };
                            };
                            switch (Swap.completeDeposit(swap, newDeposit)) {
                                case (#ok(swap)) {
                                    var trx = _copy(tx, #Swap(swap));
                                    transactions.put(txId, trx);
                                    return #ok();
                                };
                                case (#err(error)) { return #err(error) };
                            };
                        };
                    };
                };
                case(#Deposit(deposit)) {
                    let newDeposit = switch(Deposit.complete(deposit)) {
                        case (#ok(deposit)) { deposit };
                        case (#err(error)) { return #err(error) };
                    };
                    var trx = _copy(tx, #Deposit(newDeposit));
                    transactions.put(txId, trx);
                    return #ok();               
                };
                case(_) {
                    return #err("InvalidTransaction");
                };
            };
        };
        public func failDeposit(txId: Nat, err: Types.Error): Result.Result<(), Error> {
            let tx = switch (transactions.get(txId)) {
                case null { return #err("TransactionNotFound") };
                case (?tx) { tx };
            };
            switch(tx.action) {
                case (#Swap(swap)) {
                    switch(swap.deposit) {
                        case null { return #err("DepositNotFound"); };
                        case (?deposit) {
                            let newDeposit = switch(Deposit.fail(deposit, err)) {
                                case (#ok(deposit)) { deposit };
                                case (#err(error)) { return #err(error) };
                            };
                            switch (Swap.failDeposit(swap, newDeposit)) {
                                case (#ok(swap)) {
                                    var trx = _copy(tx, #Swap(swap));
                                    transactions.put(txId, trx);
                                    return #ok();
                                };
                                case (#err(error)) { return #err(error) };
                            };
                        };
                    };
                };
                case(#Deposit(deposit)) {
                    let newDeposit = switch(Deposit.fail(deposit, err)) {
                        case (#ok(deposit)) { deposit };
                        case (#err(error)) { return #err(error) };
                    };
                    var trx = _copy(tx, #Deposit(newDeposit));
                    transactions.put(txId, trx);
                    return #ok();               
                };
                case(_) {
                    return #err("InvalidTransaction");
                };
            };
        };

        // --------------------------- swap ------------------------------------
        public func startSwap(owner: Principal, canisterId: Principal, tokenIn: Principal, tokenOut: Principal, amountIn: Amount): Nat {
            let txId = getTxId();
            transactions.put(txId, {
                id = txId;
                timestamp = Time.now();
                owner = owner;
                canisterId = canisterId;
                action = #Swap(Swap.start(tokenIn, tokenOut, amountIn));
            });
            return txId;
        };
        public func processSwap(txId: Nat, amountIn: Nat): Result.Result<(), Error> {
            let tx = switch (transactions.get(txId)) {
                case null { return #err("TransactionNotFound") };
                case (?tx) { tx };
            };
            switch(tx.action) {
                case (#Swap(swap)) {
                    let newSwap = switch(Swap.processSwap(swap, amountIn)) {
                        case (#ok(swap)) { swap };
                        case (#err(error)) { return #err(error) };
                    };
                    let trx = _copy(tx, #Swap(newSwap));
                    transactions.put(txId, trx);
                    return #ok();
                };
                case(_) {
                    return #err("InvalidTransaction");
                };
            };
        };
        public func completeSwap(txId: Nat, amountOut: Nat): Result.Result<(), Error> {
            Debug.print("==> -- completeSwap --" # debug_show(txId));
            let tx = switch (transactions.get(txId)) {
                case null { return #err("TransactionNotFound") };
                case (?tx) { tx };
            };
            switch(tx.action) {
                case (#Swap(swap)) {
                    let newSwap = switch(Swap.completeSwap(swap, amountOut)) {
                        case (#ok(swap)) { swap };
                        case (#err(error)) { return #err(error) };
                    };
                    let trx = _copy(tx, #Swap(newSwap));
                    transactions.put(txId, trx);
                    return #ok();
                };
                case(_) {
                    return #err("InvalidTransaction");
                };
            };
        };
        public func failSwap(txId: Nat, error: Text): Result.Result<(), Error> {
            let tx = switch (transactions.get(txId)) {
                case null { return #err("TransactionNotFound") };
                case (?tx) { tx };
            };
            switch(tx.action) {
                case (#Swap(swap)) {
                    let newSwap = switch(Swap.failSwap(swap, error)) {
                        case (#ok(swap)) { swap };
                        case (#err(error)) { return #err(error) };
                    };
                    let trx = _copy(tx, #Swap(newSwap));
                    transactions.put(txId, trx);
                    return #ok();
                };
                case(_) {
                    return #err("InvalidTransaction");
                };
            };
        };
        
        // --------------------------- withdraw ------------------------------------
        public func startWithdraw(owner: Principal, canisterId: Principal, token: Principal, from: Account, to: Account, amount: Nat, fee: Nat): Nat {
            let txId = getTxId();
            let memo = ?PoolUtils.natToBlob(txId);
            transactions.put(txId, {
                id = txId;
                timestamp = Time.now();
                owner = owner;
                canisterId = canisterId;
                action = #Withdraw(Withdraw.start(token, from, to, amount, fee, memo));
            });
            return txId;
        };
        public func processWithdraw(txId: Nat): Result.Result<(), Error> {
            let tx = switch (transactions.get(txId)) {
                case null { return #err("TransactionNotFound") };
                case (?tx) { tx };
            };
            switch(tx.action) {
                case (#Swap(swap)) {
                    switch(swap.withdraw) {
                        case null { return #err("WithdrawNotFound"); };
                        case (?withdraw) {
                            let newWithdraw = switch(Withdraw.process(withdraw)) {
                                case (#ok(withdraw)) { withdraw };
                                case (#err(error)) { return #err(error) };
                            };
                            switch (Swap.processWithdraw(swap, newWithdraw)) {
                                case (#ok(swap)) {
                                    var trx = _copy(tx, #Swap(swap));
                                    transactions.put(txId, trx);
                                    return #ok();
                                };
                                case (#err(error)) { return #err(error) };
                            };
                        };
                    };
                };
                case(#Withdraw(withdraw)) {
                    let newWithdraw = switch(Withdraw.process(withdraw)) {
                        case (#ok(withdraw)) { withdraw };
                        case (#err(error)) { return #err(error) };
                    };
                    var trx = _copy(tx, #Withdraw(newWithdraw));
                    transactions.put(txId, trx);
                    return #ok();
                };
                case(_) {
                    return #err("InvalidTransaction");
                };
            };
        };
        public func successWithdraw(txId: Nat, transferIndex: Nat): Result.Result<(), Error> {
            let tx = switch (transactions.get(txId)) {
                case null { return #err("TransactionNotFound") };
                case (?tx) { tx };
            };
            switch(tx.action) {
                case (#Swap(swap)) {
                    switch(swap.withdraw) {
                        case null { return #err("WithdrawNotFound"); };
                        case (?withdraw) {
                            let newWithdraw = switch(Withdraw.success(withdraw, transferIndex)) {
                                case (#ok(withdraw)) { withdraw };
                                case (#err(error)) { return #err(error) };
                            };
                            switch (Swap.completeWithdraw(swap, newWithdraw)) {
                                case (#ok(swap)) {
                                    var trx = _copy(tx, #Swap(swap));
                                    transactions.put(txId, trx);
                                    return #ok();
                                };
                                case (#err(error)) { return #err(error) };
                            };
                        };
                    };
                };
                case(#Withdraw(withdraw)) {
                    let newWithdraw = switch(Withdraw.success(withdraw, transferIndex)) {
                        case (#ok(withdraw)) { withdraw };
                        case (#err(error)) { return #err(error) };
                    };
                    var trx = _copy(tx, #Withdraw(newWithdraw));
                    transactions.put(txId, trx);
                    return #ok();
                };
                case(_) {
                    return #err("InvalidTransaction");
                };
            };
        };
        public func failWithdraw(txId: Nat, err: Types.Error): Result.Result<(), Error> {
            let tx = switch (transactions.get(txId)) {
                case null { return #err("TransactionNotFound") };
                case (?tx) { tx };
            };
            switch(tx.action) {
                case (#Swap(swap)) {
                    switch(swap.withdraw) {
                        case null { return #err("WithdrawNotFound"); };
                        case (?withdraw) {
                            let newWithdraw = switch(Withdraw.fail(withdraw, err)) {
                                case (#ok(withdraw)) { withdraw };
                                case (#err(error)) { return #err(error) };
                            };
                            switch (Swap.failWithdraw(swap, newWithdraw)) {
                                case (#ok(swap)) {
                                    var trx = _copy(tx, #Swap(swap));
                                    transactions.put(txId, trx);
                                    return #ok();
                                };
                                case (#err(error)) { return #err(error) };
                            };
                        };
                    };
                };
                case(_) {
                    return #err("InvalidTransaction");
                };
            };
        };
        
        // --------------------------- one step swap ------------------------------------
        public func startDepositForSwap(txId: Nat, token: Principal, from: Account, to: Account, amount: Nat, fee: Nat, memo: ?Blob): Result.Result<(), Error> {
            let tx = switch (transactions.get(txId)) {
                case null { return #err("TransactionNotFound") };
                case (?tx) { tx };
            };
            switch(tx.action) {
                case (#Swap(swap)) {
                    let newSwap = switch (Swap.startDeposit(swap, Deposit.start(token, from, to, amount, fee, memo))) {
                        case (#ok(swap)) { swap };
                        case (#err(error)) { return #err(error) };
                    };
                    let trx = _copy(tx, #Swap(newSwap));
                    transactions.put(txId, trx);
                    return #ok();
                };
                case(_) {
                    return #err("InvalidTransaction");
                };
            };
        };
        public func successAndCompleteSwap(txId: Nat, amountOut: Nat): Result.Result<(), Error> {
            let tx = switch (transactions.get(txId)) {
                case null { return #err("TransactionNotFound") };
                case (?tx) { tx };
            };
            switch(tx.action) {
                case (#Swap(swap)) {
                    let newSwap = switch(Swap.successAndComplete(swap, amountOut)) {
                        case (#ok(swap)) { swap };
                        case (#err(error)) { return #err(error) };
                    };
                    let trx = _copy(tx, #Swap(newSwap));
                    transactions.put(txId, trx);
                    return #ok();
                };
                case(_) {
                    return #err("InvalidTransaction");
                };
            };
        };
        public func startWithdrawForSwap(txId: Nat, token: Principal, from: Account, to: Account, amount: Nat, fee: Nat, memo: ?Blob): Result.Result<(), Error> {
            let tx = switch (transactions.get(txId)) {
                case null { return #err("TransactionNotFound") };
                case (?tx) { tx };
            };
            switch(tx.action) {
                case (#Swap(swap)) {
                    let newSwap = switch (Swap.startWithdraw(swap, Withdraw.start(token, from, to, amount, fee, memo))) {
                        case (#ok(swap)) { swap };
                        case (#err(error)) { return #err(error) };
                    };
                    let trx = _copy(tx, #Swap(newSwap));
                    transactions.put(txId, trx);
                    return #ok();
                };
                case(_) {
                    return #err("InvalidTransaction");
                };
            };
        };
        public func startRefundForSwap(txId: Nat, token: Principal, from: Account, to: Account, amount: Nat, fee: Nat, memo: ?Blob): Result.Result<(), Error> {
            let tx = switch (transactions.get(txId)) {
                case null { return #err("TransactionNotFound") };
                case (?tx) { tx };
            };
            switch(tx.action) {
                case (#Swap(swap)) {  
                    let newSwap = switch(Swap.startAndProcessRefund(swap, token, from, to, amount, fee, memo)) {
                        case (#ok(swap)) { swap };
                        case (#err(error)) { return #err(error) };
                    };
                    let trx = _copy(tx, #Swap(newSwap));
                    transactions.put(txId, trx);
                    return #ok();
                };
                case(_) {
                    return #err("InvalidTransaction");
                };
            };
        };
        public func completeRefundForSwap(txId: Nat, index: Nat): Result.Result<(), Error> {
            let tx = switch (transactions.get(txId)) {
                case null { return #err("TransactionNotFound") };
                case (?tx) { tx };
            };
            switch(tx.action) {
                case (#Swap(swap)) {
                    let newSwap = switch(Swap.completeRefund(swap, index)) {
                        case (#ok(swap)) { swap };
                        case (#err(error)) { return #err(error) };
                    };
                    let trx = _copy(tx, #Swap(newSwap));
                    transactions.put(txId, trx);
                    return #ok();
                };
                case(_) { 
                    return #err("InvalidTransaction");
                };
            };
        };
        public func failRefund(txId: Nat, error: Text): Result.Result<(), Error> {
            let tx = switch (transactions.get(txId)) {
                case null { return #err("TransactionNotFound") };
                case (?tx) { tx };
            };
            switch(tx.action) {
                case (#Swap(swap)) {
                    switch(Swap.failRefund(swap, error)) {
                        case (#ok(swap)) {
                            let trx = _copy(tx, #Swap(swap));
                            transactions.put(txId, trx);
                            return #ok();
                        };
                        case (#err(error)) { return #err(error) };
                    };
                };
                case(_) {
                    return #err("InvalidTransaction");
                };
            };
        };  
        
        // --------------------------- add liquidity ------------------------------------
        public func startAddLiquidity(owner: Principal, canisterId: Principal, token0: Principal, token1: Principal): Nat {
            let txId = getTxId();
            transactions.put(txId, {
                id = txId;
                timestamp = Time.now();
                owner = owner;
                canisterId = canisterId;
                action = #AddLiquidity(AddLiquidity.start(token0, token1));
            });
            return txId;
        };
        public func startDepositToken0ForAddLiquidity(txId: Nat, token: Principal, from: Account, to: Account, amount: Nat, fee: Nat, memo: ?Blob): Result.Result<(), Error> {
            let tx = switch (transactions.get(txId)) {
                case null { return #err("TransactionNotFound") };
                case (?tx) { tx };
            };
            switch(tx.action) {
                case (#AddLiquidity(addLiquidity)) {
                    let newAddLiquidity = switch(AddLiquidity.startDepositToken0(addLiquidity, Deposit.start(token, from, to, amount, fee, memo))) {
                        case (#ok(addLiquidity)) { addLiquidity };
                        case (#err(error)) { return #err(error) };
                    };
                    let trx = _copy(tx, #AddLiquidity(newAddLiquidity));
                    transactions.put(txId, trx);
                    return #ok();
                };
                case(_) {
                    return #err("InvalidTransaction");
                };
            };
        };
        public func startDepositForAddLiquidity(txId: Nat, token: Principal, from: Account, to: Account, amount: Nat, fee: Nat, memo: ?Blob): Result.Result<(), Error> {
            let tx = switch (transactions.get(txId)) {
                case null { return #err("TransactionNotFound") };
                case (?tx) { tx };
            };
            switch(tx.action) {
                case (#AddLiquidity(info)) {
                    let newAddLiquidity = switch(info.status) {
                        case (#Created) {
                            switch(AddLiquidity.startDepositToken0(info, Deposit.start(token, from, to, amount, fee, memo))) {
                                case (#ok(addLiquidity)) { addLiquidity };
                                case (#err(error)) { return #err(error) };
                            };
                        };
                        case (#Token0DepositCompleted) {
                            switch(AddLiquidity.startDepositToken1(info, Deposit.start(token, from, to, amount, fee, memo))) {
                                case (#ok(addLiquidity)) { addLiquidity };
                                case (#err(error)) { return #err(error) };
                            };
                        };
                        case (_) {
                            return #err("InvalidTransaction");
                        };
                    };
                    let trx = _copy(tx, #AddLiquidity(newAddLiquidity));
                    transactions.put(txId, trx);
                    return #ok();
                };
                case(_) {
                    return #err("InvalidTransaction");
                };
            };
        };
        public func startMintLiquidity(txId: Nat, positionId: Nat): Result.Result<(), Error> {
            let tx = switch (transactions.get(txId)) {
                case null { return #err("TransactionNotFound") };
                case (?tx) { tx };
            };
            switch(tx.action) {
                case (#AddLiquidity(info)) {
                    let newAddLiquidity = switch(AddLiquidity.startMintLiquidity(info, positionId)) {
                        case (#ok(addLiquidity)) { addLiquidity };
                        case (#err(error)) { return #err(error) };
                    };
                    let trx = _copy(tx, #AddLiquidity(newAddLiquidity));
                    transactions.put(txId, trx);
                    return #ok();
                };
                case(_) {
                    return #err("InvalidTransaction");
                };
            };
        };
        public func completeAddLiquidity(txId: Nat, amount0: Nat, amount1: Nat): Result.Result<(), Error> {
            let tx = switch (transactions.get(txId)) {
                case null { return #err("TransactionNotFound") };
                case (?tx) { tx };
            };
            switch(tx.action) {
                case (#AddLiquidity(info)) {
                    let newAddLiquidity = switch(AddLiquidity.complete(info, amount0, amount1)) {
                        case (#ok(addLiquidity)) { addLiquidity };
                        case (#err(error)) { return #err(error) };
                    };
                    let trx = _copy(tx, #AddLiquidity(newAddLiquidity));
                    transactions.put(txId, trx);
                    return #ok();
                };
                case(_) {
                    return #err("InvalidTransaction");
                };
            };
        };
        public func failAddLiquidity(txId: Nat, error: Text): Result.Result<(), Error> {
            let tx = switch (transactions.get(txId)) {
                case null { return #err("TransactionNotFound") };
                case (?tx) { tx };
            };
            switch(tx.action) {
                case (#AddLiquidity(info)) {
                    let newAddLiquidity = switch(AddLiquidity.fail(info, error)) {
                        case (#ok(addLiquidity)) { addLiquidity };
                        case (#err(error)) { return #err(error) };
                    };
                    let trx = _copy(tx, #AddLiquidity(newAddLiquidity));
                    transactions.put(txId, trx);
                    return #ok();
                };
                case(_) {
                    return #err("InvalidTransaction");
                };
            };
        };

        // --------------------------- decrease liquidity ------------------------------------
        public func startDecreaseLiquidity(owner: Principal, canisterId: Principal, positionId: Nat, token0: Principal, token1: Principal): Nat {
            let txId = getTxId();
            transactions.put(txId, {
                id = txId;  
                timestamp = Time.now();
                owner = owner;
                canisterId = canisterId;
                action = #DecreaseLiquidity(DecreaseLiquidity.start(positionId, token0, token1));
            });
            return txId;
        };
        public func successDecreaseLiquidity(txId: Nat, amount0: Nat, amount1: Nat): Result.Result<(), Error> {
            let tx = switch (transactions.get(txId)) {
                case null { return #err("TransactionNotFound") };
                case (?tx) { tx };
            };
            switch(tx.action) {
                case (#DecreaseLiquidity(info)) {
                    let newDecreaseLiquidity = switch(DecreaseLiquidity.success(info, amount0, amount1)) {
                        case (#ok(decreaseLiquidity)) { decreaseLiquidity };
                        case (#err(error)) { return #err(error) };
                    };
                    let trx = _copy(tx, #DecreaseLiquidity(newDecreaseLiquidity));
                    transactions.put(txId, trx);
                    return #ok();
                };
                case(_) {
                    return #err("InvalidTransaction");
                };
            };
        };
        public func failDecreaseLiquidity(txId: Nat, error: Text): Result.Result<(), Error> {
            let tx = switch (transactions.get(txId)) {
                case null { return #err("TransactionNotFound") };
                case (?tx) { tx };
            };
            switch(tx.action) {
                case (#DecreaseLiquidity(info)) {
                    let newDecreaseLiquidity = switch(DecreaseLiquidity.fail(info, error)) {
                        case (#ok(decreaseLiquidity)) { decreaseLiquidity };
                        case (#err(error)) { return #err(error) };
                    };
                    let trx = _copy(tx, #DecreaseLiquidity(newDecreaseLiquidity));
                    transactions.put(txId, trx);
                    return #ok();
                };
                case(_) {
                    return #err("InvalidTransaction");
                };
            };
        };
        public func startWithdrawToken0ForDecreaseLiquidity(txId: Nat, token: Principal, from: Account, to: Account, amount: Nat, fee: Nat, memo: ?Blob): Result.Result<(), Error> {
            let tx = switch (transactions.get(txId)) {
                case null { return #err("TransactionNotFound") };
                case (?tx) { tx };
            };
            switch(tx.action) {
                case (#DecreaseLiquidity(info)) {
                    let newDecreaseLiquidity = switch(DecreaseLiquidity.startWithdrawToken0(info, Withdraw.start(token, from, to, amount, fee, memo))) {
                        case (#ok(decreaseLiquidity)) { decreaseLiquidity };    
                        case (#err(error)) { return #err(error) };
                    };
                    let trx = _copy(tx, #DecreaseLiquidity(newDecreaseLiquidity));
                    transactions.put(txId, trx);
                    return #ok();
                };
                case(_) {
                    return #err("InvalidTransaction");
                };
            };  
        };
        public func successAndCompleteDecreaseLiquidity(txId: Nat, amount0: Nat, amount1: Nat): Result.Result<(), Error> {
            let tx = switch (transactions.get(txId)) {
                case null { return #err("TransactionNotFound") };
                case (?tx) { tx };
            };
            switch(tx.action) {
                case (#DecreaseLiquidity(info)) {
                    let newDecreaseLiquidity = switch(DecreaseLiquidity.successAndComplete(info, amount0, amount1)) {   
                        case (#ok(decreaseLiquidity)) { decreaseLiquidity };
                        case (#err(error)) { return #err(error) };
                    };
                    let trx = _copy(tx, #DecreaseLiquidity(newDecreaseLiquidity));
                    transactions.put(txId, trx);
                    return #ok();
                };
                case(_) {
                    return #err("InvalidTransaction");
                };
            };
        };
        public func completeDecreaseLiquidity(txId: Nat): Result.Result<(), Error> {
            let tx = switch (transactions.get(txId)) {
                case null { return #err("TransactionNotFound") };
                case (?tx) { tx };
            };
            switch(tx.action) {
                case (#DecreaseLiquidity(info)) {
                    let newDecreaseLiquidity = switch(DecreaseLiquidity.complete(info)) {
                        case (#ok(decreaseLiquidity)) { decreaseLiquidity };
                        case (#err(error)) { return #err(error) };
                    };
                    let trx = _copy(tx, #DecreaseLiquidity(newDecreaseLiquidity));
                    transactions.put(txId, trx);
                    return #ok();
                };
                case(_) {
                    return #err("InvalidTransaction");
                };
            };  
        };

        // --------------------------- claim ------------------------------------
        public func startClaim(owner: Principal, canisterId: Principal, positionId: Nat, token0: Principal, token1: Principal): Nat {
            let txId = getTxId();
            transactions.put(txId, {
                id = txId;
                timestamp = Time.now();
                owner = owner;  
                canisterId = canisterId;
                action = #Claim(Claim.start(positionId, token0, token1));
            });
            return txId;
        };
        public func successClaim(txId: Nat, amount0: Nat, amount1: Nat): Result.Result<(), Error> {
            let tx = switch (transactions.get(txId)) {
                case null { return #err("TransactionNotFound") };
                case (?tx) { tx };
            };
            switch(tx.action) {
                case (#Claim(info)) {
                    let newClaim = switch(Claim.success(info, amount0, amount1)) {
                        case (#ok(claim)) { claim };
                        case (#err(error)) { return #err(error) };
                    };
                    let trx = _copy(tx, #Claim(newClaim));
                    transactions.put(txId, trx);
                    return #ok();
                };
                case(_) {
                    return #err("InvalidTransaction");
                };
            };
        };    
        public func successAndCompleteClaim(txId: Nat, amount0: Nat, amount1: Nat): Result.Result<(), Error> {
            let tx = switch (transactions.get(txId)) {
                case null { return #err("TransactionNotFound") };
                case (?tx) { tx };
            };
            switch(tx.action) {
                case (#Claim(info)) {
                    let newClaim = switch(Claim.successAndComplete(info, amount0, amount1)) {
                        case (#ok(claim)) { claim };
                        case (#err(error)) { return #err(error) };
                    };
                    let trx = _copy(tx, #Claim(newClaim));
                    transactions.put(txId, trx);
                    return #ok();
                };
                case(_) {
                    return #err("InvalidTransaction");
                };  
            };
        };
        public func completeClaim(txId: Nat): Result.Result<(), Error> {
            let tx = switch (transactions.get(txId)) {
                case null { return #err("TransactionNotFound") };
                case (?tx) { tx };
            };
            switch(tx.action) {
                case (#Claim(info)) {
                    let newClaim = switch(Claim.complete(info)) {
                        case (#ok(claim)) { claim };
                        case (#err(error)) { return #err(error) };
                    };
                    let trx = _copy(tx, #Claim(newClaim));
                    transactions.put(txId, trx);
                    return #ok();
                };
                case(_) {
                    return #err("InvalidTransaction");
                };
            };
        };
        public func failClaim(txId: Nat, error: Text): Result.Result<(), Error> {
            let tx = switch (transactions.get(txId)) {
                case null { return #err("TransactionNotFound") };
                case (?tx) { tx };
            };
            switch(tx.action) {
                case (#Claim(info)) {
                    let newClaim = switch(Claim.fail(info, error)) {
                        case (#ok(claim)) { claim };
                        case (#err(error)) { return #err(error) };
                    };
                    let trx = _copy(tx, #Claim(newClaim));
                    transactions.put(txId, trx);
                    return #ok();
                };
                case(_) {
                    return #err("InvalidTransaction");
                };
            };
        };

        // --------------------------- transfer position ------------------------------------s
        public func completeTransferPosition(owner: Principal, canisterId: Principal, positionId: Nat, from: Account, to: Account): Nat {
            let txId = getTxId();
            transactions.put(txId, {
                id = txId;
                timestamp = Time.now();
                owner = owner;
                canisterId = canisterId; 
                action = #TransferPosition(TransferPosition.complete(positionId, from, to));    
            });
            return txId;
        };
        // public func completeWithdrawToken0ForDecreaseLiquidity(txId: Nat): Result.Result<(), Error> {
        //     let tx = switch (transactions.get(txId)) {
        //         case null { return #err("TransactionNotFound") };
        //         case (?tx) { tx };
        //     };  
        //     switch(tx.action) {
        //         case (#DecreaseLiquidity(info)) {
        //             let newDecreaseLiquidity = switch(DecreaseLiquidity.completeWithdrawToken0(info, Withdraw.start(token, from, to, amount, fee, memo))) {
        //                 case (#ok(decreaseLiquidity)) { decreaseLiquidity };
        //                 case (#err(error)) { return #err(error) };
        //             };
        //             let trx = _copy(tx, #DecreaseLiquidity(newDecreaseLiquidity));
        //             transactions.put(txId, trx);
        //             return #ok();
        //         };
        //         case(_) {
        //             return #err("InvalidTransaction");
        //         };
        //     };  
        // };
        // public func failWithdrawToken0(txId: Nat, error: Text): Result.Result<(), Error> {
        //     let tx = switch (transactions.get(txId)) {
        //         case null { return #err("TransactionNotFound") };
        //         case (?tx) { tx };
        //     };
        //     switch(tx.action) {
        //         case (#DecreaseLiquidity(info)) {
        //             let newDecreaseLiquidity = switch(DecreaseLiquidity.failWithdrawToken0(info, error)) {  
        //                 case (#ok(decreaseLiquidity)) { decreaseLiquidity };
        //                 case (#err(error)) { return #err(error) };
        //             };
        //             let trx = _copy(tx, #DecreaseLiquidity(newDecreaseLiquidity));
        //             transactions.put(txId, trx);
        //             return #ok();
        //         };  
        //         case(_) {
        //             return #err("InvalidTransaction");
        //         };
        //     };
        // };
        
    };
};
