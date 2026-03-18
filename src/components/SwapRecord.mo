import Array "mo:base/Array";
import Buffer "mo:base/Buffer";
import Nat "mo:base/Nat";
import Option "mo:base/Option";
import Types "../Types";

module SwapRecord {

    /// Default max size for a single getPendingSyncData response to avoid oversized payload
    public let DEFAULT_MAX_PENDING_LIMIT : Nat = 100;

    public type State = {
        records : [Types.SwapRecordInfo];
        retryCount : Nat;
        errors : [Types.PushError];
    };

    private func _initRecord(arr : [Types.SwapRecordInfo]) : Buffer.Buffer<Types.SwapRecordInfo> {
        var buffer : Buffer.Buffer<Types.SwapRecordInfo> = Buffer.Buffer<Types.SwapRecordInfo>(arr.size());
        for (it in arr.vals()) {
            buffer.add(it);
        };
        return buffer;
    };

    public class Service(initState : State) {
        private var _swapRecordCache : Buffer.Buffer<Types.SwapRecordInfo> = _initRecord(initState.records);

        public func addRecord(record : Types.SwapRecordInfo) { _swapRecordCache.add(record); };

        public func getState() : State {
            return {
                records = Buffer.toArray(_swapRecordCache);
                retryCount = initState.retryCount;
                errors = initState.errors;
            };
        };

        /// Returns the oldest pending records up to limit (capped by DEFAULT_MAX_PENDING_LIMIT). Read-only.
        public func getPendingSyncData(limit : ?Nat) : [Types.SwapRecordInfo] {
            let cap = Nat.min(Option.get(limit, DEFAULT_MAX_PENDING_LIMIT), DEFAULT_MAX_PENDING_LIMIT);
            let n = Nat.min(cap, _swapRecordCache.size());
            if (n == 0) { return [] };
            let out = Buffer.Buffer<Types.SwapRecordInfo>(n);
            var i : Nat = 0;
            while (i < n) {
                out.add(_swapRecordCache.get(i));
                i += 1;
            };
            Buffer.toArray(out);
        };

        /// Removes records whose txInfo.id is in ids. Idempotent for repeated calls with the same ids.
        public func deleteSyncedData(ids : [Nat]) : () {
            if (ids.size() == 0) return;
            let keep = Buffer.Buffer<Types.SwapRecordInfo>(_swapRecordCache.size());
            for (rec in _swapRecordCache.vals()) {
                let id = rec.txInfo.id;
                switch (Array.find(ids, func(x : Nat) : Bool { x == id })) {
                    case (null) { keep.add(rec) };
                    case (_) {};
                };
            };
            _swapRecordCache := keep;
        };
    };
};
