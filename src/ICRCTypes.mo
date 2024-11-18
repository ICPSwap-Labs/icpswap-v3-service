import Blob "mo:base/Blob";
import Int16 "mo:base/Int16";
import Nat16 "mo:base/Nat16";
import Nat "mo:base/Nat";
import Text "mo:base/Text";

module {
    public type Icrc21ConsentInfo = {
        metadata : Icrc21ConsentMessageMetadata;
        consent_message : Icrc21ConsentMessage;
    };
    public type Icrc21ConsentMessage = {
        #LineDisplayMessage : { pages : [{ lines : [Text] }] };
        #GenericDisplayMessage : Text;
    };
    public type Icrc21ConsentMessageMetadata = {
        utc_offset_minutes : ?Int16;
        language : Text;
    };
    public type Icrc21ConsentMessageRequest = {
        arg : Blob;
        method : Text;
        user_preferences : Icrc21ConsentMessageSpec;
    };
    public type Icrc21ConsentMessageResponse = {
        #Ok : Icrc21ConsentInfo;
        #Err : Icrc21Error;
    };
    public type Icrc21ConsentMessageSpec = {
        metadata : Icrc21ConsentMessageMetadata;
        device_spec : ?{
            #GenericDisplay;
            #LineDisplay : { characters_per_line : Nat16; lines_per_page : Nat16 };
        };
    };
    public type Icrc21Error = {
        #GenericError : { description : Text; error_code : Nat };
        #InsufficientPayment : Icrc21ErrorInfo;
        #UnsupportedCanisterCall : Icrc21ErrorInfo;
        #ConsentMessageUnavailable : Icrc21ErrorInfo;
    };
    public type Icrc21ErrorInfo = { description : Text };
    public type Icrc28TrustedOriginsResponse = { trusted_origins : [Text] };
};