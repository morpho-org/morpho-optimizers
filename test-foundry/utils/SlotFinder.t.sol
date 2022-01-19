// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "./TestSetup.sol";

contract SlotFinder is TestSetup {
    uint256 ref = type(uint64).max;

    function test_find_slot() public {
        for (uint256 assetIndex = 0; assetIndex < pools.length; assetIndex++) {
            address asset = IAToken(pools[assetIndex]).UNDERLYING_ASSET_ADDRESS();
            string memory symbol = ERC20(asset).symbol();

            bool found = false;
            for (uint256 slot = 0; slot < 15; slot++) {
                bytes32 value = hevm.load(asset, keccak256(abi.encode(address(this), slot)));
                hevm.store(asset, keccak256(abi.encode(address(this), slot)), bytes32(ref));

                if (IERC20(asset).balanceOf(address(this)) != 0) {
                    emit log_named_uint(symbol, slot);
                    found = true;
                    break;
                }

                hevm.store(asset, keccak256(abi.encode(address(this), slot)), value);
            }

            assertTrue(found, symbol);
        }
    }
}
