import Nat "mo:base/Nat";
import Debug "mo:base/Debug";
import Int "mo:base/Int";
import Text "mo:base/Text";
import Hash "mo:base/Hash";
import List "mo:base/List";
import Principal "mo:base/Principal";
import Result "mo:base/Result";
import HashMap "mo:base/HashMap";
import SafeUint "mo:commons/math/SafeUint";
import SafeInt "mo:commons/math/SafeInt";
import IntUtils "mo:commons/math/SafeInt/IntUtils";
import ListUtils "mo:commons/utils/ListUtils";
import Types "../Types";
import Tick "../libraries/Tick";
import TickBitmap "../libraries/TickBitmap";
import FullMath "../libraries/FullMath";
import TickMath "../libraries/TickMath";
import LiquidityMath "../libraries/LiquidityMath";
import SqrtPriceMath "../libraries/SqrtPriceMath";
import BlockTimestamp "../libraries/BlockTimestamp";
import FixedPoint128 "../libraries/FixedPoint128";

module PositionTick {

    public class Service(
        initUserPositions: [(Nat, Types.UserPositionInfo)], 
        initPositions: [(Text, Types.PositionInfo)],
        initTickBitmaps: [(Int, Nat)],
        initTicks: [(Text, Types.TickInfo)],
        initUserPositionIds: [(Text, [Nat])],
        initAllowanceUserPositions: [(Nat, Text)], 
    ) {
        private var _userPositions = HashMap.fromIter<Nat, Types.UserPositionInfo>(initUserPositions.vals(), 10, Nat.equal, Hash.hash);
        private var _positions = HashMap.fromIter<Text, Types.PositionInfo>(initPositions.vals(), 10, Text.equal, Text.hash);
        private var _ticks = HashMap.fromIter<Text, Types.TickInfo>(initTicks.vals(), 10, Text.equal, Text.hash);
        private var _tickBitmaps = HashMap.fromIter<Int, Nat>(initTickBitmaps.vals(), 10, Int.equal, Int.hash);
        private var _userPositionIds = HashMap.fromIter<Text, [Nat]>(initUserPositionIds.vals(), 10, Text.equal, Text.hash);
        private var _allowancedUserPositions = HashMap.fromIter<Nat, Text>(initAllowanceUserPositions.vals(), 10, Nat.equal, Hash.hash);

        public func getUserPositions() : HashMap.HashMap<Nat, Types.UserPositionInfo> {
            return _userPositions;
        };

        public func getUserPosition(positionId: Nat) : Types.UserPositionInfo {
            return switch(_userPositions.get(positionId)){
                case (?_p){ _p; };
                case (_){
                    {
                        tickLower = 0;
                        tickUpper = 0;
                        liquidity = 0;
                        feeGrowthInside0LastX128 = 0;
                        feeGrowthInside1LastX128 = 0;
                        tokensOwed0 = 0;
                        tokensOwed1 = 0;
                    }
                }
            };
        };

        public func putUserPosition(positionId: Nat, userPositionInfo: Types.UserPositionInfo) : () {
            _userPositions.put(positionId, userPositionInfo);
        };

        public func getPosition(positionKey: Text) : Types.PositionInfo {
            return switch(_positions.get(positionKey)){
                case (?_p){ _p; };
                case (_){
                    {
                        liquidity = 0;
                        feeGrowthInside0LastX128 = 0;
                        feeGrowthInside1LastX128 = 0;
                        tokensOwed0 = 0;
                        tokensOwed1 = 0;
                    }
                }
            };
        };

        public func putPosition(positionKey: Text, positionInfo: Types.PositionInfo) : () {
            _positions.put(positionKey, positionInfo);
        };

        public func getPositions() : HashMap.HashMap<Text, Types.PositionInfo> {
            return _positions;
        };

        public func putTickBitmap(wordPos: Int, bitInfo: Nat) : () {
            _tickBitmaps.put(wordPos, bitInfo);
        };

        public func getTickBitmaps() : HashMap.HashMap<Int, Nat> {
            return _tickBitmaps;
        };

        public func putTick(tickIndex: Text, tickInfo: Types.TickInfo) : () {
            _ticks.put(tickIndex, tickInfo);
        };

        public func getTicks() : HashMap.HashMap<Text, Types.TickInfo> {
            return _ticks;
        };

        public func putAllowancedUserPosition(positionId: Nat, spender: Text) : () {
            _allowancedUserPositions.put(positionId, spender);
        };

        public func deleteAllowancedUserPosition(positionId: Nat) : () {
            _allowancedUserPositions.delete(positionId);
        };

        public func getAllowancedUserPosition(positionId: Nat) : Text {
            return switch(_allowancedUserPositions.get(positionId)){
                case (?spender){ spender; }; case (_){ ""; };
            };
        };

        public func getAllowancedUserPositions() : HashMap.HashMap<Nat, Text> {
            return _allowancedUserPositions;
        };

        public func checkUserPositionIdByOwner(owner: Text, positionId: Nat) : Bool {
            switch(_userPositionIds.get(owner)) {
                case (?positionArray) {
                    if (ListUtils.arrayContains(positionArray, positionId, Nat.equal)){ true; } 
                    else { false; };
                };
                case (_) { false; };
            };
        };

        public func putUserPositionId(owner: Text, positionId: Nat) : () {
            switch(_userPositionIds.get(owner)) {
                case (?positionArray) {
                    var positionList : List.List<Nat> = List.fromArray(positionArray);
                    positionList := List.push(positionId, positionList);
                    _userPositionIds.put(owner, List.toArray(positionList));
                };
                case (_) {
                    var positionList = List.nil<Nat>();
                    positionList := List.push(positionId, positionList);
                    _userPositionIds.put(owner, List.toArray(positionList));
                };
            };
        };

        public func putUserPositionIds(owner: Text, positionIds: [Nat]) : () {
            switch(_userPositionIds.get(owner)) {
                case (?positionArray) {
                    var positionList : List.List<Nat> = List.fromArray(positionIds);
                    for (positionId in positionArray.vals()) {
                        if (not ListUtils.arrayContains(positionIds, positionId, Nat.equal)) {
                            positionList := List.push(positionId, positionList);
                        };
                    };
                    _userPositionIds.put(owner, List.toArray(positionList));
                };
                case (_) {
                    _userPositionIds.put(owner, positionIds);
                };
            };
        };

        public func removeUserPositionId(owner: Text, positionId: Nat) : () {
            switch(_userPositionIds.get(owner)) {
                case (?positionArray) {
                    _userPositionIds.put(owner, ListUtils.arrayRemove(positionArray, positionId, Nat.equal));
                };
                case (_) { };
            };
        };

        public func getUserPositionIdsByOwner(owner: Text) : [Nat] {
            switch(_userPositionIds.get(owner)) {
                case (?positionArray) { positionArray; };
                case (_) { [];};
            };
        };

        public func getUserPositionIds() : HashMap.HashMap<Text, [Nat]> {
            return _userPositionIds;
        };

        public func getTick(tickIndex: Text) : Types.TickInfo {
            return switch(_ticks.get(tickIndex)){
                case (?_t){ _t; };
                case (_){
                    {
                        var liquidityGross = 0;
                        var liquidityNet = 0;
                        var feeGrowthOutside0X128 = 0;
                        var feeGrowthOutside1X128 = 0;
                        var tickCumulativeOutside = 0;
                        var secondsPerLiquidityOutsideX128 = 0;
                        var secondsOutside = 0;
                        var initialized = false;
                    }
                }
            };
        };

        public func addPositionForUser(owner: Text, positionId: Nat, userPositionInfo: Types.UserPositionInfo) : () {
            _userPositions.put(positionId, userPositionInfo);
            switch(_userPositionIds.get(owner)) {
                case (?positionArray) {
                    var positionList : List.List<Nat> = List.fromArray(positionArray);
                    positionList := List.push(positionId, positionList);
                    _userPositionIds.put(owner, List.toArray(positionList));
                };
                case (_) {
                    var positionList = List.nil<Nat>();
                    positionList := List.push(positionId, positionList);
                    _userPositionIds.put(owner, List.toArray(positionList));
                };
            };
        };

        public func deletePositionForUser(owner: Text, positionId: Nat) : () {
            switch(_userPositionIds.get(owner)) {
                case (?positionArray) {
                    if (ListUtils.arrayContains(positionArray, positionId, Nat.equal)){
                        _userPositionIds.put(owner, ListUtils.arrayRemove(positionArray, positionId, Nat.equal));
                        ignore _userPositions.remove(positionId);
                    };
                };
                case (_) { };
            };
        };

        public func resetPositionsAndTicks(
            _userPositionsEntriesBak: [(Nat, Types.UserPositionInfo)],
            _positionsEntriesBak: [(Text, Types.PositionInfo)],
            _tickBitmapsEntriesBak: [(Int, Nat)],
            _ticksEntriesBak: [(Text, Types.TickInfo)],
            _userPositionIdsEntriesBak: [(Text, [Nat])], 
        ) : () {
            _userPositions := HashMap.fromIter<Nat, Types.UserPositionInfo>(_userPositionsEntriesBak.vals(), 100, Nat.equal, Hash.hash);
            _positions := HashMap.fromIter<Text, Types.PositionInfo>(_positionsEntriesBak.vals(), 100, Text.equal, Text.hash);
            _ticks := HashMap.fromIter<Text, Types.TickInfo>(_ticksEntriesBak.vals(), 100, Text.equal, Text.hash);
            _tickBitmaps := HashMap.fromIter<Int, Nat>(_tickBitmapsEntriesBak.vals(), 100, Int.equal, Int.hash);
            _userPositionIds := HashMap.fromIter<Text, [Nat]>(_userPositionIdsEntriesBak.vals(), 100, Text.equal, Text.hash);
        };

        public func modifyPosition(
            tickCurrent: Int,
            sqrtPriceX96Current: Nat,
            liquidityCurrent: Nat,
            feeGrowthGlobal0X128: Nat,
            feeGrowthGlobal1X128: Nat,
            maxLiquidityPerTick: Nat,
            tickSpacing: Int,
            tickLower: Int, 
            tickUpper: Int, 
            liquidityDelta: Int,
        ) : Result.Result<{ liquidityAfter: Nat; amount0: Int; amount1: Int; }, Text> {
            if (not _checkTicks(tickLower, tickUpper)) {
                return #err("illegal ticks");
            };
            var position = switch (_updatePosition(
                SafeInt.Int24(tickLower),
                SafeInt.Int24(tickUpper),
                SafeInt.Int128(liquidityDelta),
                SafeInt.Int24(tickCurrent),
                SafeUint.Uint256(feeGrowthGlobal0X128),
                SafeUint.Uint256(feeGrowthGlobal1X128),
                SafeUint.Uint128(maxLiquidityPerTick),
                SafeInt.Int24(tickSpacing),
            )) {
                case (#ok(result)) { result; };
                case (#err(code)) { return #err(code); };
            };
            var sqrtRatioAtTickLower = switch (TickMath.getSqrtRatioAtTick(SafeInt.Int24(tickLower))) {
                case (#ok(r)) { r; }; case (#err(code)) { return #err("modify TickMath.getSqrtRatioAtTick Lower failed: " # debug_show(code)); };
            };
            var sqrtRatioAtTickUpper = switch (TickMath.getSqrtRatioAtTick(SafeInt.Int24(tickUpper))) {
                 case (#ok(r)) { r; }; case (#err(code)) { return #err("modify TickMath.getSqrtRatioAtTick Upper failed: " # debug_show(code)); };
            };
            var amount0:Int = 0;
            var amount1:Int = 0;
            var liquidityAfter: Nat = liquidityCurrent;
            if (liquidityDelta != 0) {
                if (tickCurrent < tickLower) {
                    amount0 := switch (SqrtPriceMath.getAmount0Delta(
                        SafeUint.Uint160(sqrtRatioAtTickLower),
                        SafeUint.Uint160(sqrtRatioAtTickUpper),
                        SafeInt.Int128(liquidityDelta)
                    )) {
                        case (#ok(result)) { result; };
                        case (#err(code)) { return #err("modify SqrtPriceMath.getAmount0Delta failed: " # debug_show(code)); };
                    };
                } else if (tickCurrent < tickUpper) {
                    var liquidityBefore = liquidityCurrent;
                    amount0 := switch (SqrtPriceMath.getAmount0Delta(
                        SafeUint.Uint160(sqrtPriceX96Current),
                        SafeUint.Uint160(sqrtRatioAtTickUpper),
                        SafeInt.Int128(liquidityDelta)
                    )) {
                        case (#ok(result)) { result; };
                        case (#err(code)) { return #err("modify SqrtPriceMath.getAmount0Delta failed: " # debug_show(code)); };
                    };
                    amount1 := switch (SqrtPriceMath.getAmount1Delta(
                        SafeUint.Uint160(sqrtRatioAtTickLower),
                        SafeUint.Uint160(sqrtPriceX96Current),
                        SafeInt.Int128(liquidityDelta)
                    )) {
                        case (#ok(result)) { result; };
                        case (#err(code)) { return #err("modify SqrtPriceMath.getAmount1Delta failed: " # debug_show(code)); };
                    };
                    liquidityAfter := switch (LiquidityMath.addDelta(SafeUint.Uint128(liquidityBefore), SafeInt.Int128(liquidityDelta))) {
                        case (#ok(result)) { result; };
                        case (#err(code)) { return #err("modify LiquidityMath.addDelta failed: " # debug_show(code)); };
                    };
                } else {
                    amount1 := switch (SqrtPriceMath.getAmount1Delta(
                        SafeUint.Uint160(sqrtRatioAtTickLower),
                        SafeUint.Uint160(sqrtRatioAtTickUpper),
                        SafeInt.Int128(liquidityDelta)
                    )) {
                        case (#ok(result)) { result; };
                        case (#err(code)) { return #err("modify SqrtPriceMath.getAmount1Delta failed: " # debug_show(code)); };
                    };
                }
            };

            return #ok({
                liquidityAfter = liquidityAfter;
                amount0 = amount0;
                amount1 = amount1;
            });
        };

        private func _updatePosition(
            tickLower: SafeInt.Int24,
            tickUpper: SafeInt.Int24,
            liquidityDelta: SafeInt.Int128,
            tick: SafeInt.Int24,
            feeGrowthGlobal0X128: SafeUint.Uint256,
            feeGrowthGlobal1X128: SafeUint.Uint256,
            maxLiquidityPerTick: SafeUint.Uint128,
            tickSpacing: SafeInt.Int24,
        ) : Result.Result<Types.PositionInfo, Text> {
            var flippedLower: Bool = false;
            var flippedUpper: Bool = false;
            if (liquidityDelta.val() != 0) {
                var time = BlockTimestamp.blockTimestamp();

                var secondsPerLiquidityCumulativeX128 = 0;
                var tickCumulative = 0;

                var lowerUpdateResult = switch (Tick.update(
                    _ticks,
                    tickLower,
                    tick,
                    liquidityDelta,
                    feeGrowthGlobal0X128,
                    feeGrowthGlobal1X128,
                    SafeUint.Uint160(secondsPerLiquidityCumulativeX128),
                    SafeInt.Int56(tickCumulative),
                    SafeUint.Uint32(time),
                    false,
                    maxLiquidityPerTick
                )) {
                    case (#ok(result)) { result; };
                    case (#err(code)) { return #err("tick lower update failed: " # debug_show(code)); };
                };
                flippedLower := lowerUpdateResult.updateResult;
                _ticks.put(Int.toText(tickLower.val()), {
                    var liquidityGross = lowerUpdateResult.liquidityGross;
                    var liquidityNet = lowerUpdateResult.liquidityNet;
                    var feeGrowthOutside0X128 = lowerUpdateResult.feeGrowthOutside0X128;
                    var feeGrowthOutside1X128 = lowerUpdateResult.feeGrowthOutside1X128;
                    var tickCumulativeOutside = lowerUpdateResult.tickCumulativeOutside;
                    var secondsPerLiquidityOutsideX128 = lowerUpdateResult.secondsPerLiquidityOutsideX128;
                    var secondsOutside = lowerUpdateResult.secondsOutside;
                    var initialized = lowerUpdateResult.initialized;
                });
                var upperUpdateResult = switch (Tick.update(
                    _ticks,
                    tickUpper,
                    tick,
                    liquidityDelta,
                    feeGrowthGlobal0X128,
                    feeGrowthGlobal1X128,
                    SafeUint.Uint160(secondsPerLiquidityCumulativeX128),
                    SafeInt.Int56(tickCumulative),
                    SafeUint.Uint32(time),
                    true,
                    maxLiquidityPerTick
                )) {
                    case (#ok(result)) { result; };
                    case (#err(code)) { return #err("tick upper update failed: " # debug_show(code)); };
                };
                flippedUpper := upperUpdateResult.updateResult;
                _ticks.put(Int.toText(tickUpper.val()), {
                    var liquidityGross = upperUpdateResult.liquidityGross;
                    var liquidityNet = upperUpdateResult.liquidityNet;
                    var feeGrowthOutside0X128 = upperUpdateResult.feeGrowthOutside0X128;
                    var feeGrowthOutside1X128 = upperUpdateResult.feeGrowthOutside1X128;
                    var tickCumulativeOutside = upperUpdateResult.tickCumulativeOutside;
                    var secondsPerLiquidityOutsideX128 = upperUpdateResult.secondsPerLiquidityOutsideX128;
                    var secondsOutside = upperUpdateResult.secondsOutside;
                    var initialized = upperUpdateResult.initialized;
                });
                if (flippedLower) {
                    var flipTickResult = switch (TickBitmap.flipTick(_tickBitmaps, tickLower, tickSpacing)) {
                        case (#ok(result)) { result; };
                        case (#err(code)) { return #err("tick lower flip failed: "# debug_show(code)); };
                    };
                    _tickBitmaps.put(flipTickResult.wordPos, flipTickResult.tickStatus);
                };
                if (flippedUpper) {
                    var flipTickResult = switch (TickBitmap.flipTick(_tickBitmaps, tickUpper, tickSpacing)) {
                        case (#ok(result)) { result; };
                        case (#err(code)) { return #err("tick upper flip failed: "# debug_show(code)); };
                    };
                    _tickBitmaps.put(flipTickResult.wordPos, flipTickResult.tickStatus);
                };
            };
            var _data = Tick.getFeeGrowthInside(
                _ticks,
                tickLower,
                tickUpper,
                tick,
                feeGrowthGlobal0X128,
                feeGrowthGlobal1X128
            );
            var feeGrowthInside0X128:SafeUint.Uint256 = SafeUint.Uint256(_data.feeGrowthInside0X128);
            var feeGrowthInside1X128:SafeUint.Uint256 = SafeUint.Uint256(_data.feeGrowthInside1X128);

            let positionKey = "" # Int.toText(tickLower.val()) # "_" # Int.toText(tickUpper.val()) # "";
            var position = switch (_update(positionKey, liquidityDelta, feeGrowthInside0X128, feeGrowthInside1X128)) {
                case (#ok(p)) { p; }; case (#err(code)) { return #err(code); };
            };

            if (liquidityDelta.val() < 0) {
                if (flippedLower) { _ticks.delete(Int.toText(tick.val())); };
                if (flippedUpper) { _ticks.delete(Int.toText(tick.val())); };
            };
            return #ok(position);
        };

        private func _update(
            positionKey: Text,
            liquidityDelta: SafeInt.Int128,
            feeGrowthInside0X128:SafeUint.Uint256,
            feeGrowthInside1X128:SafeUint.Uint256,
        ): Result.Result<Types.PositionInfo, Text> {
            var _self: Types.PositionInfo = switch(_positions.get(positionKey)){
                case (?_p){ _p; };
                case (_){
                    {
                        liquidity = 0;
                        feeGrowthInside0LastX128 = 0;
                        feeGrowthInside1LastX128 = 0;
                        tokensOwed0 = 0;
                        tokensOwed1 = 0;
                    }
                }
            };

            var _liquidity = _self.liquidity;
            var liquidityNext = 0;
            if (liquidityDelta.val() == 0) {
                if(_self.liquidity <= 0){ return #ok(_self); };
                liquidityNext := _self.liquidity;
            } else {
                liquidityNext := switch (LiquidityMath.addDelta(SafeUint.Uint128(_self.liquidity), liquidityDelta)) {
                    case (#ok(result)) { result; };
                    case (#err(code)) { return #err("add liquidity delta failed " # debug_show(code)); };
                };
            };
            // calculate accumulated fees
            var tokensOwed0 = FullMath.mulDiv(
                feeGrowthInside0X128.sub(SafeUint.Uint256(_self.feeGrowthInside0LastX128)), 
                SafeUint.Uint256(_self.liquidity), 
                SafeUint.Uint256(FixedPoint128.Q128)
            );
            var tokensOwed1 = FullMath.mulDiv(
                feeGrowthInside1X128.sub(SafeUint.Uint256(_self.feeGrowthInside1LastX128)), 
                SafeUint.Uint256(_self.liquidity), 
                SafeUint.Uint256(FixedPoint128.Q128)
            );

            // update the position
            if (liquidityDelta.val() != 0) _liquidity := liquidityNext;

            var _tokensOwed0 = _self.tokensOwed0;
            var _tokensOwed1 = _self.tokensOwed1;
            if (tokensOwed0 > 0 or tokensOwed1 > 0) {
                // overflow is acceptable, have to withdraw before you hit type(uint128).max fees
                _tokensOwed0 := SafeUint.Uint128(_tokensOwed0).add(SafeUint.Uint128(tokensOwed0)).val();
                _tokensOwed1 := SafeUint.Uint128(_tokensOwed1).add(SafeUint.Uint128(tokensOwed1)).val();
            };

            _positions.put(positionKey, {
                tokensOwed0 = _tokensOwed0;
                tokensOwed1 = _tokensOwed1;
                liquidity = _liquidity;
                feeGrowthInside0LastX128 = feeGrowthInside0X128.val();
                feeGrowthInside1LastX128 = feeGrowthInside1X128.val();
            });

            return #ok({
                tokensOwed0 = _tokensOwed0;
                tokensOwed1 = _tokensOwed1;
                liquidity = _liquidity;
                feeGrowthInside0LastX128 = feeGrowthInside0X128.val();
                feeGrowthInside1LastX128 = feeGrowthInside1X128.val();
            });
        };

        private func _checkTicks(tickLower: Int, tickUpper:Int) : Bool {
            if((tickLower >= tickUpper) or (tickLower < Tick.MIN_TICK) or (tickUpper > Tick.MAX_TICK)){
                return false;
            };
            return true;
        };
    };
    
}