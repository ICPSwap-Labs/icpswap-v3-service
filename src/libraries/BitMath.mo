import Debug "mo:base/Debug";
import Nat "mo:base/Nat";

import Result "mo:base/Result";
import SafeUint "mo:commons/math/SafeUint";

/// @dev This library provides funcality for computing bit properties of an unsigned integer
module BitMath {

    type Uint256 = Nat;
    type Uint8 = Nat;

    public func mostSignificantBit(_x:SafeUint.Uint256): Result.Result<Uint8, Text> {
        var r = 0;
        var x:SafeUint.Uint256 = _x;
        if(x.val() <= 0) {
            return #err("illegal _x");
        };
        if (x.val() >= 0x100000000000000000000000000000000) {
            x := x.bitshiftRight(128);
            r := r + 128;
        };
        if (x.val() >= 0x10000000000000000) {
            x := x.bitshiftRight(64);
            r := r + 64;
        };
        if (x.val() >= 0x100000000) {
            x := x.bitshiftRight(32);
            r := r + 32;
        };
        if (x.val() >= 0x10000) {
            x := x.bitshiftRight(16);
            r := r + 16;
        };
        if (x.val() >= 0x100) {
            x := x.bitshiftRight(8);
            r := r + 8;
        };
        if (x.val() >= 0x10) {
            x := x.bitshiftRight(4);
            r := r + 4;
        };
        if (x.val() >= 0x4) {
            x := x.bitshiftRight(2);
            r := r + 2;
        };
        if (x.val() >= 0x2) r := r + 1;
        return #ok(r);
    };
    
    public func leastSignificantBit(_x:SafeUint.Uint256): Result.Result<Uint8, Text> {
        var x:SafeUint.Uint256 = _x;
        if(x.val() <= 0) {
            return #err("illegal _x");
        };
        var r = 255;
        if (x.bitand(SafeUint.Uint256(SafeUint.UINT_128_MAX)).val() > 0) {
            r := r - 128;
        } else {
            x := x.bitshiftRight(128);
        };
        if (x.bitand(SafeUint.Uint256(SafeUint.UINT_64_MAX)).val() > 0) {
            r := r - 64;
        } else {
            x := x.bitshiftRight(64);
        };
        if (x.bitand(SafeUint.Uint256(SafeUint.UINT_32_MAX)).val() > 0) {
            r := r - 32;
        } else {
            x := x.bitshiftRight(32);
        };
        if (x.bitand(SafeUint.Uint256(SafeUint.UINT_16_MAX)).val() > 0) {
            r := r - 16;
        } else {
            x := x.bitshiftRight(16);
        };
        if (x.bitand(SafeUint.Uint256(SafeUint.UINT_8_MAX)).val() > 0) {
            r := r - 8;
        } else {
            x := x.bitshiftRight(8);
        };
        if (x.bitand(SafeUint.Uint256(SafeUint.UINT_4_MAX)).val() > 0) {
            r := r - 4;
        } else {
            x := x.bitshiftRight(4);
        };
        if (x.bitand(SafeUint.Uint256(SafeUint.UINT_2_MAX)).val() > 0) {
            r := r - 2;
        } else {
            x := x.bitshiftRight(2);
        };
        if (x.bitand(SafeUint.Uint256(SafeUint.UINT_1_MAX)).val() > 0) r := r - 1;
        return #ok(r);
    };
};