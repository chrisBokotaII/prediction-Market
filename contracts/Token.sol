//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

contract Token is ERC1155 {
    event Minted(address indexed account, uint256 id, uint256 amount);
    event Burned(address indexed account, uint256 id, uint256 amount);

    constructor() ERC1155("") {}
    function safeMint(address account, uint256 id, uint256 amount) external {
        require(account != address(0), "ERC1155: mint to the zero address");
        require(amount > 0, "ERC1155: mint amount must be greater than zero");
        _mint(account, id, amount, "");
        emit Minted(account, id, amount);
    }

    function burn(address account, uint256 id, uint256 amount) external {
        require(account != address(0), "ERC1155: burn from the zero address");
        require(amount > 0, "ERC1155: burn amount must be greater than zero");
        _burn(account, id, amount);
        emit Burned(account, id, amount);
    }
}
