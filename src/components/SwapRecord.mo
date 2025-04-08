import Int "mo:base/Int";
import Time "mo:base/Time";
import Buffer "mo:base/Buffer";
import Debug "mo:base/Debug";
import Error "mo:base/Error";
import Nat "mo:base/Nat";
import Text "mo:base/Text";
import Types "../Types";
import EvictingQueue "mo:commons/collections/EvictingQueue";

module SwapRecord {

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

    private func _errorEqual(t1 : Types.PushError, t2 : Types.PushError) : Bool {
        Int.equal(t1.time, t2.time) and Text.equal(t1.message, t2.message);
    };

    private func _initError(arr : [Types.PushError]) : EvictingQueue.EvictingQueue<Types.PushError> {
        var errors : EvictingQueue.EvictingQueue<Types.PushError> = EvictingQueue.EvictingQueue<Types.PushError>(100, _errorEqual);
        for (it in arr.vals()) { ignore errors.add(it) };
        return errors;
    };

    public class Service(initState : State, infoCid : Text) {
        private var _lastSyncTime : Int = 0;
        private var _swapRecordCache : Buffer.Buffer<Types.SwapRecordInfo> = _initRecord(initState.records);
        private var _infoCid : Text = infoCid;
        private var _infoAct = actor (infoCid) : Types.TxStorage;
        private var _retryCount : Nat = initState.retryCount;
        private var _errors : EvictingQueue.EvictingQueue<Types.PushError> = _initError(initState.errors);

        public func setInfoCid(cid : Text) {
            _infoCid := cid;
            _infoAct := actor (cid) : Types.TxStorage;
        };

        public func addRecord(record : Types.SwapRecordInfo) { _swapRecordCache.add(record); };

        public func getState() : State {
            return {
                infoCid = _infoCid;
                records = Buffer.toArray(_swapRecordCache);
                retryCount = _retryCount;
                errors = _errors.toArray();
            };
        };

        public func syncRecord() : async () {
            let now : Int = Time.now();
            if (_checkSyncInterval(now)) {
                _lastSyncTime := now;
                Debug.print("==> start job.");
                var tempRecordCache : Buffer.Buffer<Types.SwapRecordInfo> = _getRecordToBePushed();
                if (tempRecordCache.size() > 0) {
                    try {
                        Debug.print("==> start push record to : " # _infoCid);
                        await _infoAct.batchPushV2(Buffer.toArray<Types.SwapRecordInfo>(tempRecordCache));
                        Debug.print("==> push success..");
                        if (_retryCount > 0) {
                            _retryCount := 0;
                            _errors := _initError([]);
                        };
                    } catch (e) {
                        Debug.print("==> push fail. " # Error.message(e) # ", retryCount = " # Nat.toText(_retryCount));
                        _rollbackRecordToBePushed(tempRecordCache);
                        _retryCount := _retryCount + 1;
                        ignore _errors.add({ time = now; message = Error.message(e) } : Types.PushError);
                    };
                };
            };
        };

        private func _getRecordToBePushed() : Buffer.Buffer<Types.SwapRecordInfo> {
            var tempRecordCache : Buffer.Buffer<Types.SwapRecordInfo> = Buffer.Buffer<Types.SwapRecordInfo>(0);
            var number = 0;
            label l while (number < 10) {
                if (_swapRecordCache.size() > 0) {
                    switch (_swapRecordCache.removeLast()) {
                        case (?rec) { tempRecordCache.add(rec) };
                        case (null) { break l };
                    };
                };
                number := number + 1;
            };
            return tempRecordCache;
        };

        private func _rollbackRecordToBePushed(arr : Buffer.Buffer<Types.SwapRecordInfo>) : () {
            _swapRecordCache.append(arr);
        };

        public func _checkSyncInterval(now : Int) : Bool {
            Debug.print("==> now : " # debug_show(now));
            Debug.print("==> _lastSyncTime : " # debug_show(_lastSyncTime));
            if (_retryCount < 3) {
                true;
            } else {
                if (now - _lastSyncTime > 1 * 60 * 1000000000) {
                    true;
                } else {
                    false;
                };
            };
        };
    };
};
