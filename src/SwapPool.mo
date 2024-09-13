import Nat "mo:base/Nat";
import Int "mo:base/Int";
import Iter "mo:base/Iter";
import List "mo:base/List";
import Buffer "mo:base/Buffer";
import Cycles "mo:base/ExperimentalCycles";
import Text "mo:base/Text";
import Result "mo:base/Result";
import Principal "mo:base/Principal";
import Debug "mo:base/Debug";
import Option "mo:base/Option";
import Error "mo:base/Error";
import Time "mo:base/Time";
import Timer "mo:base/Timer";
import HashMap "mo:base/HashMap";
import RBTree "mo:base/RBTree";
import PoolUtils "./utils/PoolUtils";
import AccountUtils "./utils/AccountUtils";
import PositionTick "./components/PositionTick";
import TokenHolder "./components/TokenHolder";
import TokenAmount "./components/TokenAmount";
import SwapRecord "./components/SwapRecord";
import Types "./Types";
import LiquidityMath "./libraries/LiquidityMath";
import LiquidityAmounts "./libraries/LiquidityAmounts";
import TickMath "./libraries/TickMath";
import SqrtPriceMath "./libraries/SqrtPriceMath";
import Tick "./libraries/Tick";
import BlockTimestamp "./libraries/BlockTimestamp";
import TickBitmap "./libraries/TickBitmap";
import FullMath "./libraries/FullMath";
import SwapMath "./libraries/SwapMath";
import FixedPoint128 "./libraries/FixedPoint128";
import SafeUint "mo:commons/math/SafeUint";
import SafeInt "mo:commons/math/SafeInt";
import IntUtils "mo:commons/math/SafeInt/IntUtils";
import TextUtils "mo:commons/utils/TextUtils";
import PrincipalUtils "mo:commons/utils/PrincipalUtils";
import TokenFactory "mo:token-adapter/TokenFactory";
import TokenAdapterTypes "mo:token-adapter/Types";
import ListUtils "mo:commons/utils/ListUtils";
import CollectionUtils "mo:commons/utils/CollectionUtils";
import Bool "mo:base/Bool";
import Prim "mo:⛔";
import Hash "mo:base/Hash";

