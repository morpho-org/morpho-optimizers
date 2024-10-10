// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {SafeTransferLib, ERC20} from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";

import {PercentageMath} from "@morpho-dao/morpho-utils/math/PercentageMath.sol";
import {Math} from "@morpho-dao/morpho-utils/math/Math.sol";
import {WadRayMath} from "@morpho-dao/morpho-utils/math/WadRayMath.sol";

import {BaseConfig} from "config/BaseConfig.sol";
import "@forge-std/console.sol";
import "@forge-std/Test.sol";

contract ProdTest is Test, BaseConfig {
    // Show block number for reproducibility.
    function testShowBlockNumber() public view {
        console.log("Testing at block", block.number);
    }
}
