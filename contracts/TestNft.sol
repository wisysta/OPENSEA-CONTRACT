pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract TestNft is ERC721 {
    constructor() ERC721("Test", "TEST") {
        for (uint i = 0; i < 10; i++) {
            _safeMint(msg.sender, i);
        }
    }
}
