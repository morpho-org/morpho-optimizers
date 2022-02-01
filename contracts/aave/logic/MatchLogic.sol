// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAToken} from "../interfaces/aave/IAToken.sol";

import "../../common/libraries/DoubleLinkedList.sol";
import "../libraries/aave/WadRayMath.sol";
import "../libraries/DataStructs.sol";
import "./PoolLogic.sol";
import "./DataLogic.sol";

import "@openzeppelin/contracts/utils/math/Math.sol";

/// @title MatchLogic
/// @notice Implement the base logic for (un)matching specific functions.
library MatchLogic {
    using DoubleLinkedList for DoubleLinkedList.List;
    using WadRayMath for uint256;

    /// Structs ///

    // Struct to avoid stack too deep inside matching functions
    struct MatchVars {
        address user;
        uint256 toMatch;
        uint256 iterationCount;
    }

    /// Events ///

    /// @notice Emitted when the position of a supplier is updated.
    /// @param _user The address of the supplier.
    /// @param _poolTokenAddress The address of the market.
    /// @param _balanceOnPool The supply balance on pool after update.
    /// @param _balanceInP2P The supply balance in P2P after update.
    event SupplierPositionUpdated(
        address indexed _user,
        address indexed _poolTokenAddress,
        uint256 _balanceOnPool,
        uint256 _balanceInP2P
    );

    /// @notice Emitted when the position of a borrower is updated.
    /// @param _user The address of the borrower.
    /// @param _poolTokenAddress The address of the market.
    /// @param _balanceOnPool The borrow balance on pool after update.
    /// @param _balanceInP2P The borrow balance in P2P after update.
    event BorrowerPositionUpdated(
        address indexed _user,
        address indexed _poolTokenAddress,
        uint256 _balanceOnPool,
        uint256 _balanceInP2P
    );

    /// @notice Matches suppliers' liquidity waiting on Aave and move it to P2P.
    /// @dev Note: P2P exchange rates must have been updated before calling this function.
    /// @param params The required parameters to execute the function.
    /// @param _NMAX The NMAX value for the matching process.
    /// @param _suppliersOnPool The suppliers waiting on Pool.
    /// @param _supplyBalanceInOf The supply balances of all suppliers.
    /// @return matchedSupply The amount of liquidity matched (in underlying).
    function matchSuppliers(
        DataStructs.CommonParams memory params,
        uint256 _NMAX,
        mapping(address => DoubleLinkedList.List) storage _suppliersOnPool,
        mapping(address => mapping(address => DataStructs.SupplyBalance)) storage _supplyBalanceInOf
    ) external returns (uint256 matchedSupply) {
        MatchVars memory vars;
        uint256 normalizedIncome = params.lendingPool.getReserveNormalizedIncome(
            address(params.underlyingToken)
        );
        uint256 supplyP2PExchangeRate = params.marketsManagerForAave.supplyP2PExchangeRate(
            params.poolTokenAddress
        );
        vars.user = _suppliersOnPool[params.poolTokenAddress].getHead();

        while (
            matchedSupply < params.amount && vars.user != address(0) && vars.iterationCount < _NMAX
        ) {
            vars.iterationCount++;
            uint256 onPoolInUnderlying = _supplyBalanceInOf[params.poolTokenAddress][vars.user]
            .onPool
            .mulWadByRay(normalizedIncome);
            vars.toMatch = Math.min(onPoolInUnderlying, params.amount - matchedSupply);
            matchedSupply += vars.toMatch;

            _supplyBalanceInOf[params.poolTokenAddress][vars.user].onPool -= vars
            .toMatch
            .divWadByRay(normalizedIncome);
            _supplyBalanceInOf[params.poolTokenAddress][vars.user].inP2P += vars
            .toMatch
            .divWadByRay(supplyP2PExchangeRate); // In p2pUnit
            DataLogic.updateSuppliers(
                params.poolTokenAddress,
                vars.user,
                params.matchingEngineManager
            );

            emit SupplierPositionUpdated(
                vars.user,
                params.poolTokenAddress,
                _supplyBalanceInOf[params.poolTokenAddress][vars.user].onPool,
                _supplyBalanceInOf[params.poolTokenAddress][vars.user].inP2P
            );
            vars.user = _suppliersOnPool[params.poolTokenAddress].getHead();
        }

        if (matchedSupply > 0) {
            matchedSupply = Math.min(
                matchedSupply,
                IAToken(params.poolTokenAddress).balanceOf(address(this))
            );
            PoolLogic.withdrawERC20FromPool(
                params.underlyingToken,
                matchedSupply,
                params.lendingPool
            ); // Revert on error
        }
    }

    /// @notice Unmatches suppliers' liquidity in P2P and move it to Aave.
    /// @dev Note: P2P exchange rates must have been updated before calling this function.
    /// @param params The required parameters to execute the function.
    /// @param _suppliersInP2P The suppliers in P2P.
    /// @param _supplyBalanceInOf The supply balances of all suppliers.
    function unmatchSuppliers(
        DataStructs.CommonParams memory params,
        mapping(address => DoubleLinkedList.List) storage _suppliersInP2P,
        mapping(address => mapping(address => DataStructs.SupplyBalance)) storage _supplyBalanceInOf
    ) external {
        IAToken poolToken = IAToken(params.poolTokenAddress);
        IERC20 underlyingToken = IERC20(poolToken.UNDERLYING_ASSET_ADDRESS());
        uint256 normalizedIncome = params.lendingPool.getReserveNormalizedIncome(
            address(underlyingToken)
        );
        uint256 supplyP2PExchangeRate = params.marketsManagerForAave.supplyP2PExchangeRate(
            params.poolTokenAddress
        );
        address user = _suppliersInP2P[params.poolTokenAddress].getHead();
        uint256 remainingToUnmatch = params.amount; // In underlying

        while (remainingToUnmatch > 0 && user != address(0)) {
            uint256 toUnmatch = Math.min(
                _supplyBalanceInOf[params.poolTokenAddress][user].inP2P.mulWadByRay(
                    supplyP2PExchangeRate
                ),
                remainingToUnmatch
            ); // In underlying
            remainingToUnmatch -= toUnmatch;

            _supplyBalanceInOf[params.poolTokenAddress][user].onPool += toUnmatch.divWadByRay(
                normalizedIncome
            );
            _supplyBalanceInOf[params.poolTokenAddress][user].inP2P -= toUnmatch.divWadByRay(
                supplyP2PExchangeRate
            ); // In p2pUnit
            DataLogic.updateSuppliers(params.poolTokenAddress, user, params.matchingEngineManager);

            emit SupplierPositionUpdated(
                user,
                params.poolTokenAddress,
                _supplyBalanceInOf[params.poolTokenAddress][user].onPool,
                _supplyBalanceInOf[params.poolTokenAddress][user].inP2P
            );
            user = _suppliersInP2P[params.poolTokenAddress].getHead();
        }

        // Supply the remaining on Aave
        uint256 toSupply = params.amount - remainingToUnmatch;
        if (toSupply > 0)
            PoolLogic.supplyERC20ToPool(underlyingToken, toSupply, params.lendingPool); // Revert on error
    }

    /// @notice Matches borrowers' liquidity waiting on Aave and move it to P2P.
    /// @dev Note: P2P exchange rates must have been updated before calling this function.
    /// @param _NMAX The NMAX value for the matching process.
    /// @param _dataProvider The Aave's Data Provider.
    /// @param _borrowersOnPool The borrowers waiting on Pool.
    /// @param _borrowBalanceInOf The borrow balances of all borrowers.
    /// @return matchedBorrow The amount of liquidity matched (in underlying).
    function matchBorrowers(
        DataStructs.CommonParams memory params,
        uint256 _NMAX,
        IProtocolDataProvider _dataProvider,
        mapping(address => DoubleLinkedList.List) storage _borrowersOnPool,
        mapping(address => mapping(address => DataStructs.BorrowBalance)) storage _borrowBalanceInOf
    ) external returns (uint256 matchedBorrow) {
        MatchVars memory vars;
        uint256 normalizedVariableDebt = params.lendingPool.getReserveNormalizedVariableDebt(
            address(params.underlyingToken)
        );
        uint256 borrowP2PExchangeRate = params.marketsManagerForAave.borrowP2PExchangeRate(
            params.poolTokenAddress
        );
        vars.user = _borrowersOnPool[params.poolTokenAddress].getHead();

        while (
            matchedBorrow < params.amount && vars.user != address(0) && vars.iterationCount < _NMAX
        ) {
            vars.iterationCount++;
            uint256 onPoolInUnderlying = _borrowBalanceInOf[params.poolTokenAddress][vars.user]
            .onPool
            .mulWadByRay(normalizedVariableDebt);
            vars.toMatch = Math.min(onPoolInUnderlying, params.amount - matchedBorrow);
            matchedBorrow += vars.toMatch;

            _borrowBalanceInOf[params.poolTokenAddress][vars.user].onPool -= vars
            .toMatch
            .divWadByRay(normalizedVariableDebt);
            _borrowBalanceInOf[params.poolTokenAddress][vars.user].inP2P += vars
            .toMatch
            .divWadByRay(borrowP2PExchangeRate);
            DataLogic.updateBorrowers(
                params.poolTokenAddress,
                vars.user,
                params.matchingEngineManager
            );

            emit BorrowerPositionUpdated(
                vars.user,
                params.poolTokenAddress,
                _borrowBalanceInOf[params.poolTokenAddress][vars.user].onPool,
                _borrowBalanceInOf[params.poolTokenAddress][vars.user].inP2P
            );
            vars.user = _borrowersOnPool[params.poolTokenAddress].getHead();
        }

        if (matchedBorrow > 0)
            PoolLogic.repayERC20ToPool(
                params.underlyingToken,
                matchedBorrow,
                normalizedVariableDebt,
                params.lendingPool,
                _dataProvider
            ); // Revert on error
    }

    /// @notice Unmatches borrowers' liquidity in P2P and move it to Aave.
    /// @dev Note: P2P exchange rates must have been updated before calling this function.
    /// @param params The required parameters to execute the function.
    /// @param _borrowersInP2P The borrowers in P2P.
    /// @param _borrowBalanceInOf The borrow balances of all borrowers.
    function unmatchBorrowers(
        DataStructs.CommonParams memory params,
        mapping(address => DoubleLinkedList.List) storage _borrowersInP2P,
        mapping(address => mapping(address => DataStructs.BorrowBalance)) storage _borrowBalanceInOf
    ) external {
        uint256 borrowP2PExchangeRate = params.marketsManagerForAave.borrowP2PExchangeRate(
            params.poolTokenAddress
        );
        uint256 normalizedVariableDebt = params.lendingPool.getReserveNormalizedVariableDebt(
            address(params.underlyingToken)
        );
        address user = _borrowersInP2P[params.poolTokenAddress].getHead();
        uint256 remainingToUnmatch = params.amount;

        while (remainingToUnmatch > 0 && user != address(0)) {
            uint256 inP2P = _borrowBalanceInOf[params.poolTokenAddress][user].inP2P;
            uint256 toUnmatch = Math.min(
                inP2P.mulWadByRay(borrowP2PExchangeRate),
                remainingToUnmatch
            ); // In underlying
            remainingToUnmatch -= toUnmatch;

            _borrowBalanceInOf[params.poolTokenAddress][user].onPool += toUnmatch.divWadByRay(
                normalizedVariableDebt
            );
            _borrowBalanceInOf[params.poolTokenAddress][user].inP2P -= toUnmatch.divWadByRay(
                borrowP2PExchangeRate
            );
            DataLogic.updateBorrowers(params.poolTokenAddress, user, params.matchingEngineManager);

            emit BorrowerPositionUpdated(
                user,
                params.poolTokenAddress,
                _borrowBalanceInOf[params.poolTokenAddress][user].onPool,
                _borrowBalanceInOf[params.poolTokenAddress][user].inP2P
            );
            user = _borrowersInP2P[params.poolTokenAddress].getHead();
        }

        uint256 toBorrow = params.amount - remainingToUnmatch;
        if (toBorrow > 0)
            PoolLogic.borrowERC20FromPool(params.underlyingToken, toBorrow, params.lendingPool); // Revert on error
    }
}
