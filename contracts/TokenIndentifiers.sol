// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

library TokenIndentifiers {
    uint8 constant ADDRESS_BITS = 20 * 8;
    uint8 constant INDEX_BITS = 12 * 8;

    uint256 constant INDEX_MASK =
        0x0000000000000000000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF;

    function tokenIndex(uint256 _id) public pure returns (uint256) {
        return _id & INDEX_MASK;
    }

    function tokenCreator(uint256 _id) public pure returns (address) {
        return address(uint160(_id >> ADDRESS_BITS));
    }
}
