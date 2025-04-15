import Text "mo:base/Text";
import Nat "mo:base/Nat";
import Int "mo:base/Int";
import Nat8 "mo:base/Nat8";
import Blob "mo:base/Blob";
import Principal "mo:base/Principal";
import Array "mo:base/Array";
import Option "mo:base/Option";
import TokenTypes "mo:token-adapter/Types";
import TokenFactory "mo:token-adapter/TokenFactory";
import TickMath "../src/libraries/TickMath";
import SafeInt "mo:commons/math/SafeInt";
import Float "mo:base/Float";

actor {

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

    public query (msg) func getSubaccount() : async Blob {
        return _principalToBlob(msg.caller);
    };

    public query (msg) func getSubaccountText() : async Text {
        var text : Text = debug_show (Option.make(_principalToBlob(msg.caller)));
        text := Text.replace(text, #text("\\"), "\\");
        return "text__" # text # "__";
    };

    public shared func testTokenAdapterBalanceOf(addr : Text, std : Text, account : Principal, subaccount : ?Principal) : async Nat {
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

    public shared (msg) func testTokenAdapterTransferFrom(addr : Text, std : Text, _from : Principal, to : Principal, amount : TokenTypes.Amount) : async TokenTypes.TransferFromResult {
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

    public shared func tickToPrice(tick : Int) : async Float {
        switch (TickMath.getSqrtRatioAtTick(SafeInt.Int24(tick))) {
            case (#ok(sqrtPriceX96)) {
                _computeToICPPrice(sqrtPriceX96);
            };
            case (#err(_)) {
                return 0;
            };
        };
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
