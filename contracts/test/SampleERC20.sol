// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract SampleERC20 is ERC20 {
    /** 
     * @dev Calls ERC20 constructor and takes name and symbol of token as input
     * @dev Mints total Supply into Admin's Account
     */
    constructor() ERC20("SampleERC20", "TEST") {
        _mint(msg.sender, 1_000_000_000 ether);
    }
}