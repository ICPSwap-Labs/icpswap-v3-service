import Time "mo:base/Time";
import IntUtils "mo:commons/math/SafeInt/IntUtils";

module BlockTimestamp{
    public func blockTimestamp(): Nat {
        return IntUtils.toNat(Time.now() / 1000000000, 256);
    }
}
