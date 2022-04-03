// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import {Utils} from "./setup/Utils.sol";
import "@config/Config.sol";
import "@contracts/aave/PositionsManagerForAave.sol";
import "@contracts/aave/positions-manager-parts/PositionsManagerForAaveStorage.sol";
import "@contracts/aave/positions-manager-parts/PositionsManagerForAaveEventsErrors.sol";
import "forge-std/stdlib.sol";
import "hardhat/console.sol";

contract TestInitializePositionsManager is stdCheats, Config, Utils {
    Vm public hevm = Vm(HEVM_ADDRESS);
    PositionsManagerForAave pos;

    constructor() {
        pos = new PositionsManagerForAave();
        pos.initialize(
            IMarketsManagerForAave(address(1)),
            IMatchingEngineForAave(address(2)),
            ILendingPoolAddressesProvider(lendingPoolAddressesProviderAddress),
            PositionsManagerForAaveStorage.MaxGas(100_000, 100_000, 100_000, 100_000),
            PositionsManagerForAaveStorage.MaxGas(1_000, 1_000, 1_000, 1_000),
            PositionsManagerForAaveStorage.MaxGas(
                type(uint64).max,
                type(uint64).max,
                type(uint64).max,
                type(uint64).max
            ),
            50,
            0,
            1000
        );
    }

    function testNDSBounds() public {
        hevm.expectRevert(PositionsManagerForAaveEventsErrors.NdsOutOfBounds.selector);
        pos.setNDS(2000);

        pos.setNDS(500);
        testEquality(pos.NDS(), 500);
    }

    function testMaxGasBounds() public {
        hevm.expectRevert(PositionsManagerForAaveEventsErrors.MaxGasOutOfBounds.selector);
        pos.setMaxGas(PositionsManagerForAaveStorage.MaxGas(100_000, 100_000, 500, 100_000));

        pos.setMaxGas(PositionsManagerForAaveStorage.MaxGas(100_000, 2_000, 100_000, 100_000));
        (, uint256 maxGasBorrowValue, , ) = pos.maxGas();
        testEquality(maxGasBorrowValue, 2_000);
    }
}
