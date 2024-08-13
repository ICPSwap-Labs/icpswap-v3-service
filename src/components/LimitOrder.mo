import Hash "mo:base/Hash";
import HashMap "mo:base/HashMap";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";
import Types "../Types";

module TokenAmount {

    public type State = {
        limitOrder : [(Nat, Types.LimitOrder)];
    };
    public class Service(initState : State) {
        private var _limitOrder : HashMap.HashMap<Nat, Types.LimitOrder> = HashMap.fromIter(initState.limitOrder.vals(), 0, Nat.equal, Hash.hash);

        public func addLimitOrder(userPositionId : Nat, limitOrder : Types.LimitOrder) : () {
            _limitOrder.put(userPositionId, limitOrder);
        };
        public func deleteLimitOrder(userPositionId : Nat) : () {
            _limitOrder.delete(userPositionId);
        };

        public func getState() : State {
            return {
                limitOrder = Iter.toArray(_limitOrder.entries());
            };
        };
    };
};
