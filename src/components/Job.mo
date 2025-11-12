import Timer "mo:base/Timer";
import Time "mo:base/Time";
import HashMap "mo:base/HashMap";
import Iter "mo:base/Iter";
import Text "mo:base/Text";
import Option "mo:base/Option";
import Debug "mo:base/Debug";
import Nat "mo:base/Nat";

module Jobs {
    public type Job = {
        name : Text;
        interval : Nat;
        job : () -> async ();
        timerId : ?Nat;
        lastRun : Time.Time;
    };
    public type JobInfo = {
        name : Text;
        interval : Nat;
        timerId : ?Nat;
        lastRun : Time.Time;
    };
    public type Level = {
        #Active;
        #Inactive;
    };
    
    public class JobService() {

        private let LEVEL_DOWNGRADE_THRESHOLD = 24 * 3600 * 1000000000;

        let _jobs: HashMap.HashMap<Text, Job> = HashMap.HashMap<Text, Job>(4, Text.equal, Text.hash);
        var _lastActivity: Time.Time = 0; 
        var _level: Level = #Active;
        public func getJobs(): { level : Level; jobs : [JobInfo]} {
            return {
                level = _level;
                jobs = Iter.toArray(Iter.map<(Text, Job), JobInfo>(_jobs.entries(), func((name, job)): JobInfo {
                    {
                        name = job.name;
                        interval = job.interval;
                        timerId = job.timerId;
                       lastRun = job.lastRun;
                    }
                }));
            };
        };
        public func active() {
            _lastActivity := Time.now();
            _level := #Active;
        };
        public func createJob<system>(name: Text, interval: Nat, job: () -> async ()) {
            Debug.print("[INFO][Job] Creating job: name=" # name # ", interval=" # Nat.toText(interval) # "s");
            let wrapped = func() : async() {
                Debug.print("[INFO][Job] Running job: name=" # name);
                await job();
                switch (_jobs.get(name)) {
                    case (null) {  };
                    case (?job) {
                        _jobs.put(name, {
                            name = job.name;
                            interval = job.interval;
                            job = job.job;
                            timerId = job.timerId;
                            lastRun = Time.now();
                        });
                    };
                };
                if ((Time.now() - _lastActivity) > LEVEL_DOWNGRADE_THRESHOLD) {
                    Debug.print("[INFO][Job] Downgrading level to Inactive due to inactivity");
                    _level := #Inactive;
                    stopJobs([]);
                };
            };
            let id = Option.make(Timer.recurringTimer<system>(#seconds(interval), wrapped));
            _jobs.put(name, {
                name = name;
                interval = interval;
                job = job;
                timerId = id;
                lastRun = 0;
            });
        };
        private func _stopJob(name: Text) {
            Debug.print("[INFO][Job] Stopping job: name=" # name);
            switch (_jobs.get(name)) {
                case (null) {  };
                case (?job) {
                    switch (job.timerId) {
                        case (null) {  };
                        case (?timerId) {
                            Debug.print("[INFO][Job] Cancelling timer: name=" # name # ", timerId=" # Nat.toText(timerId));
                            Timer.cancelTimer(timerId);
                            _jobs.put(name, {
                                name = job.name;
                                interval = job.interval;
                                job = job.job;
                                timerId = null;
                                lastRun = job.lastRun;
                            });
                        };
                    };
                };
            };
        };
        private func _startJob<system>(name: Text) {
            _stopJob(name);
            switch (_jobs.get(name)) {
                case (null) {  };
                case (?job) {
                    createJob<system>(name, job.interval, job.job);
                };
            };
        };
        public func onActivity<system>() {
            _lastActivity := Time.now();
            if (_level == #Inactive) {
                Debug.print("[INFO][Job] Upgrading level to Active");
                _level := #Active;
                restartJobs<system>([]);
            };
        };
        
        public func stopJobs(names: [Text]) {
            let arr: [Text] = if (names.size() == 0) {
                Iter.toArray(_jobs.keys())
            } else {
                names;
            };
            for (name in arr.vals()) {
                _stopJob(name);
            };
        };
        public func restartJobs<system>(names: [Text]) {
            if (_level == #Inactive) {
                Debug.print("[WARN][Job] Cannot restart jobs: level=Inactive");
                return;
            };
            
            if ((Time.now() - _lastActivity) > LEVEL_DOWNGRADE_THRESHOLD) {
                Debug.print("[WARN][Job] Cannot restart jobs: inactivity threshold exceeded");
                return;
            };

            let arr: [Text] = if (names.size() == 0) {
                Iter.toArray(_jobs.keys())
            } else {
                names;
            };
            
            for (name in arr.vals()) {
                _startJob<system>(name);
            };
        };
    };
};