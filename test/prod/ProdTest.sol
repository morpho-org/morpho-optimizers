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
    // Needed because AAVE packs the balance struct.
    function dealAave(address who, uint104 amount) public {
        // The slot of the balance struct "_balances" is 0.
        bytes32 slot = keccak256(abi.encode(who, uint256(0)));
        bytes32 initialValue = vm.load(aave, slot);
        // The balance is stored in the first 104 bits.
        bytes32 finalValue = ((initialValue >> 104) << 104) | bytes32(uint256(amount));
        vm.store(aave, slot, finalValue);
        require(ERC20(aave).balanceOf(who) == uint256(amount));
    }
}
