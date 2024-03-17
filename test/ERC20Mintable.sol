// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "solmate/tokens/ERC20.sol";

contract ERC20Mintable is ERC20 {
    address public owner;
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) ERC20(_name, _symbol, _decimals) {
        owner=msg.sender;
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}
