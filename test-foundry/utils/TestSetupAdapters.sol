// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "./TestSetup.sol";
import "@contracts/aave/adapters/LiquidationFlashSwapForMorpho.sol";
import "./Utils.sol";

contract TestSetupAdapters is TestSetup {
    FlashSwapLiquidatorForMorpho internal flashSwapLiquidator;

    function setUp() public override {
        super.setUp();
        flashSwapLiquidator = new FlashSwapLiquidatorForMorpho(
            positionsManager,
            ISwapRouter(uniswapRouter),
            ILendingPoolAddressesProvider(lendingPoolAddressesProviderAddress)
        );
    }
}
