// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "@aave/core-v3/contracts/interfaces/IPriceOracleSentinel.sol";
import "@aave/core-v3/contracts/interfaces/IVariableDebtToken.sol";

import "@rari-capital/solmate/src/utils/SafeTransferLib.sol";

import "./MatchingEngine.sol";

/// @title PositionsManagerUtils.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Utils shared by the EntryPositionsManager and ExitPositionsManager.
abstract contract PositionsManagerUtils is MatchingEngine {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using SafeTransferLib for ERC20;
    using WadRayMath for uint256;

    /// COMMON EVENTS ///

    /// @notice Emitted when the borrow peer-to-peer delta is updated.
    /// @param _poolTokenAddress The address of the market.
    /// @param _p2pBorrowDelta The borrow peer-to-peer delta after update.
    event P2PBorrowDeltaUpdated(address indexed _poolTokenAddress, uint256 _p2pBorrowDelta);

    /// @notice Emitted when the supply peer-to-peer delta is updated.
    /// @param _poolTokenAddress The address of the market.
    /// @param _p2pSupplyDelta The supply peer-to-peer delta after update.
    event P2PSupplyDeltaUpdated(address indexed _poolTokenAddress, uint256 _p2pSupplyDelta);

    /// @notice Emitted when the supply and borrow peer-to-peer amounts are updated.
    /// @param _poolTokenAddress The address of the market.
    /// @param _p2pSupplyAmount The supply peer-to-peer amount after update.
    /// @param _p2pBorrowAmount The borrow peer-to-peer amount after update.
    event P2PAmountsUpdated(
        address indexed _poolTokenAddress,
        uint256 _p2pSupplyAmount,
        uint256 _p2pBorrowAmount
    );

    /// COMMON ERRORS ///

    /// @notice Thrown when the amount is equal to 0.
    error AmountIsZero();

    /// POOL INTERACTION ///

    /// @dev Supplies underlying tokens to Aave.
    /// @param _underlyingToken The underlying token of the market to supply to.
    /// @param _amount The amount of token (in underlying).
    function _supplyToPool(ERC20 _underlyingToken, uint256 _amount) internal {
        _underlyingToken.safeApprove(address(pool), _amount);
        pool.deposit(address(_underlyingToken), _amount, address(this), NO_REFERRAL_CODE);
    }

    /// @dev Withdraws underlying tokens from Aave.
    /// @param _underlyingToken The underlying token of the market to withdraw from.
    /// @param _poolTokenAddress The address of the market.
    /// @param _amount The amount of token (in underlying).
    function _withdrawFromPool(
        ERC20 _underlyingToken,
        address _poolTokenAddress,
        uint256 _amount
    ) internal {
        // Withdraw only what is possible. The remaining dust is taken from the contract balance.
        _amount = Math.min(IAToken(_poolTokenAddress).balanceOf(address(this)), _amount);
        pool.withdraw(address(_underlyingToken), _amount, address(this));
    }

    /// @dev Borrows underlying tokens from Aave.
    /// @param _underlyingToken The underlying token of the market to borrow from.
    /// @param _amount The amount of token (in underlying).
    function _borrowFromPool(ERC20 _underlyingToken, uint256 _amount) internal {
        pool.borrow(
            address(_underlyingToken),
            _amount,
            VARIABLE_INTEREST_MODE,
            NO_REFERRAL_CODE,
            address(this)
        );
    }

    /// @dev Repays underlying tokens to Aave.
    /// @param _underlyingToken The underlying token of the market to repay to.
    /// @param _amount The amount of token (in underlying).
    function _repayToPool(
        ERC20 _underlyingToken,
        uint256 _amount,
        uint256 _poolBorrowIndex
    ) internal {
        // Repay only what is necessary. The remaining tokens stays on the contract and are claimable by the DAO.
        _amount = Math.min(
            _amount,
            IVariableDebtToken(
                pool.getReserveData(address(_underlyingToken)).variableDebtTokenAddress
            ).scaledBalanceOf(address(this))
            .rayMul(_poolBorrowIndex) // The debt of the contract.
        );

        if (_amount > 0) {
            _underlyingToken.safeApprove(address(pool), _amount);
            pool.repay(address(_underlyingToken), _amount, VARIABLE_INTEREST_MODE, address(this));
        }
    }
}
