import Principal "mo:base/Principal";
import Text "mo:base/Text";
import Iter "mo:base/Iter";
import HashMap "mo:base/HashMap";
import Types "../Types";

module PoolData {

    public type State = {
        poolEntries: [(Text, Types.PoolData)];
        removedPoolEntries: [(Text, Types.PoolData)];
    };

    public class Service(initState: State) {
        private var _poolMap: HashMap.HashMap<Text, Types.PoolData> = HashMap.fromIter(initState.poolEntries.vals(), 10, Text.equal, Text.hash);
        private var _removedPoolMap: HashMap.HashMap<Text, Types.PoolData> = HashMap.fromIter(initState.removedPoolEntries.vals(), 10, Text.equal, Text.hash);

        public func getPools() : HashMap.HashMap<Text, Types.PoolData> {
            return _poolMap;
        };

        public func getRemovedPools() : HashMap.HashMap<Text, Types.PoolData> {
            return _removedPoolMap;
        };

        public func putPool(poolKey: Text, poolData: Types.PoolData) : () {
            return _poolMap.put(poolKey, poolData);
        };

        public func removePool(poolKey: Text) : Text {
            switch(_poolMap.remove(poolKey)) {
                case (?poolData) { 
                    _removedPoolMap.put(Principal.toText(poolData.canisterId), poolData); 
                    return Principal.toText(poolData.canisterId); 
                };
                case (null) { return "";};
            };
        };

        public func deletePool(canisterId: Text) : Text {
            switch(_removedPoolMap.remove(canisterId)) {
                case (?_) { return canisterId; };
                case (null) { return "";};
            };
        };

        public func getState(): State {
            return {
                poolEntries = Iter.toArray(_poolMap.entries());
                removedPoolEntries = Iter.toArray(_removedPoolMap.entries());
            };
        };
    }
}