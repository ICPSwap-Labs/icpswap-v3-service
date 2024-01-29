import Blob "mo:base/Blob";
import Bool "mo:base/Bool";
import Time "mo:base/Time";
import Hash "mo:base/Hash";
import Int "mo:base/Int";
import Nat "mo:base/Nat";
import Nat32 "mo:base/Nat32";
import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Text "mo:base/Text";
import ExtCore "mo:token-adapter/standard/EXT/ext/Core";
import IcsNonFungible "mo:token-adapter/standard/EXT/ext/IcsNonFungible";

module {

    public type Value = { #Nat : Nat; #Int : Int; #Blob : Blob; #Text : Text };
    public type Error = {
        #CommonError;
        #InternalError : Text;
        #UnsupportedToken : Text;
        #InsufficientFunds;
    };
    public type Token = {
        address : Text;
        standard : Text;
    };
    public type AccountIdentifier = Text;
    public type Account = {
        principal : Principal;
        subaccount : ?Blob;
    };
    public type User = {
        #address : AccountIdentifier;
        #account : Account;
    };
    public type PoolMetadata = {
        key : Text;
        token0 : Token;
        token1 : Token;
        fee : Nat;
        tick : Int;
        liquidity : Nat;
        sqrtPriceX96 : Nat;
        maxLiquidityPerTick : Nat;
        nextPositionId : Nat;
    };
    public type PoolData = {
        key : Text;
        token0 : Token;
        token1 : Token;
        fee : Nat;
        tickSpacing : Int;
        canisterId : Principal;
    };
    public type PositionInfo = {
        liquidity : Nat;
        feeGrowthInside0LastX128 : Nat;
        feeGrowthInside1LastX128 : Nat;
        tokensOwed0 : Nat;
        tokensOwed1 : Nat;
    };
    public type PositionInfoWithId = {
        id : Text;
        liquidity : Nat;
        feeGrowthInside0LastX128 : Nat;
        feeGrowthInside1LastX128 : Nat;
        tokensOwed0 : Nat;
        tokensOwed1 : Nat;
    };
    public type UserPositionInfo = {
        tickLower : Int;
        tickUpper : Int;
        liquidity : Nat;
        feeGrowthInside0LastX128 : Nat;
        feeGrowthInside1LastX128 : Nat;
        tokensOwed0 : Nat;
        tokensOwed1 : Nat;
    };
    public type UserPositionInfoWithId = {
        id : Nat;
        tickLower : Int;
        tickUpper : Int;
        liquidity : Nat;
        feeGrowthInside0LastX128 : Nat;
        feeGrowthInside1LastX128 : Nat;
        tokensOwed0 : Nat;
        tokensOwed1 : Nat;
    };
    public type UserPositionInfoWithTokenAmount = {
        id : Nat;
        tickLower : Int;
        tickUpper : Int;
        liquidity : Nat;
        feeGrowthInside0LastX128 : Nat;
        feeGrowthInside1LastX128 : Nat;
        tokensOwed0 : Nat;
        tokensOwed1 : Nat;
        token0Amount : Nat;
        token1Amount : Nat;
    };
    public type WithdrawErrorLog = {
        token : Token;
        amount : Nat;
        time : Int;
        user : Principal;
    };
    public type QueryPositionResult = {
        token0 : Token;
        token1 : Token;
        pool : Text;
        fee : Nat;
        positionId : Text;
        tickLower : Int;
        tickUpper : Int;
        liquidity : Nat;
        feeGrowthInside0LastX128 : Nat;
        feeGrowthInside1LastX128 : Nat;
        tokensOwed0 : Nat;
        tokensOwed1 : Nat;
    };
    public type TickInfo = {
        var liquidityGross : Nat;
        var liquidityNet : Int;
        var feeGrowthOutside0X128 : Nat;
        var feeGrowthOutside1X128 : Nat;
        var tickCumulativeOutside : Int;
        var secondsPerLiquidityOutsideX128 : Nat;
        var secondsOutside : Nat;
        var initialized : Bool;
    };
    public type TickInfoWithId = {
        id : Text;
        liquidityGross : Nat;
        liquidityNet : Int;
        feeGrowthOutside0X128 : Nat;
        feeGrowthOutside1X128 : Nat;
        tickCumulativeOutside : Int;
        secondsPerLiquidityOutsideX128 : Nat;
        secondsOutside : Nat;
        initialized : Bool;
    };
    public type TickLiquidityInfo = {
        liquidityGross : Nat;
        liquidityNet : Int;
        price0 : Nat;
        price1 : Nat;
        tickIndex : Int;
        price0Decimal : Nat;
        price1Decimal : Nat;
    };
    public type TokenBalance = {
        token : Token;
        balance : Nat;
    };
    public type CreatePoolArgs = {
        token0 : Token;
        token1 : Token;
        fee : Nat;
        sqrtPriceX96 : Text;
    };
    public type GetPoolArgs = {
        token0 : Token;
        token1 : Token;
        fee : Nat;
    };
    public type GetPositionArgs = {
        tickLower : Int;
        tickUpper : Int;
    };
    public type DepositArgs = {
        token : Text;
        amount : Nat;
        fee : Nat;
    };
    public type DepositAndMintArgs = {
        tickLower : Int;
        tickUpper : Int;
        amount0Desired : Text;
        amount1Desired : Text;
        positionOwner : Principal;
        fee0 : Nat;
        fee1 : Nat;
        amount0 : Nat;
        amount1 : Nat;
    };
    public type MintArgs = {
        token0 : Text;
        token1 : Text;
        fee : Nat;
        tickLower : Int;
        tickUpper : Int;
        amount0Desired : Text;
        amount1Desired : Text;
    };
    public type IncreaseLiquidityArgs = {
        positionId : Nat;
        amount0Desired : Text;
        amount1Desired : Text;
    };
    public type DecreaseLiquidityArgs = {
        positionId : Nat;
        liquidity : Text;
    };
    public type ClaimArgs = {
        positionId : Nat;
    };
    public type SwapArgs = {
        zeroForOne : Bool;
        amountIn : Text;
        amountOutMinimum : Text;
    };
    public type WithdrawArgs = {
        token : Text;
        fee : Nat;
        amount : Nat;
    };
    public type TransactionType = {
        #addLiquidity;
        #increaseLiquidity;
        #decreaseLiquidity;
        #claim;
        #swap;
    };
    public type TxStorage = actor {
        push : (SwapRecordInfo) -> async ();
        batchPush : ([SwapRecordInfo]) -> async ();
        addOwner : (Principal) -> async ();
        addClient : (Principal) -> async ();
    };
    public type PushError = {
        message : Text;
        time : Int;
    };
    public type TxStorageCanister = {
        canisterId : Text;
        canister : TxStorage;
        var retryCount : Nat;
        var errors : [PushError];
    };
    public type SwapRecordInfo = {
        action : TransactionType;
        feeTire : Nat;
        from : Text;
        liquidityChange : Nat;
        liquidityTotal : Nat;
        poolId : Text;
        price : Nat;
        feeAmount : Int;
        feeAmountTotal : Int;
        TVLToken0 : Int;
        TVLToken1 : Int;
        recipient : Text;
        tick : Int;
        timestamp : Int;
        to : Text;
        token0AmountTotal : Nat;
        token0ChangeAmount : Nat;
        token0Fee : Nat;
        token0Id : Text;
        token0Standard : Text;
        token1AmountTotal : Nat;
        token1ChangeAmount : Nat;
        token1Fee : Nat;
        token1Id : Text;
        token1Standard : Text;
    };
    public type CycleInfo = {
        balance : Nat;
        available : Nat;
    };
    public type Page<T> = {
        totalElements : Nat;
        content : [T];
        offset : Nat;
        limit : Nat;
    };

    public type SwapPoolMsg = {
        #allTokenBalance : () -> (Nat, Nat);
        #approvePosition : () -> (Principal, Nat);
        #batchRefreshIncome : () -> ([Nat]);
        #checkOwnerOfUserPosition : () -> (Principal, Nat);
        #claim : () -> ClaimArgs;
        #decreaseLiquidity : () -> DecreaseLiquidityArgs;
        #deposit : () -> DepositArgs;
        #depositFrom : () -> DepositArgs;
        #getAddressPrincipals : () -> ();
        #getAvailabilityState : () -> ();
        #getClaimLog : () -> ();
        #getCycleInfo : () -> ();
        #getPosition : () -> GetPositionArgs;
        #getPositions : () -> (Nat, Nat);
        #getPrincipal : () -> Text;
        #getSwapRecordState : () -> ();
        #getTheoreticalAmount : () -> ();
        #getTickInfos : () -> (Nat, Nat);
        #getTicks : () -> (Nat, Nat);
        #getTokenAmountState : () -> ();
        #getTokenBalance : () -> ();
        #getTokenMeta : () -> ();
        #getUserByPositionId : () -> Nat;
        #getUserPosition : () -> Nat;
        #getUserPositionWithTokenAmount : () -> (Nat, Nat);
        #getUserPositions : () -> (Nat, Nat);
        #getUserPositionIds : () -> ();
        #getUserUnusedBalance : () -> Principal;
        #getUserPositionsByPrincipal : () -> Principal;
        #getUserPositionIdsByPrincipal : () -> Principal;
        #getVersion : () -> ();
        #getTransferLogs : () -> ();
        #getWithdrawErrorLog : () -> ();
        #increaseLiquidity : () -> IncreaseLiquidityArgs;
        #metadata : () -> ();
        #mint : () -> MintArgs;
        #quote : () -> SwapArgs;
        #quoteForAll : () -> SwapArgs;
        #refreshIncome : () -> Nat;
        #sumTick : () -> ();
        #swap : () -> SwapArgs;
        #transferPosition : () -> (Principal, Principal, Nat);
        // #transferToken : () -> (Nat, Principal, Nat);
        #withdraw : () -> WithdrawArgs;
        #getAdmins : () -> ();
        #getMistransferBalance : () -> Token;
        #withdrawMistransferBalance : () -> Token;
        // --------  Admin permission required.  ---------
        #depositAllAndMint : () -> DepositAndMintArgs;
        #setAvailable : () -> Bool;
        #setWhiteList : () -> [Principal];
        #removeErrorTransferLog : () -> (Nat, Bool);
        #removeWithdrawErrorLog : () -> (Nat, Bool);
        // --------  Controller permission required.  ---------
        #init : () -> (Nat, Int, Nat);
        #setAdmins : () -> [Principal];
        #upgradeTokenStandard : () -> Principal;
        #resetTokenAmountState : () -> (Nat, Nat, Nat, Nat);
    };
    public type SwapFactoryMsg = {
        #createPool : () -> CreatePoolArgs;
        #getCycleInfo : () -> ();
        #getGovernanceCid : () -> ();
        #getInvalidPools : () -> ();
        #getPool : () -> GetPoolArgs;
        #getPools : () -> ();
        #getPagedPools : () -> (Nat, Nat);
        #getRemovedPools : () -> ();
        #getVersion : () -> ();
        #removePool : () -> GetPoolArgs;
        #validateRemovePool : () -> GetPoolArgs;
        #restorePool : () -> Principal;
        #validateRestorePool : () -> Principal;
        #removePoolWithdrawErrorLog : () -> (Principal, Nat, Bool);
        #validateRemovePoolWithdrawErrorLog : () -> (Principal, Nat, Bool);
        #clearRemovedPool : () -> Principal;
        #validateClearRemovedPool : () -> Principal;
        #setPoolAdmins : () -> (Principal, [Principal]);
        #validateSetPoolAdmins : () -> (Principal, [Principal]);
        #addPoolControllers : () -> (Principal, [Principal]);
        #validateAddPoolControllers : () -> (Principal, [Principal]);
        #upgradePoolTokenStandard : () -> (Principal, Principal);
        #validateUpgradePoolTokenStandard : () -> (Principal, Principal);
        #removePoolControllers : () -> (Principal, [Principal]);
        #validateRemovePoolControllers : () -> (Principal, [Principal]);
        #batchSetPoolAdmins : () -> ([Principal], [Principal]);
        #validateBatchSetPoolAdmins : () -> ([Principal], [Principal]);
        #batchAddPoolControllers : () -> ([Principal], [Principal]);
        #validateBatchAddPoolControllers : () -> ([Principal], [Principal]);
        #batchRemovePoolControllers : () -> ([Principal], [Principal]);
        #validateBatchRemovePoolControllers : () -> ([Principal], [Principal]);
    };
    public type SwapFeeReceiverMsg = {
        #claim : () -> (Principal, Principal, Nat, Nat);
        #getCycleInfo : () -> ();
        #getVersion : () -> ();
        #transfer : () -> (Principal, Text, Principal, Nat);
    };
    public type SwapPoolActor = actor {
        initUserPositionIdMap : shared (userPositionIds : [(Text, [Nat])]) -> async ();
        getUserPositionIds : query () -> async Result.Result<[(Text, [Nat])], Error>;
        getUserPositionIdsByPrincipal : query (owner : Principal) -> async Result.Result<[Nat], Error>;
        setAdmins : shared ([Principal]) -> async ();
        metadata : query () -> async Result.Result<PoolMetadata, Error>;
        upgradeTokenStandard : shared (Principal) -> async ();
        removeWithdrawErrorLog : shared (Nat, Bool) -> async ();
        getUserUnusedBalance : shared (Principal) -> async Result.Result<{ balance0 : Nat; balance1 : Nat }, Error>;
        withdraw : shared (WithdrawArgs) -> async Result.Result<Nat, Error>;
    };
    public type SwapFactoryActor = actor {
        getPools : query () -> async Result.Result<[PoolData], Error>;
    };
};
