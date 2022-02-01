// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import {IAToken} from "../interfaces/aave/IAToken.sol";
import "../interfaces/IMarketsManagerForAave.sol";
import "../interfaces/IMatchingEngineManager.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../libraries/aave/WadRayMath.sol";
import "./MatchLogic.sol";

/// @title P2PLogic
/// @notice Implement the base logic for P2P specific functions.
library P2PLogic {
    using WadRayMath for uint256;
    using SafeERC20 for IERC20;

    /// @notice Supplies tokens to P2P for `_user` on a specific market.
    /// @param params The required parameters to execute the function.
    /// @param _user The address of the user.
    /// @param _NMAX The NMAX value for the matching process.
    /// @param _dataProvider The Aave's Data Provider.
    /// @param _borrowersOnPool The borrowers waiting on Pool.
    /// @param _supplyBalanceInOf The supply balances of all suppliers.
    /// @param _borrowBalanceInOf The borrow balances of all borrowers.
    /// @return matched The amount matched by the borrowers waiting on Pool.
    function supplyPositionToP2P(
        DataStructs.CommonParams memory params,
        address _user,
        uint256 _NMAX,
        IProtocolDataProvider _dataProvider,
        mapping(address => DoubleLinkedList.List) storage _borrowersOnPool,
        mapping(address => mapping(address => DataStructs.SupplyBalance))
            storage _supplyBalanceInOf,
        mapping(address => mapping(address => DataStructs.BorrowBalance)) storage _borrowBalanceInOf
    ) external returns (uint256 matched) {
        uint256 supplyP2PExchangeRate = params.marketsManagerForAave.supplyP2PExchangeRate(
            params.poolTokenAddress
        );

        matched = MatchLogic.matchBorrowers(
            params,
            _NMAX,
            _dataProvider,
            _borrowersOnPool,
            _borrowBalanceInOf
        ); // In underlying

        if (matched > 0) {
            _supplyBalanceInOf[params.poolTokenAddress][_user].inP2P += matched.divWadByRay(
                supplyP2PExchangeRate
            ); // In p2pUnit
            DataLogic.updateSuppliers(params.poolTokenAddress, _user, params.matchingEngineManager);
        }
    }

    /// @notice Borrows tokens from P2P for `_user` on a specific market.
    /// @param params The required parameters to execute the function.
    /// @param _user The address of the user.
    /// @param _NMAX The NMAX value for the matching process.
    /// @param _suppliersOnPool The suppliers waiting on Pool.
    /// @param _supplyBalanceInOf The supply balances of all suppliers.
    /// @param _borrowBalanceInOf The borrow balances of all borrowers.
    /// @return matched The amount matched by the suppliers waiting on Pool.
    function borrowPositionFromP2P(
        DataStructs.CommonParams memory params,
        address _user,
        uint256 _NMAX,
        mapping(address => DoubleLinkedList.List) storage _suppliersOnPool,
        mapping(address => mapping(address => DataStructs.SupplyBalance))
            storage _supplyBalanceInOf,
        mapping(address => mapping(address => DataStructs.BorrowBalance)) storage _borrowBalanceInOf
    ) external returns (uint256 matched) {
        uint256 borrowP2PExchangeRate = params.marketsManagerForAave.borrowP2PExchangeRate(
            params.poolTokenAddress
        );
        matched = MatchLogic.matchSuppliers(params, _NMAX, _suppliersOnPool, _supplyBalanceInOf); // In underlying

        if (matched > 0) {
            _borrowBalanceInOf[params.poolTokenAddress][_user].inP2P += matched.divWadByRay(
                borrowP2PExchangeRate
            ); // In p2pUnit
            DataLogic.updateBorrowers(params.poolTokenAddress, _user, params.matchingEngineManager);
        }
    }

    /// @notice Withdraws tokens from P2P `_user`'s position.
    /// @param params The required parameters to execute the function.
    /// @param _user The address of the user.
    /// @param _NMAX The NMAX value for the matching process.
    /// @param _suppliersOnPool The suppliers waiting on Pool.
    /// @param _borrowersInP2P The borrowers in P2P.
    /// @param _supplyBalanceInOf The supply balances of all suppliers.
    /// @param _borrowBalanceInOf The borrow balances of all borrowers.
    function withdrawPositionFromP2P(
        DataStructs.CommonParams memory params,
        address _user,
        uint256 _NMAX,
        mapping(address => DoubleLinkedList.List) storage _suppliersOnPool,
        mapping(address => DoubleLinkedList.List) storage _borrowersInP2P,
        mapping(address => mapping(address => DataStructs.SupplyBalance))
            storage _supplyBalanceInOf,
        mapping(address => mapping(address => DataStructs.BorrowBalance)) storage _borrowBalanceInOf
    ) external {
        uint256 supplyP2PExchangeRate = params.marketsManagerForAave.supplyP2PExchangeRate(
            params.poolTokenAddress
        );

        _supplyBalanceInOf[params.poolTokenAddress][_user].inP2P -= Math.min(
            _supplyBalanceInOf[params.poolTokenAddress][_user].inP2P,
            params.amount.divWadByRay(supplyP2PExchangeRate)
        ); // In p2pUnit
        DataLogic.updateSuppliers(params.poolTokenAddress, _user, params.matchingEngineManager);

        uint256 matchedSupply = MatchLogic.matchSuppliers(
            params,
            _NMAX,
            _suppliersOnPool,
            _supplyBalanceInOf
        );

        // We break some P2P credit lines the supplier had with borrowers and fallback on Aave.
        if (params.amount > matchedSupply) {
            params.amount -= matchedSupply;
            MatchLogic.unmatchBorrowers(params, _borrowersInP2P, _borrowBalanceInOf); // Revert on error
        }
    }

    /// @notice Repays tokens of P2P `_user`'s position.
    /// @param params The required parameters to execute the function.
    /// @param _user The address of the user.
    /// @param _NMAX The NMAX value for the matching process.
    /// @param _borrowersOnPool The borrowers waiting on Pool.
    /// @param _suppliersInP2P The suppliers in P2P.
    /// @param _supplyBalanceInOf The supply balances of all suppliers.
    /// @param _borrowBalanceInOf The borrow balances of all borrowers.
    function repayPositionToP2P(
        DataStructs.CommonParams memory params,
        address _user,
        uint256 _NMAX,
        IProtocolDataProvider _dataProvider,
        mapping(address => DoubleLinkedList.List) storage _borrowersOnPool,
        mapping(address => DoubleLinkedList.List) storage _suppliersInP2P,
        mapping(address => mapping(address => DataStructs.SupplyBalance))
            storage _supplyBalanceInOf,
        mapping(address => mapping(address => DataStructs.BorrowBalance)) storage _borrowBalanceInOf
    ) external {
        uint256 borrowP2PExchangeRate = params.marketsManagerForAave.borrowP2PExchangeRate(
            params.poolTokenAddress
        );

        _borrowBalanceInOf[params.poolTokenAddress][_user].inP2P -= Math.min(
            _borrowBalanceInOf[params.poolTokenAddress][_user].inP2P,
            params.amount.divWadByRay(borrowP2PExchangeRate)
        ); // In p2pUnit
        DataLogic.updateBorrowers(params.poolTokenAddress, _user, params.matchingEngineManager);

        uint256 matchedBorrow = MatchLogic.matchBorrowers(
            params,
            _NMAX,
            _dataProvider,
            _borrowersOnPool,
            _borrowBalanceInOf
        );

        // We break some P2P credit lines the borrower had with suppliers and fallback on Aave.
        if (params.amount > matchedBorrow) {
            params.amount -= matchedBorrow;
            MatchLogic.unmatchSuppliers(params, _suppliersInP2P, _supplyBalanceInOf); // Revert on error
        }
    }
}
