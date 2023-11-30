// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import {ERC20} from "../../lib/solmate/src/tokens/ERC20.sol";

contract MorphoToken is ERC20 {
    constructor() ERC20("Morpho Token", "MORPHO", 18) {}
}
