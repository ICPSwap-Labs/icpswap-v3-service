import Text "mo:base/Text";
import Time "mo:base/Time";
import Debug "mo:base/Debug";
import Nat "mo:base/Nat";
import Int "mo:base/Int";
import Nat8 "mo:base/Nat8";
import Blob "mo:base/Blob";
import Principal "mo:base/Principal";
import Array "mo:base/Array";
import Option "mo:base/Option";
import Result "mo:base/Result";
import HashMap "mo:base/HashMap";
import Hash "mo:base/Hash";
import TokenTypes "mo:token-adapter/Types";
import TokenFactory "mo:token-adapter/TokenFactory";
import Types "../src/Types";
import TickMath "../src/libraries/TickMath";
import IntUtils "mo:commons/math/SafeInt/IntUtils";
import UintUtils "mo:commons/math/SafeUint/UintUtils";
import SafeInt "mo:commons/math/SafeInt";
import SafeUint "mo:commons/math/SafeUint";
import Float "mo:base/Float";

actor {

    private stable var Q96 : Float = 0x1000000000000000000000000;

    func _principalToBlob(p : Principal) : Blob {
        var arr : [Nat8] = Blob.toArray(Principal.toBlob(p));
        var defaultArr : [var Nat8] = Array.init<Nat8>(32, 0);
        defaultArr[0] := Nat8.fromNat(arr.size());
        var ind : Nat = 0;
        while (ind < arr.size() and ind < 32) {
            defaultArr[ind + 1] := arr[ind];
            ind := ind + 1;
        };
        return Blob.fromArray(Array.freeze(defaultArr));
    };

    public shared (msg) func getSubaccount() : async Text {
        var text : Text = debug_show (Option.make(_principalToBlob(msg.caller)));
        text := Text.replace(text, #text("\\"), "\\");
        return "text__" # text # "__";
    };

    public shared (msg) func testTokenAdapterBalanceOf(addr : Text, std : Text, account : Principal, subaccount : ?Principal) : async Nat {
        return await TokenFactory.getAdapter(addr, std).balanceOf(
            {
                owner = account;
                subaccount = switch (subaccount) {
                    case (?p) { Option.make(_principalToBlob(p)) };
                    case (_) { null };
                };
            } : TokenTypes.Account
        );
    };

    public shared (msg) func testTokenAdapterTransfer(addr : Text, std : Text, fromSubaccount : ?Principal, to : Principal, toSubaccount : ?Principal, amount : TokenTypes.Amount) : async TokenTypes.TransferResult {
        let _subaccount = switch (fromSubaccount) {
            case (?p) { Option.make(_principalToBlob(p)) };
            case (_) { null };
        };
        return await TokenFactory.getAdapter(addr, std).transfer({
            from = {
                owner = msg.caller;
                subaccount = _subaccount;
            };
            from_subaccount = _subaccount;
            to = {
                owner = to;
                subaccount = switch (toSubaccount) {
                    case (?p) { Option.make(_principalToBlob(p)) };
                    case (_) { null };
                };
            };
            amount = amount;
            fee = null;
            memo = null;
            created_at_time = null;
        });
    };

    public shared (msg) func testTokenAdapterTransferFrom(addr : Text, std : Text, from : Principal, to : Principal, amount : TokenTypes.Amount) : async TokenTypes.TransferFromResult {
        return await TokenFactory.getAdapter(addr, std).transferFrom({
            from = {
                owner = msg.caller;
                subaccount = null;
            };
            to = { owner = to; subaccount = null };
            amount = amount;
            fee = null;
            memo = null;
            created_at_time = null;
        });
    };

    private stable var _feeTickSpacingEntries : [(Nat, [Int])] = [(500, [-887270, 887270]), (3000, [-887220, 887220]), (10000, [-887200, 887200])];
    private var _feeTickSpacingMap : HashMap.HashMap<Nat, [Int]> = HashMap.fromIter<Nat, [Int]>(_feeTickSpacingEntries.vals(), 10, Nat.equal, Hash.hash);

    public shared (msg) func priceToTick(price : Float, fee : Nat) : async Int {
        var sqrtPriceX96 = IntUtils.toNat(Float.toInt(Float.sqrt(price) * Q96), 256);
        switch (TickMath.getTickAtSqrtRatio(SafeUint.Uint160(sqrtPriceX96))) {
            case (#ok(r)) {
                var addFlag = if (Int.rem(r, 60) >= 30) { true } else { false };
                var tick = r / 60 * 60;
                if (addFlag) {
                    if (tick >= 0) {
                        tick + 60;
                    } else {
                        tick - 60;
                    };
                } else { tick };
            };
            case (#err(code)) { 0 };
        };
    };

    private stable var FeeTickSpacing : [(Nat, Int)] = [(500, 10), (3000, 60), (10000, 200)];
    private stable var MaxTick : [(Nat, Int)] = [(500, 887270), (3000, 887220), (10000, 887200)];
    private stable var MinTick : [(Nat, Int)] = [(500, -887270), (3000, -887220), (10000, -887200)];
    public shared (msg) func priceToTick2(price : Float, fee : Nat) : async Int {
        var feeTickSpacingMap : HashMap.HashMap<Nat, Int> = HashMap.fromIter<Nat, Int>(FeeTickSpacing.vals(), 3, Nat.equal, Hash.hash);
        var maxTickMap : HashMap.HashMap<Nat, Int> = HashMap.fromIter<Nat, Int>(MaxTick.vals(), 3, Nat.equal, Hash.hash);
        var minTickMap : HashMap.HashMap<Nat, Int> = HashMap.fromIter<Nat, Int>(MaxTick.vals(), 3, Nat.equal, Hash.hash);

        var tickSpacing = switch (feeTickSpacingMap.get(fee)) {
            case (?r) { r };
            case (_) { 0 };
        };
        var maxTick = switch (maxTickMap.get(fee)) {
            case (?r) { r };
            case (_) { 0 };
        };
        var minTick = switch (minTickMap.get(fee)) {
            case (?r) { r };
            case (_) { 0 };
        };

        var sqrtPriceX96 = IntUtils.toNat(Float.toInt(Float.sqrt(price) * Q96), 256);
        switch (TickMath.getTickAtSqrtRatio(SafeUint.Uint160(sqrtPriceX96))) {
            case (#ok(r)) {
                var addFlag = if (Int.rem(r, tickSpacing) >= (tickSpacing / 2)) {
                    true;
                } else { false };
                var tick = r / tickSpacing * tickSpacing;
                if (addFlag) {
                    if (tick >= 0) {
                        if (tick + tickSpacing > maxTick) {
                            maxTick;
                        } else {
                            tick + tickSpacing;
                        };
                    } else {
                        if (tick - tickSpacing < minTick) {
                            minTick;
                        } else {
                            tick - tickSpacing;
                        };
                    };
                } else { tick };
            };
            case (#err(code)) { 0 };
        };
    };

    public shared (msg) func tickToPrice(tick : Int) : async Float {
        switch (TickMath.getSqrtRatioAtTick(SafeInt.Int24(tick))) {
            case (#ok(sqrtPriceX96)) {
                _computeToICPPrice(sqrtPriceX96);
            };
            case (#err(code)) {
                return 0;
            };
        };
    };

    public shared (msg) func computePrice(sqrtPriceX96 : Nat) : async Nat {
        sqrtPriceX96 ** 2 / 2 ** 192;
    };

    private func _computeToICPPrice(sqrtPriceX96 : Nat) : Float {
        let DECIMALS = 10000000;
        let Q192 = (2 ** 96) ** 2;

        // decimal0 = 8
        let part1 = sqrtPriceX96 ** 2 * 10 ** 8 * DECIMALS;
        // decimal1 = 8
        let part2 = Q192 * 10 ** 8;
        let priceWithDecimals = Float.div(Float.fromInt(part1), Float.fromInt(part2));
        return Float.div(priceWithDecimals, Float.fromInt(DECIMALS));
    };
};
