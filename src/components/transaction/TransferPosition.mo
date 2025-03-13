import Types "./Types";

module TransferPosition {
    public func complete(positionId: Nat, from: Types.Account, to: Types.Account) : Types.TransferPositionInfo {
        return {
            positionId = positionId;
            from = from;
            to = to;
            status = #Completed;
        };
    };
    
};
