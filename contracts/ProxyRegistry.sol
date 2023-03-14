// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./AuthenticatedProxy.sol";

contract ProxyRegistry is Ownable {
    mapping(address => bool) public contracts;
    mapping(address => address) public proxies;

    // 오픈씨가 실행, 실제로는 2주간의 기간을 둠
    function grantAuthentication(address addr) external onlyOwner {
        require(!contracts[addr], "Already registered");
        contracts[addr] = true;
    }

    function revokeAuthentication(address addr) external onlyOwner {
        require(contracts[addr], "Not registered");
        delete contracts[addr];
    }

    // 유저가 실행
    function registerProxy() external returns (AuthenticatedProxy) {
        require(proxies[msg.sender] == address(0), "Already registered");
        AuthenticatedProxy proxy = new AuthenticatedProxy(msg.sender);
        proxies[msg.sender] = address(proxy);
        return proxy;
    }
}
