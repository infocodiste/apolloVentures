// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

contract TestERC721 is ERC721Enumerable {
    /** 
     * @dev Calls ERC20 constructor and takes name and symbol of token as input
     * @dev Mints total Supply into Admin's Account
     */
    constructor() ERC721("ERC721", "MYTKN") {}

    function mint(address to, uint256 amount) public {
        for(uint256 i=0; i < amount; i++) {
            _safeMint(to, totalSupply());
        }
    }
}