// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./HEVM.sol";

contract HevmAdapter {
    HEVM public hevm = HEVM(address(bytes20(uint160(uint256(keccak256("hevm cheat code"))))));

    mapping(address => uint8) public slots; // Token slot for balance storage.
    mapping(address => bool) public isSlotSet; // Set if the slot is assigned.

    /// @dev Write the balance of `_who` for `_acct` token with `_value` amount.
    /// @param _who  user address
    /// @param _acct  token address
    /// @param _value  amount
    function writeBalanceOf(
        address _who,
        address _acct,
        uint256 _value
    ) internal {
        if (!isSlotSet[_acct]) {
            findAndSetSlot(_acct);
        }
        hevm.store(_acct, keccak256(abi.encode(_who, slots[_acct])), bytes32(_value));
    }

    /// @dev Find and set the  slot for the given asset.
    /// @param _asset	ERC20 asset
    function findAndSetSlot(address _asset) internal {
        bool found = false;
        for (uint8 slot = 0; slot < type(uint8).max; slot++) {
            bytes32 loc = keccak256(abi.encode(address(this), slot));
            bytes32 value = hevm.load(_asset, loc);
            hevm.store(_asset, loc, bytes32(type(uint256).max));

            uint256 balance = IERC20(_asset).balanceOf(address(this));
            hevm.store(_asset, loc, value);

            if (balance != 0) {
                isSlotSet[_asset] = true;
                slots[_asset] = slot;
                found = true;
                break;
            }
        }

        require(found, "Slot not found.");
    }

    /// @dev Mine `_nbBlocks`: adjust block number and timestamp with 10s/block
    /// @param _nbBlocks  number of blocks
    function mineBlocks(uint256 _nbBlocks) internal {
        hevm.warp(block.timestamp + 10 * _nbBlocks);
        hevm.roll(block.number + _nbBlocks);
    }
}
