// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "@contracts/aave-v3/interfaces/aave/IPool.sol";
import "@rari-capital/solmate/src/utils/SafeTransferLib.sol";

contract FlashLoan {
    IPool public pool;

    constructor(IPool _pool) {
        pool = _pool;
    }

    function callFlashLoan(address _asset, uint256 _amount) public {
        address receiverAddress = address(this);
        address[] memory assets = new address[](1);
        assets[0] = _asset;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = _amount;
        // 0 = no debt, 1 = stable, 2 = variable
        uint256[] memory modes = new uint256[](1);
        modes[0] = 0;
        address onBehalfOf = address(this);
        bytes memory params = "";
        uint16 referralCode = 0;
        pool.flashLoan(receiverAddress, assets, amounts, modes, onBehalfOf, params, referralCode);
    }

    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address,
        bytes calldata
    ) external returns (bool) {
        for (uint256 i = 0; i < assets.length; i++) {
            uint256 amountOwing = amounts[i] + premiums[i];
            ERC20(assets[i]).approve(address(pool), amountOwing);
        }

        return true;
    }
}
