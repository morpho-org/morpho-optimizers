// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {ERC20} from "../../lib/solmate/src/tokens/ERC20.sol";

library SafeTransferLib {
    function safeTransfer(
        ERC20 token,
        address to,
        uint256 amount
    ) internal {
        bool success = token.transfer(to, amount);

        require(success, "TRANSFER_FAILED");
    }
}
