// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./interfaces/IProxyRegistry.sol";

contract AuthenticatedProxy {
    address public userAddress;
    address proxyRegistryAddress;
    bool public revoked;

    constructor(address userAddress_) {
        userAddress = userAddress_;
        proxyRegistryAddress = msg.sender;
    }

    modifier onlyUser() {
        require(msg.sender == userAddress);
        _;
    }

    function setRevoke() external onlyUser {
        require(!revoked);
        revoked = true;
    }

    function proxy(
        address dest,
        bytes calldata calldata_
    ) external returns (bool result) {
        // 1.msg.sender가 유저인 경우 2.프록시 레지스트리에 등록된(오픈씨가 등록한) 컨트랙트인 경우
        require(
            msg.sender == userAddress ||
                ((!revoked) &&
                    IProxyRegistry(proxyRegistryAddress).contracts(msg.sender))
        );

        (result, ) = dest.call(calldata_);
        return result;
    }
}
