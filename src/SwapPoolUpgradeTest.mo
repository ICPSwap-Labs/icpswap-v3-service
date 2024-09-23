import Text "mo:base/Text";
import Principal "mo:base/Principal";
import Types "./Types";

shared (initMsg) actor class SwapPool(
    token0 : Types.Token,
    token1 : Types.Token,
    infoCid : Principal,
    feeReceiverCid : Principal,
) = this {
    
    // --------------------------- Version Control ------------------------------------
    private var _version : Text = "3.3.7";
    public query (msg) func getVersion() : async Text { _version };
    
};
