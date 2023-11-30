// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {ERC20} from "@rari-capital/solmate/src/tokens/ERC20.sol";

/// @notice Harnessed contract for transfer, originally written by Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/utils/SafeTransferLib.sol)
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
