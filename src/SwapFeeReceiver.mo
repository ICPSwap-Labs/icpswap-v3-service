import Text "mo:base/Text";
import Array "mo:base/Array";
import Nat "mo:base/Nat";
import List "mo:base/List";
import Int "mo:base/Int";
import Hash "mo:base/Hash";
import Principal "mo:base/Principal";
import Cycles "mo:base/ExperimentalCycles";
import Time "mo:base/Time";
import Timer "mo:base/Timer";
import Debug "mo:base/Debug";
import Blob "mo:base/Blob";
import Buffer "mo:base/Buffer";
import HashMap "mo:base/HashMap";
import Iter "mo:base/Iter";
import Option "mo:base/Option";
import Result "mo:base/Result";
import Types "./Types";
import ListUtils "mo:commons/utils/ListUtils";
import Bool "mo:base/Bool";
import CollectionUtils "mo:commons/utils/CollectionUtils";
import PrincipalUtils "mo:commons/utils/PrincipalUtils";

shared (msg) actor class SwapFeeReceiver() {

    public shared func getCycleInfo() : async Result.Result<Types.CycleInfo, Types.Error> {
        return #ok({
            balance = Cycles.balance();
            available = Cycles.available();
        });
    };

    system func preupgrade() {
    };

    system func postupgrade() {
    };
};
