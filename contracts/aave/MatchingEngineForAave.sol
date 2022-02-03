// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import {IAToken} from "./interfaces/aave/IAToken.sol";
import "./interfaces/aave/IScaledBalanceToken.sol";
import "./interfaces/IMatchingEngineForAave.sol";
import "./interfaces/IPositionsManagerForAave.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./libraries/aave/WadRayMath.sol";

import "../common/libraries/DoubleLinkedList.sol";
import "./PositionsManagerForAave.sol";

/// @title MatchingEngineManager
/// @dev Smart contract managing the matching engine.
contract MatchingEngineForAave is ReentrancyGuard {
    using DoubleLinkedList for DoubleLinkedList.List;
    using WadRayMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address;

    /// Enums ///

    enum PositionType {
        SUPPLIERS_IN_P2P,
        SUPPLIERS_ON_POOL,
        BORROWERS_IN_P2P,
        BORROWERS_ON_POOL
    }

    /// Storage ///

    uint16 public NMAX = 1000;

    mapping(address => DoubleLinkedList.List) internal suppliersInP2P; // Suppliers in peer-to-peer.
    mapping(address => DoubleLinkedList.List) internal suppliersOnPool; // Suppliers on Aave.
    mapping(address => DoubleLinkedList.List) internal borrowersInP2P; // Borrowers in peer-to-peer.
    mapping(address => DoubleLinkedList.List) internal borrowersOnPool; // Borrowers on Aave.

    IPositionsManagerForAave public positionsManagerForAave;
    IMarketsManagerForAave public marketsManagerForAave;

    constructor(address positionsManagerForAaveAddress, address marketsManagerForAaveAddress) {
        positionsManagerForAave = IPositionsManagerForAave(positionsManagerForAaveAddress);
        marketsManagerForAave = IMarketsManagerForAave(marketsManagerForAaveAddress);
    }

    /// @dev Emitted the maximum number of users to have in the tree is updated.
    /// @param _newValue The new value of the maximum number of users to have in the tree.
    event MaxNumberSet(uint16 _newValue);

    /// @dev Emitted when the position of a supplier is updated.
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

    /// @dev Emitted when the position of a borrower is updated.
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

    /// @notice Thrown when only the markets manager can call the function.
    error OnlyMarketsManager();

    /// @notice Thrown when only the markets manager's owner can call the function.
    error OnlyMarketsManagerOwner();

    /// @dev Prevents a user to call function only allowed for `marketsManagerForAave`'s owner.
    modifier onlyMarketsManagerOwner() {
        if (msg.sender != marketsManagerForAave.owner()) revert OnlyMarketsManagerOwner();
        _;
    }

    /// @dev Sets the maximum number of users in data structure.
    /// @param _newMaxNumber The maximum number of users to sort in the data structure.
    function setNmaxForMatchingEngine(uint16 _newMaxNumber) external onlyMarketsManagerOwner {
        NMAX = _newMaxNumber;
        emit MaxNumberSet(_newMaxNumber);
    }

    /// @dev Matches suppliers' liquidity waiting on Aave for the given `_amount` and move it to P2P.
    /// @dev Note: p2pExchangeRates must have been updated before calling this function.
    /// @param _poolToken The pool token of the market from which to match suppliers.
    /// @param _underlyingToken The underlying token of the market to find liquidity.
    /// @param _amount The token amount to search for (in underlying).
    /// @return matchedSupply The amount of liquidity matched (in underlying).
    function matchSuppliers(
        IAToken _poolToken,
        IERC20 _underlyingToken,
        uint256 _amount
    ) public returns (uint256 matchedSupply) {
        address poolTokenAddress = address(_poolToken);
        uint256 normalizedIncome = positionsManagerForAave.lendingPool().getReserveNormalizedIncome(
            address(_underlyingToken)
        );
        address user = suppliersOnPool[poolTokenAddress].getHead();
        uint256 supplyP2PExchangeRate = marketsManagerForAave.supplyP2PExchangeRate(
            poolTokenAddress
        );
        uint256 iterationCount;

        while (matchedSupply < _amount && user != address(0) && iterationCount < NMAX) {
            iterationCount++;
            uint256 onPoolInUnderlying = positionsManagerForAave
            .supplyBalanceInOf(poolTokenAddress, user)
            .onPool
            .mulWadByRay(normalizedIncome);
            uint256 toMatch = Math.min(onPoolInUnderlying, _amount - matchedSupply);
            matchedSupply += toMatch;
            positionsManagerForAave.updateSupplyBalanceInOfOnPool(
                poolTokenAddress,
                user,
                -int256(toMatch.divWadByRay(normalizedIncome))
            );
            positionsManagerForAave.updateSupplyBalanceInOfInP2P(
                poolTokenAddress,
                user,
                int256(toMatch.divWadByRay(supplyP2PExchangeRate)) // In p2pUnit
            );
            updateSuppliers(poolTokenAddress, user);
            emit SupplierPositionUpdated(
                user,
                poolTokenAddress,
                positionsManagerForAave.supplyBalanceInOf(poolTokenAddress, user).onPool,
                positionsManagerForAave.supplyBalanceInOf(poolTokenAddress, user).inP2P
            );
            user = suppliersOnPool[poolTokenAddress].getHead();
        }

        if (matchedSupply > 0) {
            matchedSupply = Math.min(
                matchedSupply,
                _poolToken.balanceOf(address(positionsManagerForAave))
            );
            positionsManagerForAave._withdrawERC20FromPool(_underlyingToken, matchedSupply); // Revert on error
        }
    }

    /// @dev Unmatches suppliers' liquidity in P2P for the given `_amount` and move it to Aave.
    /// @dev Note: p2pExchangeRates must have been updated before calling this function.
    /// @param _poolTokenAddress The address of the market from which to unmatch suppliers.
    /// @param _amount The amount to search for (in underlying).
    function unmatchSuppliers(address _poolTokenAddress, uint256 _amount) public {
        IAToken poolToken = IAToken(_poolTokenAddress);
        IERC20 underlyingToken = IERC20(poolToken.UNDERLYING_ASSET_ADDRESS());
        uint256 normalizedIncome = positionsManagerForAave.lendingPool().getReserveNormalizedIncome(
            address(underlyingToken)
        );
        uint256 supplyP2PExchangeRate = marketsManagerForAave.supplyP2PExchangeRate(
            _poolTokenAddress
        );
        address user = suppliersInP2P[_poolTokenAddress].getHead();
        uint256 remainingToUnmatch = _amount; // In underlying

        while (remainingToUnmatch > 0 && user != address(0)) {
            uint256 inP2P = positionsManagerForAave
            .supplyBalanceInOf(_poolTokenAddress, user)
            .inP2P; // In poolToken
            uint256 toUnmatch = Math.min(
                inP2P.mulWadByRay(supplyP2PExchangeRate),
                remainingToUnmatch
            ); // In underlying
            remainingToUnmatch -= toUnmatch;
            positionsManagerForAave.updateSupplyBalanceInOfOnPool(
                _poolTokenAddress,
                user,
                int256(toUnmatch.divWadByRay(normalizedIncome))
            );
            positionsManagerForAave.updateSupplyBalanceInOfInP2P(
                _poolTokenAddress,
                user,
                -int256(toUnmatch.divWadByRay(supplyP2PExchangeRate)) // In p2pUnit
            );
            updateSuppliers(_poolTokenAddress, user);
            emit SupplierPositionUpdated(
                user,
                _poolTokenAddress,
                positionsManagerForAave.supplyBalanceInOf(_poolTokenAddress, user).onPool,
                positionsManagerForAave.supplyBalanceInOf(_poolTokenAddress, user).inP2P
            );
            user = suppliersInP2P[_poolTokenAddress].getHead();
        }

        // Supply the remaining on Aave
        uint256 toSupply = _amount - remainingToUnmatch;
        if (toSupply > 0) positionsManagerForAave._supplyERC20ToPool(underlyingToken, toSupply); // Revert on error
    }

    /// @dev Matches borrowers' liquidity waiting on Aave for the given `_amount` and move it to P2P.
    /// @dev Note: p2pExchangeRates must have been updated before calling this function.
    /// @param _poolToken The pool token of the market from which to match borrowers.
    /// @param _underlyingToken The underlying token of the market to find liquidity.
    /// @param _amount The amount to search for (in underlying).
    /// @return matchedBorrow The amount of liquidity matched (in underlying).
    function matchBorrowers(
        IAToken _poolToken,
        IERC20 _underlyingToken,
        uint256 _amount
    ) public returns (uint256 matchedBorrow) {
        address poolTokenAddress = address(_poolToken);
        uint256 normalizedVariableDebt = positionsManagerForAave
        .lendingPool()
        .getReserveNormalizedVariableDebt(address(_underlyingToken));
        uint256 borrowP2PExchangeRate = marketsManagerForAave.borrowP2PExchangeRate(
            poolTokenAddress
        );
        address user = borrowersOnPool[poolTokenAddress].getHead();
        uint256 iterationCount;

        while (matchedBorrow < _amount && user != address(0) && iterationCount < NMAX) {
            iterationCount++;
            uint256 onPoolInUnderlying = positionsManagerForAave
            .borrowBalanceInOf(poolTokenAddress, user)
            .onPool
            .mulWadByRay(normalizedVariableDebt);
            uint256 toMatch = Math.min(onPoolInUnderlying, _amount - matchedBorrow);
            matchedBorrow += toMatch;
            positionsManagerForAave.updateBorrowBalanceInOfOnPool(
                poolTokenAddress,
                user,
                -int256(toMatch.divWadByRay(normalizedVariableDebt))
            );
            positionsManagerForAave.updateBorrowBalanceInOfInP2P(
                poolTokenAddress,
                user,
                int256(toMatch.divWadByRay(borrowP2PExchangeRate))
            );
            updateBorrowers(poolTokenAddress, user);
            emit BorrowerPositionUpdated(
                user,
                poolTokenAddress,
                positionsManagerForAave.borrowBalanceInOf(poolTokenAddress, user).onPool,
                positionsManagerForAave.borrowBalanceInOf(poolTokenAddress, user).inP2P
            );
            user = borrowersOnPool[poolTokenAddress].getHead();
        }

        if (matchedBorrow > 0)
            positionsManagerForAave._repayERC20ToPool(
                _underlyingToken,
                matchedBorrow,
                normalizedVariableDebt
            ); // Revert on error
    }

    /// @dev Unmatches borrowers' liquidity in P2P for the given `_amount` and move it to Aave.
    /// @dev Note: p2pExchangeRates must have been updated before calling this function.
    /// @param _poolTokenAddress The address of the market from which to unmatch borrowers.
    /// @param _amount The amount to unmatch (in underlying).
    function unmatchBorrowers(address _poolTokenAddress, uint256 _amount) public {
        IAToken poolToken = IAToken(_poolTokenAddress);
        IERC20 underlyingToken = IERC20(poolToken.UNDERLYING_ASSET_ADDRESS());
        uint256 borrowP2PExchangeRate = marketsManagerForAave.borrowP2PExchangeRate(
            _poolTokenAddress
        );
        uint256 normalizedVariableDebt = positionsManagerForAave
        .lendingPool()
        .getReserveNormalizedVariableDebt(address(underlyingToken));
        address user = borrowersInP2P[_poolTokenAddress].getHead();
        uint256 remainingToUnmatch = _amount;

        while (remainingToUnmatch > 0 && user != address(0)) {
            uint256 inP2P = positionsManagerForAave
            .borrowBalanceInOf(_poolTokenAddress, user)
            .inP2P;
            uint256 toUnmatch = Math.min(
                inP2P.mulWadByRay(borrowP2PExchangeRate),
                remainingToUnmatch
            ); // In underlying
            remainingToUnmatch -= toUnmatch;
            positionsManagerForAave.updateBorrowBalanceInOfOnPool(
                _poolTokenAddress,
                user,
                int256(toUnmatch.divWadByRay(normalizedVariableDebt))
            );
            positionsManagerForAave.updateBorrowBalanceInOfInP2P(
                _poolTokenAddress,
                user,
                -int256(toUnmatch.divWadByRay(borrowP2PExchangeRate))
            );
            updateBorrowers(_poolTokenAddress, user);
            emit BorrowerPositionUpdated(
                user,
                _poolTokenAddress,
                positionsManagerForAave.borrowBalanceInOf(_poolTokenAddress, user).onPool,
                positionsManagerForAave.borrowBalanceInOf(_poolTokenAddress, user).inP2P
            );
            user = borrowersInP2P[_poolTokenAddress].getHead();
        }

        uint256 toBorrow = _amount - remainingToUnmatch;
        if (toBorrow > 0) positionsManagerForAave._borrowERC20FromPool(underlyingToken, toBorrow); // Revert on error
    }

    /// @dev Updates borrowers matching engine with the new balances of a given account.
    /// @param _poolTokenAddress The address of the market on which to update the borrowers data structure.
    /// @param _account The address of the borrower to move.
    function updateBorrowers(address _poolTokenAddress, address _account) public {
        uint256 onPool = positionsManagerForAave
        .borrowBalanceInOf(_poolTokenAddress, _account)
        .onPool;
        uint256 inP2P = positionsManagerForAave
        .borrowBalanceInOf(_poolTokenAddress, _account)
        .inP2P;
        uint256 formerValueOnPool = borrowersOnPool[_poolTokenAddress].getValueOf(_account);
        uint256 formerValueInP2P = borrowersInP2P[_poolTokenAddress].getValueOf(_account);

        // Check pool
        bool wasOnPoolAndValueChanged = formerValueOnPool != 0 && formerValueOnPool != onPool;
        if (wasOnPoolAndValueChanged) borrowersOnPool[_poolTokenAddress].remove(_account);
        if (onPool > 0 && (wasOnPoolAndValueChanged || formerValueOnPool == 0)) {
            uint256 totalStaked = IScaledBalanceToken(_poolTokenAddress).scaledTotalSupply();
            (, , address variableDebtTokenAddress) = positionsManagerForAave
            .dataProvider()
            .getReserveTokensAddresses(IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS());
            positionsManagerForAave.rewardsManager().updateUserAssetAndAccruedRewards(
                _account,
                variableDebtTokenAddress,
                formerValueOnPool,
                totalStaked
            );
            borrowersOnPool[_poolTokenAddress].insertSorted(_account, onPool, NMAX);
        }

        // Check P2P
        bool wasInP2PAndValueChanged = formerValueInP2P != 0 && formerValueInP2P != inP2P;
        if (wasInP2PAndValueChanged) borrowersInP2P[_poolTokenAddress].remove(_account);
        if (inP2P > 0 && (wasInP2PAndValueChanged || formerValueInP2P == 0))
            borrowersInP2P[_poolTokenAddress].insertSorted(_account, inP2P, NMAX);
    }

    /// @dev Updates suppliers matching engine with the new balances of a given account.
    /// @param _poolTokenAddress The address of the market on which to update the suppliers data structure.
    /// @param _account The address of the supplier to move.
    function updateSuppliers(address _poolTokenAddress, address _account) public {
        uint256 onPool = positionsManagerForAave
        .supplyBalanceInOf(_poolTokenAddress, _account)
        .onPool;
        uint256 inP2P = positionsManagerForAave
        .supplyBalanceInOf(_poolTokenAddress, _account)
        .inP2P;
        uint256 formerValueOnPool = suppliersOnPool[_poolTokenAddress].getValueOf(_account);
        uint256 formerValueInP2P = suppliersInP2P[_poolTokenAddress].getValueOf(_account);

        // Check pool
        bool wasOnPoolAndValueChanged = formerValueOnPool != 0 && formerValueOnPool != onPool;
        if (wasOnPoolAndValueChanged) suppliersOnPool[_poolTokenAddress].remove(_account);
        if (onPool > 0 && (wasOnPoolAndValueChanged || formerValueOnPool == 0)) {
            uint256 totalStaked = IScaledBalanceToken(_poolTokenAddress).scaledTotalSupply();
            positionsManagerForAave.rewardsManager().updateUserAssetAndAccruedRewards(
                _account,
                _poolTokenAddress,
                formerValueOnPool,
                totalStaked
            );
            suppliersOnPool[_poolTokenAddress].insertSorted(_account, onPool, NMAX);
        }

        // Check P2P
        bool wasInP2PAndValueChanged = formerValueInP2P != 0 && formerValueInP2P != inP2P;
        if (wasInP2PAndValueChanged) suppliersInP2P[_poolTokenAddress].remove(_account);
        if (inP2P > 0 && (wasInP2PAndValueChanged || formerValueInP2P == 0))
            suppliersInP2P[_poolTokenAddress].insertSorted(_account, inP2P, NMAX);
    }

    /// View functions ///

    /// @dev Gets the head of the data structure on a specific market (for UI).
    /// @param _poolTokenAddress The address of the market from which to get the head.
    /// @param _positionType The type of user from which to get the head.
    /// @return head The head in the data structure.
    function getHead(address _poolTokenAddress, uint8 _positionType)
        external
        returns (address head)
    {
        if (_positionType == positionsManagerForAave.SUPPLIERS_IN_P2P())
            head = suppliersInP2P[_poolTokenAddress].getHead();
        else if (_positionType == positionsManagerForAave.SUPPLIERS_ON_POOL())
            head = suppliersOnPool[_poolTokenAddress].getHead();
        else if (_positionType == positionsManagerForAave.BORROWERS_IN_P2P())
            head = borrowersInP2P[_poolTokenAddress].getHead();
        else if (_positionType == positionsManagerForAave.BORROWERS_ON_POOL())
            head = borrowersOnPool[_poolTokenAddress].getHead();
    }

    /// @dev Gets the next user after `_user` in the data structure on a specific market (for UI).
    /// @param _poolTokenAddress The address of the market from which to get the user.
    /// @param _positionType The type of user from which to get the next user.
    /// @param _user The address of the user from which to get the next user.
    /// @return next The next user in the data structure.
    function getNext(
        address _poolTokenAddress,
        uint8 _positionType,
        address _user
    ) external returns (address next) {
        if (_positionType == positionsManagerForAave.SUPPLIERS_IN_P2P())
            next = suppliersInP2P[_poolTokenAddress].getNext(_user);
        else if (_positionType == positionsManagerForAave.SUPPLIERS_ON_POOL())
            next = suppliersOnPool[_poolTokenAddress].getNext(_user);
        else if (_positionType == positionsManagerForAave.BORROWERS_IN_P2P())
            next = borrowersInP2P[_poolTokenAddress].getNext(_user);
        else if (_positionType == positionsManagerForAave.BORROWERS_ON_POOL())
            next = borrowersOnPool[_poolTokenAddress].getNext(_user);
    }
}
