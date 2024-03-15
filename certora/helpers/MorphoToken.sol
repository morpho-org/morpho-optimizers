// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import "@rari-capital/solmate/src/tokens/ERC20.sol";

contract MorphoToken is ERC20 {
    constructor(address _receiver) ERC20("Morpho Token", "MORPHO", 18) {
        _mint(_receiver, 1_000_000_000 ether);
    }
}
