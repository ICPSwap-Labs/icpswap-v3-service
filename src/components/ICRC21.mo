import Text "mo:base/Text";
import Option "mo:base/Option";
import Nat "mo:base/Nat";
import Int "mo:base/Int";
import Principal "mo:base/Principal";
import ICRCTypes "../ICRCTypes";
import Types "../Types";
module {

    public func icrc10_supported_standards() : [{ url : Text; name : Text }] {
        return [
          { url = "https://github.com/dfinity/ICRC/blob/main/ICRCs/ICRC-10/ICRC-10.md"; name = "ICRC-10" },
          { url = "https://github.com/dfinity/ICRC/blob/main/ICRCs/ICRC-21/ICRC-21.md"; name = "ICRC-21" },
          { url = "https://github.com/dfinity/wg-identity-authentication/blob/main/topics/icrc_28_trusted_origins.md"; name = "ICRC-28" }
        ];
    };
    
    public func icrc21_canister_call_consent_message(request : ICRCTypes.Icrc21ConsentMessageRequest) : ICRCTypes.Icrc21ConsentMessageResponse {
        let metadata = {
            utc_offset_minutes = null;
            language = "en";
        };
        // if (Text.equal(request.method, "addLimitOrder")) {
        //     return add_limit_order_consent_msg(request.arg, metadata);
        // } else 
        let msg = if (Text.equal(request.method, "approvePosition")) {
            approve_position_consent_msg(request.arg)
        } else if (Text.equal(request.method, "claim")) {
            claim_consent_msg(request.arg)
        } else if (Text.equal(request.method, "decreaseLiquidity")) {
            decrease_liquidity_consent_msg(request.arg)
        } else if (Text.equal(request.method, "deposit") or Text.equal(request.method, "depositFrom")) {
            deposit_consent_msg(request.arg)
        } else if (Text.equal(request.method, "increaseLiquidity")) {
            increase_liquidity_consent_msg(request.arg)
        } else if (Text.equal(request.method, "mint")) {
            mint_consent_msg(request.arg)
        } else if (Text.equal(request.method, "swap")) {
            swap_consent_msg(request.arg)
        } else if (Text.equal(request.method, "transferPosition")) {
            transfer_position_consent_msg(request.arg)
        } else if (Text.equal(request.method, "withdraw")) {
            withdraw_consent_msg(request.arg)
        } else if (Text.equal(request.method, "depositFromAndSwap") or Text.equal(request.method, "depositAndSwap")) {
            deposit_and_swap_consent_msg(request.arg)
        } else if (Text.equal(request.method, "addLimitOrder")) {
            add_limit_order_consent_msg(request.arg)
        } else if (Text.equal(request.method, "removeLimitOrder")) {
            remove_limit_order_consent_msg(request.arg)
        } else if (Text.equal(request.method, "createPool")) {
            create_pool_consent_msg(request.arg)
        } else {
            null
            // return #Err(#UnsupportedCanisterCall({ description = "Unsupported method: " # request.method }));
        };
        switch (msg) {
            case (?_msg) {
                return #Ok({
                    metadata = metadata;
                    consent_message = #GenericDisplayMessage(_msg);
                });
            };
            case (_) {
                return #Err(#GenericError({ description = "Invalid request"; error_code = 1; }));
            };
        };
    };
    private func approve_position_consent_msg(args_candid: Blob): ?Text {
        let _args: ?(Principal, Nat) = from_candid(args_candid);
        switch (_args) {
            case (?args) {
                return Option.make("approvePosition(" # Principal.toText(args.0) # ", " # Nat.toText(args.1) # ")");
            };
            case (_) {
                return null;
            };
        };
    };
    private func claim_consent_msg(args_candid: Blob): ?Text {
        let _args: ?Types.ClaimArgs = from_candid(args_candid);
        switch (_args) {
            case (?args) {
                return Option.make("claim({positionId: " # Nat.toText(args.positionId) # "})");
            };
            case (_) {
                return null;
            };
        };
    };
    private func decrease_liquidity_consent_msg(args_candid: Blob): ?Text {
        let _args: ?Types.DecreaseLiquidityArgs = from_candid(args_candid);
        switch (_args) {
            case (?args) {
                return Option.make("decreaseLiquidity({positionId: " # Nat.toText(args.positionId) # ", liquidity: " # args.liquidity # "})")
            };
            case (_) {
                return null;
            };
        };
    };
    private func deposit_consent_msg(args_candid: Blob): ?Text {
        let _args: ?Types.DepositArgs = from_candid(args_candid);
        switch (_args) {
            case (?args) {
                return Option.make("deposit({token: " # args.token # ", amount: " # Nat.toText(args.amount) # ", fee: " # Nat.toText(args.fee) # "})")
            };
            case (_) {
                return null;
            };
        };
    };
    private func deposit_and_swap_consent_msg(args_candid: Blob): ?Text {
        let _args: ?Types.DepositAndSwapArgs = from_candid(args_candid);
        switch (_args) {
            case (?args) {
                return Option.make("depositAndSwap({" # 
                    "zeroForOne: " # debug_show(args.zeroForOne) # 
                    ", amountIn: " # args.amountIn # 
                    ", tokenInFee: " # Nat.toText(args.tokenInFee) # 
                    ", amountOutMinimum: " # args.amountOutMinimum # 
                    ", tokenOutFee: " # Nat.toText(args.tokenOutFee) # 
                "})")
            };
            case (_) {
                return null;
            };
        };
    };
    private func increase_liquidity_consent_msg(args_candid: Blob): ?Text {
        let _args: ?Types.IncreaseLiquidityArgs = from_candid(args_candid);
        switch (_args) {
            case (?args) {
                return Option.make("increaseLiquidity({positionId: " # Nat.toText(args.positionId) # ", amount0Desired: " # args.amount0Desired # ", amount1Desired: " # args.amount1Desired # "})");
            };
            case (_) {
                return null;
            };
        };
    };
    private func mint_consent_msg(args_candid: Blob): ?Text {
        let _args: ?Types.MintArgs = from_candid(args_candid);
        switch (_args) {
            case (?args) {
                return Option.make("mint({tickLower: " # Int.toText(args.tickLower) # ", tickUpper: " # Int.toText(args.tickUpper) # ", amount0Desired: " # args.amount0Desired # ", amount1Desired: " # args.amount1Desired # "})");
            };
            case (_) {
                return null;
            };
        };
    };
    private func swap_consent_msg(args_candid: Blob): ?Text {
        let _args: ?Types.SwapArgs = from_candid(args_candid);
        switch (_args) {
            case (?args) {
                return Option.make("swap({amountIn: " # args.amountIn # ", amountOutMinimum: " # args.amountOutMinimum # "})");
            };
            case (_) {
                return null;
            };
        };
    };
    private func transfer_position_consent_msg(args_candid: Blob): ?Text {
        let _args: ?(Principal, Principal, Nat) = from_candid(args_candid);
        switch (_args) {
            case (?args) {
                return Option.make("transferPosition({positionId: " # Nat.toText(args.2) # ", to: " # Principal.toText(args.1) # "})");
            };
            case (_) {
                return null;
            };
        };
    };
    private func withdraw_consent_msg(args_candid: Blob): ?Text {
        let _args: ?Types.WithdrawArgs = from_candid(args_candid);
        switch (_args) {
            case (?args) {
                return Option.make("withdraw({token: " # args.token # ", amount: " # Nat.toText(args.amount) # ", fee: " # Nat.toText(args.fee) # "})");
            };
            case (_) {
                return null;
            };
        };
    };
    private func create_pool_consent_msg(args_candid: Blob): ?Text {
        let _args: ?Types.CreatePoolArgs = from_candid(args_candid);
        switch (_args) {
            case (?args) {
                return Option.make("createPool({token0: " # args.token0.address # ", token1: " # args.token1.address # ", fee: " # Nat.toText(args.fee) # ", sqrtPriceX96: " # args.sqrtPriceX96 # "})");
            };
            case (_) {
                return null;
            };
        };
    };
    private func add_limit_order_consent_msg(args_candid: Blob): ?Text {
        let _args: ?Types.LimitOrderArgs = from_candid(args_candid);
        switch (_args) {
            case (?args) {
                return Option.make("addLimitOrder({" # 
                    "positionId: " # debug_show(args.positionId) # 
                    ", tickLimit: " # debug_show(args.tickLimit) # 
                "})")
            };
            case (_) {
                return null;
            };
        };
    };
    private func remove_limit_order_consent_msg(args_candid: Blob): ?Text {
        let _args: ?(Nat) = from_candid(args_candid);
        switch (_args) {
            case (?args) {
                return Option.make("removeLimitOrder({" # 
                    "positionId: " # debug_show(args) # 
                "})")
            };
            case (_) {
                return null;
            };
        };
    };
}