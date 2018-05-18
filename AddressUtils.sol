pragma solidity ^0.4.23;


/// @title AddressUtils
/// @dev Utility library of inline functions on addresses
library AddressUtils {

    /// @dev Returns whether the target address is a contract
    /// @param addr address to check
    /// @return whether the target address is a contract
    function isContract(address addr) internal view returns (bool) {
        uint256 size;
        // XXX Currently there is no better way to check if there is a contract in an address
        // than to check the size of the code at that address.
        // See https://ethereum.stackexchange.com/a/14016/36603
        // for more details about how this works.
        // TODO Check this again before the Serenity release, because all addresses will be
        // contracts then.
        // solium-disable-next-line security/no-inline-assembly
        assembly { size := extcodesize(addr) }
        return size > 0;
    }
}