// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.10;

import {IPriceOracleSentinel} from "@aave/core-v3/contracts/interfaces/IPriceOracleSentinel.sol";
import {IVariableDebtToken} from "@aave/core-v3/contracts/interfaces/IVariableDebtToken.sol";
import {IPool} from "../../interfaces/aave/IPool.sol";
import {IPriceOracleGetter} from "@aave/core-v3/contracts/interfaces/IPriceOracleGetter.sol";
import {IAToken} from "@aave/core-v3/contracts/interfaces/IAToken.sol";