shared (initMsg) actor class SwapPool(
    token0 : Types.Token,
    token1 : Types.Token,
    infoCid : Principal,
    feeReceiverCid : Principal,
    trustedCanisterManagerCid : Principal,
) = this {
    private stable var _inited : Bool = false;
    public shared ({ caller }) func init (
        fee : Nat,
        tickSpacing : Int,
        sqrtPriceX96 : Nat,
    ) : async () {
        assert(not _inited);
        assert(_isAvailable(caller));
        _checkControllerPermission(caller);

        _tick := switch (TickMath.getTickAtSqrtRatio(SafeUint.Uint160(sqrtPriceX96))) { 
            case (#ok(r)) { r }; 
            case (#err(code)) { throw Error.reject("init pool failed: " # code); }; 
        };
        _fee := fee;
        _tickSpacing := tickSpacing;
        _sqrtPriceX96 := sqrtPriceX96;
        _maxLiquidityPerTick := Tick.tickSpacingToMaxLiquidityPerTick(SafeInt.Int24(tickSpacing));
        _inited := true;
        _canisterId := ?Principal.fromActor(this);
        await _syncTokenFee();
    };

    private var _canisterId : ?Principal = null;
    private stable var _admins : [Principal] = [];
    private stable var _available : Bool = true;
    private stable var _whiteList : [Principal] = [];
    /// pool invariant metadatas.
    private stable var _token0 : Types.Token = PoolUtils.sort(token0, token1).0;
    private stable var _token1 : Types.Token = PoolUtils.sort(token0, token1).1;
    private stable var _fee : Nat = 0;
    private stable var _tickSpacing : Int = 0;
    private stable var _maxLiquidityPerTick : Nat = 0;

    private stable var _token0Fee : ?Nat = null;
    private stable var _token1Fee : ?Nat = null;

    private stable var _positionLimit : Nat = 10000;

    private stable var _recordState : SwapRecord.State = {
        records = [];
        retryCount = 0;
        errors = [];
    };
    private stable var _tokenHolderState : TokenHolder.State = {
        token0 = _token0;
        token1 = _token1;
        balances = [];
    };
    private stable var _tokenAmountState : TokenAmount.State = {
        tokenAmount0 = 0;
        tokenAmount1 = 0;
        swapFee0Repurchase = 0;
        swapFee1Repurchase = 0;
        withdrawErrorLogIndex = 0;
        withdrawErrorLog = [];
    };
    /// pool invariant metadatas.
    private stable var _tick : Int = 0;
    private stable var _sqrtPriceX96 : Nat = 0;
    private stable var _liquidity : Nat = 0;
    private stable var _feeGrowthGlobal0X128 : Nat = 0;
    private stable var _feeGrowthGlobal1X128 : Nat = 0;
    private stable var _nextPositionId : Nat = 1;

    private stable var _userPositionsEntries : [(Nat, Types.UserPositionInfo)] = [];
    private stable var _positionsEntries : [(Text, Types.PositionInfo)] = [];
    private stable var _tickBitmapsEntries : [(Int, Nat)] = [];
    private stable var _ticksEntries : [(Text, Types.TickInfo)] = [];
    private stable var _userPositionIdsEntries : [(Text, [Nat])] = [];
    private stable var _allowancedUserPositionEntries : [(Nat, Text)] = [];

    private var _positionTickService : PositionTick.Service = PositionTick.Service(_userPositionsEntries, _positionsEntries, _tickBitmapsEntries, _ticksEntries, _userPositionIdsEntries, _allowancedUserPositionEntries);
    private var _tokenHolderService : TokenHolder.Service = TokenHolder.Service(_tokenHolderState);
    private var _swapRecordService : SwapRecord.Service = SwapRecord.Service(_recordState, Principal.toText(infoCid));
    private var _tokenAmountService : TokenAmount.Service = TokenAmount.Service(_tokenAmountState);

    private var _token0Act : TokenAdapterTypes.TokenAdapter = TokenFactory.getAdapter(_token0.address, _token0.standard);
    private var _token1Act : TokenAdapterTypes.TokenAdapter = TokenFactory.getAdapter(_token1.address, _token1.standard);
    private let _trustAct = actor (Principal.toText(trustedCanisterManagerCid)) : actor { isCanisterTrusted : shared query (Principal) -> async Bool; };
    private let NANOSECONDS_PER_SECOND : Nat = 1_000_000_000;
    private let SECOND_PER_DAY : Nat = 86400;
    private func _syncRecord() : async () { await _swapRecordService.syncRecord(); };
    let _syncRecordPerMinute = Timer.recurringTimer<system>(#seconds(60), _syncRecord);

    private func _syncTokenFee() : async () { _token0Fee := ?(await _token0Act.fee()); _token1Fee := ?(await _token1Act.fee()); };
    let _syncTokenFeePerHour = Timer.recurringTimer<system>(#seconds(3600), _syncTokenFee);

    // --------------------------- limit order ------------------------------------
    private stable var _isLimitOrderAvailable = true;
    public shared (msg) func setLimitOrderAvailable(available : Bool) : async () {
        assert(_isAvailable(msg.caller));
        _checkAdminPermission(msg.caller);
        _isLimitOrderAvailable := available;
    };
    public query func getLimitOrderAvailabilityState() : async Bool { _isLimitOrderAvailable; };

    private stable var _limitOrderStack : List.List<(Types.LimitOrderKey, Types.LimitOrderValue)> = List.nil<(Types.LimitOrderKey, Types.LimitOrderValue)>();
    private func _pushLimitOrderStack(limitOrder : (Types.LimitOrderKey, Types.LimitOrderValue)) : () { _limitOrderStack := ?(limitOrder, _limitOrderStack); };
    private func _popLimitOrderStack() : ?(Types.LimitOrderKey, Types.LimitOrderValue) { switch _limitOrderStack { case null { null }; case (?(h, t)) { _limitOrderStack := t; ?h }; }; };
    public query func getLimitOrderStack() : async Result.Result<[(Types.LimitOrderKey, Types.LimitOrderValue)], Types.Error> { return #ok(List.toArray(_limitOrderStack)); };

    private func _limitOrderKeyCompare(x : Types.LimitOrderKey, y : Types.LimitOrderKey) : { #less; #equal; #greater } {
        if (x.tickLimit < y.tickLimit) { #less } 
        else if (x.tickLimit == y.tickLimit) {
            if (x.timestamp < y.timestamp) { #less } else if (x.timestamp == y.timestamp) { #equal } else { #greater };
        } 
        else { #greater }
    };
    private stable var _lowerLimitOrderEntries : [(Types.LimitOrderKey, Types.LimitOrderValue)] = [];
    private stable var _upperLimitOrderEntries : [(Types.LimitOrderKey, Types.LimitOrderValue)] = [];
    private var _lowerLimitOrders = RBTree.RBTree<Types.LimitOrderKey, Types.LimitOrderValue>(_limitOrderKeyCompare);
    private var _upperLimitOrders = RBTree.RBTree<Types.LimitOrderKey, Types.LimitOrderValue>(_limitOrderKeyCompare);
    private func _checkLimitOrder() : async () {
        if (not _isLimitOrderAvailable) { return; };
        // backward iteration
        label lt {
            for ((key, value) in RBTree.iter(_lowerLimitOrders.share(), #bwd)) {
                if (_tick <= key.tickLimit) {
                    _lowerLimitOrders.delete({ timestamp = key.timestamp; tickLimit = key.tickLimit; });
                    _pushLimitOrderStack((key, value));
                    ignore Timer.setTimer<system>(#nanoseconds (0), _autoDecrease);
                    ignore Timer.setTimer<system>(#nanoseconds (0), _checkLimitOrder);
                    return;
                } else { break lt; };
            };
        };
        // forward iteration
        label ut {
            for ((key, value) in RBTree.iter(_upperLimitOrders.share(), #fwd)) {
                if (_tick >= key.tickLimit) {
                    _upperLimitOrders.delete({ timestamp = key.timestamp; tickLimit = key.tickLimit; });
                    _pushLimitOrderStack((key, value));
                    ignore Timer.setTimer<system>(#nanoseconds (0), _autoDecrease);
                    ignore Timer.setTimer<system>(#nanoseconds (0), _checkLimitOrder);
                    return;
                } else { break ut; };
            };
        };
    };
    private func _autoDecrease() : async () {
        switch (_popLimitOrderStack()) {
            case (?(key, value)) {
                var userPositionInfo = _positionTickService.getUserPosition(value.userPositionId);
                ignore _decreaseLiquidity(value.owner, { positionId = value.userPositionId; liquidity = Nat.toText(userPositionInfo.liquidity); });
            };
            case (_) {};
        };
    };
    public query func getLimitOrders() : async Result.Result<{
        lowerLimitOrders : [(Types.LimitOrderKey, Types.LimitOrderValue)];
        upperLimitOrders : [(Types.LimitOrderKey, Types.LimitOrderValue)];
    }, Types.Error> {
        return #ok({
            lowerLimitOrders = Iter.toArray(RBTree.iter(_lowerLimitOrders.share(), #bwd));
            upperLimitOrders = Iter.toArray(RBTree.iter(_upperLimitOrders.share(), #fwd));
        });
    };
    public query func getUserLimitOrders(user : Principal) : async Result.Result<{ lowerLimitOrderIds : [Nat]; upperLimitOrdersIds : [Nat]; }, Types.Error> {
        let userPositionIds = _positionTickService.getUserPositionIdsByOwner(PrincipalUtils.toAddress(user));
        var lowerLimitOrderIds : Buffer.Buffer<Nat> = Buffer.Buffer<Nat>(0);
        var upperLimitOrderIds : Buffer.Buffer<Nat> = Buffer.Buffer<Nat>(0);
        for (userPositionId in userPositionIds.vals()) {
            label ut for ((key, value) in RBTree.iter(_upperLimitOrders.share(), #fwd)) {
                if (Nat.equal(userPositionId, value.userPositionId)) {
                    upperLimitOrderIds.add(userPositionId);
                    break ut;
                };
            };
            label lt for ((key, value) in RBTree.iter(_lowerLimitOrders.share(), #bwd)) {
                if (Nat.equal(userPositionId, value.userPositionId)) {
                    lowerLimitOrderIds.add(userPositionId);
                    break lt;
                };
            };
        };     
        return #ok({
            lowerLimitOrderIds = Buffer.toArray(lowerLimitOrderIds);
            upperLimitOrdersIds = Buffer.toArray(upperLimitOrderIds);
        });
    };

    private stable var _transferLogArray : [(Nat, Types.TransferLog)] = [];
    private stable var _transferIndex: Nat = 0;
    private var _transferLog: HashMap.HashMap<Nat, Types.TransferLog> = HashMap.fromIter<Nat, Types.TransferLog>(_transferLogArray.vals(), 0, Nat.equal, Hash.hash);
    private func _preTransfer(owner: Principal, from: Principal, fromSubaccount: ?Blob, to: Principal, action: Text, token: Types.Token, amount: Nat, fee: Nat): Nat {
        let time: Nat = Int.abs(Time.now());
        let ind: Nat = _transferIndex;
        let transferLog: Types.TransferLog = {
            index = ind;
            owner = owner;
            from = from;
            fromSubaccount = fromSubaccount;
            to = to;
            action = action;
            amount = amount;
            fee = fee;
            token = token;
            result = "processing";
            errorMsg = "";
            daysFrom19700101 = time / NANOSECONDS_PER_SECOND / SECOND_PER_DAY;
            timestamp = time;
        };
        _transferLog.put(ind, transferLog);
        _transferIndex := _transferIndex + 1;
        return ind;
    };
    private func _postTransferComplete(index: Nat) {
        _transferLog.delete(index);
    };
    private func _postTransferError(index: Nat, msg: Text) {
        switch(_transferLog.get(index)) {
            case (?log) {
                _transferLog.put(index, {
                    index = log.index;
                    owner = log.owner;
                    from = log.from;
                    fromSubaccount = log.fromSubaccount;
                    to = log.to;
                    action = log.action;
                    amount = log.amount;
                    fee = log.fee;
                    token = log.token;
                    result = "error";
                    errorMsg = msg;
                    daysFrom19700101 = log.daysFrom19700101;
                    timestamp = log.timestamp;
                });
            };
            case (_) {};
        };
    };
    private stable var _claimLog : [Text] = [];
    private var _claimLogBuffer : Buffer.Buffer<Text> = Buffer.Buffer<Text>(0);
    public query func getClaimLog() : async [Text] { return Buffer.toArray(_claimLogBuffer); };
    private func _claimSwapFeeRepurchase() : async () {
        let balance0 = _tokenAmountService.getSwapFee0Repurchase();
        let balance1 = _tokenAmountService.getSwapFee1Repurchase();
        if (balance0 > 0 or balance1 > 0) {
            _claimLogBuffer.add("{\"amount0\": \"" # debug_show(balance0) # "\", \"amount1\": \"" # debug_show(balance1) # "\", \"timestamp\": \"" # debug_show(BlockTimestamp.blockTimestamp()) # "\"}");
            ignore _tokenHolderService.deposit2(feeReceiverCid, _token0, balance0, _token1, balance1);
            _tokenAmountService.setTokenAmount0(SafeUint.Uint256(_tokenAmountService.getTokenAmount0()).sub(SafeUint.Uint256(balance0)).val());
            _tokenAmountService.setTokenAmount1(SafeUint.Uint256(_tokenAmountService.getTokenAmount1()).sub(SafeUint.Uint256(balance1)).val());
            _tokenAmountService.setSwapFee0Repurchase(0);
            _tokenAmountService.setSwapFee1Repurchase(0);
        };
    };
    let _claimSwapFeeRepurchasePerWeek = Timer.recurringTimer<system>(#seconds(604800), _claimSwapFeeRepurchase);

    private func _checkAmount(amountDesired : Nat, operator : Principal, token : Types.Token) : Bool {
        var balance = _tokenHolderService.getBalance(operator, token);
        if (amountDesired > balance) { return false };
        return true;
    };

    private func _checkAmounts(amount0Desired : Nat, amount1Desired : Nat, operator : Principal) : Bool {
        var accountBalance : TokenHolder.AccountBalance = _tokenHolderService.getBalances(operator);
        if (amount0Desired > accountBalance.balance0 or amount1Desired > accountBalance.balance1) { return false; };
        return true;
    };

    private func _checkUserPositionLimit() : Bool {
        if (_positionTickService.getUserPositions().size() >= _positionLimit) { return false; };
        return true;
    };

    private func _addLiquidity(tickLower : Int, tickUpper : Int, amount0Desired : SafeUint.Uint256, amount1Desired : SafeUint.Uint256) : Result.Result<{ amount0 : Nat; amount1 : Nat; liquidityDelta : Nat }, Text> {
        var sqrtPriceX96 = SafeUint.Uint160(_sqrtPriceX96);
        var sqrtRatioAX96 = switch (TickMath.getSqrtRatioAtTick(SafeInt.Int24(tickLower))) {
            case (#ok(r)) { SafeUint.Uint160(r) };
            case (#err(code)) {
                return #err("compute sqrtRatioAX96 failed: " # debug_show (code));
            };
        };
        var sqrtRatioBX96 = switch (TickMath.getSqrtRatioAtTick(SafeInt.Int24(tickUpper))) {
            case (#ok(r)) { SafeUint.Uint160(r) };
            case (#err(code)) {
                return #err("compute sqrtRatioBX96 failed: " # debug_show (code));
            };
        };
        var liquidityDelta = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            sqrtRatioAX96,
            sqrtRatioBX96,
            amount0Desired,
            amount1Desired,
        );
        var data = switch (
            _positionTickService.modifyPosition(
                _tick,
                _sqrtPriceX96,
                _liquidity,
                _feeGrowthGlobal0X128,
                _feeGrowthGlobal1X128,
                _maxLiquidityPerTick,
                _tickSpacing,
                tickLower,
                tickUpper,
                liquidityDelta,
            )
        ) {
            case (#ok(result)) { result };
            case (#err(code)) {
                return #err("modify position failed: " # debug_show (code));
            };
        };
        _liquidity := data.liquidityAfter;

        return #ok({
            amount0 = IntUtils.toNat(data.amount0, 256);
            amount1 = IntUtils.toNat(data.amount1, 256);
            liquidityDelta = liquidityDelta;
        });
    };

    private func _decreaseLiquidity(owner : Principal, args : Types.DecreaseLiquidityArgs) : Result.Result<{ amount0 : Nat; amount1 : Nat }, Types.Error> {        
        var userPositionInfo = _positionTickService.getUserPosition(args.positionId);
        var liquidityDelta = TextUtils.toNat(args.liquidity);
        if (Nat.equal(liquidityDelta, 0)) { return #err(#InternalError("Illegal liquidity delta")); };
        if (liquidityDelta > userPositionInfo.liquidity) { return #err(#InternalError("Illegal liquidity delta")); };
        var collectResult = { amount0 = 0; amount1 = 0 };
        ignore switch (_removeLiquidity(args.positionId, liquidityDelta)) {
            case (#ok(result)) { result };
            case (#err(code)) { Prim.trap("Decrease liquidity failed: _removeLiquidity " # debug_show (code)); };
        };
        collectResult := switch (_collect(args.positionId)) {
            case (#ok(result)) { result };
            case (#err(code)) { Prim.trap("Decrease liquidity failed: _collect " # debug_show (code)); };
        };
        if (liquidityDelta == userPositionInfo.liquidity) {
            _positionTickService.deletePositionForUser(PrincipalUtils.toAddress(owner), args.positionId);
        };
        _tokenAmountService.setTokenAmount0(SafeUint.Uint256(_tokenAmountService.getTokenAmount0()).sub(SafeUint.Uint256(collectResult.amount0)).val());
        _tokenAmountService.setTokenAmount1(SafeUint.Uint256(_tokenAmountService.getTokenAmount1()).sub(SafeUint.Uint256(collectResult.amount1)).val());
        if (0 != collectResult.amount0 or 0 != collectResult.amount1) {
            _pushSwapInfoCache(#decreaseLiquidity, Principal.toText(Principal.fromActor(this)), Principal.toText(owner), Principal.toText(owner), liquidityDelta, collectResult.amount0, collectResult.amount1, true);
            ignore _tokenHolderService.deposit2(owner, _token0, collectResult.amount0, _token1, collectResult.amount1);
        };
        return #ok({
            amount0 = collectResult.amount0;
            amount1 = collectResult.amount1;
        });
    };

    private func _removeLiquidity(positionId : Nat, liquidityDelta : Nat) : Result.Result<{ amount0 : Nat; amount1 : Nat }, Text> {
        var userPositionInfo = _positionTickService.getUserPosition(positionId);
        var data = switch (
            _positionTickService.modifyPosition(
                _tick,
                _sqrtPriceX96,
                _liquidity,
                _feeGrowthGlobal0X128,
                _feeGrowthGlobal1X128,
                _maxLiquidityPerTick,
                _tickSpacing,
                userPositionInfo.tickLower,
                userPositionInfo.tickUpper,
                -liquidityDelta,
            )
        ) {
            case (#ok(result)) { result };
            case (#err(code)) {
                return #err("remove liquidity modify position failed: " # debug_show (code));
            };
        };
        var amount0 = IntUtils.toNat(-data.amount0, 128);
        var amount1 = IntUtils.toNat(-data.amount1, 128);
        _liquidity := data.liquidityAfter;

        let positionKey = "" # Int.toText(userPositionInfo.tickLower) # "_" # Int.toText(userPositionInfo.tickUpper) # "";
        var positionInfo = _positionTickService.getPosition(positionKey);

        positionInfo := {
            liquidity = positionInfo.liquidity;
            feeGrowthInside0LastX128 = positionInfo.feeGrowthInside0LastX128;
            feeGrowthInside1LastX128 = positionInfo.feeGrowthInside1LastX128;
            tokensOwed0 = SafeUint.Uint128(positionInfo.tokensOwed0).add(SafeUint.Uint128(amount0)).val();
            tokensOwed1 = SafeUint.Uint128(positionInfo.tokensOwed1).add(SafeUint.Uint128(amount1)).val();
        };
        _positionTickService.putPosition(positionKey, positionInfo);

        let distributedFeeResult = _distributeFee(positionInfo, userPositionInfo);
        _tokenAmountService.setSwapFee0Repurchase(SafeUint.Uint128(_tokenAmountService.getSwapFee0Repurchase()).add(SafeUint.Uint128(distributedFeeResult.swapFee0Repurchase)).val());
        _tokenAmountService.setSwapFee1Repurchase(SafeUint.Uint128(_tokenAmountService.getSwapFee1Repurchase()).add(SafeUint.Uint128(distributedFeeResult.swapFee1Repurchase)).val());

        _positionTickService.putUserPosition(
            positionId,
            {
                tokensOwed0 = SafeUint.Uint128(userPositionInfo.tokensOwed0).add(SafeUint.Uint128(amount0)).add(SafeUint.Uint128(distributedFeeResult.swapFee0Lp)).val();
                tokensOwed1 = SafeUint.Uint128(userPositionInfo.tokensOwed1).add(SafeUint.Uint128(amount1)).add(SafeUint.Uint128(distributedFeeResult.swapFee1Lp)).val();
                feeGrowthInside0LastX128 = positionInfo.feeGrowthInside0LastX128;
                feeGrowthInside1LastX128 = positionInfo.feeGrowthInside1LastX128;
                liquidity = SafeUint.Uint128(userPositionInfo.liquidity).sub(SafeUint.Uint128(liquidityDelta)).val();
                tickLower = userPositionInfo.tickLower;
                tickUpper = userPositionInfo.tickUpper;
            },
        );
        return #ok({
            amount0 = amount0;
            amount1 = amount1;
        });
    };

    private func _collect(positionId : Nat) : Result.Result<{ amount0 : Nat; amount1 : Nat }, Text> {
        var userPositionInfo = _positionTickService.getUserPosition(positionId);
        let positionKey = "" # Int.toText(userPositionInfo.tickLower) # "_" # Int.toText(userPositionInfo.tickUpper) # "";
        var positionInfo = _positionTickService.getPosition(positionKey);
        var amount0Collect = if (userPositionInfo.tokensOwed0 > positionInfo.tokensOwed0) {
            positionInfo.tokensOwed0;
        } else { userPositionInfo.tokensOwed0 };
        var amount1Collect = if (userPositionInfo.tokensOwed1 > positionInfo.tokensOwed1) {
            positionInfo.tokensOwed1;
        } else { userPositionInfo.tokensOwed1 };
        _positionTickService.putPosition(
            positionKey,
            {
                liquidity = positionInfo.liquidity;
                feeGrowthInside0LastX128 = positionInfo.feeGrowthInside0LastX128;
                feeGrowthInside1LastX128 = positionInfo.feeGrowthInside1LastX128;
                tokensOwed0 = SafeUint.Uint128(positionInfo.tokensOwed0).sub(SafeUint.Uint128(amount0Collect)).val();
                tokensOwed1 = SafeUint.Uint128(positionInfo.tokensOwed1).sub(SafeUint.Uint128(amount1Collect)).val();
            },
        );
        _positionTickService.putUserPosition(
            positionId,
            {
                tokensOwed0 = SafeUint.Uint128(userPositionInfo.tokensOwed0).sub(SafeUint.Uint128(amount0Collect)).val();
                tokensOwed1 = SafeUint.Uint128(userPositionInfo.tokensOwed1).sub(SafeUint.Uint128(amount1Collect)).val();
                feeGrowthInside0LastX128 = positionInfo.feeGrowthInside0LastX128;
                feeGrowthInside1LastX128 = positionInfo.feeGrowthInside1LastX128;
                liquidity = userPositionInfo.liquidity;
                tickLower = userPositionInfo.tickLower;
                tickUpper = userPositionInfo.tickUpper;
            },
        );
        return #ok({
            amount0 = amount0Collect;
            amount1 = amount1Collect;
        });
    };

    private func _preSwap(args : Types.SwapArgs, operator : Principal) : Result.Result<Nat, Types.Error> {
        var swapResult = switch (_computeSwap(args, operator, false)) {
            case (#ok(result)) { result };
            case (#err(code)) {
                return #err(#InternalError("preswap " # debug_show (code)));
            };
        };
        var swapAmount = 0;
        if (args.zeroForOne and swapResult.amount1 < 0) {
            swapAmount := IntUtils.toNat(-(swapResult.amount1), 256);
        };
        if ((not args.zeroForOne) and swapResult.amount0 < 0) {
            swapAmount := IntUtils.toNat(-(swapResult.amount0), 256);
        };
        return #ok(swapAmount);
    };

    private func _preSwapForAll(args : Types.SwapArgs, operator : Principal) : Result.Result<Nat, Types.Error> {
        var swapResult = switch (_computeSwap(args, operator, false)) {
            case (#ok(result)) { result };
            case (#err(code)) { return #err(#InternalError("preswap " # debug_show (code))); };
        };
        var effectiveAmount = 0;
        var swapAmount = 0;
        if (args.zeroForOne and swapResult.amount1 < 0) {
            swapAmount := IntUtils.toNat(-(swapResult.amount1), 256);
            effectiveAmount := IntUtils.toNat(swapResult.amount0, 256);
        };
        if ((not args.zeroForOne) and swapResult.amount0 < 0) {
            swapAmount := IntUtils.toNat(-(swapResult.amount0), 256);
            effectiveAmount := IntUtils.toNat(swapResult.amount1, 256);
        };

        if (swapAmount <= 0) {
            return #err(#InternalError("The amount of input token is too small."));
        } else if (TextUtils.toInt(args.amountIn) > effectiveAmount and effectiveAmount > 0) {
            return #err(#InternalError("The maximum amount of input tokens is " # debug_show (effectiveAmount)));
        } else {
            return #ok(swapAmount);
        };
    };

    private func _computeSwap(args : Types.SwapArgs, operator : Principal, effective : Bool) : Result.Result<{ amount0 : Int; amount1 : Int }, Text> {
        var amountIn = TextUtils.toInt(args.amountIn);
        if (amountIn <= 0) { return #err("illegal amountIn") };
        if (effective) {
            if (not _checkAmount(IntUtils.toNat(amountIn, 256), operator, if (args.zeroForOne) { _token0 } else { _token1 })) {
                return #err("illegal deposit balance in pool");
            };
        };
        var sqrtPriceLimitX96 = if (args.zeroForOne) {
            SafeUint.Uint160(SqrtPriceMath.MIN_SQRT_RATIO).add(SafeUint.Uint160(1)).val();
        } else {
            SafeUint.Uint160(SqrtPriceMath.MAX_SQRT_RATIO).sub(SafeUint.Uint160(1)).val();
        };
        if (args.zeroForOne) {
            if (sqrtPriceLimitX96 >= _sqrtPriceX96 or sqrtPriceLimitX96 <= SqrtPriceMath.MIN_SQRT_RATIO) return #err("price limit out of bound");
        } else {
            if (sqrtPriceLimitX96 <= _sqrtPriceX96 or sqrtPriceLimitX96 >= SqrtPriceMath.MAX_SQRT_RATIO) return #err("price limit out of bound");
        };

        var timestamp : Nat = BlockTimestamp.blockTimestamp();
        var cache = {
            var liquidityStart : Nat = _liquidity;
            var blockTimestamp : Nat = timestamp;
            var tickCumulative : Int = 0;
            var secondsPerLiquidityCumulativeX128 : Nat = 0;
            var computedLatestObservation : Bool = false;
        };
        var state = {
            var amountSpecifiedRemaining : Int = amountIn;
            var amountCalculated : Int = 0;
            var sqrtPriceX96 : Nat = _sqrtPriceX96;
            var tick : Int = _tick;
            var feeGrowthGlobalX128 : Nat = if (args.zeroForOne) {
                _feeGrowthGlobal0X128;
            } else { _feeGrowthGlobal1X128 };
            var protocolFee : Nat = 0;
            var liquidity : Nat = cache.liquidityStart;
        };
        var feeAmount = 0;

        // continue swapping as long as we haven't used the entire input/output and haven't reached the price limit
        while (Int.notEqual(state.amountSpecifiedRemaining, 0) and Int.notEqual(state.sqrtPriceX96, sqrtPriceLimitX96)) {
            var nextInitializedTickWithinOneWord = switch (
                TickBitmap.nextInitializedTickWithinOneWord(
                    _positionTickService.getTickBitmaps(),
                    SafeInt.Int24(state.tick),
                    SafeInt.Int24(_tickSpacing),
                    args.zeroForOne,
                )
            ) {
                case (#ok(result)) { result };
                case (#err(code)) {
                    return #err("get next initialized tick within one word failed: " # debug_show (code));
                };
            };
            var step = {
                var sqrtPriceNextX96 : Nat = 0;
                var tickNext : Int = nextInitializedTickWithinOneWord.next;
                var initialized : Bool = nextInitializedTickWithinOneWord.initialized;
                var sqrtPriceStartX96 : Nat = state.sqrtPriceX96;
                var amountIn : Nat = 0;
                var amountOut : Nat = 0;
                var feeAmount : Nat = 0;
            };
            // ensure that we do not overshoot the min/max tick, as the tick bitmap is not aware of these bounds
            if (step.tickNext < Tick.MIN_TICK) {
                step.tickNext := Tick.MIN_TICK;
            } else if (step.tickNext > Tick.MAX_TICK) {
                step.tickNext := Tick.MAX_TICK;
            };
            // get the price for the next tick
            step.sqrtPriceNextX96 := switch (TickMath.getSqrtRatioAtTick(SafeInt.Int24(step.tickNext))) {
                case (#ok(r)) { r };
                case (#err(code)) {
                    return #err("get sqrt ratio at tick failed: " # debug_show (code));
                };
            };
            // compute values to swap to the target tick, price limit, or point where input/output amount is exhausted
            var sqrtPrice = if (args.zeroForOne) {
                if (step.sqrtPriceNextX96 < sqrtPriceLimitX96) {
                    sqrtPriceLimitX96;
                } else { step.sqrtPriceNextX96 };
            } else {
                if (step.sqrtPriceNextX96 > sqrtPriceLimitX96) {
                    sqrtPriceLimitX96;
                } else { step.sqrtPriceNextX96 };
            };
            var computeSwapStep = switch (
                SwapMath.computeSwapStep(
                    SafeUint.Uint160(state.sqrtPriceX96),
                    SafeUint.Uint160(sqrtPrice),
                    SafeUint.Uint128(state.liquidity),
                    SafeInt.Int256(state.amountSpecifiedRemaining),
                    SafeUint.Uint24(_fee),
                )
            ) {
                case (#ok(result)) { result };
                case (#err(code)) {
                    return #err("compute swap step failed: " # debug_show (code));
                };
            };
            state.sqrtPriceX96 := computeSwapStep.sqrtRatioNextX96;
            step.amountIn := computeSwapStep.amountIn;
            step.amountOut := computeSwapStep.amountOut;
            step.feeAmount := computeSwapStep.feeAmount;

            if (effective) {
                feeAmount := feeAmount + computeSwapStep.feeAmount;
            };

            state.amountSpecifiedRemaining := SafeInt.Int256(state.amountSpecifiedRemaining).sub(SafeInt.Int256(IntUtils.toInt(step.amountIn + step.feeAmount, 256))).val();
            state.amountCalculated := SafeInt.Int256(state.amountCalculated).sub(SafeInt.Int256(IntUtils.toInt(step.amountOut, 256))).val();
            // update global fee tracker
            if (state.liquidity > 0) {
                state.feeGrowthGlobalX128 := state.feeGrowthGlobalX128 + FullMath.mulDiv(SafeUint.Uint256(step.feeAmount), SafeUint.Uint256(FixedPoint128.Q128), SafeUint.Uint256(state.liquidity));
            };

            // shift tick if we reached the next price
            if (state.sqrtPriceX96 == step.sqrtPriceNextX96) {
                // if the tick is initialized, run the tick transition
                if (step.initialized) {
                    // crosses an initialized tick
                    var crossedTick = Tick.cross(
                        _positionTickService.getTicks(),
                        SafeInt.Int24(step.tickNext),
                        SafeUint.Uint256(if (args.zeroForOne) { state.feeGrowthGlobalX128 } else { _feeGrowthGlobal0X128 }),
                        SafeUint.Uint256(if (args.zeroForOne) { _feeGrowthGlobal1X128 } else { state.feeGrowthGlobalX128 }),
                        SafeUint.Uint160(cache.secondsPerLiquidityCumulativeX128),
                        SafeInt.Int56(cache.tickCumulative),
                        SafeUint.Uint32(cache.blockTimestamp),
                    );
                    var liquidityNet : Int = crossedTick.liquidityNet;

                    if (effective) {
                        _positionTickService.putTick(Int.toText(step.tickNext), crossedTick);
                    };

                    // if we're moving leftward, we interpret liquidityNet as the opposite sign safe because liquidityNet cannot be type(int128).min
                    if (args.zeroForOne) liquidityNet := -liquidityNet;
                    state.liquidity := switch (LiquidityMath.addDelta(SafeUint.Uint128(state.liquidity), SafeInt.Int128(liquidityNet))) {
                        case (#ok(result)) { result };
                        case (#err(code)) {
                            return #err("liquidity add delta failed: " # debug_show (code));
                        };
                    };
                };
                state.tick := if (args.zeroForOne) { step.tickNext - 1 } else {
                    step.tickNext;
                };
            } else if (state.sqrtPriceX96 != step.sqrtPriceStartX96) {
                // recompute unless we're on a lower tick boundary (i.e. already transitioned ticks), and haven't moved
                state.tick := switch (TickMath.getTickAtSqrtRatio(SafeUint.Uint160(state.sqrtPriceX96))) {
                    case (#ok(r)) { r };
                    case (#err(code)) {
                        return #err("get tick at sqrt ratio failed: " # debug_show (code));
                    };
                };
            };
        };

        if (effective) {
            // update the price
            _sqrtPriceX96 := state.sqrtPriceX96;
            // update tick if it changed
            if (_tick != state.tick) {
                _tick := state.tick;
            };
            // update liquidity if it changed
            if (cache.liquidityStart != state.liquidity) _liquidity := state.liquidity;
            // update global fee growth
            if (args.zeroForOne) {
                _feeGrowthGlobal0X128 := state.feeGrowthGlobalX128;
            } else { _feeGrowthGlobal1X128 := state.feeGrowthGlobalX128 };
        };
        return #ok(
            if (args.zeroForOne) {
                {
                    amount0 = SafeInt.Int256(amountIn).sub(SafeInt.Int256(state.amountSpecifiedRemaining)).val();
                    amount1 = state.amountCalculated;
                }
            } else {
                {
                    amount0 = state.amountCalculated;
                    amount1 = SafeInt.Int256(amountIn).sub(SafeInt.Int256(state.amountSpecifiedRemaining)).val();
                }
            }
        );
    };

    private func _refreshIncome(positionId : Nat) : Result.Result<{ tokensOwed0 : Nat; tokensOwed1 : Nat }, Text> {
        var userPositionInfo = _positionTickService.getUserPosition(positionId);
        ignore switch (
            _positionTickService.modifyPosition(
                _tick,
                _sqrtPriceX96,
                _liquidity,
                _feeGrowthGlobal0X128,
                _feeGrowthGlobal1X128,
                _maxLiquidityPerTick,
                _tickSpacing,
                userPositionInfo.tickLower,
                userPositionInfo.tickUpper,
                0,
            )
        ) {
            case (#ok(result)) { result };
            case (#err(code)) {
                return #err("refresh income failed: " # debug_show (code));
            };
        };
        let positionKey = "" # Int.toText(userPositionInfo.tickLower) # "_" # Int.toText(userPositionInfo.tickUpper) # "";
        var positionInfo = _positionTickService.getPosition(positionKey);
        let distributedFeeResult = _distributeFee(positionInfo, userPositionInfo);

        return #ok({
            tokensOwed0 = SafeUint.Uint128(userPositionInfo.tokensOwed0).add(SafeUint.Uint128(distributedFeeResult.swapFee0Lp)).val();
            tokensOwed1 = SafeUint.Uint128(userPositionInfo.tokensOwed1).add(SafeUint.Uint128(distributedFeeResult.swapFee1Lp)).val();
        });
    };

    private func _distributeFee(positionInfo : Types.PositionInfo, userPositionInfo : Types.UserPositionInfo) : {
        swapFee0Repurchase : Nat;
        swapFee1Repurchase : Nat;
        swapFee0Lp : Nat;
        swapFee1Lp : Nat;
    } {
        var swapFee0Total = SafeUint.Uint128(
            FullMath.mulDiv(
                SafeUint.Uint256(positionInfo.feeGrowthInside0LastX128).sub(SafeUint.Uint256(userPositionInfo.feeGrowthInside0LastX128)),
                SafeUint.Uint256(userPositionInfo.liquidity),
                SafeUint.Uint256(FixedPoint128.Q128),
            )
        ).val();
        // var swapFee0Repurchase = 0;
        var swapFee0Repurchase = SafeUint.Uint128(swapFee0Total).div(SafeUint.Uint128(10)).mul(SafeUint.Uint128(2)).val();
        var swapFee0Lp = if (swapFee0Total > swapFee0Repurchase) {
            SafeUint.Uint128(swapFee0Total).sub(SafeUint.Uint128(swapFee0Repurchase)).val();
        } else { swapFee0Repurchase := 0; swapFee0Total };
        var swapFee1Total = SafeUint.Uint128(
            FullMath.mulDiv(
                SafeUint.Uint256(positionInfo.feeGrowthInside1LastX128).sub(SafeUint.Uint256(userPositionInfo.feeGrowthInside1LastX128)),
                SafeUint.Uint256(userPositionInfo.liquidity),
                SafeUint.Uint256(FixedPoint128.Q128),
            )
        ).val();
        // var swapFee1Repurchase = 0;
        var swapFee1Repurchase = SafeUint.Uint128(swapFee1Total).div(SafeUint.Uint128(10)).mul(SafeUint.Uint128(2)).val();
        var swapFee1Lp = if (swapFee1Total > swapFee1Repurchase) {
            SafeUint.Uint128(swapFee1Total).sub(SafeUint.Uint128(swapFee1Repurchase)).val();
        } else { swapFee1Repurchase := 0; swapFee1Total };

        return {
            swapFee0Repurchase = swapFee0Repurchase;
            swapFee1Repurchase = swapFee1Repurchase;
            swapFee0Lp = swapFee0Lp;
            swapFee1Lp = swapFee1Lp;
        };
    };

    private func _pushSwapInfoCache(
        action : Types.TransactionType,
        from : Text,
        to : Text,
        recipient : Text,
        liquidityChange : Nat,
        token0ChangeAmount : Nat,
        token1ChangeAmount : Nat,
        zeroForOne : Bool,
    ) : () {
        var poolCid : Text = Principal.toText(Principal.fromActor(this));
        let (token0Id, token1Id, token0Standard, token1Standard, token0Amount, token1Amount) = if (zeroForOne) {
            (_token0.address, _token1.address, _token0.standard, _token1.standard, _tokenAmountService.getTokenAmount0(), _tokenAmountService.getTokenAmount1());
        } else {
            (_token1.address, _token0.address, _token1.standard, _token0.standard, _tokenAmountService.getTokenAmount1(), _tokenAmountService.getTokenAmount0());
        };
        _swapRecordService.addRecord(
            poolCid,
            token0Id,
            token0Standard,
            token0Amount,
            token0ChangeAmount,
            token1Id,
            token1Standard,
            token1Amount,
            token1ChangeAmount,
            action,
            from,
            to,
            recipient,
            _tick,
            _sqrtPriceX96,
            _liquidity,
            liquidityChange,
            _fee,
        );
    };
    private func _submit(): async () {};
    private func _rollback(msg: Text) : () {
        Prim.trap(msg);
    };

    public shared ({ caller }) func deposit(args : Types.DepositArgs) : async Result.Result<Nat, Types.Error> {
        assert(_isAvailable(caller));
        if (Principal.isAnonymous(caller)) return #err(#InternalError("Illegal anonymous call"));
        if (args.token != _token0.address and args.token != _token1.address) {
            return #err(#UnsupportedToken(args.token));
        };
        let (token, tokenAct, fee) = if (Text.equal(args.token, _token0.address)) {
            (_token0, _token0Act, switch _token0Fee { 
                case (?f) { f }; 
                case (null) {
                    var f = await _token0Act.fee();
                    _token0Fee := ?(f);
                    f;
                };
            });
        } else {
            (_token1, _token1Act, switch _token1Fee { 
                case (?f) { f }; 
                case (null) {
                    var f = await _token1Act.fee();
                    _token1Fee := ?(f);
                    f;
                };
            });
        };
        if (not Nat.equal(fee, args.fee)) {
            return #err(#InternalError("Wrong fee cache, please try later"));
        };
        if (Text.notEqual(token.standard, "ICP") and Text.notEqual(token.standard, "ICRC1") and Text.notEqual(token.standard, "ICRC2") and Text.notEqual(token.standard, "ICRC3")) {
            return #err(#InternalError("Illegal token standard: " # debug_show (token.standard)));
        };
        var canisterId = Principal.fromActor(this);
        var subaccount : ?Blob = Option.make(AccountUtils.principalToBlob(caller));
        if (Option.isNull(subaccount)) {
            return #err(#InternalError("Subaccount can't be null"));
        };
        if (not (args.amount > 0)) { return #err(#InternalError("Input amount should be greater than 0")) };
        if (not (args.amount > args.fee)) { return #err(#InternalError("Input amount should be greater than fee")) };
        var amount : Nat = Nat.sub(args.amount, args.fee);
        let preTransIndex: Nat = _preTransfer(caller, canisterId, subaccount, canisterId, "deposit", token, amount, args.fee);
        try {
            switch (await tokenAct.transfer({ 
                from = { owner = canisterId; subaccount = subaccount }; from_subaccount = subaccount; 
                to = { owner = canisterId; subaccount = null }; 
                amount = amount; 
                fee = ?args.fee; 
                memo = Option.make(PoolUtils.natToBlob(preTransIndex)); 
                created_at_time = null 
            })) {
                case (#Ok(_)) {
                    ignore _tokenHolderService.deposit(caller, token, amount);
                    _postTransferComplete(preTransIndex);
                    return #ok(amount);
                };
                case (#Err(msg)) {
                    _postTransferComplete(preTransIndex);
                    return #err(#InternalError(debug_show (msg)));
                };
            };
        } catch (e) {        
            let msg: Text = debug_show (Error.message(e));
            _postTransferError(preTransIndex, msg);   
            return #err(#InternalError(msg));
        };
    };

    public shared ({ caller }) func depositFrom(args : Types.DepositArgs) : async Result.Result<Nat, Types.Error> {
        assert(_isAvailable(caller));
        if (Principal.isAnonymous(caller)) return #err(#InternalError("Illegal anonymous call"));
        if (args.token != _token0.address and args.token != _token1.address) {
            return #err(#UnsupportedToken(args.token));
        };
        let (token, tokenAct, fee) = if (Text.equal(args.token, _token0.address)) {
            (_token0, _token0Act, switch _token0Fee { 
                case (?f) { f }; 
                case (null) {
                    var f = await _token0Act.fee();
                    _token0Fee := ?(f);
                    f;
                };
            });
        } else {
            (_token1, _token1Act, switch _token1Fee { 
                case (?f) { f }; 
                case (null) {
                    var f = await _token1Act.fee();
                    _token1Fee := ?(f);
                    f;
                };
            });
        };
        if (not Nat.equal(fee, args.fee)) {
            return #err(#InternalError("Wrong fee cache, please try later"));
        };
        var canisterId = Principal.fromActor(this);
        if (Principal.equal(caller, canisterId)) {
                return #err(#InternalError("Caller and canister id can't be the same"));
            };
        let preTransIndex: Nat = _preTransfer(caller, caller, null, canisterId, "deposit", token, args.amount, args.fee);
        try {
            switch (await tokenAct.transferFrom({ 
                from = { owner = caller; subaccount = null }; 
                to = { owner = canisterId; subaccount = null }; 
                amount = args.amount; 
                fee = ?args.fee; 
                memo = Option.make(PoolUtils.natToBlob(preTransIndex)); 
                created_at_time = null 
            })) {
                case (#Ok(_)) {
                    ignore _tokenHolderService.deposit(caller, token, args.amount);
                    _postTransferComplete(preTransIndex);
                    return #ok(args.amount);
                };
                case (#Err(msg)) {
                    _postTransferComplete(preTransIndex);
                    return #err(#InternalError(debug_show (msg)));
                };
            };
        } catch (e) {
            let msg: Text = debug_show (Error.message(e));
            _postTransferError(preTransIndex, msg);
            return #err(#InternalError(msg));
        };
    };

    public shared ({ caller }) func withdraw(args : Types.WithdrawArgs) : async Result.Result<Nat, Types.Error> {
        assert(_isAvailable(caller));
        if (Principal.isAnonymous(caller)) return #err(#InternalError("Illegal anonymous call"));
        if (args.token != _token0.address and args.token != _token1.address) {
            return #err(#UnsupportedToken(args.token));
        };
        let (token, tokenAct, fee) = if (Text.equal(args.token, _token0.address)) {
            (_token0, _token0Act, switch _token0Fee { 
                case (?f) { f }; 
                case (null) {
                    var f = await _token0Act.fee();
                    _token0Fee := ?(f);
                    f;
                };
            });
        } else {
            (_token1, _token1Act, switch _token1Fee { 
                case (?f) { f }; 
                case (null) {
                    var f = await _token1Act.fee();
                    _token1Fee := ?(f);
                    f;
                };
            });
        };
        if (not Nat.equal(fee, args.fee)) {
            return #err(#InternalError("Wrong fee cache, please try later"));
        };
        var canisterId = Principal.fromActor(this);
        var balance : Nat = _tokenHolderService.getBalance(caller, token);
        if (not (balance > 0)) { return #err(#InsufficientFunds) };
        if (not (args.amount > 0)) {
            return #err(#InternalError("Amount can not be 0"));
        };
        if (args.amount > balance) { return #err(#InsufficientFunds) };
        if (not (args.amount > fee)) { return #err(#InsufficientFunds) };
        var amount : Nat = Nat.sub(args.amount, fee);
        if (_tokenHolderService.withdraw(caller, token, args.amount)) {
            var preTransIndex = _preTransfer(caller, canisterId, null, caller, "withdraw", token, amount, args.fee);
            try{
                switch (await tokenAct.transfer({ 
                    from = { owner = canisterId; subaccount = null }; from_subaccount = null; 
                    to = { owner = caller; subaccount = null }; 
                    amount = amount; 
                    fee = ?args.fee; 
                    memo = Option.make(PoolUtils.natToBlob(preTransIndex));  
                    created_at_time = null 
                })) {
                    case (#Ok(_)) {
                        _postTransferComplete(preTransIndex);
                        return #ok(amount);
                    };
                    case (#Err(msg)) {
                        _postTransferError(preTransIndex, debug_show(msg));
                        return #err(#InternalError(debug_show (msg)));
                    };
                };
            } catch (e) {        
                let msg: Text = debug_show (Error.message(e));
                _postTransferError(preTransIndex, msg);   
                return #err(#InternalError(msg));
            };
        } else {
            return #err(#InsufficientFunds);
        };
    };

    public shared ({ caller }) func depositAllAndMint(args : Types.DepositAndMintArgs) : async Result.Result<Nat, Types.Error> {
        assert(_isAvailable(caller));
        _checkAdminPermission(caller);
        if (not _checkUserPositionLimit()) {
            return #err(#InternalError("Number of user position exceeds limit"));
        };
        if ((args.tickLower >= args.tickUpper) or (args.tickLower < Tick.MIN_TICK) or (args.tickUpper > Tick.MAX_TICK)) {
            return #err(#InternalError("Illegal tick number"));
        };
        if (Text.notEqual(_token0.standard, "ICP") and Text.notEqual(_token0.standard, "ICRC1") and Text.notEqual(_token0.standard, "ICRC2") and Text.notEqual(_token0.standard, "ICRC3")) {
            return #err(#InternalError("Illegal token0 standard: " # debug_show (_token0.standard)));
        };
        if (Text.notEqual(_token1.standard, "ICP") and Text.notEqual(_token1.standard, "ICRC1") and Text.notEqual(_token1.standard, "ICRC2") and Text.notEqual(_token1.standard, "ICRC3")) {
            return #err(#InternalError("Illegal token1 standard: " # debug_show (_token1.standard)));
        };
        var fee0 = switch _token0Fee {
            case (?f) { f };
            case (null) {
                return #err(#InternalError("Fee0 cache not available, please try later"));
            };
        };
        var fee1 = switch _token1Fee {
            case (?f) { f };
            case (null) {
                return #err(#InternalError("Fee1 cache not available, please try later"));
            };
        };
        if (not Nat.equal(fee0, args.fee0)) {
            return #err(#InternalError("Wrong fee0 cache, please try later"));
        };
        if (not Nat.equal(fee1, args.fee1)) {
            return #err(#InternalError("Wrong fee1 cache, please try later"));
        };
        var canisterId = Principal.fromActor(this);
        var subaccount : ?Blob = Option.make(AccountUtils.principalToBlob(args.positionOwner));
        if (Option.isNull(subaccount)) {
            return #err(#InternalError("Subaccount can't be null"));
        };

        if (args.amount0 > 0) {
            if (args.amount0 > args.fee0) {
                var amount0 : Nat = Nat.sub(args.amount0, args.fee0);
                let preTransIndex = _preTransfer(args.positionOwner, canisterId, subaccount, canisterId, "deposit", token0, amount0, args.fee0);
                switch (await _token0Act.transfer({ 
                    from = { owner = canisterId; subaccount = subaccount }; from_subaccount = subaccount; 
                    to = { owner = canisterId; subaccount = null }; 
                    amount = amount0; 
                    fee = ?args.fee0; 
                    memo = Option.make(PoolUtils.natToBlob(preTransIndex)); 
                    created_at_time = null
                })) {
                    case (#Ok(_)) { 
                        ignore _tokenHolderService.deposit(args.positionOwner, _token0, amount0); 
                        _postTransferComplete(preTransIndex);
                    };
                    case (#Err(msg)) { 
                        _postTransferComplete(preTransIndex);
                        return #err(#InternalError(debug_show(msg))); 
                    };
                };
            };
        };

        if (args.amount1 > 0) {
            if (args.amount1 > args.fee1) {
                var amount1 : Nat = Nat.sub(args.amount1, args.fee1);
                let preTransIndex = _preTransfer(args.positionOwner, canisterId, subaccount, canisterId, "deposit", token1, amount1, args.fee1);
                switch (await _token1Act.transfer({ 
                    from = { owner = canisterId; subaccount = subaccount }; from_subaccount = subaccount; 
                    to = { owner = canisterId; subaccount = null }; 
                    amount = amount1; 
                    fee = ?args.fee1; 
                    memo = Option.make(PoolUtils.natToBlob(preTransIndex)); 
                    created_at_time = null 
                })) {
                    case (#Ok(_)) { 
                        ignore _tokenHolderService.deposit(args.positionOwner, _token1, amount1); 
                        _postTransferComplete(preTransIndex);    
                    };
                    case (#Err(msg)) { 
                        _postTransferComplete(preTransIndex);
                        return #err(#InternalError(debug_show(msg))); 
                    };
                };
            };
        };
        // Submit the above message to prevent an incorrect rollback of the token holder balance when a trap occurs below.
        await _submit();

        var amount0Desired = SafeUint.Uint256(TextUtils.toNat(args.amount0Desired));
        var amount1Desired = SafeUint.Uint256(TextUtils.toNat(args.amount1Desired));
        let unusedBalance = _tokenHolderService.getBalances(args.positionOwner);
        let (amount0, amount1) = (unusedBalance.balance0, unusedBalance.balance1);

        if (_tick < args.tickLower) {
            if (amount0 == 0) {
                throw Error.reject("Insufficient funds of token0");
            };
            if (amount0Desired.val() == 0 or amount0Desired.val() > amount0) {
                throw Error.reject("Balance of token0: " # debug_show (amount0) # " is less than amount0Desired");
            };
        } else if (_tick < args.tickUpper) {
            if (amount0 == 0) {
                throw Error.reject("Insufficient funds of token0");
            };
            if (amount1 == 0) {
                throw Error.reject("Insufficient funds of token1");
            };
            if (amount0Desired.val() == 0 or amount0Desired.val() > amount0) {
                throw Error.reject("Balance of token0: " # debug_show (amount0) # " is less than amount0Desired");
            };
            if (amount1Desired.val() == 0 or amount1Desired.val() > amount1) {
                throw Error.reject("Balance of token1: " # debug_show (amount1) # " is less than amount1Desired");
            };
        } else {
            if (amount1 == 0) {
                throw Error.reject("Insufficient funds of token1");
            };
            if (amount1Desired.val() == 0 or amount1Desired.val() > amount1) {
                throw Error.reject("Balance of token1: " # debug_show (amount1) # " is less than amount1Desired");
            };
        };
        let positionId = _nextPositionId;
        _nextPositionId := _nextPositionId + 1;
        try {
            var addResult = switch (_addLiquidity(args.tickLower, args.tickUpper, amount0Desired, amount1Desired)) {
                case (#ok(result)) { result };
                case (#err(code)) {
                    throw Error.reject("auto mint " # debug_show (code));
                };
            };
            var positionInfo = _positionTickService.getPosition("" # Int.toText(args.tickLower) # "_" # Int.toText(args.tickUpper) # "");
            _positionTickService.addPositionForUser(
                PrincipalUtils.toAddress(args.positionOwner),
                positionId,
                {
                    tickLower = args.tickLower;
                    tickUpper = args.tickUpper;
                    liquidity = addResult.liquidityDelta;
                    feeGrowthInside0LastX128 = positionInfo.feeGrowthInside0LastX128;
                    feeGrowthInside1LastX128 = positionInfo.feeGrowthInside1LastX128;
                    tokensOwed0 = 0;
                    tokensOwed1 = 0;
                },
            );
            _tokenAmountService.setTokenAmount0(SafeUint.Uint256(_tokenAmountService.getTokenAmount0()).add(SafeUint.Uint256(addResult.amount0)).val());
            _tokenAmountService.setTokenAmount1(SafeUint.Uint256(_tokenAmountService.getTokenAmount1()).add(SafeUint.Uint256(addResult.amount1)).val());
            ignore _tokenHolderService.withdraw2(args.positionOwner, _token0, addResult.amount0, _token1, addResult.amount1);

            _pushSwapInfoCache(#addLiquidity, Principal.toText(args.positionOwner), Principal.toText(Principal.fromActor(this)), Principal.toText(args.positionOwner), addResult.liquidityDelta, addResult.amount0, addResult.amount1, true);
        } catch (e) {
            _rollback("DepositAllAndMint.mint failed: " # Error.message(e));
        };

        return #ok(positionId);
    };

    public shared (msg) func mint(args : Types.MintArgs) : async Result.Result<Nat, Types.Error> {
        assert(_isAvailable(msg.caller));
        if (Principal.isAnonymous(msg.caller)) return #err(#InternalError("Illegal anonymous call"));
        if (not _checkUserPositionLimit()) { return #err(#InternalError("Number of user position exceeds limit")); };
        var amount0Desired = SafeUint.Uint256(TextUtils.toNat(args.amount0Desired));
        var amount1Desired = SafeUint.Uint256(TextUtils.toNat(args.amount1Desired));
        if (Nat.equal(amount0Desired.val(), 0) and Nat.equal(amount1Desired.val(), 0)) { return #err(#InternalError("Amount desired can't be both 0")); };

        if (not _checkAmounts(amount0Desired.val(), amount1Desired.val(), msg.caller)) {
            var accountBalance : TokenHolder.AccountBalance = _tokenHolderService.getBalances(msg.caller);
            return #err(#InternalError("Illegal balance in pool. " 
                # "amount0Desired=" # debug_show (amount0Desired.val()) # ", amount1Desired=" # debug_show (amount1Desired.val())
                # ". amount0Balance=" # debug_show (accountBalance.balance0) # ", amount1Balance=" # debug_show (accountBalance.balance1)
            ));
        };
        try {
            let positionId = _nextPositionId;
            _nextPositionId := _nextPositionId + 1;

            var addResult = switch (_addLiquidity(args.tickLower, args.tickUpper, amount0Desired, amount1Desired)) {
                case (#ok(result)) { result }; case (#err(code)) { throw Error.reject("mint " # debug_show (code)); };
            };
            // check actualAmount
            if (addResult.amount0 > amount0Desired.val() or addResult.amount1 > amount1Desired.val()) {
                // throw error to rollback
                throw Error.reject("Illegal balance in pool. " 
                # "amount0Desired=" # debug_show (amount0Desired.val()) # ", amount1Desired=" # debug_show (amount1Desired.val())
                # ". actualAmount0=" # debug_show (addResult.amount0) # ", actualAmount1=" # debug_show (addResult.amount1));
            };

            var positionInfo = _positionTickService.getPosition("" # Int.toText(args.tickLower) # "_" # Int.toText(args.tickUpper) # "");
            _positionTickService.addPositionForUser(
                PrincipalUtils.toAddress(msg.caller),
                positionId,
                {
                    tickLower = args.tickLower;
                    tickUpper = args.tickUpper;
                    liquidity = addResult.liquidityDelta;
                    feeGrowthInside0LastX128 = positionInfo.feeGrowthInside0LastX128;
                    feeGrowthInside1LastX128 = positionInfo.feeGrowthInside1LastX128;
                    tokensOwed0 = 0;
                    tokensOwed1 = 0;
                },
            );
            _tokenAmountService.setTokenAmount0(SafeUint.Uint256(_tokenAmountService.getTokenAmount0()).add(SafeUint.Uint256(addResult.amount0)).val());
            _tokenAmountService.setTokenAmount1(SafeUint.Uint256(_tokenAmountService.getTokenAmount1()).add(SafeUint.Uint256(addResult.amount1)).val());
            _pushSwapInfoCache(#addLiquidity, Principal.toText(msg.caller), Principal.toText(Principal.fromActor(this)), Principal.toText(msg.caller), addResult.liquidityDelta, addResult.amount0, addResult.amount1, true);
            ignore _tokenHolderService.withdraw2(msg.caller, _token0, addResult.amount0, _token1, addResult.amount1);

            return #ok(positionId);
        } catch (e) {
            _rollback("mint failed: " # Error.message(e));
            return #err(#InternalError("Mint failed: " # Error.message(e)));
        };
    };

    public shared (msg) func addLimitOrder(args : Types.LimitOrderArgs) : async Result.Result<Bool, Types.Error> {
        assert(_isAvailable(msg.caller) and _isLimitOrderAvailable);
        if (Principal.isAnonymous(msg.caller)) return #err(#InternalError("Illegal anonymous call"));
        if (not _positionTickService.checkUserPositionIdByOwner(PrincipalUtils.toAddress(msg.caller), args.positionId)) {
            return #err(#InternalError("Check operator failed"));
        };

        var tickCurrent = _tick;
        var tickLimit = args.tickLimit;
        var userPositionInfo = _positionTickService.getUserPosition(args.positionId);
        var tickLower = userPositionInfo.tickLower;
        var tickUpper = userPositionInfo.tickUpper;
        if (tickLimit > tickUpper or tickLimit < tickLower) { return #err(#InternalError("Invalid tickLimit.")); };
        var timestamp = Int.abs(Time.now());
        if (tickCurrent < tickLower and tickLimit > tickLower) {
            _upperLimitOrders.put({ timestamp = timestamp; tickLimit = tickLimit; }, { userPositionId = args.positionId; owner = msg.caller; });
        } else if (tickCurrent > tickUpper and tickLimit < tickUpper) {
            _lowerLimitOrders.put({ timestamp = timestamp; tickLimit = tickLimit; }, { userPositionId = args.positionId; owner = msg.caller; });
        } else {
            return #err(#InternalError("Invalid price range."));
        };
        return #ok(true);
    };

    public shared (msg) func increaseLiquidity(args : Types.IncreaseLiquidityArgs) : async Result.Result<Nat, Types.Error> {
        assert(_isAvailable(msg.caller));
        // verify msg.caller matches the owner of position
        if (not _positionTickService.checkUserPositionIdByOwner(PrincipalUtils.toAddress(msg.caller), args.positionId)) {
            return #err(#InternalError("Check operator failed"));
        };
        var amount0Desired = SafeUint.Uint256(TextUtils.toNat(args.amount0Desired));
        var amount1Desired = SafeUint.Uint256(TextUtils.toNat(args.amount1Desired));
        if (Nat.equal(amount0Desired.val(), 0) and Nat.equal(amount1Desired.val(), 0)) { return #err(#InternalError("Amount desired can't be both 0")); };

        if (not _checkAmounts(amount0Desired.val(), amount1Desired.val(), msg.caller)) {
            var accountBalance : TokenHolder.AccountBalance = _tokenHolderService.getBalances(msg.caller);
            return #err(#InternalError("Illegal balance in pool. " 
                # "amount0Desired=" # debug_show (amount0Desired.val()) # ", amount1Desired=" # debug_show (amount1Desired.val())
                # ". amount0Balance=" # debug_show (accountBalance.balance0) # ", amount1Balance=" # debug_show (accountBalance.balance1)
            ));       
        };
        var userPositionInfo = _positionTickService.getUserPosition(args.positionId);
        try {
            var addResult = switch (_addLiquidity(userPositionInfo.tickLower, userPositionInfo.tickUpper, amount0Desired, amount1Desired)) {
                case (#ok(result)) { result };
                case (#err(code)) {
                    throw Error.reject("increaseLiquidity " # debug_show (code));
                };
            };

            // check actualAmount
            if (addResult.amount0 > amount0Desired.val() or addResult.amount1  > amount1Desired.val()) {
                // throw error to rollback
                throw Error.reject("illegal balance in pool. " 
                # "amount0Desired=" # debug_show (amount0Desired.val()) 
                # ", amount1Desired=" # debug_show (amount1Desired.val())
                # ". actualAmount0=" # debug_show (addResult.amount0) 
                # ", actualAmount1=" # debug_show (addResult.amount1));
            };

            var positionInfo = _positionTickService.getPosition("" # Int.toText(userPositionInfo.tickLower) # "_" # Int.toText(userPositionInfo.tickUpper) # "");
            let distributedFeeResult = _distributeFee(positionInfo, userPositionInfo);
            _tokenAmountService.setSwapFee0Repurchase(SafeUint.Uint128(_tokenAmountService.getSwapFee0Repurchase()).add(SafeUint.Uint128(distributedFeeResult.swapFee0Repurchase)).val());
            _tokenAmountService.setSwapFee1Repurchase(SafeUint.Uint128(_tokenAmountService.getSwapFee1Repurchase()).add(SafeUint.Uint128(distributedFeeResult.swapFee1Repurchase)).val());
            _positionTickService.putUserPosition(
                args.positionId,
                {
                    tickLower = userPositionInfo.tickLower;
                    tickUpper = userPositionInfo.tickUpper;
                    liquidity = SafeUint.Uint128(userPositionInfo.liquidity).add(SafeUint.Uint128(addResult.liquidityDelta)).val();
                    feeGrowthInside0LastX128 = positionInfo.feeGrowthInside0LastX128;
                    feeGrowthInside1LastX128 = positionInfo.feeGrowthInside1LastX128;
                    tokensOwed0 = SafeUint.Uint128(userPositionInfo.tokensOwed0).add(SafeUint.Uint128(distributedFeeResult.swapFee0Lp)).val();
                    tokensOwed1 = SafeUint.Uint128(userPositionInfo.tokensOwed1).add(SafeUint.Uint128(distributedFeeResult.swapFee1Lp)).val();
                },
            );
            _tokenAmountService.setTokenAmount0(SafeUint.Uint256(_tokenAmountService.getTokenAmount0()).add(SafeUint.Uint256(addResult.amount0)).val());
            _tokenAmountService.setTokenAmount1(SafeUint.Uint256(_tokenAmountService.getTokenAmount1()).add(SafeUint.Uint256(addResult.amount1)).val());
            _pushSwapInfoCache(#increaseLiquidity, Principal.toText(msg.caller), Principal.toText(Principal.fromActor(this)), Principal.toText(msg.caller), addResult.liquidityDelta, addResult.amount0, addResult.amount1, true);

            ignore _tokenHolderService.withdraw2(msg.caller, _token0, addResult.amount0, _token1, addResult.amount1);
        } catch (e) {
            _rollback("increase liquidity failed: " # Error.message(e));
        };

        return #ok(args.positionId);
    };

    public shared (msg) func decreaseLiquidity(args : Types.DecreaseLiquidityArgs) : async Result.Result<{ amount0 : Nat; amount1 : Nat }, Types.Error> {
        assert(_isAvailable(msg.caller));
        // verify msg.caller matches the owner of position
        if (not _positionTickService.checkUserPositionIdByOwner(PrincipalUtils.toAddress(msg.caller), args.positionId)) {
            return #err(#InternalError("Check operator failed"));
        };

        return _decreaseLiquidity(msg.caller, args);
    };

    public shared (msg) func claim(args : Types.ClaimArgs) : async Result.Result<{ amount0 : Nat; amount1 : Nat }, Types.Error> {
        assert(_isAvailable(msg.caller));
        // verify msg.caller matches the owner of position
        if (not _positionTickService.checkUserPositionIdByOwner(PrincipalUtils.toAddress(msg.caller), args.positionId)) {
            return #err(#InternalError("Check operator failed"));
        };
        var userPositionInfo = _positionTickService.getUserPosition(args.positionId);
        var collectResult = { amount0 = 0; amount1 = 0 };
        try {
            if (userPositionInfo.liquidity > 0) {
                ignore switch (_removeLiquidity(args.positionId, 0)) {
                    case (#ok(result)) { result };
                    case (#err(code)) {
                        throw Error.reject("claim " # debug_show (code));
                    };
                };
            };
            collectResult := switch (_collect(args.positionId)) {
                case (#ok(result)) { result };
                case (#err(code)) {
                    throw Error.reject("claim " # debug_show (code));
                };
            };
            _tokenAmountService.setTokenAmount0(SafeUint.Uint256(_tokenAmountService.getTokenAmount0()).sub(SafeUint.Uint256(collectResult.amount0)).val());
            _tokenAmountService.setTokenAmount1(SafeUint.Uint256(_tokenAmountService.getTokenAmount1()).sub(SafeUint.Uint256(collectResult.amount1)).val());
            if (0 != collectResult.amount0 or 0 != collectResult.amount1) {
                _pushSwapInfoCache(#claim, Principal.toText(Principal.fromActor(this)), Principal.toText(msg.caller), Principal.toText(msg.caller), 0, collectResult.amount0, collectResult.amount1, true);
                ignore _tokenHolderService.deposit2(msg.caller, _token0, collectResult.amount0, _token1, collectResult.amount1);
            };
        } catch (e) {
            _rollback("claim failed: " # Error.message(e));
        };

        return #ok({
            amount0 = collectResult.amount0;
            amount1 = collectResult.amount1;
        });
    };

    public shared (msg) func swap(args : Types.SwapArgs) : async Result.Result<Nat, Types.Error> {
        assert(_isAvailable(msg.caller));
        if (Principal.isAnonymous(msg.caller)) return #err(#InternalError("Illegal anonymous call"));
        if (TextUtils.toInt(args.amountOutMinimum) > 0) {
            var preCheckAmount = switch (_preSwap(args, msg.caller)) {
                case (#ok(result)) { result };
                case (#err(code)) {
                    return #err(#InternalError("Slippage check failed: " # debug_show (code)));
                };
            };
            if (preCheckAmount < TextUtils.toInt(args.amountOutMinimum)) {
                return #err(#InternalError("Slippage is over range, please withdraw your unused token"));
            };
        };

        var swapAmount = 0;
        try {
            var swapResult = switch (_computeSwap(args, msg.caller, true)) {
                case (#ok(result)) { result };
                case (#err(code)) {
                    throw Error.reject("swap " # debug_show (code));
                };
            };
            var amount0 = swapResult.amount0;
            var amount1 = swapResult.amount1;
            if (args.zeroForOne and amount1 < 0) {
                swapAmount := IntUtils.toNat(-(amount1), 256);
                _tokenAmountService.setTokenAmount0(SafeUint.Uint256(_tokenAmountService.getTokenAmount0()).add(SafeUint.Uint256(IntUtils.toNat(amount0, 256))).val());
                _tokenAmountService.setTokenAmount1(SafeUint.Uint256(_tokenAmountService.getTokenAmount1()).sub(SafeUint.Uint256(swapAmount)).val());
                _pushSwapInfoCache(#swap, Principal.toText(msg.caller), Principal.toText(Principal.fromActor(this)), Principal.toText(msg.caller), 0, SafeUint.Uint256(IntUtils.toNat(amount0, 256)).val(), SafeUint.Uint256(swapAmount).val(), args.zeroForOne);

                ignore _tokenHolderService.swap(msg.caller, _token0, IntUtils.toNat(amount0, 256), _token1, swapAmount);
            };
            if ((not args.zeroForOne) and amount0 < 0) {
                swapAmount := IntUtils.toNat(-(amount0), 256);
                _tokenAmountService.setTokenAmount0(SafeUint.Uint256(_tokenAmountService.getTokenAmount0()).sub(SafeUint.Uint256(swapAmount)).val());
                _tokenAmountService.setTokenAmount1(SafeUint.Uint256(_tokenAmountService.getTokenAmount1()).add(SafeUint.Uint256(IntUtils.toNat(amount1, 256))).val());
                _pushSwapInfoCache(#swap, Principal.toText(msg.caller), Principal.toText(Principal.fromActor(this)), Principal.toText(msg.caller), 0, SafeUint.Uint256(IntUtils.toNat(amount1, 256)).val(), SafeUint.Uint256(swapAmount).val(), args.zeroForOne);

                ignore _tokenHolderService.swap(msg.caller, _token1, IntUtils.toNat(amount1, 256), _token0, swapAmount);
            };
        } catch (e) {
            _rollback("swap failed: " # Error.message(e));
        };

        // set a one-time timer to remove limit order automatically
        ignore Timer.setTimer<system>(#nanoseconds (0), _checkLimitOrder);
        
        return #ok(swapAmount);
    };

    public shared (msg) func approvePosition(spender : Principal, positionId : Nat) : async Result.Result<Bool, Types.Error> {
        assert(_isAvailable(msg.caller));
        switch (_positionTickService.getUserPositionIds().get(PrincipalUtils.toAddress(msg.caller))) {
            case (?positionArray) {
                if (ListUtils.arrayContains(positionArray, positionId, Nat.equal)) {
                    _positionTickService.putAllowancedUserPosition(positionId, PrincipalUtils.toAddress(spender));
                    return #ok(true);
                } else {
                    throw Error.reject("approve failed: you don't own the position");
                };
            };
            case (_) {
                throw Error.reject("approve failed: you don't have any positions");
            };
        };
    };

    public shared (msg) func transferPosition(from : Principal, to : Principal, positionId : Nat) : async Result.Result<Bool, Types.Error> {
        assert(_isAvailable(msg.caller));
        var sender = PrincipalUtils.toAddress(msg.caller);
        var spender = _positionTickService.getAllowancedUserPosition(positionId);
        if ((not Text.equal(sender, spender)) and (not Principal.equal(msg.caller, from))) {
            return #err(#InternalError("Permission denied"));
        };

        var owner = PrincipalUtils.toAddress(from);
        switch (_positionTickService.getUserPositionIds().get(owner)) {
            case (?positionArray) {
                if (ListUtils.arrayContains(positionArray, positionId, Nat.equal)) {
                    _positionTickService.removeUserPositionId(owner, positionId);
                    _positionTickService.putUserPositionId(PrincipalUtils.toAddress(to), positionId);

                    _positionTickService.deleteAllowancedUserPosition(positionId);
                    _pushSwapInfoCache(#transferPosition(positionId), Principal.toText(from), Principal.toText(to), Principal.toText(to), 0, 0, 0, true);
                    return #ok(true);
                } else {
                    throw Error.reject("transfer position failed: the sender don't own the position");
                };
            };
            case (_) {
                throw Error.reject("transfer position failed: the sender don't have any positions");
            };
        };
    };

    public shared (msg) func removeWithdrawErrorLog(id : Nat, rollback : Bool) : async () {
        assert(_isAvailable(msg.caller));
        _checkAdminPermission(msg.caller);
        switch (_tokenAmountService.getWithdrawErrorLog().get(id)) {
            case (?log) {
                if (rollback) { ignore _tokenHolderService.deposit(log.user, log.token, log.amount); };
                _tokenAmountService.getWithdrawErrorLog().delete(id);
            };
            case (_) {};
        };
    };
    public shared(msg) func removeErrorTransferLog(index: Nat, rollback: Bool) : async () {
        assert(_isAvailable(msg.caller));
        _checkAdminPermission(msg.caller);
        switch (_transferLog.get(index)) {
            case (?log) {
                _postTransferComplete(index);
                if (rollback ) { 
                    // The log with error status can be removed immediately.
                    // The log with processing status can be cleaned up after 24 hours
                    if (Text.equal("error", log.result) or (Text.equal(log.result, "processing") and ((Nat.sub(Int.abs(Time.now()), log.timestamp) / NANOSECONDS_PER_SECOND) > SECOND_PER_DAY))) {
                        ignore _tokenHolderService.deposit(log.owner, log.token, log.amount);
                    } else {
                        Prim.trap("rollback error: Error status or insufficient time interval");
                    };
                };
            };
            case (_) {};
        };
    };

    public shared (msg) func upgradeTokenStandard(tokenCid: Principal) : async Result.Result<Text, Types.Error> {
        assert(_isAvailable(msg.caller));
        _checkControllerPermission(msg.caller);
        let address = Principal.toText(tokenCid);
        // Debug.print("==>upgradeTokenStandard" # address);
        if ((not Text.equal(address, _token0.address)) and (not Text.equal(address, _token1.address))) {
            return #err(#InternalError("Wrong address"));
        };
        let token = if (Text.equal(address, _token0.address)) { _token0 } else { _token1 };
        if ((not Text.equal(token.standard, "ICRC1")) and ((not Text.equal(token.standard, "ICP")))) {
            return #err(#InternalError("Unsupported token standard"));
        };
        let act = actor(address) : actor {
            icrc1_supported_standards : shared query () -> async [{ url : Text; name : Text }];
        };
        // Debug.print("==>upgradeTokenStandard - 1");
        let suppportedStandards: [{ url : Text; name : Text }] = await act.icrc1_supported_standards();
        // Debug.print("==>upgradeTokenStandard - 2");
        var supported: Bool = false;
        label l for ( it in  suppportedStandards.vals() ) {
            if (Text.equal(it.name, "ICRC-2")) {
                supported := true;
                break l;
            }
        };
        if (supported) {
            if (Text.equal(address, _token0.address)) { 
                _token0 := { address = address; standard = "ICRC2" };
                _token0Act := TokenFactory.getAdapter(address, "ICRC2");
            } else {
                _token1 := { address = address; standard = "ICRC2" };
                _token1Act := TokenFactory.getAdapter(address, "ICRC2");
            };
            _tokenHolderService := TokenHolder.Service({
                token0 = _token0;
                token1 = _token1;
                balances = _tokenHolderService.getState().balances;
            });
            #ok("Success")
        } else {
            #err(#InternalError("This token does not support ICRC-2"))
        };
    };

    public query (msg) func quote(args : Types.SwapArgs) : async Result.Result<Nat, Types.Error> {
        assert(_isAvailable(msg.caller));
        return _preSwap(args, msg.caller);
    };

    public query (msg) func quoteForAll(args : Types.SwapArgs) : async Result.Result<Nat, Types.Error> {
        assert(_isAvailable(msg.caller));
        return _preSwapForAll(args, msg.caller);
    };

    public query (msg) func refreshIncome(positionId : Nat) : async Result.Result<{ tokensOwed0 : Nat; tokensOwed1 : Nat }, Types.Error> {
        assert(_isAvailable(msg.caller));
        let result = switch (_refreshIncome(positionId)) {
            case (#ok(result)) { result };
            case (#err(code)) { throw Error.reject(code) };
        };
        return #ok({
            tokensOwed0 = result.tokensOwed0;
            tokensOwed1 = result.tokensOwed1;
        });
    };

    public query (msg) func batchRefreshIncome(positionIds : [Nat]) : async Result.Result<{ totalTokensOwed0 : Nat; totalTokensOwed1 : Nat; tokenIncome : [(Nat, { tokensOwed0 : Nat; tokensOwed1 : Nat })] }, Types.Error> {
        assert(_isAvailable(msg.caller));
        var totalTokensOwed0 : Nat = 0;
        var totalTokensOwed1 : Nat = 0;
        var tokenIncomeBuffer : Buffer.Buffer<(Nat, { tokensOwed0 : Nat; tokensOwed1 : Nat })> = Buffer.Buffer<(Nat, { tokensOwed0 : Nat; tokensOwed1 : Nat })>(0);
        for (positionId in positionIds.vals()) {
            var userPosition = _positionTickService.getUserPosition(positionId);
            let result = if (Nat.equal(userPosition.liquidity, 0)) {
                { tokensOwed0 = 0; tokensOwed1 = 0 };
            } else {
                switch (_refreshIncome(positionId)) {
                    case (#ok(result)) { result };
                    case (#err(_)) { { tokensOwed0 = 0; tokensOwed1 = 0 } };
                };
            };
            totalTokensOwed0 := totalTokensOwed0 + result.tokensOwed0;
            totalTokensOwed1 := totalTokensOwed1 + result.tokensOwed1;
            tokenIncomeBuffer.add((positionId, { tokensOwed0 = result.tokensOwed0; tokensOwed1 = result.tokensOwed1 }));
        };
        return #ok({
            totalTokensOwed0 = totalTokensOwed0;
            totalTokensOwed1 = totalTokensOwed1;
            tokenIncome = Buffer.toArray(tokenIncomeBuffer);
        });
    };

    public query func allTokenBalance(offset : Nat, limit : Nat) : async Result.Result<Types.Page<(Principal, TokenHolder.AccountBalance)>, Types.Error> {
        let resultArr : Buffer.Buffer<(Principal, TokenHolder.AccountBalance)> = Buffer.Buffer<(Principal, TokenHolder.AccountBalance)>(0);
        var begin : Nat = 0;
        label l {
            for ((principal, balance) in _tokenHolderService.getAllBalances().entries()) {
                if (begin >= offset and begin < (offset + limit)) {
                    resultArr.add((principal, balance));
                };
                if (begin >= (offset + limit)) { break l };
                begin := begin + 1;
            };
        };
        return #ok({
            totalElements = _tokenHolderService.getAllBalances().size();
            content = Buffer.toArray(resultArr);
            offset = offset;
            limit = limit;
        });
    };

    public shared (msg) func getTokenMeta() : async {
        token0 : [(Text, Types.Value)];
        token1 : [(Text, Types.Value)];
        token0Fee : ? Nat;
        token1Fee : ? Nat;
    } {
        assert(_isAvailable(msg.caller));
        return {
            token0 = await _token0Act.metadata();
            token1 = await _token1Act.metadata();
            token0Fee = _token0Fee;
            token1Fee = _token1Fee;
        };
    };

    public shared (msg) func getTokenBalance() : async {
        token0 : Nat;
        token1 : Nat;
    } {
        assert(_isAvailable(msg.caller));
        var canisterId = Principal.fromActor(this);
        return {
            token0 = await _token0Act.balanceOf({
                owner = canisterId;
                subaccount = null;
            });
            token1 = await _token1Act.balanceOf({
                owner = canisterId;
                subaccount = null;
            });
        };
    };

    public query func getTickInfos(offset : Nat, limit : Nat) : async Result.Result<Types.Page<Types.TickLiquidityInfo>, Types.Error> {
        var tempTickList = List.nil<(Text, Types.TickInfo)>();
        var begin : Nat = 0;
        label l {
            for ((tickIndex, tickInfo) in _positionTickService.getTicks().entries()) {
                if (begin >= offset and begin < (offset + limit)) {
                    tempTickList := List.push((tickIndex, tickInfo), tempTickList);
                };
                if (begin >= (offset + limit)) { break l };
                begin := begin + 1;
            };
        };

        var tickLiquidityInfoList : Buffer.Buffer<Types.TickLiquidityInfo> = Buffer.Buffer<Types.TickLiquidityInfo>(0);
        for ((tickIndex, tickInfo) in List.toArray(tempTickList).vals()) {
            var sqrtRatioX = switch (TickMath.getSqrtRatioAtTick(SafeInt.Int24(TextUtils.toInt(tickIndex)))) {
                case (#ok(r)) { r };
                case (#err(code)) { throw Error.reject(code) };
            };
            var tempInfo = {
                liquidityGross = tickInfo.liquidityGross;
                liquidityNet = tickInfo.liquidityNet;
                price0 = sqrtRatioX;
                price1 = 1 / sqrtRatioX;
                tickIndex : Int = TextUtils.toInt(tickIndex);
                price0Decimal = 1;
                price1Decimal = 1;
            };
            tickLiquidityInfoList.add(tempInfo);
        };
        return #ok({
            totalElements = _positionTickService.getTicks().size();
            content = Buffer.toArray(tickLiquidityInfoList);
            offset = offset;
            limit = limit;
        });
    };

    public query func sumTick() : async Result.Result<Int, Types.Error> {
        var sum : Int = 0;
        for ((tickIndex, tickInfo) in _positionTickService.getTicks().entries()) {
            sum += tickInfo.liquidityNet;
        };
        return #ok(sum);
    };

    public query func getUserPositionWithTokenAmount(offset : Nat, limit : Nat) : async Result.Result<Types.Page<Types.UserPositionInfoWithTokenAmount>, Types.Error> {
        var tempUserPositionList = List.nil<(Nat, Types.UserPositionInfo)>();
        var begin : Nat = 0;
        label l {
            for ((positionId, userPositionInfo) in _positionTickService.getUserPositions().entries()) {
                if (begin >= offset and begin < (offset + limit)) {
                    tempUserPositionList := List.push((positionId, userPositionInfo), tempUserPositionList);
                };
                if (begin >= (offset + limit)) { break l };
                begin := begin + 1;
            };
        };
        let resultArr : Buffer.Buffer<Types.UserPositionInfoWithTokenAmount> = Buffer.Buffer<Types.UserPositionInfoWithTokenAmount>(0);
        for ((positionId, userPositionInfo) in List.toArray<(Nat, Types.UserPositionInfo)>(tempUserPositionList).vals()) {
            var sqrtRatioAX96 = switch (TickMath.getSqrtRatioAtTick(SafeInt.Int24(userPositionInfo.tickLower))) {
                case (#ok(r)) { r };
                case (#err(code)) {
                    throw Error.reject("TickMath getSqrtRatio A AtTick " # debug_show (code));
                };
            };
            var sqrtRatioBX96 = switch (TickMath.getSqrtRatioAtTick(SafeInt.Int24(userPositionInfo.tickUpper))) {
                case (#ok(r)) { r };
                case (#err(code)) {
                    throw Error.reject("TickMath getSqrtRatio B AtTick " # debug_show (code));
                };
            };
            var result = LiquidityAmounts.getAmountsForLiquidity(
                SafeUint.Uint160(_sqrtPriceX96),
                SafeUint.Uint160(sqrtRatioAX96),
                SafeUint.Uint160(sqrtRatioBX96),
                SafeUint.Uint128(userPositionInfo.liquidity),
            );
            ignore switch (
                _positionTickService.modifyPosition(
                    _tick,
                    _sqrtPriceX96,
                    _liquidity,
                    _feeGrowthGlobal0X128,
                    _feeGrowthGlobal1X128,
                    _maxLiquidityPerTick,
                    _tickSpacing,
                    userPositionInfo.tickLower,
                    userPositionInfo.tickUpper,
                    0,
                )
            ) {
                case (#ok(result)) { result };
                case (#err(_)) {
                    throw Error.reject("refresh income failed");
                };
            };
            let positionKey = "" # Int.toText(userPositionInfo.tickLower) # "_" # Int.toText(userPositionInfo.tickUpper) # "";
            var positionInfo = _positionTickService.getPosition(positionKey);
            let distributedFeeResult = _distributeFee(positionInfo, userPositionInfo);
            resultArr.add({
                id = positionId;
                tickLower = userPositionInfo.tickLower;
                tickUpper = userPositionInfo.tickUpper;
                liquidity = userPositionInfo.liquidity;
                feeGrowthInside0LastX128 = userPositionInfo.feeGrowthInside0LastX128;
                feeGrowthInside1LastX128 = userPositionInfo.feeGrowthInside1LastX128;
                token0Amount = result.amount0;
                token1Amount = result.amount1;
                tokensOwed0 = SafeUint.Uint128(userPositionInfo.tokensOwed0).add(SafeUint.Uint128(distributedFeeResult.swapFee0Lp)).val();
                tokensOwed1 = SafeUint.Uint128(userPositionInfo.tokensOwed1).add(SafeUint.Uint128(distributedFeeResult.swapFee1Lp)).val();
            });
        };
        return #ok({
            totalElements = _positionTickService.getUserPositions().size();
            content = Buffer.toArray(resultArr);
            offset = offset;
            limit = limit;
        });
    };

    public query func getUserByPositionId(positionId : Nat) : async Result.Result<Text, Types.Error> {
        var userAccount = "";
        label l {
            for ((user, positionIds) in _positionTickService.getUserPositionIds().entries()) {
                if (CollectionUtils.arrayContains(positionIds, positionId, Nat.equal)) {
                    userAccount := user;
                    break l;
                };
            };
        };
        return #ok(userAccount);
    };

    public query func getUserPositionIdsByPrincipal(owner : Principal) : async Result.Result<[Nat], Types.Error> {
        let positionIds = _positionTickService.getUserPositionIdsByOwner(PrincipalUtils.toAddress(owner));
        return #ok(positionIds);
    };

    public query func getUserPositionsByPrincipal(owner : Principal) : async Result.Result<[Types.UserPositionInfoWithId], Types.Error> {
        let resultArr : Buffer.Buffer<Types.UserPositionInfoWithId> = Buffer.Buffer<Types.UserPositionInfoWithId>(0);
        let positionIds = _positionTickService.getUserPositionIdsByOwner(PrincipalUtils.toAddress(owner));
        for (positionId in positionIds.vals()) {
            var userPositionInfo = _positionTickService.getUserPosition(positionId);
            resultArr.add({
                id = positionId;
                tickLower = userPositionInfo.tickLower;
                tickUpper = userPositionInfo.tickUpper;
                liquidity = userPositionInfo.liquidity;
                feeGrowthInside0LastX128 = userPositionInfo.feeGrowthInside0LastX128;
                feeGrowthInside1LastX128 = userPositionInfo.feeGrowthInside1LastX128;
                tokensOwed0 = userPositionInfo.tokensOwed0;
                tokensOwed1 = userPositionInfo.tokensOwed1;
            });
        };
        return #ok(Buffer.toArray(resultArr));
    };

    public query func getUserPositions(offset : Nat, limit : Nat) : async Result.Result<Types.Page<Types.UserPositionInfoWithId>, Types.Error> {
        let resultArr : Buffer.Buffer<Types.UserPositionInfoWithId> = Buffer.Buffer<Types.UserPositionInfoWithId>(0);
        var begin : Nat = 0;
        label l {
            for ((positionId, userPositionInfo) in _positionTickService.getUserPositions().entries()) {
                if (begin >= offset and begin < (offset + limit)) {
                    resultArr.add({
                        id = positionId;
                        tickLower = userPositionInfo.tickLower;
                        tickUpper = userPositionInfo.tickUpper;
                        liquidity = userPositionInfo.liquidity;
                        feeGrowthInside0LastX128 = userPositionInfo.feeGrowthInside0LastX128;
                        feeGrowthInside1LastX128 = userPositionInfo.feeGrowthInside1LastX128;
                        tokensOwed0 = userPositionInfo.tokensOwed0;
                        tokensOwed1 = userPositionInfo.tokensOwed1;
                    });
                };
                if (begin >= (offset + limit)) { break l };
                begin := begin + 1;
            };
        };
        return #ok({
            totalElements = _positionTickService.getUserPositions().size();
            content = Buffer.toArray(resultArr);
            offset = offset;
            limit = limit;
        });
    };

    public query func getPositions(offset : Nat, limit : Nat) : async Result.Result<Types.Page<Types.PositionInfoWithId>, Types.Error> {
        let resultArr : Buffer.Buffer<Types.PositionInfoWithId> = Buffer.Buffer<Types.PositionInfoWithId>(0);
        var begin : Nat = 0;
        label l {
            for ((positionId, positionInfo) in _positionTickService.getPositions().entries()) {
                if (begin >= offset and begin < (offset + limit)) {
                    resultArr.add({
                        id = positionId;
                        liquidity = positionInfo.liquidity;
                        feeGrowthInside0LastX128 = positionInfo.feeGrowthInside0LastX128;
                        feeGrowthInside1LastX128 = positionInfo.feeGrowthInside1LastX128;
                        tokensOwed0 = positionInfo.tokensOwed0;
                        tokensOwed1 = positionInfo.tokensOwed1;
                    });
                };
                if (begin >= (offset + limit)) { break l };
                begin := begin + 1;
            };
        };
        return #ok({
            totalElements = _positionTickService.getPositions().size();
            content = Buffer.toArray(resultArr);
            offset = offset;
            limit = limit;
        });
    };

    public query func getTicks(offset : Nat, limit : Nat) : async Result.Result<Types.Page<Types.TickInfoWithId>, Types.Error> {
        let resultArr : Buffer.Buffer<Types.TickInfoWithId> = Buffer.Buffer<Types.TickInfoWithId>(0);
        var begin : Nat = 0;
        label l {
            for ((tickId, tickInfo) in _positionTickService.getTicks().entries()) {
                if (begin >= offset and begin < (offset + limit)) {
                    resultArr.add({
                        id = tickId;
                        liquidityGross = tickInfo.liquidityGross;
                        liquidityNet = tickInfo.liquidityNet;
                        feeGrowthOutside0X128 = tickInfo.feeGrowthOutside0X128;
                        feeGrowthOutside1X128 = tickInfo.feeGrowthOutside1X128;
                        tickCumulativeOutside = tickInfo.tickCumulativeOutside;
                        secondsPerLiquidityOutsideX128 = tickInfo.secondsPerLiquidityOutsideX128;
                        secondsOutside = tickInfo.secondsOutside;
                        initialized = tickInfo.initialized;
                    });
                };
                if (begin >= (offset + limit)) { break l };
                begin := begin + 1;
            };
        };
        return #ok({
            totalElements = _positionTickService.getTicks().size();
            content = Buffer.toArray(resultArr);
            offset = offset;
            limit = limit;
        });
    };

    public query func getUserPositionIds() : async Result.Result<[(Text, [Nat])], Types.Error> {
        return #ok(Iter.toArray(_positionTickService.getUserPositionIds().entries()));
    };

    public query func metadata() : async Result.Result<Types.PoolMetadata, Types.Error> {
        var metadata = {
            key = PoolUtils.getPoolKey(_token0, _token1, _fee);
            token0 = _token0;
            token1 = _token1;
            fee = _fee;
            tick = _tick;
            liquidity = _liquidity;
            sqrtPriceX96 = _sqrtPriceX96;
            maxLiquidityPerTick = _maxLiquidityPerTick;
            nextPositionId = _nextPositionId;
        };
        #ok(metadata);
    };

    public query func getUserPosition(positionId : Nat) : async Result.Result<Types.UserPositionInfo, Types.Error> {
        let refreshResult = switch (_refreshIncome(positionId)) {
            case (#ok(result)) { result };
            case (#err(code)) { throw Error.reject(code) };
        };
        let userPositionInfo = _positionTickService.getUserPosition(positionId);
        return #ok({
            tickLower = userPositionInfo.tickLower;
            tickUpper = userPositionInfo.tickUpper;
            liquidity = userPositionInfo.liquidity;
            feeGrowthInside0LastX128 = userPositionInfo.feeGrowthInside0LastX128;
            feeGrowthInside1LastX128 = userPositionInfo.feeGrowthInside1LastX128;
            tokensOwed0 = refreshResult.tokensOwed0;
            tokensOwed1 = refreshResult.tokensOwed1;
        });
    };
    
    public query func getUserUnusedBalance(account : Principal) : async Result.Result<{ balance0 : Nat; balance1 : Nat }, Types.Error> {
        return #ok(_tokenHolderService.getBalances(account));
    };

    public query func getPosition(args : Types.GetPositionArgs) : async Result.Result<Types.PositionInfo, Types.Error> {
        return #ok(_positionTickService.getPosition("" # Int.toText(args.tickLower) # "_" # Int.toText(args.tickUpper) # ""));
    };

    public query func getTokenAmountState() : async Result.Result<{ token0Amount : Nat; token1Amount : Nat; swapFee0Repurchase : Nat; swapFee1Repurchase : Nat; swapFeeReceiver : Text;}, Types.Error> {
        return #ok({
            token0Amount = _tokenAmountService.getTokenAmount0();
            token1Amount = _tokenAmountService.getTokenAmount1();
            swapFee0Repurchase = _tokenAmountService.getSwapFee0Repurchase();
            swapFee1Repurchase = _tokenAmountService.getSwapFee1Repurchase();
            swapFeeReceiver = Principal.toText(feeReceiverCid);
        });
    };

    public query func getWithdrawErrorLog() : async Result.Result<[(Nat, Types.WithdrawErrorLog)], Types.Error> {
        return #ok(Iter.toArray(_tokenAmountService.getWithdrawErrorLog().entries()));
    };
    public query func getTransferLogs() : async Result.Result<[Types.TransferLog], Types.Error> {
        return #ok(Iter.toArray(_transferLog.vals()));
    };
    public query func getSwapRecordState() : async Result.Result<{
        infoCid : Text;
        records : [Types.SwapRecordInfo];
        retryCount : Nat;
        errors : [Types.PushError];
    }, Types.Error> {
        var swapRecordState = _swapRecordService.getState();
        return #ok({
            infoCid = Principal.toText(infoCid);
            records = swapRecordState.records;
            retryCount = swapRecordState.retryCount;
            errors = swapRecordState.errors;
        });
    };

    public query (msg) func checkOwnerOfUserPosition(owner : Principal, positionId : Nat) : async Result.Result<Bool, Types.Error> {
        assert(_isAvailable(msg.caller));
        return #ok(_positionTickService.checkUserPositionIdByOwner(PrincipalUtils.toAddress(owner), positionId));
    };

    public shared func getCycleInfo() : async Result.Result<Types.CycleInfo, Types.Error> {
        return #ok({
            balance = Cycles.balance();
            available = Cycles.available();
        });
    };

    // --------------------------- ACL ------------------------------------
    public shared (msg) func setAdmins(admins : [Principal]) : async () {
        assert(_isAvailable(msg.caller));
        _checkControllerPermission(msg.caller);
        _admins := admins;
    };
    public query func getAdmins(): async [Principal] {
        return _admins;
    };
    
    public shared (msg) func setAvailable(available : Bool) : async () {
        assert(_isAvailable(msg.caller));
        _checkAdminPermission(msg.caller);
        _available := available;
    };
    public shared (msg) func setWhiteList(whiteList: [Principal]): async () {
        assert(_isAvailable(msg.caller));
        _checkAdminPermission(msg.caller);
        _whiteList := whiteList;
    };
    public query func getAvailabilityState() : async {
        available : Bool;
        whiteList : [Principal];
    } {
        return {
            available = _available;
            whiteList = _whiteList;
        };
    };
    private func _isAvailable(caller: Principal) : Bool {
        if (_available and _transferLog.size() < 2000) {
            return true;
        };
        if (CollectionUtils.arrayContains<Principal>(_whiteList, caller, Principal.equal)) {
            return true;
        };
        if (CollectionUtils.arrayContains<Principal>(_admins, caller, Principal.equal)) {
            return true;
        };
        if (Prim.isController(caller)) {
            return true;
        };
        return false;
    };
    private func _checkControllerPermission(caller: Principal) {
        assert(Prim.isController(caller));
    };
    private func _checkAdminPermission(caller: Principal) {
        assert(CollectionUtils.arrayContains<Principal>(_admins, caller, Principal.equal) or Prim.isController(caller));
    };
    private func _hasPermission(msg: Types.SwapPoolMsg, caller: Principal): Bool {
        switch (msg) {
            // Controller
            case (#init _)                   { (not _inited) and Prim.isController(caller) };
            case (#setAdmins _)              { Prim.isController(caller) };
            case (#upgradeTokenStandard _)   { Prim.isController(caller) };
            case (#resetTokenAmountState _)  { Prim.isController(caller) };
            // Admin
            case (#depositAllAndMint _)      { CollectionUtils.arrayContains<Principal>(_admins, caller, Principal.equal) or Prim.isController(caller) };
            case (#removeErrorTransferLog _) { CollectionUtils.arrayContains<Principal>(_admins, caller, Principal.equal) or Prim.isController(caller) };
            case (#setAvailable _)           { CollectionUtils.arrayContains<Principal>(_admins, caller, Principal.equal) or Prim.isController(caller) };
            case (#setWhiteList _)           { CollectionUtils.arrayContains<Principal>(_admins, caller, Principal.equal) or Prim.isController(caller) };
            case (#removeWithdrawErrorLog _) { CollectionUtils.arrayContains<Principal>(_admins, caller, Principal.equal) or Prim.isController(caller) };
            // Anyone
            case (_)                            { true };
        }
    };

    // --------------------------- Version Control ------------------------------------
    private var _version : Text = "3.5.0";
    public query func getVersion() : async Text { _version };
    // --------------------------- mistransfer recovery ------------------------------------
    public shared({caller}) func getMistransferBalance(token: Types.Token) : async Result.Result<Nat, Types.Error> {
        assert(_isAvailable(caller));
        if (Principal.isAnonymous(caller)) return #err(#InternalError("Illegal anonymous call"));
        if (Text.equal(token.address, _token0.address) or Text.equal(token.address, _token1.address)) return #err(#InternalError("Please use deposit and withdraw instead"));
        if (not Text.equal(token.standard, "ICRC1")) return #err(#InternalError("Only support ICRC-1 standard."));
        if(not (await _trustAct.isCanisterTrusted(Principal.fromText(token.address)))) {
            return #err(#InternalError("Untrusted canister: " # token.address));
        };
        let act : TokenAdapterTypes.TokenAdapter = TokenFactory.getAdapter(token.address, token.standard);
        return #ok(await act.balanceOf({ owner = Principal.fromActor(this); subaccount = Option.make(AccountUtils.principalToBlob(caller)); }))
    };
    public shared({caller}) func withdrawMistransferBalance(token: Types.Token) : async Result.Result<Nat, Types.Error> {
        assert(_isAvailable(caller));
        if (Principal.isAnonymous(caller)) return #err(#InternalError("Illegal anonymous call"));
        if (Text.equal(token.address, _token0.address) or Text.equal(token.address, _token1.address)) return #err(#InternalError("Please use deposit and withdraw instead"));
        if (not Text.equal(token.standard, "ICRC1")) return #err(#InternalError("Only support ICRC-1 standard."));
        // validate if the canister is trusted.
        if(not (await _trustAct.isCanisterTrusted(Principal.fromText(token.address)))) {
            return #err(#InternalError("Untrusted canister: " # token.address));
        };
        let tokenAct : TokenAdapterTypes.TokenAdapter = TokenFactory.getAdapter(token.address, token.standard);
        let balance : Nat = await tokenAct.balanceOf({ owner = Principal.fromActor(this); subaccount = Option.make(AccountUtils.principalToBlob(caller)); });
        let fee: Nat = await tokenAct.fee();
        if (balance > fee) {
            let amount = Nat.sub(balance, fee);
            let fromSubaccount: ?Blob = Option.make(AccountUtils.principalToBlob(caller));
            switch (await tokenAct.transfer({ 
                from = { owner = Principal.fromActor(this); subaccount = fromSubaccount }; 
                from_subaccount = fromSubaccount; 
                to = { owner = caller; subaccount = null }; 
                amount = amount; 
                fee = Option.make(fee); 
                memo = null; 
                created_at_time = null 
            })){
                case (#Ok(index)) {
                    return #ok(index);
                };
                case (#Err(msg)) {
                    return #err(#InternalError("Transfer failed: " # debug_show(msg)));
                };
            }
        } else {
            return #err(#InternalError("Insufficient balance: " # Nat.toText(balance)));
        };
    };

    // jobs...
    // Clear transfer logs older than 60 days every 12 hours.
    let _clearExpiredTransferLogsJob = Timer.recurringTimer<system>(#seconds(43200), func (): async () {
        let today: Nat = Int.abs(Time.now()) / NANOSECONDS_PER_SECOND / SECOND_PER_DAY;
        for ((index, log) in _transferLog.entries()) {
            if (Nat.sub(today, log.daysFrom19700101) > 60) {
                _postTransferComplete(index);
            };
        };
    });

    system func preupgrade() {
        _userPositionsEntries := Iter.toArray(_positionTickService.getUserPositions().entries());
        _positionsEntries := Iter.toArray(_positionTickService.getPositions().entries());
        _tickBitmapsEntries := Iter.toArray(_positionTickService.getTickBitmaps().entries());
        _ticksEntries := Iter.toArray(_positionTickService.getTicks().entries());
        _userPositionIdsEntries := Iter.toArray(_positionTickService.getUserPositionIds().entries());
        _allowancedUserPositionEntries := Iter.toArray(_positionTickService.getAllowancedUserPositions().entries());
        _recordState := _swapRecordService.getState();
        _tokenHolderState := _tokenHolderService.getState();
        _tokenAmountState := _tokenAmountService.getState();
        _claimLog := Buffer.toArray(_claimLogBuffer);
        _transferLogArray := Iter.toArray(_transferLog.entries());
        _lowerLimitOrderEntries := Iter.toArray(_lowerLimitOrders.entries());
        _upperLimitOrderEntries := Iter.toArray(_upperLimitOrders.entries());
    };

    system func postupgrade() {
        _canisterId := ?Principal.fromActor(this);
        _claimLogBuffer := Buffer.fromArray(_claimLog);
        for ((k,v) in _lowerLimitOrderEntries.vals()) { _lowerLimitOrders.put(k,v) };
        for ((k,v) in _upperLimitOrderEntries.vals()) { _upperLimitOrders.put(k,v) };
        _userPositionsEntries := [];
        _userPositionIdsEntries := [];
        _allowancedUserPositionEntries := [];
        _positionsEntries := [];
        _tickBitmapsEntries := [];
        _ticksEntries := [];
        _transferLogArray := [];
        _lowerLimitOrderEntries := [];
        _upperLimitOrderEntries := [];
    };
    
    system func inspect({
        arg : Blob;
        caller : Principal;
        msg : Types.SwapPoolMsg;
    }) : Bool {
        return _isAvailable(caller) and _hasPermission(msg, caller);
    };
};
