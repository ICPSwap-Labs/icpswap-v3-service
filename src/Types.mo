import Blob "mo:base/Blob";
import Bool "mo:base/Bool";
import Int "mo:base/Int";
import Nat "mo:base/Nat";
import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Text "mo:base/Text";
import ICRCTypes "./ICRCTypes";
import TxTypes "./components/transaction/Types";

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
    public type PoolInitArgs = {
        token0 : Token;
        token1 : Token;
        infoCid : Principal;
        feeReceiverCid : Principal;
        trustedCanisterManagerCid : Principal;
        positionIndexCid : Principal;
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
        subnet : ?Text;
    };
    public type CreatePoolRecord = {
        caller: Principal;
        timestamp: Int;
        token0: Token;
        token1: Token;
        fee: Nat;
        poolId: ?Principal;
        status: Text;
        err: ?Text;
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
    public type LimitOrderArgs = {
        positionId : Nat;
        tickLimit : Int;
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
    public type DecreaseLimitOrderArgs = {
        isLimitOrder : Bool;
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
    public type WithdrawToSubaccountArgs = {
        token : Text;
        fee : Nat;
        amount : Nat;
        subaccount : Blob;
    };
    public type TransactionType = {
        #addLiquidity;
        #increaseLiquidity;
        #decreaseLiquidity;
        #claim;
        #addPositionLiquidity : Nat;
        #increasePositionLiquidity : Nat;
        #decreasePositionLiquidity : Nat;
        #claimPosition : Nat;
        #swap;
        #transferPosition : Nat;
        #limitOrder : { positionId : Nat; token0InAmount : Nat; token1InAmount : Nat; tickLimit : Int };
    };
    public type SwapRecordInfo = {
        txInfo : TxTypes.Transaction;
        currentLiquidity : Nat;
        currentTick : Int;
        currentSqrtPriceX96 : Nat;
    };
    public type TxStorage = actor {
        push : (SwapRecordInfo) -> async ();
        batchPush : ([SwapRecordInfo]) -> async ();
        batchPushV2 : ([SwapRecordInfo]) -> async ();
        addClient : (Principal) -> async ();
    };
    public type PushError = {
        message : Text;
        time : Int;
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
    public type Passcode = {
        token0 : Principal;
        token1 : Principal;
        fee : Nat;
    };
    public type TransferLog = {
        index : Nat;
        owner : Principal;
        from : Principal;
        fromSubaccount : ?Blob;
        to : Principal;
        toSubaccount : ?Blob;
        action : Text; // deposit, withdraw
        amount : Nat;
        fee : Nat;
        token : Token;
        result : Text; // processing, success, error
        errorMsg : Text;
        daysFrom19700101 : Nat;
        timestamp : Nat;
    };
    public type LimitOrderType = {
        #Lower;
        #Upper;
    };
    public type LimitOrderKey = {
        timestamp : Nat;
        tickLimit : Int;
    };
    public type LimitOrderValue = {
        userPositionId : Nat;
        owner : Principal;
        token0InAmount : Nat;
        token1InAmount : Nat;
    };
    public type ClaimedPoolData = {
        token0 : Token;
        token1 : Token;
        fee : Nat;
        claimed : Bool;
    };
    public type UpgradePoolArgs = {
        poolIds : [Principal];
    };
    public type PoolUpgradeTaskStep = {
        timestamp : Nat;
        isDone : Bool;
    };
    public type ReceiverClaimLog = {
        timestamp : Nat;
        amount : Nat;
        poolId : Principal;
        token : Token;
        errMsg : Text;
    };
    public type ReceiverSwapLog = {
        timestamp : Nat;
        token : Token;
        amountIn : Nat;
        amountOut : Nat;
        errMsg : Text;
        step : Text;
        poolId : ?Principal;
    };
    public type ReceiverBurnLog = {
        timestamp : Nat;
        amount : Nat;
        errMsg : Text;
    };
    public type PoolUpgradeTask = {
        poolData : PoolData;
        moduleHashBefore : ?Blob;
        moduleHashAfter : ?Blob;
        backup : { timestamp : Nat; isDone : Bool; retryCount : Nat; isSent : Bool; };
        turnOffAvailable : PoolUpgradeTaskStep;
        stop : PoolUpgradeTaskStep;
        upgrade : PoolUpgradeTaskStep;
        start : PoolUpgradeTaskStep;
        turnOnAvailable : PoolUpgradeTaskStep;
    };
    public type FailedPoolInfo = {
        task: PoolUpgradeTask;
        timestamp: Nat;
        errorMsg: Text;
    };
    public type PoolInstaller = {
        canisterId : Principal;
        subnet : Text;
        subnetType: Text;
        weight : Nat;
    };
    public type DepositAndSwapArgs = {
        zeroForOne : Bool;
        tokenInFee: Nat;
        tokenOutFee: Nat;
        amountIn : Text;
        amountOutMinimum : Text;
    };
    public type SwapPoolMsg = {
        #activeJobs : () -> ();
        #addLimitOrder : () -> LimitOrderArgs;
        #allTokenBalance : () -> (Nat, Nat);
        #approvePosition : () -> (Principal, Nat);
        #batchRefreshIncome : () -> [Nat];
        #checkOwnerOfUserPosition : () -> (Principal, Nat);
        #claim : () -> ClaimArgs;
        #decreaseLiquidity : () -> DecreaseLiquidityArgs;
        #deleteFailedTransaction : () -> (Nat, Bool);
        #deposit : () -> DepositArgs;
        #depositAllAndMint : () -> DepositAndMintArgs;
        #depositAndSwap : () -> DepositAndSwapArgs;
        #depositFrom : () -> DepositArgs;
        #depositFromAndSwap : () -> DepositAndSwapArgs;
        #getAdmins : () -> ();
        #getAvailabilityState : () -> ();
        #getCachedTokenFee : () -> ();
        #getClaimLog : () -> ();
        #getCycleInfo : () -> ();
        #getFailedTransactions : () -> ();
        #getFeeGrowthGlobal : () -> ();
        #getInitArgs : () -> ();
        #getJobs : () -> ();
        #getLimitOrderAvailabilityState : () -> ();
        #getLimitOrderStack : () -> ();
        #getLimitOrders : () -> ();
        #getMistransferBalance : () -> Token;
        #getPosition : () -> GetPositionArgs;
        #getPositions : () -> (Nat, Nat);
        #getSortedUserLimitOrders : () -> Principal;
        #getSwapRecordState : () -> ();
        #getTickBitmaps : () -> ();
        #getTickInfos : () -> (Nat, Nat);
        #getTicks : () -> (Nat, Nat);
        #getTokenAmountState : () -> ();
        #getTokenBalance : () -> ();
        #getTransactions : () -> ();
        #getUserByPositionId : () -> Nat;
        #getUserLimitOrders : () -> Principal;
        #getUserPosition : () -> Nat;
        #getUserPositionIds : () -> ();
        #getUserPositionIdsByPrincipal : () -> Principal;
        #getUserPositionWithTokenAmount : () -> (Nat, Nat);
        #getUserPositions : () -> (Nat, Nat);
        #getUserPositionsByPrincipal : () -> Principal;
        #getUserUnusedBalance : () -> Principal;
        #getVersion : () -> ();
        #icrc10_supported_standards : () -> ();
        #icrc21_canister_call_consent_message : () -> ICRCTypes.Icrc21ConsentMessageRequest;
        #icrc28_trusted_origins : () -> ();
        #increaseLiquidity : () -> IncreaseLiquidityArgs;
        #init : () -> (Nat, Int, Nat);
        #metadata : () -> ();
        #mint : () -> MintArgs;
        #quote : () -> SwapArgs;
        #quoteForAll : () -> SwapArgs;
        #refreshIncome : () -> Nat;
        #removeLimitOrder : () -> Nat;
        #restartJobs : () -> [Text];
        #setAdmins : () -> [Principal];
        #setAvailable : () -> Bool;
        #setIcrc28TrustedOrigins : () -> [Text];
        #setLimitOrderAvailable : () -> Bool;
        #setWhiteList : () -> [Principal];
        #stopJobs : () -> [Text];
        #sumTick : () -> ();
        #swap : () -> SwapArgs;
        #transferPosition : () -> (Principal, Principal, Nat);
        #updateTokenFee : () -> ();
        #upgradeTokenStandard : () -> Principal;
        #withdraw : () -> WithdrawArgs;
        #withdrawMistransferBalance : () -> Token;
        #withdrawToSubaccount : () -> WithdrawToSubaccountArgs;  
    };
    public type SwapFactoryMsg = {
        #activateWasm : () -> ();
        #addPasscode : () -> (principal : Principal, passcode : Passcode);
        #addPoolInstallers : () -> (installers : [PoolInstaller]);
        #addPoolInstallersValidate : () -> (installers : [PoolInstaller]);
        #batchAddPoolControllers :
          () -> (poolCids : [Principal], controllers : [Principal]);
        #batchClearRemovedPool : () -> (poolCids : [Principal]);
        #batchRemovePoolControllers :
          () -> (poolCids : [Principal], controllers : [Principal]);
        #batchRemovePools : () -> (poolCids : [Principal]);
        #batchSetPoolAdmins :
          () -> (poolCids : [Principal], admins : [Principal]);
        #batchSetPoolAvailable :
          () -> (poolCids : [Principal], available : Bool);
        #batchSetPoolIcrc28TrustedOrigins :
          () -> (poolCids : [Principal], origins : [Text]);
        #batchSetPoolLimitOrderAvailable :
          () -> (poolCids : [Principal], available : Bool);
        #clearChunks : () -> ();
        #clearPoolUpgradeTaskHis : () -> ();
        #clearUpgradeFailedPoolList : () -> ();
        #combineWasmChunks : () -> ();
        #createPool : () -> (args : CreatePoolArgs);
        #deletePasscode : () -> (principal : Principal, passcode : Passcode);
        #getActiveWasm : () -> ();
        #getAdmins : () -> ();
        #getCreatePoolRecords : () -> ();
        #getCreatePoolRecordsByCaller : () -> (caller : Principal);
        #getCurrentUpgradeTask : () -> ();
        #getCycleInfo : () -> ();
        #getGovernanceCid : () -> ();
        #getInitArgs : () -> ();
        #getInstallerModuleHash : () -> ();
        #getNextPoolVersion : () -> ();
        #getPasscodesByPrincipal : () -> (principal : Principal);
        #getPendingUpgradePoolList : () -> ();
        #getPool : () -> (args : GetPoolArgs);
        #getPoolInstallers : () -> ();
        #getPoolUpgradeTaskHis : () -> (poolCid : Principal);
        #getPoolUpgradeTaskHisList : () -> ();
        #getPools : () -> ();
        #getPrincipalPasscodes : () -> ();
        #getRemovedPools : () -> ();
        #getStagingWasm : () -> ();
        #getUpgradeFailedPoolList : () -> ();
        #getVersion : () -> ();
        #getWasmActiveStatus : () -> ();
        #icrc10_supported_standards : () -> ();
        #icrc21_canister_call_consent_message :
          () -> (request : ICRCTypes.Icrc21ConsentMessageRequest);
        #icrc28_trusted_origins : () -> ();
        #removePoolInstaller : () -> (canisterId : Principal);
        #removePoolInstallerValidate : () -> (canisterId : Principal);
        #retryAllFailedUpgrades : () -> ();
        #setAdmins : () -> (admins : [Principal]);
        #setIcrc28TrustedOrigins : () -> (origins : [Text]);
        #setInstallerModuleHash : () -> (moduleHash : Blob);
        #setInstallerModuleHashValidate : () -> (moduleHash : Blob);
        #setUpgradePoolList : () -> (args : UpgradePoolArgs);
        #upgradePoolTokenStandard :
          () -> (poolCid : Principal, tokenCid : Principal);
        #uploadWasmChunk : () -> (chunk : [Nat8]);
    };
    public type SwapFeeReceiverMsg = {
        #burnICS : () -> ();
        #claim : () -> (Principal, Token, Nat);
        #getBaseBalances : () -> ();
        #getCanisterId : () -> ();
        #getConfig : () -> ();
        #getCycleInfo : () -> ();
        #getFees : () -> ();
        #getInitArgs : () -> ();
        #getPools : () -> ();
        #getSyncingStatus : () -> ();
        #getTokenBurnLog : () -> ();
        #getTokenClaimLog : () -> ();
        #getTokenSwapLog : () -> ();
        #getTokens : () -> ();
        #getVersion : () -> ();
        #setAutoBurnIcsEnabled : () -> Bool;
        #setAutoSwapToIcsEnabled : () -> Bool;
        #setCanisterId : () -> ();
        #setFees : () -> ();
        #setIcpPoolClaimInterval : () -> Nat;
        #setNoIcpPoolClaimInterval : () -> Nat;
        #startAutoSyncPools : () -> ();
        #swapICPToICS : () -> ();
        #swapToICP : () -> Token;
        #swapWithoutDeposit : () -> (Principal, Bool, Text, Text);
        #transfer : () -> (Token, Principal, Nat);
        #transferAll : () -> (Token, Principal);
    };
    public type SwapPoolActor = actor {
        init : (Nat, Int, Nat) -> async ();
        allTokenBalance : query (Nat, Nat) -> async Result.Result<Page<(Principal, { balance0: Nat; balance1: Nat; })>, Error>;
        initUserPositionIdMap : shared (userPositionIds : [(Text, [Nat])]) -> async ();
        getUserPositionIds : query () -> async Result.Result<[(Text, [Nat])], Error>;
        getUserPositionIdsByPrincipal : query (owner : Principal) -> async Result.Result<[Nat], Error>;
        setAdmins : shared ([Principal]) -> async ();
        setAvailable : shared (Bool) -> async ();
        setLimitOrderAvailable : shared (Bool) -> async ();
        metadata : query () -> async Result.Result<PoolMetadata, Error>;
        upgradeTokenStandard : shared (Principal) -> async ();
        removeErrorTransferLog : shared (Nat, Bool) -> async ();
        getUserUnusedBalance : query (Principal) -> async Result.Result<{ balance0 : Nat; balance1 : Nat }, Error>;
        withdraw : shared (WithdrawArgs) -> async Result.Result<Nat, Error>;
        getTransferLogs : query () -> async Result.Result<[TransferLog], Error>;
        getAvailabilityState : query () -> async { available : Bool; whiteList : [Principal]; };
        deposit : shared (DepositArgs) -> async Result.Result<Nat, Error>;
        depositFrom : shared (DepositArgs) -> async Result.Result<Nat, Error>;
        swap : shared (SwapArgs) -> async Result.Result<Nat, Error>;
        getLimitOrderAvailabilityState : query () -> async Result.Result<Bool, Error>;
        getLimitOrderStack : query () -> async Result.Result<[(LimitOrderKey, LimitOrderValue)], Error>;
        getLimitOrders : query () -> async Result.Result<{ lowerLimitOrders : [(LimitOrderKey, LimitOrderValue)]; upperLimitOrders : [(LimitOrderKey, LimitOrderValue)]; },Error>;
        getPositions : query (Nat, Nat) -> async Result.Result<Page<PositionInfoWithId>, Error>;
        getSwapRecordState : query () -> async Result.Result<{ infoCid : Text; records : [SwapRecordInfo]; retryCount : Nat; errors : [PushError]; }, Error>;
        getTicks : query (Nat, Nat) -> async Result.Result<Page<TickInfoWithId>, Error>;
        getTokenAmountState : query () -> async Result.Result<{ token0Amount : Nat; token1Amount : Nat; swapFee0Repurchase : Nat; swapFee1Repurchase : Nat; swapFeeReceiver : Text;}, Error>;
        getUserPositions : query (Nat, Nat) -> async Result.Result<Page<UserPositionInfoWithId>, Error>;
        getAdmins : query () -> async [Principal];
        getVersion : query () -> async Text;
        getTickBitmaps : query () -> async Result.Result<[(Int, Nat)], Error>;
        getFeeGrowthGlobal : query () -> async Result.Result<{ feeGrowthGlobal0X128 : Nat; feeGrowthGlobal1X128 : Nat; }, Error>;
        getInitArgs : query () -> async Result.Result<PoolInitArgs, Error>;
        setIcrc28TrustedOrigins : shared ([Text]) -> async Result.Result<Bool, ()>;
        recoverUserPositions : shared ([UserPositionInfoWithId]) -> async ();
        recoverPositions : shared ([PositionInfoWithId]) -> async ();
        recoverTickBitmaps : shared ([(Int, Nat)]) -> async ();
        recoverTicks : shared ([TickInfoWithId]) -> async ();
        recoverUserPositionIds : shared ([(Text, [Nat])]) -> async ();
        resetPositionTickService : shared () -> async ();
        recoverMetadata : shared (PoolMetadata, { feeGrowthGlobal0X128 : Nat; feeGrowthGlobal1X128 : Nat; }) -> async ();
    };
    public type SwapFactoryActor = actor {
        getPendingUpgradePoolList : query () -> async Result.Result<[PoolData], Error>;
        getPool : query (GetPoolArgs) -> async Result.Result<PoolData, Error>;
        getPools : query () -> async Result.Result<[PoolData], Error>;
        addPasscode : (Principal, Passcode) -> async Result.Result<(), Error>;
        deletePasscode : (Principal, Passcode) -> async Result.Result<(), Error>;
        getRemovedPools : query () -> async Result.Result<[PoolData], Error>;
        getPoolInstallers : query () -> async [PoolInstaller];
    };
    public type SwapDataBackupActor = actor {
        backup : (Principal) -> async Result.Result<(), Error>;
        isBackupDone : (Principal) -> async Result.Result<Bool, Error>;
        removeBackupData : (Principal) -> async Result.Result<(), Error>;
    };
    public type SwapPoolInstaller = actor {
        install : (Token, Token, Principal, Principal, Principal, Principal) -> async Principal;
        getCycleInfo : () -> async Result.Result<CycleInfo, Error>;
    };
    public type PositionIndexActor = actor {
        updatePoolIds : () -> async ();
        updateUserPool : (Principal, ?Principal) -> async Result.Result<Bool, Error>;
        addPoolToUser : (Principal) -> async Result.Result<Bool, Error>;
        removePoolFromUser : (Principal) -> async Result.Result<Bool, Error>;
    };
};
