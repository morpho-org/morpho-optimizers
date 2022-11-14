// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.10;

import {MorphoStorage as S} from "../storage/MorphoStorage.sol";
import {IAToken, IVariableDebtToken} from "../interfaces/Interfaces.sol";
import {Math} from "./Libraries.sol";

library LibPositions {
    function c() internal pure returns (MorphoStorage.ContractsLayout storage c) {
        return S.contractsLayout();
    }

    /// @dev Supplies underlying tokens to Aave.
    /// @param _underlyingToken The underlying token of the market to supply to.
    /// @param _amount The amount of token (in underlying).
    function supplyToPool(ERC20 _underlyingToken, uint256 _amount) internal {
        c().pool.supply(address(_underlyingToken), _amount, address(this), NO_REFERRAL_CODE);
    }

    /// @dev Withdraws underlying tokens from Aave.
    /// @param _underlyingToken The underlying token of the market to withdraw from.
    /// @param _poolToken The address of the market.
    /// @param _amount The amount of token (in underlying).
    function withdrawFromPool(
        ERC20 _underlyingToken,
        address _poolToken,
        uint256 _amount
    ) internal {
        // Withdraw only what is possible. The remaining dust is taken from the contract balance.
        _amount = Math.min(IAToken(_poolToken).balanceOf(address(this)), _amount);
        c().pool.withdraw(address(_underlyingToken), _amount, address(this));
    }

    /// @dev Borrows underlying tokens from Aave.
    /// @param _underlyingToken The underlying token of the market to borrow from.
    /// @param _amount The amount of token (in underlying).
    function borrowFromPool(ERC20 _underlyingToken, uint256 _amount) internal {
        c().pool.borrow(
            address(_underlyingToken),
            _amount,
            S.VARIABLE_INTEREST_MODE,
            S.NO_REFERRAL_CODE,
            address(this)
        );
    }

    /// @dev Repays underlying tokens to Aave.
    /// @param _underlyingToken The underlying token of the market to repay to.
    /// @param _amount The amount of token (in underlying).
    function repayToPool(ERC20 _underlyingToken, uint256 _amount) internal {
        if (
            _amount == 0 ||
            IVariableDebtToken(
                c().pool.getReserveData(address(_underlyingToken)).variableDebtTokenAddress
            ).scaledBalanceOf(address(this)) ==
            0
        ) return;

        c().pool.repay(address(_underlyingToken), _amount, S.VARIABLE_INTEREST_MODE, address(this)); // Reverts if debt is 0.
    }
}
