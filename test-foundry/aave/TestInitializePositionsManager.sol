// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "@contracts/aave/positions-manager-parts/PositionsManagerForAaveEventsErrors.sol";
import "@contracts/aave/positions-manager-parts/PositionsManagerForAaveStorage.sol";
import "@contracts/aave/PositionsManagerForAave.sol";

import {Utils} from "./setup/Utils.sol";
import "forge-std/stdlib.sol";
import "hardhat/console.sol";
import "@config/Config.sol";

contract TestInitializePositionsManager is stdCheats, Config, Utils {
    Vm public hevm = Vm(HEVM_ADDRESS);
    PositionsManagerForAave public pos;

    uint64 public MAX_GAS = 10_000;
    uint64 public MAX_GAS_FLOOR = 1_000;
    uint64 public MAX_GAS_CEILING = 100_000;

    uint256 public NDS = 50;
    uint256 public NDS_FLOOR = 10;
    uint256 public NDS_CEILING = 100;

    constructor() {
        pos = new PositionsManagerForAave();

        pos.initialize(
            IMarketsManagerForAave(address(1)),
            IMatchingEngineForAave(address(2)),
            ILendingPoolAddressesProvider(lendingPoolAddressesProviderAddress),
            PositionsManagerForAaveStorage.MaxGas(MAX_GAS, MAX_GAS, MAX_GAS, MAX_GAS),
            PositionsManagerForAaveStorage.MaxGas(
                MAX_GAS_FLOOR,
                MAX_GAS_FLOOR,
                MAX_GAS_FLOOR,
                MAX_GAS_FLOOR
            ),
            PositionsManagerForAaveStorage.MaxGas(
                MAX_GAS_CEILING,
                MAX_GAS_CEILING,
                MAX_GAS_CEILING,
                MAX_GAS_CEILING
            ),
            NDS,
            NDS_FLOOR,
            NDS_CEILING
        );
    }

    function testNDSBounds() public {
        hevm.expectRevert(PositionsManagerForAaveEventsErrors.NDSOutOfBounds.selector);
        pos.setNDS(NDS_FLOOR - 1);

        hevm.expectRevert(PositionsManagerForAaveEventsErrors.NDSOutOfBounds.selector);
        pos.setNDS(NDS_CEILING + 1);

        pos.setNDS(NDS_FLOOR);
        testEquality(pos.NDS(), NDS_FLOOR);

        pos.setNDS(NDS_CEILING);
        testEquality(pos.NDS(), NDS_CEILING);
    }

    function testMaxGasBounds() public {
        hevm.expectRevert(PositionsManagerForAaveEventsErrors.MaxGasOutOfBounds.selector);
        pos.setMaxGas(
            PositionsManagerForAaveStorage.MaxGas(
                MAX_GAS_FLOOR - 1,
                MAX_GAS_FLOOR,
                MAX_GAS_FLOOR,
                MAX_GAS_FLOOR
            )
        );
        hevm.expectRevert(PositionsManagerForAaveEventsErrors.MaxGasOutOfBounds.selector);
        pos.setMaxGas(
            PositionsManagerForAaveStorage.MaxGas(
                MAX_GAS_FLOOR,
                MAX_GAS_FLOOR - 1,
                MAX_GAS_FLOOR,
                MAX_GAS_FLOOR
            )
        );
        hevm.expectRevert(PositionsManagerForAaveEventsErrors.MaxGasOutOfBounds.selector);
        pos.setMaxGas(
            PositionsManagerForAaveStorage.MaxGas(
                MAX_GAS_FLOOR,
                MAX_GAS_FLOOR,
                MAX_GAS_FLOOR - 1,
                MAX_GAS_FLOOR
            )
        );
        hevm.expectRevert(PositionsManagerForAaveEventsErrors.MaxGasOutOfBounds.selector);
        pos.setMaxGas(
            PositionsManagerForAaveStorage.MaxGas(
                MAX_GAS_FLOOR,
                MAX_GAS_FLOOR,
                MAX_GAS_FLOOR,
                MAX_GAS_FLOOR - 1
            )
        );

        hevm.expectRevert(PositionsManagerForAaveEventsErrors.MaxGasOutOfBounds.selector);
        pos.setMaxGas(
            PositionsManagerForAaveStorage.MaxGas(
                MAX_GAS_CEILING + 1,
                MAX_GAS_CEILING,
                MAX_GAS_CEILING,
                MAX_GAS_CEILING
            )
        );
        hevm.expectRevert(PositionsManagerForAaveEventsErrors.MaxGasOutOfBounds.selector);
        pos.setMaxGas(
            PositionsManagerForAaveStorage.MaxGas(
                MAX_GAS_CEILING,
                MAX_GAS_CEILING + 1,
                MAX_GAS_CEILING,
                MAX_GAS_CEILING
            )
        );
        hevm.expectRevert(PositionsManagerForAaveEventsErrors.MaxGasOutOfBounds.selector);
        pos.setMaxGas(
            PositionsManagerForAaveStorage.MaxGas(
                MAX_GAS_CEILING,
                MAX_GAS_CEILING,
                MAX_GAS_CEILING + 1,
                MAX_GAS_CEILING
            )
        );
        hevm.expectRevert(PositionsManagerForAaveEventsErrors.MaxGasOutOfBounds.selector);
        pos.setMaxGas(
            PositionsManagerForAaveStorage.MaxGas(
                MAX_GAS_CEILING,
                MAX_GAS_CEILING,
                MAX_GAS_CEILING,
                MAX_GAS_CEILING + 1
            )
        );

        pos.setMaxGas(
            PositionsManagerForAaveStorage.MaxGas(
                MAX_GAS_FLOOR,
                MAX_GAS_FLOOR,
                MAX_GAS_FLOOR,
                MAX_GAS_FLOOR
            )
        );
        (uint256 a, uint256 b, uint256 c, uint256 d) = pos.maxGas();
        testEquality(a, MAX_GAS_FLOOR);
        testEquality(b, MAX_GAS_FLOOR);
        testEquality(c, MAX_GAS_FLOOR);
        testEquality(d, MAX_GAS_FLOOR);

        pos.setMaxGas(
            PositionsManagerForAaveStorage.MaxGas(
                MAX_GAS_CEILING,
                MAX_GAS_CEILING,
                MAX_GAS_CEILING,
                MAX_GAS_CEILING
            )
        );
        (a, b, c, d) = pos.maxGas();
        testEquality(a, MAX_GAS_CEILING);
        testEquality(b, MAX_GAS_CEILING);
        testEquality(c, MAX_GAS_CEILING);
        testEquality(d, MAX_GAS_CEILING);
    }
}
