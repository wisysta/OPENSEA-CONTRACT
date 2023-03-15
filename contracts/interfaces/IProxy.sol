// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IProxy {
    function proxy(
        address dest,
        bytes calldata calldata_
    ) external returns (bool result);
}
