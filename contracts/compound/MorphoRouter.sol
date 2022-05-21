// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import {IRewardsManager} from "./interfaces/IRewardsManager.sol";
import {IMorpho} from "./interfaces/IMorpho.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IComptroller, ICToken, ICEther, ICEth} from "./interfaces/compound/ICompound.sol";
import {IVault} from "./interfaces/balancer/IVault.sol";
import {IFlashLoanRecipient} from "./interfaces/balancer/IFlashLoanRecipient.sol";

// To be delegate called. Has no storage variables. (Cannot use re-entry guard for this reason)
contract MorphoRouter is IFlashLoanRecipient {
    using SafeERC20 for IERC20;

    uint256 constant MAX_NUM_TOKENS = 10;
    address public constant BALANCER_VAULT_ADDRESS = address(0); // TODO: Set this to the address of the balancer vault.

    // Always the first bytes in data
    enum Action {
        MigrateFromCompound
    }

    /// EXTERNAL ///

    function migrateFromCompound(
        IERC20[] memory collateralTokens,
        uint256[] memory collateralAmounts,
        IERC20[] memory debtTokens,
        uint256[] memory debtAmounts
    ) external {
        // 1. Get flash loan from balancer for debt assets
        IVault(BALANCER_VAULT_ADDRESS).flashLoan(
            address(this),
            debtTokens,
            debtAmounts,
            abi.encode(
                Action.MigrateFromCompound,
                collateralTokens,
                collateralAmounts,
                debtTokens,
                debtAmounts
            )
        );
    }

    function receiveFlashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external {
        // Decode user data and redirect call to appropriate internal function
        Action action = decodeAction(userData);
    }

    /// INTERNAL ///

    function decodeAction(bytes memory userData) internal returns (Action memory action) {
        (action, ) = abi.decode(userData, (Action, bytes));
    }

    function migrateFromCompoundAfterFlashLoan(
        IERC20[] memory debtTokens,
        uint256[] memory debtAmounts,
        uint256[] memory feeAmounts,
        IERC20[] memory collateralTokens,
        uint256[] memory collateralAmounts
    ) internal {
        // 2. Pay back all debt on Compound with flash loan funds
        // 3. Withdraw all collateral from Compound
        // 4. Deposit all collateral to Morpho
        // 5. Borrow debt from Morpho equal to flash loan amount + fee
        // 6. Pay back flash loan
    }

    // Approve

    // Withdraw underlying from compound with ctoken address
    // Repay underlying to compound with ctoken address

    // Supply underlying to morpho
    // Borrow from morpho
    //
}
