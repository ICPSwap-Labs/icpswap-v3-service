import Principal "mo:base/Principal";
import IC0Utils "mo:commons/utils/IC0Utils";
import BlockTimestamp "../libraries/BlockTimestamp";
import Types "../Types";
import SwapPool "../SwapPool";
// for testing
// import SwapPoolTest "../../test/swap_pool/SwapPoolTest";

module UpgradeTask {

    public func stepTurnOffAvailable(task: Types.PoolUpgradeTask) : async Types.PoolUpgradeTask {
        var poolCid = task.poolData.canisterId;
        var poolAct = actor (Principal.toText(poolCid)) : Types.SwapPoolActor;
        let { module_hash } = await IC0Utils.canister_status(poolCid);
        await poolAct.setAvailable(false);
        {
            poolData = task.poolData;
            moduleHashBefore = module_hash;
            moduleHashAfter = task.moduleHashAfter;
            turnOffAvailable = { timestamp = BlockTimestamp.blockTimestamp(); isDone = true; };
            stop = task.stop;
            upgrade = task.upgrade;
            start = task.start;
            turnOnAvailable = task.turnOnAvailable;
        };
    };

    public func stepStop(task: Types.PoolUpgradeTask) : async Types.PoolUpgradeTask {
        await IC0Utils.stop_canister(task.poolData.canisterId);
        {
            poolData = task.poolData;
            moduleHashBefore = task.moduleHashBefore;
            moduleHashAfter = task.moduleHashAfter;
            turnOffAvailable = task.turnOffAvailable;
            stop = { timestamp = BlockTimestamp.blockTimestamp(); isDone = true; };
            upgrade = task.upgrade;
            start = task.start;
            turnOnAvailable = task.turnOnAvailable;
        };
    };

    public func stepUpgrade(task: Types.PoolUpgradeTask, infoCid : Principal, feeReceiverCid : Principal, trustedCanisterManagerCid : Principal,) : async Types.PoolUpgradeTask {
        let oldPool = actor (Principal.toText(task.poolData.canisterId)) : actor {};
        let _ = await (system SwapPool.SwapPool)(#upgrade oldPool)(task.poolData.token0, task.poolData.token1, infoCid, feeReceiverCid, trustedCanisterManagerCid);
        // for testing
        // let _ = await (system SwapPoolTest.SwapPoolTest)(#upgrade oldPool)(task.poolData.token0, task.poolData.token1, infoCid, feeReceiverCid, trustedCanisterManagerCid);
        {
            poolData = task.poolData;
            moduleHashBefore = task.moduleHashBefore;
            moduleHashAfter = task.moduleHashAfter;
            turnOffAvailable = task.turnOffAvailable;
            stop = task.stop;
            upgrade = { timestamp = BlockTimestamp.blockTimestamp(); isDone = true; };
            start = task.start;
            turnOnAvailable = task.turnOnAvailable;
        };
    };

    public func stepStart(task: Types.PoolUpgradeTask) : async Types.PoolUpgradeTask {
        var poolCid = task.poolData.canisterId;
        let { module_hash } = await IC0Utils.canister_status(poolCid);
        await IC0Utils.start_canister(poolCid);
        {
            poolData = task.poolData;
            moduleHashBefore = task.moduleHashBefore;
            moduleHashAfter = module_hash;
            turnOffAvailable = task.turnOffAvailable;
            stop = task.stop;
            upgrade = task.upgrade;
            start = { timestamp = BlockTimestamp.blockTimestamp(); isDone = true; };
            turnOnAvailable = task.turnOnAvailable;
        };
    };

    public func stepTurnOnAvailable(task: Types.PoolUpgradeTask) : async Types.PoolUpgradeTask {
        await _setPoolAvailable(task.poolData.canisterId, true);
        {
            poolData = task.poolData;
            moduleHashBefore = task.moduleHashBefore;
            moduleHashAfter = task.moduleHashAfter;
            turnOffAvailable = task.turnOffAvailable;
            stop = task.stop;
            upgrade = task.upgrade;
            start = task.start;
            turnOnAvailable = { timestamp = BlockTimestamp.blockTimestamp(); isDone = true; };
        };
    };

    private func _setPoolAvailable(poolCid : Principal, available : Bool) : async () {
        var poolAct = actor (Principal.toText(poolCid)) : Types.SwapPoolActor;
        await poolAct.setAvailable(available);
    };
};