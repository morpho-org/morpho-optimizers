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
import {IWETH} from "./interfaces/IWETH.sol";

// To be delegate called. Has no storage variables. (Cannot use re-entry guard for this reason)
contract MorphoRouter is IFlashLoanRecipient {
    using SafeERC20 for IERC20;

    uint256 constant MAX_NUM_TOKENS = 10;
    address public constant BALANCER_VAULT_ADDRESS = address(0); // TODO
    address public constant CETHER = address(0); // TODO
    address public constant WETH = address(0); // TODO
    address public constant MORPHO = address(0); // TODO

    // Always the first bytes in data
    enum Action {
        MigrateFromCompound
    }

    /// EXTERNAL ///

    function migrateFromCompound(
        ICToken[] memory collateralCTokens,
        uint256[] memory collateralAmounts,
        ICToken[] memory debtCTokens,
        uint256[] memory debtAmounts
    ) external {
        // 1. Get flash loan from balancer for debt assets
        IVault(BALANCER_VAULT_ADDRESS).flashLoan(
            IFlashLoanRecipient(address(this)),
            batchConvertToUnderlying(debtCTokens),
            debtAmounts,
            abi.encode(
                Action.MigrateFromCompound,
                collateralCTokens,
                collateralAmounts,
                debtCTokens,
                debtAmounts
            )
        );
    }

    function receiveFlashLoan(
        IERC20[] memory,
        uint256[] memory amountsReceived,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external {
        // Decode user data and redirect call to appropriate internal function
        Action action = decodeAction(userData);
        if (action == Action.MigrateFromCompound) {
            migrateFromCompoundAfterFlashLoan(amountsReceived, feeAmounts, userData);
        }
    }

    /// INTERNAL ///

    function migrateFromCompoundAfterFlashLoan(
        uint256[] memory amountsReceived,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) internal {
        (
            ICToken[] memory collateralCTokens,
            uint256[] memory collateralAmounts,
            ICToken[] memory debtCTokens
        ) = decodeCompoundMigrationData(userData);

        // 2. Pay back all debt on Compound with flash loan funds
        for (uint256 i = 0; i < debtCTokens.length; i++) {
            repayOnCompound(debtCTokens[i], amountsReceived[i]);
        }
        for (uint256 i = 0; i < collateralCTokens.length; i++) {
            // 3. Withdraw all collateral from Compound
            withdrawFromCompound(collateralCTokens[i], collateralAmounts[i]);
            // 4. Deposit all collateral to Morpho
            supplyToMorpho(collateralCTokens[i], collateralAmounts[i]);
        }
        for (uint256 i = 0; i < debtCTokens.length; i++) {
            // 5. Borrow debt from Morpho equal to flash loan amount + fee
            borrowFromMorpho(debtCTokens[i], amountsReceived[i] + feeAmounts[i]);
            // 6. Pay back flash loan
            returnFlashLoanToBalancer(debtCTokens[i], amountsReceived[i] + feeAmounts[i]);
        }
    }

    function decodeAction(bytes memory userData) internal pure returns (Action action) {
        (action, ) = abi.decode(userData, (Action, bytes));
    }

    function decodeCompoundMigrationData(bytes memory userData)
        internal
        pure
        returns (
            ICToken[] memory,
            uint256[] memory,
            ICToken[] memory
        )
    {
        (
            ,
            ICToken[] memory collateralTokens,
            uint256[] memory collateralAmounts,
            ICToken[] memory debtTokens,

        ) = abi.decode(userData, (Action, ICToken[], uint256[], ICToken[], uint256[]));
        return (collateralTokens, collateralAmounts, debtTokens);
    }

    function repayOnCompound(ICToken debtCToken, uint256 debtAmount) internal {
        IERC20 underlying = convertToUnderlying(debtCToken);
        if (address(underlying) == WETH) {
            IWETH(WETH).withdraw(debtAmount); // Turn wETH into ETH.
            ICEther(address(debtCToken)).repayBorrow{value: debtAmount}();
        } else {
            underlying.approve(address(debtCToken), debtAmount);
            require(debtCToken.repayBorrow(debtAmount) == 0, "Repay borrow failed");
        }
    }

    function withdrawFromCompound(ICToken collateralCToken, uint256 collateralAmount) internal {
        require(collateralCToken.redeemUnderlying(collateralAmount) == 0, "Redeem failed");
    }

    function supplyToMorpho(ICToken collateralCToken, uint256 collateralAmount) internal {
        IERC20(convertToUnderlying(collateralCToken)).approve(MORPHO, collateralAmount);
        IMorpho(MORPHO).supply(address(collateralCToken), collateralAmount);
    }

    function borrowFromMorpho(ICToken debtCToken, uint256 debtAmount) internal {
        IMorpho(MORPHO).borrow(address(debtCToken), debtAmount);
    }

    function returnFlashLoanToBalancer(ICToken cToken, uint256 amount) internal {
        if (address(cToken) == CETHER) {
            IWETH(WETH).deposit{value: amount}(); // Turn ETH into wETH.
            IERC20(WETH).transfer(BALANCER_VAULT_ADDRESS, amount);
        } else {
            IERC20(convertToUnderlying(cToken)).transfer(BALANCER_VAULT_ADDRESS, amount);
        }
    }

    // Convert array of CTokens to underlying
    function batchConvertToUnderlying(ICToken[] memory cTokens)
        internal
        view
        returns (IERC20[] memory underlyings)
    {
        underlyings = new IERC20[](cTokens.length);
        for (uint256 i = 0; i < cTokens.length; i++) {
            underlyings[i] = convertToUnderlying(cTokens[i]);
        }
    }

    // Get the underlying of a CToken
    function convertToUnderlying(ICToken cToken) internal view returns (IERC20 underlying) {
        if (address(cToken) == CETHER) underlying = IERC20(WETH);
        else underlying = IERC20(cToken.underlying());
    }
}
