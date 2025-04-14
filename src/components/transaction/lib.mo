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

    public class State(
        initialIndex: Nat, 
        initialTransactions: [(Nat, Transaction)]
    ) {
        public var index: Nat = initialIndex;
        public var transactions = HashMap.fromIter<Nat, Transaction>(initialTransactions.vals(), initialTransactions.size(), Nat.equal, _hash);
        public func getIndex() : Nat { return index; };
        public func getNextTxId() : Nat {
            let id = index;
            index := index + 1;
            return id;
        };
        public func get(txId: Nat) : ?Transaction { return transactions.get(txId); };
        public func delete(txId: Nat) : () { transactions.delete(txId); };

        public func getTransaction(txId: Nat): ?Transaction { return transactions.get(txId); };
        public func getTransactions(): [(Nat, Transaction)] { return Iter.toArray(transactions.entries()); };
        
        // --------------------------- deposit ------------------------------------
        public func startDeposit(owner: Principal, canisterId: Principal, token: Principal, from: Account, to: Account, amount: Nat, fee: Nat): Nat {
            let txId = getNextTxId();
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

        public func depositTransferred(txId: Nat, txIndex: Nat): () {
            switch (transactions.get(txId)) {
                case null { assert(false) };
                case (?tx) {
                    switch(tx.action) {
                        case (#Deposit(deposit)) {
                            if (deposit.status == #Created) {
                                let newDeposit = Deposit.process(deposit);
                                let trx = _copy(tx, #Deposit({ newDeposit with transfer = { newDeposit.transfer with index = txIndex } }));
                                transactions.put(txId, trx);
                            };
                        };
                        case(#OneStepSwap(info)) {
                            if (info.status == #Created) {
                                let newInfo = OneStepSwap.process(info);
                                let trx = _copy(tx, #OneStepSwap({ newInfo with deposit = { newInfo.deposit with transfer = { newInfo.deposit.transfer with index = txIndex } } }));
                                transactions.put(txId, trx);
                            };
                        };
                        case(_) { assert(false) };
                    };
                };
            };
        };

        public func depositCredited(txId: Nat): () {
            switch (transactions.get(txId)) {
                case null { assert(false) };
                case (?tx) {
                    switch(tx.action) {
                        case (#Deposit(deposit)) {
                            if (deposit.status == #TransferCompleted) {
                                let newDeposit = Deposit.process(deposit);
                                let trx = _copy(tx, #Deposit(newDeposit));
                                transactions.put(txId, trx);
                            };
                        };
                        case (#OneStepSwap(info)) {
                            if (info.status == #DepositTransferCompleted) {
                                let newInfo = OneStepSwap.process(info);
                                let trx = _copy(tx, #OneStepSwap(newInfo));
                                transactions.put(txId, trx);
                            };
                        };
                        case(_) { assert(false) };
                    };
                };
            };
        };

        public func depositFailed(txId: Nat, err: Types.Error): () {
            switch (transactions.get(txId)) {
                case null { assert(false) };
                case (?tx) {
                    switch(tx.action) {
                        case (#Deposit(deposit)) {
                            let newDeposit = Deposit.fail(deposit, err);
                            let trx = _copy(tx, #Deposit(newDeposit));
                            transactions.put(txId, trx);
                        };
                        case(_) { assert(false) };
                    };
                };
            };
        };

        // --------------------------- withdraw ------------------------------------
        public func startWithdraw(owner: Principal, canisterId: Principal, token: Principal, from: Account, to: Account, amount: Nat, fee: Nat): Nat {
            let txId = getNextTxId();
            let memo = ?PoolUtils.natToBlob(txId);
            let info = Withdraw.start(token, from, to, amount, fee, memo);
            transactions.put(txId, {
                id = txId;
                timestamp = Time.now();
                owner = owner;
                canisterId = canisterId;
                action = #Withdraw(info);
            });
            return txId;
        };

        public func withdrawCredited(txId: Nat): () {
            switch (transactions.get(txId)) {
                case null { assert(false) };
                case (?tx) {
                    switch(tx.action) {
                        case (#Withdraw(info)) {
                            if (info.status == #Created) {
                                let newInfo = Withdraw.process(info);
                                let trx = _copy(tx, #Withdraw(newInfo));
                                transactions.put(txId, trx);
                            };
                        };
                        case(#OneStepSwap(info)) {
                            if (info.status == #SwapCompleted) {
                                let newInfo = OneStepSwap.process(info);
                                let trx = _copy(tx, #OneStepSwap(newInfo));
                                transactions.put(txId, trx);
                            };
                        };
                        case(_) { assert(false) };
                    };
                };
            };
        };

        public func withdrawCompleted(txId: Nat, txIndex: ?Nat): Nat {
            switch (transactions.get(txId)) {
                case null { assert(false) };
                case (?tx) {    
                    switch(tx.action) {
                        case (#Withdraw(info)) {
                            if (info.status == #CreditCompleted) {
                                let newInfo = Withdraw.process(info);
                                let trx = _copy(tx, #Withdraw(
                                    switch(txIndex) {
                                        case null { newInfo };
                                        case (?index) { { newInfo with transfer = { newInfo.transfer with index = index } } };
                                    }
                                ));
                                transactions.put(txId, trx);    
                            };
                        };
                        case(#OneStepSwap(info)) {
                            if (info.status == #WithdrawCreditCompleted) {
                                let newInfo = OneStepSwap.process(info);
                                let trx = _copy(tx, #OneStepSwap(newInfo));
                                transactions.put(txId, trx);
                            };
                        };
                        case(_) { assert(false) };
                    };
                };
            };
            txId
        };

        public func withdrawFailed(txId: Nat, err: Types.Error): Nat {
            switch (transactions.get(txId)) {
                case null { assert(false) };
                case (?tx) {
                    switch(tx.action) {
                        case (#Withdraw(info)) {
                            let newInfo = Withdraw.fail(info, err); 
                            let trx = _copy(tx, #Withdraw(newInfo));
                            transactions.put(txId, trx);
                        };
                        case(_) { assert(false) };
                    };
                };
            };
            txId
        };

        // --------------------------- refund ------------------------------------
        public func startRefund(owner: Principal, canisterId: Principal, token: Principal, from: Account, to: Account, amount: Nat, fee: Nat, failedIndex: Nat): Nat {
            let txId = getNextTxId();
            let memo = ?PoolUtils.natToBlob(txId);
            let info = Refund.start(token, from, to, amount, fee, memo, failedIndex);
            transactions.put(txId, {
                id = txId;
                timestamp = Time.now();
                owner = owner;
                canisterId = canisterId;
                action = #Refund(info);
            });
            return txId;
        };

        public func refundCredited(txId: Nat): () {
            switch (transactions.get(txId)) {
                case null { assert(false) };
                case (?tx) {
                    switch(tx.action) {
                        case (#Refund(info)) {
                            if (info.status == #Created) {
                                let newInfo = Refund.process(info);
                                let trx = _copy(tx, #Refund(newInfo));
                                transactions.put(txId, trx);
                            };
                        };
                        case(_) { assert(false) };
                    };
                };
            };
        };

        public func refundCompleted(txId: Nat, txIndex: Nat): (Nat, ?Nat) {
            switch (transactions.get(txId)) {
                case null { assert(false); (0, null) };
                case (?tx) {
                    switch(tx.action) {
                        case (#Refund(info)) {
                            if (info.status == #CreditCompleted) {
                                let newInfo = Refund.process(info);
                                let trx = _copy(tx, #Refund({ newInfo with transfer = { newInfo.transfer with index = txIndex; } }));
                                transactions.put(txId, trx);

                                switch (transactions.get(newInfo.failedIndex)) {
                                    case null { (txId, null) };
                                    case (?failedTx) {
                                        switch(failedTx.action) {
                                            case (#Withdraw(failedInfo)) {
                                                let failedTrx = _copy(failedTx, #Withdraw({ failedInfo with status = #Completed; }));
                                                transactions.put(newInfo.failedIndex, failedTrx);
                                                (txId, ?newInfo.failedIndex)
                                            };
                                            case (#OneStepSwap(failedInfo)) {
                                                let failedTrx = _copy(failedTx, #OneStepSwap({ 
                                                    failedInfo with status = #Completed; 
                                                    withdraw = { failedInfo.withdraw with status = #Failed; }; 
                                                    swap = { failedInfo.swap with status = #Failed; }; 
                                                }));
                                                transactions.put(newInfo.failedIndex, failedTrx);
                                                (txId, ?newInfo.failedIndex)
                                            };
                                            case(_) { assert(false); (0, null) };
                                        };
                                    };
                                };
                            } else {
                                (txId, ?info.failedIndex)
                            }
                        };
                        case(_) { assert(false); (0, null) };
                    };
                };
            };
        };

        public func refundFailed(txId: Nat, err: Types.Error): Nat {
            switch (transactions.get(txId)) {
                case null { assert(false) };
                case (?tx) {
                    switch(tx.action) {
                        case (#Refund(info)) {
                            let newInfo = Refund.fail(info, err);
                            let trx = _copy(tx, #Refund(newInfo));
                            transactions.put(txId, trx);
                        };
                        case(_) { assert(false) };
                    };
                };
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
            return txId;
        };

        public func addLiquidityCompleted(txId: Nat, amount0: Nat, amount1: Nat, liquidity: Nat): Nat {
            switch (transactions.get(txId)) {
                case null { assert(false) };
                case (?tx) {
                    switch(tx.action) {
                        case (#AddLiquidity(info)) {
                            if (info.status == #Created) {
                                let newInfo = AddLiquidity.process(info);
                                let trx = _copy(tx, #AddLiquidity({ newInfo with amount0 = amount0; amount1 = amount1; liquidity = liquidity; }));
                                transactions.put(txId, trx);
                            };
                        };
                        case(_) { assert(false) };
                    };
                };
            };
            txId
        };

        public func addLiquidityFailed(txId: Nat, err: Types.Error): Nat {
            switch (transactions.get(txId)) {
                case null { assert(false) };
                case (?tx) {
                    switch(tx.action) {
                        case (#AddLiquidity(info)) {
                            let newInfo = AddLiquidity.fail(info, err);
                            let trx = _copy(tx, #AddLiquidity(newInfo));
                            transactions.put(txId, trx);
                        };
                        case(_) { assert(false) };
                    };
                };
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
            return txId;
        };

        public func decreaseLiquidityCompleted(txId: Nat, amount0: Nat, amount1: Nat): Nat {
            switch (transactions.get(txId)) {
                case null { assert(false) };
                case (?tx) {
                    switch(tx.action) {
                        case (#DecreaseLiquidity(info)) {
                            if (info.status == #Created) {
                                let newInfo = DecreaseLiquidity.process(info);
                                let trx = _copy(tx, #DecreaseLiquidity({ newInfo with amount0 = amount0; amount1 = amount1; }));
                                transactions.put(txId, trx);
                            };
                        };
                        case(_) { assert(false) };
                    };
                };
            };
            txId
        };

        public func decreaseLiquidityFailed(txId: Nat, err: Types.Error): Nat {
            switch (transactions.get(txId)) {
                case null { assert(false) };
                case (?tx) {
                    switch(tx.action) {
                        case (#DecreaseLiquidity(info)) {
                            let newInfo = DecreaseLiquidity.fail(info, err);
                            let trx = _copy(tx, #DecreaseLiquidity(newInfo));
                            transactions.put(txId, trx);
                        };
                        case(_) { assert(false) };
                    };
                };
            };
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
            return txId;
        };

        public func claimCompleted(txId: Nat, amount0: Nat, amount1: Nat): Nat {
            switch (transactions.get(txId)) {
                case null { assert(false) };
                case (?tx) {
                    switch(tx.action) {
                        case (#Claim(info)) {
                            if (info.status == #Created) {
                                let newInfo = Claim.process(info);
                                let trx = _copy(tx, #Claim({ newInfo with amount0 = amount0; amount1 = amount1; }));
                                transactions.put(txId, trx);
                            };
                        };
                        case(_) { assert(false) };
                    };
                };
            };
            txId
        };

        public func claimFailed(txId: Nat, err: Types.Error): Nat {
            switch (transactions.get(txId)) {
                case null { assert(false) };
                case (?tx) {
                    switch(tx.action) {
                        case (#Claim(info)) {
                            let newInfo = Claim.fail(info, err);
                            let trx = _copy(tx, #Claim(newInfo));
                            transactions.put(txId, trx);
                        };
                        case(_) { assert(false) };
                    };
                };
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
            return txId;
        };

        public func transferPositionCompleted(txId: Nat): Nat {
            switch (transactions.get(txId)) {
                case null { assert(false) };
                case (?tx) {
                    switch(tx.action) {
                        case (#TransferPosition(info)) {
                            if (info.status == #Created) {
                                let newInfo = TransferPosition.process(info);
                                let trx = _copy(tx, #TransferPosition(newInfo));
                                transactions.put(txId, trx);
                            };
                        };
                        case(_) { assert(false) };
                    };
                };
            };
            txId
        };

        public func transferPositionFailed(txId: Nat, err: Types.Error): Nat {
            switch (transactions.get(txId)) {
                case null { assert(false) };
                case (?tx) {
                    switch(tx.action) {
                        case (#TransferPosition(info)) {
                            let newInfo = TransferPosition.fail(info, err);
                            let trx = _copy(tx, #TransferPosition(newInfo));
                            transactions.put(txId, trx);
                        };
                        case(_) { assert(false) };
                    };
                };
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
            return txId;
        };

        public func addLimitOrderCompleted(txId: Nat): Nat {
            switch (transactions.get(txId)) {
                case null { assert(false) };
                case (?tx) {
                    switch(tx.action) {
                        case (#AddLimitOrder(info)) {
                            if (info.status == #Created) {
                                let newInfo = AddLimitOrder.process(info);
                                let trx = _copy(tx, #AddLimitOrder(newInfo));
                                transactions.put(txId, trx);
                            };
                        };
                        case(_) { assert(false) };
                    };
                };
            };
            txId
        };

        public func addLimitOrderFailed(txId: Nat, err: Types.Error): Nat {
            switch (transactions.get(txId)) {
                case null { assert(false) };
                case (?tx) {
                    switch(tx.action) {
                        case (#AddLimitOrder(info)) {
                            let newInfo = AddLimitOrder.fail(info, err);
                            let trx = _copy(tx, #AddLimitOrder(newInfo));
                            transactions.put(txId, trx);
                        };
                        case(_) { assert(false) };
                    };
                };
            };
            txId
        };

        // --------------------------- execute limit order ------------------------------------
        public func startExecuteLimitOrder(owner: Principal, canisterId: Principal, positionId: Nat, token0: Token, token1: Token): Nat {
            let txId = getNextTxId();
            let info = ExecuteLimitOrder.start(positionId, token0, token1);
            transactions.put(txId, {
                id = txId;
                timestamp = Time.now();
                owner = owner;
                canisterId = canisterId;
                action = #ExecuteLimitOrder(info);
            });
            return txId;
        };

        public func executeLimitOrderCompleted(txId: Nat, amount0: Nat, amount1: Nat): Nat {
            switch (transactions.get(txId)) {
                case null { assert(false) };
                case (?tx) {
                    switch(tx.action) {
                        case (#ExecuteLimitOrder(info)) {
                            if (info.status == #Created) {
                                let newInfo = ExecuteLimitOrder.process(info);
                                let trx = _copy(tx, #ExecuteLimitOrder({ newInfo with amount0 = amount0; amount1 = amount1; }));
                                transactions.put(txId, trx);
                            };
                        };
                        case(_) { assert(false) };
                    };
                };
            };
            txId
        };

        public func executeLimitOrderFailed(txId: Nat, err: Types.Error): Nat {
            switch (transactions.get(txId)) {
                case null { assert(false) };
                case (?tx) {
                    switch(tx.action) {
                        case (#ExecuteLimitOrder(info)) {
                            let newInfo = ExecuteLimitOrder.fail(info, err);
                            let trx = _copy(tx, #ExecuteLimitOrder(newInfo));
                            transactions.put(txId, trx);
                        };
                        case(_) { assert(false) };
                    };
                };
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
            return txId;
        };

        public func removeLimitOrderDeleted(txId: Nat): () {
            switch (transactions.get(txId)) {
                case null { assert(false) };
                case (?tx) {
                    switch(tx.action) {
                        case (#RemoveLimitOrder(info)) {
                            if (info.status == #Created) {
                                let newInfo = RemoveLimitOrder.process(info);
                                let trx = _copy(tx, #RemoveLimitOrder(newInfo));
                                transactions.put(txId, trx);
                            };
                        };
                        case(_) { assert(false) };
                    };
                };
            };
        };

        public func removeLimitOrderCompleted(txId: Nat, amount0: Nat, amount1: Nat): Nat {
            switch (transactions.get(txId)) {
                case null { assert(false) };
                case (?tx) {
                    switch(tx.action) {
                        case (#RemoveLimitOrder(info)) {
                            if (info.status == #LimitOrderDeleted) {
                                let newInfo = RemoveLimitOrder.process(info);
                                let trx = _copy(tx, #RemoveLimitOrder({ newInfo with amount0 = amount0; amount1 = amount1; }));
                                transactions.put(txId, trx);
                            };
                        };
                        case(_) { assert(false) };
                    };
                };
            };
            txId
        };

        public func removeLimitOrderFailed(txId: Nat, err: Types.Error): () {
            switch (transactions.get(txId)) {
                case null { assert(false) };
                case (?tx) {
                    switch(tx.action) {
                        case (#RemoveLimitOrder(info)) {
                            let newInfo = RemoveLimitOrder.fail(info, err);
                            let trx = _copy(tx, #RemoveLimitOrder(newInfo));
                            transactions.put(txId, trx);
                        };
                        case(_) { assert(false) };
                    };
                };
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
            return txId;
        };

        public func swapCompleted(txId: Nat, amountOut: Nat): Nat {
            switch (transactions.get(txId)) {
                case null { assert(false) };
                case (?tx) {
                    switch(tx.action) {
                        case (#Swap(info)) {
                            if (info.status == #Created) {
                                let newInfo = Swap.process(info);
                                let trx = _copy(tx, #Swap({ newInfo with amountOut = amountOut }));
                                transactions.put(txId, trx);
                            };
                        };
                        case(_) { assert(false) };
                    };
                };
            };
            txId
        };

        public func swapFailed(txId: Nat, err: Types.Error): Nat {
            switch (transactions.get(txId)) {
                case null { assert(false) };
                case (?tx) {
                    switch(tx.action) {
                        case (#Swap(info)) {
                            let newInfo = Swap.fail(info, err);
                            let trx = _copy(tx, #Swap(newInfo));
                            transactions.put(txId, trx);
                        };
                        case(_) { assert(false) };
                    };
                };
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
            return txId;
        };

        public func oneStepSwapDepositTransferred(txId: Nat, txIndex: Nat): () {
            switch (transactions.get(txId)) {
                case null { assert(false) };
                case (?tx) {
                    switch(tx.action) { 
                        case (#OneStepSwap(info)) {
                            if (info.status == #Created) {
                                let newInfo = OneStepSwap.process(info);
                                let trx = _copy(tx, #OneStepSwap({ newInfo with deposit = { info.deposit with transfer = { info.deposit.transfer with index = txIndex } } }));
                                transactions.put(txId, trx);
                            };  
                        };
                        case(_) { assert(false) };
                    };
                };
            };
        };

        public func oneStepSwapDepositCredited(txId: Nat): () {
            switch (transactions.get(txId)) {
                case null { assert(false) };
                case (?tx) {
                    switch(tx.action) { 
                        case (#OneStepSwap(info)) {
                            if (info.status == #DepositTransferCompleted) {
                                let newInfo = OneStepSwap.process(info);
                                let trx = _copy(tx, #OneStepSwap(newInfo));
                                transactions.put(txId, trx);
                            };  
                        };
                        case(_) { assert(false) };
                    };
                };
            };
        };

        public func oneStepSwapPreSwapCompleted(txId: Nat): () {
            switch (transactions.get(txId)) {
                case null { assert(false) };
                case (?tx) {
                    switch(tx.action) { 
                        case (#OneStepSwap(info)) {
                            if (info.status == #DepositCreditCompleted) {
                                let newInfo = OneStepSwap.process(info);
                                let trx = _copy(tx, #OneStepSwap(newInfo));
                                transactions.put(txId, trx);
                            };  
                        };
                        case(_) { assert(false) };
                    };
                };
            };
        };

        public func oneStepSwapSwapCompleted(txId: Nat, amountOut: Nat): () {
            switch (transactions.get(txId)) {
                case null { assert(false) };
                case (?tx) {
                    switch(tx.action) { 
                        case (#OneStepSwap(info)) {
                            if (info.status == #PreSwapCompleted) {
                                let newInfo = OneStepSwap.process(info);
                                let trx = _copy(tx, #OneStepSwap({ newInfo with swap = { info.swap with amountOut = amountOut; status = #Completed } }));
                                transactions.put(txId, trx);
                            };  
                        };
                        case(_) { assert(false) };
                    };
                };
            };
        };

        public func oneStepSwapWithdrawCredited(txId: Nat): () {
            switch (transactions.get(txId)) {
                case null { assert(false) };
                case (?tx) {
                    switch(tx.action) { 
                        case (#OneStepSwap(info)) {
                            if (info.status == #SwapCompleted) {
                                let newInfo = OneStepSwap.process(info);
                                let trx = _copy(tx, #OneStepSwap(newInfo));
                                transactions.put(txId, trx);
                            };  
                        };
                        case(_) { assert(false) };
                    };
                };
            };
        };

        public func oneStepSwapWithdrawCompleted(txId: Nat, txIndex: ?Nat): () {
            switch (transactions.get(txId)) {
                case null { assert(false) };
                case (?tx) {
                    switch(tx.action) { 
                        case (#OneStepSwap(info)) {
                            if (info.status == #WithdrawCreditCompleted) {
                                let newInfo = OneStepSwap.process(info);
                                let trx = _copy(tx, #OneStepSwap(
                                    switch(txIndex) {
                                        case null { newInfo };
                                        case (?index) { { newInfo with withdraw = { info.withdraw with transfer = { info.withdraw.transfer with index = index } } } };
                                    }
                                ));
                                transactions.put(txId, trx);
                            };  
                        };
                        case(_) { assert(false) };
                    };
                };
            };
        };

        public func oneStepSwapFailed(txId: Nat, err: Types.Error): () {
            switch (transactions.get(txId)) {
                case null { assert(false) };
                case (?tx) {
                    switch(tx.action) {
                        case (#OneStepSwap(info)) {
                            let newInfo = OneStepSwap.fail(info, err);
                            let trx = _copy(tx, #OneStepSwap(newInfo));
                            transactions.put(txId, trx);
                        };
                        case(_) { assert(false) };
                    };
                };
            };
        };

    };
};
