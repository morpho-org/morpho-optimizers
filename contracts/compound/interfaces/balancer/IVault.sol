// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./IFlashLoanRecipient.sol";

interface IVault {
    function flashLoan(
        IFlashLoanRecipient recipient,
        IERC20[] memory tokens,
        uint256[] memory amounts,
        bytes memory userData
    ) external;
}
