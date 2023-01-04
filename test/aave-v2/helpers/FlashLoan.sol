// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "src/aave-v2/interfaces/aave/ILendingPool.sol";
import "@rari-capital/solmate/src/utils/SafeTransferLib.sol";

contract FlashLoan {
    using SafeTransferLib for ERC20;

    ILendingPool public pool;

    constructor(ILendingPool _pool) {
        pool = _pool;
    }

    function callFlashLoan(address _asset, uint256 _amount) public {
        address receiver = address(this);
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
        pool.flashLoan(receiver, assets, amounts, modes, onBehalfOf, params, referralCode);
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
            ERC20(assets[i]).safeApprove(address(pool), amountOwing);
        }

        return true;
    }
}
