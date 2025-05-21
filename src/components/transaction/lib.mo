import HashMap "mo:base/HashMap";
import Hash "mo:base/Hash";
import Prim "mo:⛔";
import Time "mo:base/Time";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";

import PoolUtils "../../utils/PoolUtils";
import Types "./Types";
import Deposit "./Deposit";
import Withdraw "./Withdraw";
import Refund "./Refund";
import AddLiquidity "./AddLiquidity";
import DecreaseLiquidity "./DecreaseLiquidity";
import Claim "./Claim";
import TransferPosition "./TransferPosition";
import AddLimitOrder "./AddLimitOrder";
import ExecuteLimitOrder "./ExecuteLimitOrder";
import RemoveLimitOrder "./RemoveLimitOrder";
import Swap "./Swap";
import OneStepSwap "./OneStepSwap";

module {
    public type Transaction = Types.Transaction;
    public type Transfer = Types.Transfer;
    public type SwapInfo = Types.SwapInfo;
    public type DepositInfo = Types.DepositInfo;
    public type Error = Text;
    public type Account = Types.Account;
    public type Amount = Types.Amount;
    public type Token = Types.Token;

    private func _hash(n: Nat) : Hash.Hash { Prim.natToNat32(n) };

    private func _copy(tx: Transaction, action: Types.Action): Transaction {
        {
            id = tx.id;
            timestamp = tx.timestamp;
            owner = tx.owner;
            canisterId = tx.canisterId;
            action = action;
        }
    };

    private func _updateTransaction(txId: Nat, tx: Transaction, newAction: Types.Action, transactions: HashMap.HashMap<Nat, Transaction>): () {
        transactions.put(txId, _copy(tx, newAction))
    };

    private func _getTransaction(txId: Nat, transactions: HashMap.HashMap<Nat, Transaction>): ?Transaction {
        transactions.get(txId)
    };

    private func _assertTransactionExists(tx: ?Transaction): Transaction {
        switch (tx) {
            case null { assert(false); loop {} };
            case (?tx) tx;
        }
    };

    public class State(
        initialIndex: Nat, 
        initialTransactions: [(Nat, Transaction)]
    ) {
        public var index: Nat = initialIndex;
        public var transactions = HashMap.fromIter<Nat, Transaction>(initialTransactions.vals(), initialTransactions.size(), Nat.equal, _hash);

        public func getIndex() : Nat { index };
        public func getNextTxId() : Nat {
            let id = index;
            index := index + 1;
            id
        };
        public func get(txId: Nat) : ?Transaction { _getTransaction(txId, transactions) };
        public func delete(txId: Nat) : () { transactions.delete(txId) };
        public func getTransaction(txId: Nat): ?Transaction { _getTransaction(txId, transactions) };
        public func getTransactions(): [(Nat, Transaction)] { Iter.toArray(transactions.entries()) };
        
        // --------------------------- deposit ------------------------------------
        public func startDeposit(owner: Principal, canisterId: Principal, token: Principal, from: Account, to: Account, amount: Nat, fee: Nat, standard: Text): Nat {
            let txId = getNextTxId();
            let memo = ?PoolUtils.natToBlob(txId);
            transactions.put(txId, {
                id = txId;
                timestamp = Time.now();
                owner = owner;
                canisterId = canisterId;
                action = #Deposit(Deposit.start(token, from, to, amount, fee, memo, standard));
            });
            txId
        };

        public func depositTransferred(txId: Nat, txIndex: Nat): () {
            let tx = _assertTransactionExists(_getTransaction(txId, transactions));
            switch(tx.action) {
                case (#Deposit(deposit)) {
                    if (deposit.status == #Created) {
                        let newDeposit = Deposit.process(deposit);
                        _updateTransaction(txId, tx, #Deposit({ newDeposit with transfer = { newDeposit.transfer with index = txIndex } }), transactions);
                    };
                };
                case(#OneStepSwap(info)) {
                    if (info.status == #Created) {
                        let newInfo = OneStepSwap.process(info);
                        _updateTransaction(txId, tx, #OneStepSwap({ newInfo with deposit = { newInfo.deposit with transfer = { newInfo.deposit.transfer with index = txIndex } } }), transactions);
                    };
                };
                case(_) { assert(false) };
            };
        };

        public func depositCredited(txId: Nat, amountDeposit: Nat): () {
            let tx = _assertTransactionExists(_getTransaction(txId, transactions));
            switch(tx.action) {
                case (#Deposit(deposit)) {
                    if (deposit.status == #TransferCompleted) {
                        let newDeposit = Deposit.process(deposit);
                        _updateTransaction(txId, tx, #Deposit({ newDeposit with transfer = { newDeposit.transfer with amount = amountDeposit } }), transactions);
                    };
                };
                case (#OneStepSwap(info)) {
                    if (info.status == #DepositTransferCompleted) {
                        let newInfo = OneStepSwap.process(info);
                        _updateTransaction(txId, tx, #OneStepSwap({ newInfo with deposit = { newInfo.deposit with transfer = { newInfo.deposit.transfer with amount = amountDeposit } } }), transactions);
                    };
                };
                case(_) { assert(false) };
            };
        };

        public func depositFailed(txId: Nat, err: Types.Error): () {
            let tx = _assertTransactionExists(_getTransaction(txId, transactions));
            switch(tx.action) {
                case (#Deposit(deposit)) {
                    let newDeposit = Deposit.fail(deposit, err);
                    _updateTransaction(txId, tx, #Deposit(newDeposit), transactions);
                };
                case(#OneStepSwap(info)) {
                    let newInfo = OneStepSwap.fail(info, err);
                    _updateTransaction(txId, tx, #OneStepSwap({ newInfo with deposit = { newInfo.deposit with status = #Failed; err = ?err; } }), transactions);
                };
                case(_) { assert(false) };
            };
        };

        // --------------------------- withdraw ------------------------------------
        public func startWithdraw(owner: Principal, canisterId: Principal, token: Principal, from: Account, to: Account, amount: Nat, fee: Nat, standard: Text): Nat {
            let txId = getNextTxId();
            let memo = ?PoolUtils.natToBlob(txId);
            let info = Withdraw.start(token, from, to, amount, fee, memo, standard);
            transactions.put(txId, {
                id = txId;
                timestamp = Time.now();
                owner = owner;
                canisterId = canisterId;
                action = #Withdraw(info);
            });
            txId
        };

        public func withdrawCredited(txId: Nat): () {
            let tx = _assertTransactionExists(_getTransaction(txId, transactions));
            switch(tx.action) {
                case (#Withdraw(info)) {
                    if (info.status == #Created) {
                        let newInfo = Withdraw.process(info);
                        _updateTransaction(txId, tx, #Withdraw(newInfo), transactions);
                    };
                };
                case(#OneStepSwap(info)) {
                    if (info.status == #SwapCompleted) {
                        let newInfo = OneStepSwap.process(info);
                        _updateTransaction(txId, tx, #OneStepSwap(newInfo), transactions);
                    };
                };
                case(_) { assert(false) };
            };
        };

        public func withdrawCompleted(txId: Nat, txIndex: ?Nat): Nat {
            let tx = _assertTransactionExists(_getTransaction(txId, transactions));
            switch(tx.action) {
                case (#Withdraw(info)) {
                    if (info.status == #CreditCompleted) {
                        let newInfo = Withdraw.process(info);
                        _updateTransaction(txId, tx, #Withdraw(
                            switch(txIndex) {
                                case null { newInfo };
                                case (?index) { { newInfo with transfer = { newInfo.transfer with index = index } } };
                            }
                        ), transactions);
                    };
                };
                case(#OneStepSwap(info)) {
                    if (info.status == #WithdrawCreditCompleted) {
                        let newInfo = OneStepSwap.process(info);
                        _updateTransaction(txId, tx, #OneStepSwap(newInfo), transactions);
                    };
                    if (info.status == #SwapCompleted and txIndex == null) {
                        let newInfo = OneStepSwap.process({ info with status = #WithdrawCreditCompleted; withdraw = { info.withdraw with transfer = { info.withdraw.transfer with amount = 0 } } });
                        _updateTransaction(txId, tx, #OneStepSwap(newInfo), transactions);
                    };
                };
                case(_) { assert(false) };
            };
            txId
        };

        public func withdrawFailed(txId: Nat, err: Types.Error): Nat {
            let tx = _assertTransactionExists(_getTransaction(txId, transactions));
            switch(tx.action) {
                case (#Withdraw(info)) {
                    let newInfo = Withdraw.fail(info, err);
                    _updateTransaction(txId, tx, #Withdraw(newInfo), transactions);
                };
                case(#OneStepSwap(info)) {
                    let newInfo = OneStepSwap.fail(info, err);
                    _updateTransaction(txId, tx, #OneStepSwap({ newInfo with withdraw = { newInfo.withdraw with status = #Failed; err = ?err; } }), transactions);
                };
                case(_) { assert(false) };
            };
            txId
        };

        // --------------------------- refund ------------------------------------
        public func startRefund(owner: Principal, canisterId: Principal, token: Principal, from: Account, to: Account, amount: Nat, fee: Nat, failedIndex: Nat, standard: Text): Nat {
            let txId = getNextTxId();
            let memo = ?PoolUtils.natToBlob(txId);
            let info = Refund.start(token, from, to, amount, fee, memo, failedIndex, standard);
            transactions.put(txId, {
                id = txId;
                timestamp = Time.now();
                owner = owner;
                canisterId = canisterId;
                action = #Refund(info);
            });
            txId
        };

        public func refundCredited(txId: Nat): () {
            let tx = _assertTransactionExists(_getTransaction(txId, transactions));
            switch(tx.action) {
                case (#Refund(info)) {
                    if (info.status == #Created) {
                        let newInfo = Refund.process(info);
                        _updateTransaction(txId, tx, #Refund(newInfo), transactions);
                    };
                };
                case(_) { assert(false) };
            };
        };

        public func refundCompleted(txId: Nat, txIndex: Nat): (Nat, ?Nat) {
            let tx = _assertTransactionExists(_getTransaction(txId, transactions));
            switch(tx.action) {
                case (#Refund(info)) {
                    if (info.status == #CreditCompleted) {
                        let newInfo = Refund.process(info);
                        _updateTransaction(txId, tx, #Refund({ newInfo with transfer = { newInfo.transfer with index = txIndex; } }), transactions);
                    };
                    switch(_getTransaction(info.relatedIndex, transactions)) {
                        case null { (txId, null) };
                        case (?tx) {
                            switch(tx.action) {
                                case (#OneStepSwap(relatedInfo)) {
                                    if (relatedInfo.status != #Completed) {
                                        _updateTransaction(info.relatedIndex, tx, #OneStepSwap(
                                            {
                                                relatedInfo with status = #Failed;
                                                err = ?("Manually set as an exception");
                                                deposit = { relatedInfo.deposit with status = if (relatedInfo.deposit.status != #Completed) { #Failed } else { relatedInfo.deposit.status }; };
                                                swap = { relatedInfo.swap with status = if (relatedInfo.swap.status != #Completed) { #Failed } else { relatedInfo.swap.status }; };
                                                withdraw = { relatedInfo.withdraw with status = if (relatedInfo.withdraw.status != #Completed) { #Failed } else { relatedInfo.withdraw.status }; };
                                            }
                                        ), transactions);
                                    };
                                };
                                case (#Deposit(relatedInfo)) {
                                    if (relatedInfo.status != #Completed) {
                                        _updateTransaction(info.relatedIndex, tx, #Deposit({ relatedInfo with status = #Failed }), transactions);
                                    };
                                };
                                case (#Withdraw(relatedInfo)) {
                                    if (relatedInfo.status != #Completed) {
                                        _updateTransaction(info.relatedIndex, tx, #Withdraw({ relatedInfo with status = #Failed }), transactions);
                                    };
                                };
                                case (_) { };
                            };
                            (txId, ?info.relatedIndex) 
                        };
                    }
                };
                case(_) { assert(false); (0, null) };
            };
        };

        public func refundFailed(txId: Nat, err: Types.Error): Nat {
            let tx = _assertTransactionExists(_getTransaction(txId, transactions));
            switch(tx.action) {
                case (#Refund(info)) {
                    let newInfo = Refund.fail(info, err);
                    _updateTransaction(txId, tx, #Refund(newInfo), transactions);
                };
                case(_) { assert(false) };
            };
            txId
        };

        // --------------------------- add liquidity ------------------------------------
        public func startAddLiquidity(
            owner: Principal, 
            canisterId: Principal, 
            token0: Token, 
            token1: Token, 
            amount0: Nat, 
            amount1: Nat,
            positionId: Nat
        ): Nat {
            let txId = getNextTxId();
            let info = AddLiquidity.start(token0, token1, amount0, amount1, positionId);
            transactions.put(txId, {
                id = txId;
                timestamp = Time.now();
                owner = owner;
                canisterId = canisterId;
                action = #AddLiquidity(info);
            });
            txId
        };

        public func addLiquidityCompleted(txId: Nat, amount0: Nat, amount1: Nat, liquidity: Nat): Nat {
            let tx = _assertTransactionExists(_getTransaction(txId, transactions));
            switch(tx.action) {
                case (#AddLiquidity(info)) {
                    if (info.status == #Created) {
                        let newInfo = AddLiquidity.process(info);
                        _updateTransaction(txId, tx, #AddLiquidity({ newInfo with amount0 = amount0; amount1 = amount1; liquidity = liquidity; }), transactions);
                    };
                };
                case(_) { assert(false) };
            };
            txId
        };

        public func addLiquidityFailed(txId: Nat, err: Types.Error): Nat {
            let tx = _assertTransactionExists(_getTransaction(txId, transactions));
            switch(tx.action) {
                case (#AddLiquidity(info)) {
                    let newInfo = AddLiquidity.fail(info, err);
                    _updateTransaction(txId, tx, #AddLiquidity(newInfo), transactions);
                };
                case(_) { assert(false) };
            };
            txId
        };

        // --------------------------- decrease liquidity ------------------------------------
        public func startDecreaseLiquidity(owner: Principal, canisterId: Principal, positionId: Nat, token0: Token, token1: Token, liquidity: Nat): Nat {
            let txId = getNextTxId();
            let info = DecreaseLiquidity.start(positionId, token0, token1, liquidity);
            transactions.put(txId, {
                id = txId;
                timestamp = Time.now();
                owner = owner;
                canisterId = canisterId;
                action = #DecreaseLiquidity(info);
            });
            txId
        };

        public func decreaseLiquidityCompleted(txId: Nat, amount0: Nat, amount1: Nat): Nat {
            let tx = _assertTransactionExists(_getTransaction(txId, transactions));
            switch(tx.action) {
                case (#DecreaseLiquidity(info)) {
                    if (info.status == #Created) {
                        let newInfo = DecreaseLiquidity.process(info);
                        _updateTransaction(txId, tx, #DecreaseLiquidity({ newInfo with amount0 = amount0; amount1 = amount1; }), transactions);
                    };
                };
                case(_) { assert(false) };
            };
            txId
        };

        public func decreaseLiquidityFailed(txId: Nat, err: Types.Error): Nat {
            let tx = _assertTransactionExists(_getTransaction(txId, transactions));
            switch(tx.action) {
                case (#DecreaseLiquidity(info)) {
                    let newInfo = DecreaseLiquidity.fail(info, err);
                    _updateTransaction(txId, tx, #DecreaseLiquidity(newInfo), transactions);
                };
                case(_) { assert(false) };
            };
            txId
        };

        // --------------------------- create completed decrease liquidity ------------------------------------
        public func createCompletedDecreaseLiquidity(
            owner: Principal, 
            canisterId: Principal, 
            positionId: Nat, 
            token0: Token, 
            token1: Token, 
            liquidity: Nat,
            amount0: Nat,
            amount1: Nat
        ): Nat {
            let txId = getNextTxId();
            let info = DecreaseLiquidity.start(positionId, token0, token1, liquidity);
            let completedInfo = DecreaseLiquidity.process(info);
            let finalInfo = { completedInfo with amount0 = amount0; amount1 = amount1; };
            transactions.put(txId, {
                id = txId;
                timestamp = Time.now();
                owner = owner;
                canisterId = canisterId;
                action = #DecreaseLiquidity(finalInfo);
            });
            txId
        };

        // --------------------------- claim ------------------------------------
        public func startClaim(owner: Principal, canisterId: Principal, positionId: Nat, token0: Token, token1: Token): Nat {
            let txId = getNextTxId();
            let info = Claim.start(positionId, token0, token1);
            transactions.put(txId, {
                id = txId;
                timestamp = Time.now();
                owner = owner;
                canisterId = canisterId;
                action = #Claim(info);
            });
            txId
        };

        public func claimCompleted(txId: Nat, amount0: Nat, amount1: Nat): Nat {
            let tx = _assertTransactionExists(_getTransaction(txId, transactions));
            switch(tx.action) {
                case (#Claim(info)) {
                    if (info.status == #Created) {
                        let newInfo = Claim.process(info);
                        _updateTransaction(txId, tx, #Claim({ newInfo with amount0 = amount0; amount1 = amount1; }), transactions);
                    };
                };
                case(_) { assert(false) };
            };
            txId
        };

        public func claimFailed(txId: Nat, err: Types.Error): Nat {
            let tx = _assertTransactionExists(_getTransaction(txId, transactions));
            switch(tx.action) {
                case (#Claim(info)) {
                    let newInfo = Claim.fail(info, err);
                    _updateTransaction(txId, tx, #Claim(newInfo), transactions);
                };
                case(_) { assert(false) };
            };
            txId
        };

        // --------------------------- transfer position ------------------------------------
        public func startTransferPosition(owner: Principal, canisterId: Principal, positionId: Nat, from: Account, to: Account): Nat {
            let txId = getNextTxId();
            let info = TransferPosition.start(positionId, from, to);
            transactions.put(txId, {
                id = txId;
                timestamp = Time.now();
                owner = owner;
                canisterId = canisterId;
                action = #TransferPosition(info);
            });
            txId
        };

        public func transferPositionCompleted(txId: Nat): Nat {
            let tx = _assertTransactionExists(_getTransaction(txId, transactions));
            switch(tx.action) {
                case (#TransferPosition(info)) {
                    if (info.status == #Created) {
                        let newInfo = TransferPosition.process(info);
                        _updateTransaction(txId, tx, #TransferPosition(newInfo), transactions);
                    };
                };
                case(_) { assert(false) };
            };
            txId
        };

        public func transferPositionFailed(txId: Nat, err: Types.Error): Nat {
            let tx = _assertTransactionExists(_getTransaction(txId, transactions));
            switch(tx.action) {
                case (#TransferPosition(info)) {
                    let newInfo = TransferPosition.fail(info, err);
                    _updateTransaction(txId, tx, #TransferPosition(newInfo), transactions);
                };
                case(_) { assert(false) };
            };
            txId
        };

        // --------------------------- add limit order ------------------------------------
        public func startAddLimitOrder(owner: Principal, canisterId: Principal, positionId: Nat, token0: Token, token1: Token, amount0: Nat, amount1: Nat, tickLimit: Int): Nat {
            let txId = getNextTxId();
            let info = AddLimitOrder.start(positionId, token0, token1, amount0, amount1, tickLimit);
            transactions.put(txId, {
                id = txId;
                timestamp = Time.now();
                owner = owner;
                canisterId = canisterId;
                action = #AddLimitOrder(info);
            });
            txId
        };

        public func addLimitOrderCompleted(txId: Nat): Nat {
            let tx = _assertTransactionExists(_getTransaction(txId, transactions));
            switch(tx.action) {
                case (#AddLimitOrder(info)) {
                    if (info.status == #Created) {
                        let newInfo = AddLimitOrder.process(info);
                        _updateTransaction(txId, tx, #AddLimitOrder(newInfo), transactions);
                    };
                };
                case(_) { assert(false) };
            };
            txId
        };

        public func addLimitOrderFailed(txId: Nat, err: Types.Error): Nat {
            let tx = _assertTransactionExists(_getTransaction(txId, transactions));
            switch(tx.action) {
                case (#AddLimitOrder(info)) {
                    let newInfo = AddLimitOrder.fail(info, err);
                    _updateTransaction(txId, tx, #AddLimitOrder(newInfo), transactions);
                };
                case(_) { assert(false) };
            };
            txId
        };

        // --------------------------- execute limit order ------------------------------------
        public func startExecuteLimitOrder(owner: Principal, canisterId: Principal, positionId: Nat, token0: Token, token1: Token, token0InAmount: Nat, token1InAmount: Nat, tickLimit: Int): Nat {
            let txId = getNextTxId();
            let info = ExecuteLimitOrder.start(positionId, token0, token1, token0InAmount, token1InAmount, tickLimit);
            transactions.put(txId, {
                id = txId;
                timestamp = Time.now();
                owner = owner;
                canisterId = canisterId;
                action = #ExecuteLimitOrder(info);
            });
            txId
        };

        public func executeLimitOrderCompleted(txId: Nat, token0AmountOut: Nat, token1AmountOut: Nat): Nat {
            let tx = _assertTransactionExists(_getTransaction(txId, transactions));
            switch(tx.action) {
                case (#ExecuteLimitOrder(info)) {
                    if (info.status == #Created) {
                        let newInfo = ExecuteLimitOrder.process(info);
                        _updateTransaction(txId, tx, #ExecuteLimitOrder({ newInfo with token0AmountOut = token0AmountOut; token1AmountOut = token1AmountOut; }), transactions);
                    };
                };
                case(_) { assert(false) };
            };
            txId
        };

        public func executeLimitOrderFailed(txId: Nat, err: Types.Error): Nat {
            let tx = _assertTransactionExists(_getTransaction(txId, transactions));
            switch(tx.action) {
                case (#ExecuteLimitOrder(info)) {
                    let newInfo = ExecuteLimitOrder.fail(info, err);
                    _updateTransaction(txId, tx, #ExecuteLimitOrder(newInfo), transactions);
                };
                case(_) { assert(false) };
            };
            txId
        };

        // --------------------------- remove limit order ------------------------------------
        public func startRemoveLimitOrder(owner: Principal, canisterId: Principal, positionId: Nat, token0: Token, token1: Token): Nat {
            let txId = getNextTxId();
            let info = RemoveLimitOrder.start(positionId, token0, token1);
            transactions.put(txId, {
                id = txId;
                timestamp = Time.now();
                owner = owner;
                canisterId = canisterId;
                action = #RemoveLimitOrder(info);
            });
            txId
        };

        public func removeLimitOrderDeleted(txId: Nat, token0AmountIn: Nat, token1AmountIn: Nat, tickLimit: Int): () {
            let tx = _assertTransactionExists(_getTransaction(txId, transactions));
            switch(tx.action) {
                case (#RemoveLimitOrder(info)) {
                    if (info.status == #Created) {
                        let newInfo = RemoveLimitOrder.process(info);
                        _updateTransaction(txId, tx, #RemoveLimitOrder({ newInfo with token0AmountIn = token0AmountIn; token1AmountIn = token1AmountIn; tickLimit = tickLimit }), transactions);
                    };
                };
                case(_) { assert(false) };
            };
        };

        public func removeLimitOrderCompleted(txId: Nat, token0AmountOut: Nat, token1AmountOut: Nat): Nat {
            let tx = _assertTransactionExists(_getTransaction(txId, transactions));
            switch(tx.action) {
                case (#RemoveLimitOrder(info)) {
                    if (info.status == #LimitOrderDeleted) {
                        let newInfo = RemoveLimitOrder.process(info);
                        _updateTransaction(txId, tx, #RemoveLimitOrder({ newInfo with token0AmountOut = token0AmountOut; token1AmountOut = token1AmountOut; }), transactions);
                    };
                };
                case(_) { assert(false) };
            };
            txId
        };

        public func removeLimitOrderFailed(txId: Nat, err: Types.Error): () {
            let tx = _assertTransactionExists(_getTransaction(txId, transactions));
            switch(tx.action) {
                case (#RemoveLimitOrder(info)) {
                    let newInfo = RemoveLimitOrder.fail(info, err);
                    _updateTransaction(txId, tx, #RemoveLimitOrder(newInfo), transactions);
                };
                case(_) { assert(false) };
            };
        };

        // --------------------------- swap ------------------------------------
        public func startSwap(owner: Principal, canisterId: Principal, tokenIn: Token, tokenOut: Token, amountIn: Nat): Nat {
            let txId = getNextTxId();
            let info = Swap.start(tokenIn, tokenOut, amountIn);
            transactions.put(txId, {
                id = txId;
                timestamp = Time.now();
                owner = owner;
                canisterId = canisterId;
                action = #Swap(info);
            });
            txId
        };

        public func swapCompleted(txId: Nat, amountOut: Nat): Nat {
            let tx = _assertTransactionExists(_getTransaction(txId, transactions));
            switch(tx.action) {
                case (#Swap(info)) {
                    if (info.status == #Created) {
                        let newInfo = Swap.process(info);
                        _updateTransaction(txId, tx, #Swap({ newInfo with amountOut = amountOut }), transactions);
                    };
                };
                case(_) { assert(false) };
            };
            txId
        };

        public func swapFailed(txId: Nat, err: Types.Error): Nat {
            let tx = _assertTransactionExists(_getTransaction(txId, transactions));
            switch(tx.action) {
                case (#Swap(info)) {
                    let newInfo = Swap.fail(info, err);
                    _updateTransaction(txId, tx, #Swap(newInfo), transactions);
                };
                case(_) { assert(false) };
            };
            txId
        };

        // --------------------------- one step swap ------------------------------------
        public func startOneStepSwap(
            owner: Principal, 
            canisterId: Principal, 
            tokenIn: Token, 
            tokenOut: Token, 
            amountIn: Nat,
            amountOut: Nat,
            amountInFee: Nat, 
            amountOutFee: Nat,
            caller: Principal,
            subaccount: ?Blob
        ): Nat {
            let txId = getNextTxId();
            let info = OneStepSwap.start(tokenIn, tokenOut, amountIn, amountOut, amountInFee, amountOutFee, canisterId, caller, subaccount);
            transactions.put(txId, {
                id = txId;  
                timestamp = Time.now();
                owner = owner;
                canisterId = canisterId;
                action = #OneStepSwap(info);
            });
            txId
        };

        public func oneStepSwapDepositTransferred(txId: Nat, txIndex: Nat): () {
            let tx = _assertTransactionExists(_getTransaction(txId, transactions));
            switch(tx.action) { 
                case (#OneStepSwap(info)) {
                    if (info.status == #Created) {
                        let newInfo = OneStepSwap.process(info);
                        _updateTransaction(txId, tx, #OneStepSwap({ newInfo with deposit = { info.deposit with transfer = { info.deposit.transfer with index = txIndex } } }), transactions);
                    };  
                };
                case(_) { assert(false) };
            };
        };

        public func oneStepSwapDepositCredited(txId: Nat, amountDeposit: Nat): () {
            let tx = _assertTransactionExists(_getTransaction(txId, transactions));
            switch(tx.action) { 
                case (#OneStepSwap(info)) {
                    if (info.status == #DepositTransferCompleted) {
                        let newInfo = OneStepSwap.process(info);
                        _updateTransaction(txId, tx, #OneStepSwap({ newInfo with deposit = { newInfo.deposit with transfer = { newInfo.deposit.transfer with amount = amountDeposit } } }), transactions);
                    };  
                };
                case(_) { assert(false) };
            };
        };

        public func oneStepSwapPreSwapCompleted(txId: Nat): () {
            let tx = _assertTransactionExists(_getTransaction(txId, transactions));
            switch(tx.action) { 
                case (#OneStepSwap(info)) {
                    if (info.status == #DepositCreditCompleted) {
                        let newInfo = OneStepSwap.process(info);
                        _updateTransaction(txId, tx, #OneStepSwap(newInfo), transactions);
                    };  
                };
                case(_) { assert(false) };
            };
        };

        public func oneStepSwapSwapCompleted(txId: Nat, amountOut: Nat, amountInEffective: Nat): () {
            let tx = _assertTransactionExists(_getTransaction(txId, transactions));
            switch(tx.action) { 
                case (#OneStepSwap(info)) {
                    if (info.status == #PreSwapCompleted) {
                        let newInfo = OneStepSwap.process(info);
                        _updateTransaction(txId, tx, #OneStepSwap({
                            newInfo with swap = { info.swap with amountOut = amountOut; amountIn = amountInEffective; status = #Completed };
                            withdraw = { info.withdraw with transfer = { info.withdraw.transfer with amount = amountOut } };
                        }), transactions);
                    };  
                };
                case(_) { assert(false) };
            };
        };

        public func oneStepSwapSwapFailed(txId: Nat, err: Types.Error): () {
            let tx = _assertTransactionExists(_getTransaction(txId, transactions));
            switch(tx.action) {
                case (#OneStepSwap(info)) {
                    let newInfo = OneStepSwap.fail(info, err);
                    _updateTransaction(txId, tx, #OneStepSwap({ newInfo with swap = { newInfo.swap with status = #Failed; err = ?err; } }), transactions);
                };
                case(_) { assert(false) };
            };
        };

        public func setFailed(txId: Nat, err: Types.Error): Nat {
            let tx = _assertTransactionExists(_getTransaction(txId, transactions));
            switch(tx.action) {
                case (#Deposit(info)) {
                    if (info.status != #Completed and info.status != #Failed) {
                        _updateTransaction(txId, tx, #Deposit({ info with status = #Failed; err = ?err }), transactions);
                    };
                };
                case (#Withdraw(info)) {
                    if (info.status != #Completed and info.status != #Failed) {
                        _updateTransaction(txId, tx, #Withdraw({ info with status = #Failed; err = ?err }), transactions);
                    };
                };
                case (#Refund(info)) {
                    if (info.status != #Completed and info.status != #Failed) {
                        _updateTransaction(txId, tx, #Refund({ info with status = #Failed; err = ?err }), transactions);
                    };
                };
                case (#AddLiquidity(info)) {
                    if (info.status != #Completed and info.status != #Failed) {
                        _updateTransaction(txId, tx, #AddLiquidity({ info with status = #Failed; err = ?err }), transactions);
                    };
                };
                case (#DecreaseLiquidity(info)) {
                    if (info.status != #Completed and info.status != #Failed) {
                        _updateTransaction(txId, tx, #DecreaseLiquidity({ info with status = #Failed; err = ?err }), transactions);
                    };
                };
                case (#Claim(info)) {
                    if (info.status != #Completed and info.status != #Failed) {
                        _updateTransaction(txId, tx, #Claim({ info with status = #Failed; err = ?err }), transactions);
                    };
                };
                case (#TransferPosition(info)) {
                    if (info.status != #Completed and info.status != #Failed) {
                        _updateTransaction(txId, tx, #TransferPosition({ info with status = #Failed; err = ?err }), transactions);
                    };
                };
                case (#AddLimitOrder(info)) {
                    if (info.status != #Completed and info.status != #Failed) {
                        _updateTransaction(txId, tx, #AddLimitOrder({ info with status = #Failed; err = ?err }), transactions);
                    };
                };
                case (#ExecuteLimitOrder(info)) {
                    if (info.status != #Completed and info.status != #Failed) {
                        _updateTransaction(txId, tx, #ExecuteLimitOrder({ info with status = #Failed; err = ?err }), transactions);
                    };
                };
                case (#RemoveLimitOrder(info)) {
                    if (info.status != #Completed and info.status != #Failed) {
                        _updateTransaction(txId, tx, #RemoveLimitOrder({ info with status = #Failed; err = ?err }), transactions);
                    };
                };
                case (#Swap(info)) {
                    if (info.status != #Completed and info.status != #Failed) {
                        _updateTransaction(txId, tx, #Swap({ info with status = #Failed; err = ?err }), transactions);
                    };
                };
                case (#OneStepSwap(info)) {
                        _updateTransaction(txId, tx, #OneStepSwap({
                            info with status = if (info.status != #Completed and info.status != #Failed) { #Failed } else { info.status };
                            err = ?err;
                            withdraw = { info.withdraw with status = if (info.withdraw.status != #Completed and info.withdraw.status != #Failed) { #Failed } else { info.withdraw.status }; };
                            swap = { info.swap with status = if (info.swap.status != #Completed and info.swap.status != #Failed) { #Failed } else { info.swap.status }; };
                            deposit = { info.deposit with status = if (info.deposit.status != #Completed and info.deposit.status != #Failed) { #Failed } else { info.deposit.status }; };
                        }), transactions);
                };
            };
            return txId;
        };
    };
};
