// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IProxyRegistry {
    function contracts(address addr_) external view returns (bool);

    function proxies(address addr_) external view returns (address);
}
