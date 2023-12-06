// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import "@rari-capital/solmate/src/tokens/ERC20.sol";

contract MorphoToken is ERC20 {
    constructor() ERC20("Morpho Token", "MORPHO", 18) {}
}
