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
        public func successDeposit(txId: Nat, transferIndex: Nat): () {
            switch (transactions.get(txId)) {
                case null { assert(false) };
                case (?tx) {
                    switch(tx.action) {
                        case (#Swap(swap)) {
                            switch(swap.deposit) {
                                case null { assert(false) };
                                case (?deposit) {
                                    let trx = _copy(tx, #Swap(Swap.completeDeposit(swap, Deposit.success(deposit, transferIndex))));
                                    transactions.put(txId, trx);
                                };
                            };
                        };
                        case(#Deposit(deposit)) {
                            let newDeposit = Deposit.success(deposit, transferIndex);
                            let trx = _copy(tx, #Deposit(newDeposit));
                            transactions.put(txId, trx);
                        };
                        case(_) { assert(false) };
                    };
                };
            };
        };
        public func completeDeposit(txId: Nat): () {
            switch (transactions.get(txId)) {
                case null { assert(false) };
                case (?tx) {
                    switch(tx.action) {
                        case (#Swap(swap)) {
                            switch(swap.deposit) {
                                case null { assert(false) };
                                case (?deposit) {
                                    let newDeposit = Deposit.complete(deposit);
                                    let newSwap = Swap.completeDeposit(swap, newDeposit);
                                    let trx = _copy(tx, #Swap(newSwap));
                                    transactions.put(txId, trx);
                                };
                            };
                        };
                        case(#Deposit(deposit)) {
                            let newDeposit = Deposit.complete(deposit);
                            let trx = _copy(tx, #Deposit(newDeposit));
                            transactions.put(txId, trx);
                        };
                        case(_) { assert(false) };
                    };
                };
            };
        };
        public func failDeposit(txId: Nat, err: Types.Error): () {
            switch (transactions.get(txId)) {
                case null { assert(false) };
                case (?tx) {
                    switch(tx.action) {
                        case (#Swap(swap)) {
                            switch(swap.deposit) {
                                case null { assert(false) };
                                case (?deposit) {
                                    let newDeposit = Deposit.fail(deposit, err);
                                    let newSwap = Swap.failDeposit(swap, newDeposit);
                                    let trx = _copy(tx, #Swap(newSwap));
                                    transactions.put(txId, trx);
                                };
                            };
                        };
                        case(#Deposit(deposit)) {
                            let newDeposit = Deposit.fail(deposit, err);
                            let trx = _copy(tx, #Deposit(newDeposit));
                            transactions.put(txId, trx);
                        };
                        case(_) { assert(false) };
                    };
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
        public func processSwap(txId: Nat, amountIn: Nat): () {
            switch (transactions.get(txId)) {
                case null { assert(false) };
                case (?tx) {
                    switch(tx.action) {
                        case (#Swap(swap)) {
                            let newSwap = Swap.processSwap(swap, amountIn);
                            let trx = _copy(tx, #Swap(newSwap));
                            transactions.put(txId, trx);
                        };
                        case(_) { assert(false) };
                    };
                };
            };
        };
        public func completeSwap(txId: Nat, amountOut: Nat): () {
            switch (transactions.get(txId)) {
                case null { assert(false) };
                case (?tx) {
                    switch(tx.action) {
                        case (#Swap(swap)) {
                            let newSwap = Swap.completeSwap(swap, amountOut);
                            let trx = _copy(tx, #Swap(newSwap));
                            transactions.put(txId, trx);
                        };
                        case(_) { assert(false) };
                    };
                };
            };
        };
        public func failSwap(txId: Nat, error: Text): () {
            switch (transactions.get(txId)) {
                case null { assert(false) };
                case (?tx) {
                    switch(tx.action) {
                        case (#Swap(swap)) {
                            let newSwap = Swap.failSwap(swap, error);
                            let trx = _copy(tx, #Swap(newSwap));
                            transactions.put(txId, trx);
                        };
                        case(_) { assert(false) };
                    };
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
        public func processWithdraw(txId: Nat): () {
            switch (transactions.get(txId)) {
                case null { assert(false) };
                case (?tx) {
                    switch(tx.action) {
                case (#Swap(swap)) {
                    switch(swap.withdraw) {
                        case null { assert(false) };
                        case (?withdraw) {
                            let newWithdraw = Withdraw.process(withdraw);
                            let newSwap = Swap.processWithdraw(swap, newWithdraw);
                            let trx = _copy(tx, #Swap(newSwap));
                            transactions.put(txId, trx);
                        };
                    };
                };
                case(#Withdraw(withdraw)) {
                    let newWithdraw = Withdraw.process(withdraw);
                    let trx = _copy(tx, #Withdraw(newWithdraw));
                    transactions.put(txId, trx);
                };
                case(_) {
                    assert(false);
                };
            };
                };
            };
        };
        public func successWithdraw(txId: Nat, transferIndex: Nat): () {
            switch (transactions.get(txId)) {
                case null { assert(false) };
                case (?tx) {
                    switch(tx.action) {
                        case (#Swap(swap)) {
                            switch(swap.withdraw) {
                                case null { assert(false) };
                                case (?withdraw) {
                                    let newWithdraw = Withdraw.success(withdraw, transferIndex);
                                    let newSwap = Swap.completeWithdraw(swap, newWithdraw);
                                    let trx = _copy(tx, #Swap(newSwap));
                                    transactions.put(txId, trx);
                                };
                            };
                        };
                        case(#Withdraw(withdraw)) {
                            let newWithdraw = Withdraw.success(withdraw, transferIndex);
                            let trx = _copy(tx, #Withdraw(newWithdraw));
                            transactions.put(txId, trx);
                        };
                        case(_) { assert(false) };
                    };
                };
            };
        };
        public func failWithdraw(txId: Nat, err: Types.Error): () {
            switch (transactions.get(txId)) {
                case null { assert(false) };
                case (?tx) {
                    switch(tx.action) {
                        case (#Swap(swap)) {
                            switch(swap.withdraw) {
                                case null { assert(false) };
                                case (?withdraw) {
                                    let newWithdraw = Withdraw.fail(withdraw, err);
                                    let newSwap = Swap.failWithdraw(swap, newWithdraw);
                                    let trx = _copy(tx, #Swap(newSwap));
                                    transactions.put(txId, trx);
                                };
                            };
                        };
                        case(_) { assert(false) };
                    };
                };
            };
        };
        
        // --------------------------- one step swap ------------------------------------
        public func startDepositForSwap(
            txId: Nat, 
            token: Principal, 
            from: Account, 
            to: Account, 
            amount: Nat, 
            fee: Nat, 
            memo: ?Blob
        ): () {
            switch (transactions.get(txId)) {
                case null { assert(false) }; 
                case (?tx) {
                    switch(tx.action) {
                        case (#Swap(swap)) {
                            let newSwap = Swap.startDeposit(swap, Deposit.start(token, from, to, amount, fee, memo));
                            let trx = _copy(tx, #Swap(newSwap)); 
                            transactions.put(txId, trx);
                        };
                        case(_) { assert(false) };
                    };
                };
            };
        };
        public func successAndCompleteSwap(txId: Nat, amountOut: Nat): () {
            switch (transactions.get(txId)) {
                case null { assert(false) };
                case (?tx) {
                    switch(tx.action) {
                        case (#Swap(swap)) {
                            let newSwap = Swap.successAndComplete(swap, amountOut);
                            let trx = _copy(tx, #Swap(newSwap));
                            transactions.put(txId, trx);
                        };
                        case(_) { assert(false) };
                    };
                };
            };
        };
        public func startWithdrawForSwap(txId: Nat, token: Principal, from: Account, to: Account, amount: Nat, fee: Nat, memo: ?Blob): () {
            switch (transactions.get(txId)) {
                case null { assert(false) };
                case (?tx) {
                    switch(tx.action) {
                        case (#Swap(swap)) {
                            let newSwap = Swap.startWithdraw(swap, Withdraw.start(token, from, to, amount, fee, memo));
                            let trx = _copy(tx, #Swap(newSwap));
                            transactions.put(txId, trx);
                        };
                        case(_) { assert(false) };
                    };
                };
            };
        };
        public func startAndProcessRefund(txId: Nat, token: Principal, from: Types.Account, to: Types.Account, amount: Nat, fee: Nat, memo: ?Blob): () {
            switch (transactions.get(txId)) {
                case null { assert(false) };
                case (?tx) {
                    switch(tx.action) {
                        case (#Swap(swap)) {
                            let newSwap = Swap.startAndProcessRefund(swap, token, from, to, amount, fee, memo);
                            let trx = _copy(tx, #Swap(newSwap));
                            transactions.put(txId, trx);
                        };
                        case(_) { assert(false) };
                    };
                };
            };
        };
        public func completeRefund(txId: Nat, index: Nat): () {
            switch (transactions.get(txId)) {
                case null { assert(false) };
                case (?tx) {
                    switch(tx.action) {
                        case (#Swap(swap)) {
                            let newSwap = Swap.completeRefund(swap, index);
                            let trx = _copy(tx, #Swap(newSwap));
                            transactions.put(txId, trx);
                        };
                        case(_) { assert(false) };
                    };
                };
            };
        };
        public func failRefund(txId: Nat, error: Text): () {
            switch (transactions.get(txId)) {
                case null { assert(false) };
                case (?tx) {
                    switch(tx.action) {
                        case (#Swap(swap)) {
                            let newSwap = Swap.failRefund(swap, error);
                            let trx = _copy(tx, #Swap(newSwap));
                            transactions.put(txId, trx);
                        };
                        case(_) { assert(false) };
                    };
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
        public func startDepositToken0ForAddLiquidity(txId: Nat, token: Principal, from: Account, to: Account, amount: Nat, fee: Nat, memo: ?Blob): () {
            switch (transactions.get(txId)) {
                case null { assert(false) };
                case (?tx) {
                    switch(tx.action) {
                        case (#AddLiquidity(addLiquidity)) {
                            let trx = _copy(tx, #AddLiquidity(
                                AddLiquidity.startDepositToken0(
                                    addLiquidity, 
                                    Deposit.start(token, from, to, amount, fee, memo)
                                )
                            )); 
                            transactions.put(txId, trx);
                        };
                        case(_) { assert(false) };
                    };
                };
            };
        };
        public func startDepositForAddLiquidity(
            txId: Nat, 
            token: Principal, 
            from: Account, 
            to: Account, 
            amount: Nat, 
            fee: Nat, 
            memo: ?Blob
        ): () {
            switch (transactions.get(txId)) {
                case null { assert(false) };
                case (?tx) {
                    switch(tx.action) {
                        case (#AddLiquidity(info)) {
                            switch(info.status) {
                                case (#Created) {
                                    let trx = _copy(tx, #AddLiquidity(
                                        AddLiquidity.startDepositToken0(
                                            info, 
                                            Deposit.start(token, from, to, amount, fee, memo)
                                        )
                                    ));
                                    transactions.put(txId, trx);
                                };
                                case (#Token0DepositCompleted) {
                                    let trx = _copy(tx, #AddLiquidity(
                                        AddLiquidity.startDepositToken1(
                                            info, 
                                            Deposit.start(token, from, to, amount, fee, memo)
                                        )
                                    ));
                                    transactions.put(txId, trx);
                                };
                                case (_) { assert(false) };
                            };
                        };
                        case(_) { assert(false) };
                    };
                };
            };
        };
        public func completeAddLiquidity(txId: Nat, amount0: Nat, amount1: Nat): () {
            switch (transactions.get(txId)) {
                case null { assert(false) };
                case (?tx) {
                    switch(tx.action) {
                        case (#AddLiquidity(info)) {
                            let trx = _copy(tx, #AddLiquidity(AddLiquidity.complete(info, amount0, amount1)));
                            transactions.put(txId, trx);
                        };
                        case(_) { assert(false) };
                    };
                };
            };
        };
        public func failAddLiquidity(txId: Nat, error: Text): () {
            switch (transactions.get(txId)) {
                case null { assert(false) };
                case (?tx) {
                    switch(tx.action) {
                        case (#AddLiquidity(info)) {
                            let trx = _copy(tx, #AddLiquidity(AddLiquidity.fail(info, error)));
                            transactions.put(txId, trx);
                        };
                        case(_) { assert(false) };
                    };
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
        public func successDecreaseLiquidity(txId: Nat, amount0: Nat, amount1: Nat): () {
            switch (transactions.get(txId)) {
                case null { assert(false) };
                case (?tx) {
                    switch(tx.action) {
                        case (#DecreaseLiquidity(info)) {
                            let newDecreaseLiquidity = DecreaseLiquidity.success(info, amount0, amount1);
                            let trx = _copy(tx, #DecreaseLiquidity(newDecreaseLiquidity));
                            transactions.put(txId, trx);
                        };
                        case(_) { assert(false) };
                    };
                };
            };
        };
        public func failDecreaseLiquidity(txId: Nat, error: Text): () {
            switch (transactions.get(txId)) {
                case null { assert(false) };
                case (?tx) {
                    switch(tx.action) {
                        case (#DecreaseLiquidity(info)) {
                            let newDecreaseLiquidity = DecreaseLiquidity.fail(info, error);
                            let trx = _copy(tx, #DecreaseLiquidity(newDecreaseLiquidity));
                            transactions.put(txId, trx);
                        };
                        case(_) { assert(false) };
                    };
                };
            };
        };
        public func startWithdrawToken0ForDecreaseLiquidity(txId: Nat, token: Principal, from: Account, to: Account, amount: Nat, fee: Nat, memo: ?Blob): () {
            switch (transactions.get(txId)) {
                case null { assert(false) };
                case (?tx) {
                    switch(tx.action) {
                        case (#DecreaseLiquidity(info)) {
                            let newDecreaseLiquidity = DecreaseLiquidity.startWithdrawToken0(
                                info, 
                                Withdraw.start(token, from, to, amount, fee, memo)
                            );
                            let trx = _copy(tx, #DecreaseLiquidity(newDecreaseLiquidity));
                            transactions.put(txId, trx);
                        };
                        case(_) { assert(false) };
                    };
                };
            };
        };
        public func successAndCompleteDecreaseLiquidity(txId: Nat, amount0: Nat, amount1: Nat): () {
            switch (transactions.get(txId)) {
                case null { assert(false) };
                case (?tx) {
                    switch(tx.action) {
                        case (#DecreaseLiquidity(info)) {
                            let newDecreaseLiquidity = DecreaseLiquidity.successAndComplete(info, amount0, amount1);
                            let trx = _copy(tx, #DecreaseLiquidity(newDecreaseLiquidity));
                            transactions.put(txId, trx);
                        };
                        case(_) { assert(false) };
                    };
                };
            };
        };
        public func completeDecreaseLiquidity(txId: Nat): () {
            switch (transactions.get(txId)) {
                case null { assert(false) };
                case (?tx) {
                    switch(tx.action) {
                        case (#DecreaseLiquidity(info)) {
                            let newDecreaseLiquidity = DecreaseLiquidity.complete(info);
                            let trx = _copy(tx, #DecreaseLiquidity(newDecreaseLiquidity));
                            transactions.put(txId, trx);
                        };
                        case(_) { assert(false) };
                    };
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
        public func successClaim(txId: Nat, amount0: Nat, amount1: Nat): () {
            switch (transactions.get(txId)) {
                case null { assert(false) };
                case (?tx) {
                    switch(tx.action) {
                        case (#Claim(info)) {
                            let newClaim = Claim.success(info, amount0, amount1);
                            let trx = _copy(tx, #Claim(newClaim));
                            transactions.put(txId, trx);
                        };
                        case(_) { assert(false) };
                    };
                };
            };
        };    
        public func successAndCompleteClaim(txId: Nat, amount0: Nat, amount1: Nat): () {
            switch (transactions.get(txId)) {
                case null { assert(false) };
                case (?tx) {
                    switch(tx.action) {
                        case (#Claim(info)) {
                            let newClaim = Claim.successAndComplete(info, amount0, amount1);
                            let trx = _copy(tx, #Claim(newClaim));
                            transactions.put(txId, trx);
                        };
                        case(_) { assert(false) };
                    };
                };
            };
        };
        public func completeClaim(txId: Nat): () {
            switch (transactions.get(txId)) {
                case null { assert(false) };
                case (?tx) {
                    switch(tx.action) {
                        case (#Claim(info)) {
                            let newClaim = Claim.complete(info);
                            let trx = _copy(tx, #Claim(newClaim));
                            transactions.put(txId, trx);
                        };
                        case(_) { assert(false) };
                    };
                };
            };
        };
        public func failClaim(txId: Nat, error: Text): () {
            switch (transactions.get(txId)) {
                case null { assert(false) };
                case (?tx) {
                    switch(tx.action) {
                        case (#Claim(info)) {
                            let newClaim = Claim.fail(info, error);
                            let trx = _copy(tx, #Claim(newClaim));
                            transactions.put(txId, trx);
                        };
                        case(_) { assert(false) };
                    };
                };
            };
        };

        // --------------------------- transfer position ------------------------------------s
        public func completeTransferPosition(owner: Principal, canisterId: Principal, positionId: Nat, from: Account, to: Account): () {
            let txId = getTxId();
            transactions.put(txId, {
                id = txId;
                timestamp = Time.now();
                owner = owner;
                canisterId = canisterId; 
                action = #TransferPosition(TransferPosition.complete(positionId, from, to));    
            });
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
