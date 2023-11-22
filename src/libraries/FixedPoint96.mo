import Nat "mo:base/Nat";

module FixedPoint96{
    type Uint8 = Nat;
    type Uint256 = Nat;
    
    public let RESOLUTION:Uint8 = 96;
    public let Q96:Uint256 = 0x1000000000000000000000000;
}
