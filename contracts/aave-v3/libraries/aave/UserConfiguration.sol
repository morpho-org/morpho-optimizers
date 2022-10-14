// SPDX-License-Identifier: GNU AGPLv3
pragma solidity >=0.8.0;

import {DataTypes} from "./DataTypes.sol";

library UserConfiguration {
    function isUsingAsCollateral(DataTypes.UserConfigurationMap memory self, uint256 reserveIndex)
        internal
        pure
        returns (bool)
    {
        unchecked {
            return (self.data >> ((reserveIndex << 1) + 1)) & 1 != 0;
        }
    }
}
