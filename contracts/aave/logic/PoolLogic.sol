// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import {IVariableDebtToken} from "../interfaces/aave/IVariableDebtToken.sol";
import {IAToken} from "../interfaces/aave/IAToken.sol";
import "../interfaces/aave/IProtocolDataProvider.sol";
import "../interfaces/aave/ILendingPool.sol";
import "../interfaces/IMatchingEngineManager.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../common/libraries/DoubleLinkedList.sol";
import "../libraries/aave/WadRayMath.sol";
import "../libraries/DataStructs.sol";
import "./DataLogic.sol";

import "@openzeppelin/contracts/utils/math/Math.sol";

/// @title PoolLogic
/// @notice Implement the base logic for Pool specific functions.
library PoolLogic {
    using WadRayMath for uint256;
    using SafeERC20 for IERC20;

    /// Storage ///

    uint8 public constant NO_REFERRAL_CODE = 0;
    uint8 public constant VARIABLE_INTEREST_MODE = 2;

    /// @notice Supplies a position for `_user` on a specific market to the pool.
    /// @param params The required parameters to execute the function.
    /// @param _user The address of the user.
    /// @param _lendingPool The Aave's Lending Pool.
    /// @param _matchingEngineManager The Morpho's Maching Engine Manager.
    /// @param _supplyBalanceInOf The supply balances of all suppliers.
    function supplyPositionToPool(
        DataStructs.CommonParams memory params,
        address _user,
        ILendingPool _lendingPool,
        IMatchingEngineManager _matchingEngineManager,
        mapping(address => mapping(address => DataStructs.SupplyBalance)) storage _supplyBalanceInOf
    ) external {
        uint256 normalizedIncome = _lendingPool.getReserveNormalizedIncome(
            address(params.underlyingToken)
        );
        _supplyBalanceInOf[params.poolTokenAddress][_user].onPool += params.amount.divWadByRay(
            normalizedIncome
        ); // Scaled Balance
        DataLogic.updateSuppliers(params.poolTokenAddress, _user, _matchingEngineManager);
        supplyERC20ToPool(params.underlyingToken, params.amount, _lendingPool); // Revert on error
    }

    /// @notice Withdraws position of `_user` from the pool on a specific market.
    /// @param params The required parameters to execute the function.
    /// @param _user The address of the user.
    /// @param _lendingPool The Aave's Lending Pool.
    /// @param _matchingEngineManager The Morpho's Maching Engine Manager.
    /// @param _supplyBalanceInOf The supply balances of all suppliers.
    /// @return withdrawnInUnderlying The amount withdrawn from the pool.
    function withdrawPositionFromPool(
        DataStructs.CommonParams memory params,
        address _user,
        ILendingPool _lendingPool,
        IMatchingEngineManager _matchingEngineManager,
        mapping(address => mapping(address => DataStructs.SupplyBalance)) storage _supplyBalanceInOf
    ) external returns (uint256 withdrawnInUnderlying) {
        uint256 normalizedIncome = _lendingPool.getReserveNormalizedIncome(
            address(params.underlyingToken)
        );
        uint256 onPoolSupply = _supplyBalanceInOf[params.poolTokenAddress][_user].onPool;
        uint256 onPoolSupplyInUnderlying = onPoolSupply.mulWadByRay(normalizedIncome);
        withdrawnInUnderlying = Math.min(
            Math.min(onPoolSupplyInUnderlying, params.amount),
            IAToken(params.poolTokenAddress).balanceOf(address(this))
        );

        _supplyBalanceInOf[params.poolTokenAddress][_user].onPool -= Math.min(
            onPoolSupply,
            withdrawnInUnderlying.divWadByRay(normalizedIncome)
        ); // In poolToken
        DataLogic.updateSuppliers(params.poolTokenAddress, _user, _matchingEngineManager);

        if (withdrawnInUnderlying > 0)
            withdrawERC20FromPool(params.underlyingToken, withdrawnInUnderlying, _lendingPool); // Revert on error
    }

    /// @notice Borrows for `_user` from pool.
    /// @param params The required parameters to execute the function.
    /// @param _user The address of the user.
    /// @param _lendingPool The Aave's Lending Pool.
    /// @param _matchingEngineManager The Morpho's Maching Engine Manager.
    /// @param _borrowBalanceInOf The borrow balances of all borrowers.
    function borrowPositionFromPool(
        DataStructs.CommonParams memory params,
        address _user,
        ILendingPool _lendingPool,
        IMatchingEngineManager _matchingEngineManager,
        mapping(address => mapping(address => DataStructs.BorrowBalance)) storage _borrowBalanceInOf
    ) external {
        uint256 normalizedVariableDebt = _lendingPool.getReserveNormalizedVariableDebt(
            address(params.underlyingToken)
        );
        _borrowBalanceInOf[params.poolTokenAddress][_user].onPool += params.amount.divWadByRay(
            normalizedVariableDebt
        ); // In adUnit
        DataLogic.updateBorrowers(params.poolTokenAddress, _user, _matchingEngineManager);

        borrowERC20FromPool(params.underlyingToken, params.amount, _lendingPool);
    }

    /// @notice Repays `_amount` of the position of a `_user` on pool.
    /// @param _user The address of the user.
    /// @param _lendingPool The Aave's Lending Pool.
    /// @param _dataProvider The Aave's Data Provider.
    /// @param _matchingEngineManager The Morpho's Maching Engine Manager.
    /// @param _borrowBalanceInOf The borrow balances of all borrowers.
    /// @return repaidInUnderlying The amount repaid to the pool.
    function repayPositionToPool(
        DataStructs.CommonParams memory params,
        address _user,
        ILendingPool _lendingPool,
        IProtocolDataProvider _dataProvider,
        IMatchingEngineManager _matchingEngineManager,
        mapping(address => mapping(address => DataStructs.BorrowBalance)) storage _borrowBalanceInOf
    ) external returns (uint256 repaidInUnderlying) {
        uint256 normalizedVariableDebt = _lendingPool.getReserveNormalizedVariableDebt(
            address(params.underlyingToken)
        );
        uint256 borrowedOnPool = _borrowBalanceInOf[params.poolTokenAddress][_user].onPool;
        uint256 borrowedOnPoolInUnderlying = borrowedOnPool.mulWadByRay(normalizedVariableDebt);
        repaidInUnderlying = Math.min(borrowedOnPoolInUnderlying, params.amount);

        _borrowBalanceInOf[params.poolTokenAddress][_user].onPool -= Math.min(
            borrowedOnPool,
            repaidInUnderlying.divWadByRay(normalizedVariableDebt)
        ); // In adUnit
        DataLogic.updateBorrowers(params.poolTokenAddress, _user, _matchingEngineManager);

        if (repaidInUnderlying > 0)
            repayERC20ToPool(
                params.underlyingToken,
                repaidInUnderlying,
                normalizedVariableDebt,
                _lendingPool,
                _dataProvider
            ); // Revert on error
    }

    /// @notice Supplies underlying tokens to Aave.
    /// @param _underlyingToken The underlying token of the market to supply to.
    /// @param _amount The amount of token (in underlying).
    /// @param _lendingPool The Aave's Lending Pool.
    function supplyERC20ToPool(
        IERC20 _underlyingToken,
        uint256 _amount,
        ILendingPool _lendingPool
    ) internal {
        _underlyingToken.safeIncreaseAllowance(address(_lendingPool), _amount);
        _lendingPool.deposit(address(_underlyingToken), _amount, address(this), NO_REFERRAL_CODE);
    }

    /// @notice Withdraws underlying tokens from Aave.
    /// @param _underlyingToken The underlying token of the market to withdraw from.
    /// @param _amount The amount of token (in underlying).
    /// @param _lendingPool The Aave's Lending Pool.
    function withdrawERC20FromPool(
        IERC20 _underlyingToken,
        uint256 _amount,
        ILendingPool _lendingPool
    ) internal {
        _lendingPool.withdraw(address(_underlyingToken), _amount, address(this));
    }

    /// @notice Borrows underlying tokens from Aave.
    /// @param _underlyingToken The underlying token of the market to borrow from.
    /// @param _amount The amount of token (in underlying).
    /// @param _lendingPool The Aave's Lending Pool.
    function borrowERC20FromPool(
        IERC20 _underlyingToken,
        uint256 _amount,
        ILendingPool _lendingPool
    ) internal {
        _lendingPool.borrow(
            address(_underlyingToken),
            _amount,
            VARIABLE_INTEREST_MODE,
            NO_REFERRAL_CODE,
            address(this)
        );
    }

    /// @notice Repays underlying tokens to Aave.
    /// @param _underlyingToken The underlying token of the market to repay to.
    /// @param _amount The amount of token (in underlying).
    /// @param _normalizedVariableDebt The normalized variable debt on Aave.
    /// @param _lendingPool The Aave's Lending Pool.
    /// @param _dataProvider The Aave's Data Provider.
    function repayERC20ToPool(
        IERC20 _underlyingToken,
        uint256 _amount,
        uint256 _normalizedVariableDebt,
        ILendingPool _lendingPool,
        IProtocolDataProvider _dataProvider
    ) internal {
        _underlyingToken.safeIncreaseAllowance(address(_lendingPool), _amount);
        (, , address variableDebtToken) = _dataProvider.getReserveTokensAddresses(
            address(_underlyingToken)
        );
        // Do not repay more than the contract's debt on Aave
        _amount = Math.min(
            _amount,
            IVariableDebtToken(variableDebtToken).scaledBalanceOf(address(this)).mulWadByRay(
                _normalizedVariableDebt
            )
        );

        _lendingPool.repay(
            address(_underlyingToken),
            _amount,
            VARIABLE_INTEREST_MODE,
            address(this)
        );
    }
}
