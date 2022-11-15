// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.10;

import {Types} from "./Types.sol";
import {EventsAndErrors} from "./EventsAndErrors.sol";

import {Math} from "@morpho-dao/morpho-utils/math/Math.sol";
import {PercentageMath} from "@morpho-dao/morpho-utils/math/PercentageMath.sol";
import {WadRayMath} from "@morpho-dao/morpho-utils/math/WadRayMath.sol";

import {ReserveConfiguration} from "../../libraries/aave/ReserveConfiguration.sol";
import {UserConfiguration} from "../../libraries/aave/UserConfiguration.sol";
import {DataTypes} from "../../libraries/aave/DataTypes.sol";

import {LibDiamond} from "./LibDiamond.sol";

import {HeapOrdering} from "@morpho-dao/morpho-data-structures/HeapOrdering.sol";
import {ERC20} from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
