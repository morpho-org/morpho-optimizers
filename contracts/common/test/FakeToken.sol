// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract FakeToken is ERC20 {
    constructor(
        string memory _name,
        string memory _symbol,
        address _receiver
    ) ERC20(_name, _symbol) {
        _mint(_receiver, 10_000 ether);
    }
}
