// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import {IVariableDebtToken} from "@aave/core-v3/contracts/interfaces/IVariableDebtToken.sol";

interface IVariableDebtTokenExtended is IVariableDebtToken {
    /**
     * @dev Returns the debt balance of the user
     * @return The debt balance of the user.
     **/
    function balanceOf(address user) external view returns (uint256);
}
