// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./interfaces/IEntryManager.sol";

import "./PoolInteraction.sol";

/// @title EntryManager.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Morpho's entry points: supply and borrow.
contract EntryManager is IEntryManager, PoolInteraction {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using HeapOrdering for HeapOrdering.HeapArray;
    using PercentageMath for uint256;
    using SafeTransferLib for ERC20;
    using WadRayMath for uint256;

    /// EVENTS ///

    /// @notice Emitted when a supply happens.
    /// @param _supplier The address of the account sending funds.
    /// @param _onBehalf The address of the account whose positions will be updated.
    /// @param _poolTokenAddress The address of the market where assets are supplied into.
    /// @param _amount The amount of assets supplied (in underlying).
    /// @param _balanceOnPool The supply balance on pool after update.
    /// @param _balanceInP2P The supply balance in peer-to-peer after update.
    event Supplied(
        address indexed _supplier,
        address indexed _onBehalf,
        address indexed _poolTokenAddress,
        uint256 _amount,
        uint256 _balanceOnPool,
        uint256 _balanceInP2P
    );

    /// @notice Emitted when a borrow happens.
    /// @param _borrower The address of the borrower.
    /// @param _poolTokenAddress The address of the market where assets are borrowed.
    /// @param _amount The amount of assets borrowed (in underlying).
    /// @param _balanceOnPool The borrow balance on pool after update.
    /// @param _balanceInP2P The borrow balance in peer-to-peer after update
    event Borrowed(
        address indexed _borrower,
        address indexed _poolTokenAddress,
        uint256 _amount,
        uint256 _balanceOnPool,
        uint256 _balanceInP2P
    );

    /// ERRORS ///

    /// @notice Thrown when the user does not have enough collateral for the borrow.
    error UnauthorisedBorrow();

    /// @notice Thrown when the address is zero.
    error AddressIsZero();

    /// STRUCTS ///

    // Struct to avoid stack too deep.
    struct SupplyVars {
        uint256 remainingToSupply;
        uint256 poolBorrowIndex;
        uint256 toRepay;
    }

    /// LOGIC ///

    /// @dev Implements supply logic.
    /// @param _poolTokenAddress The address of the pool token the user wants to interact with.
    /// @param _supplier The address of the account sending funds.
    /// @param _onBehalf The address of the account whose positions will be updated.
    /// @param _amount The amount of token (in underlying).
    /// @param _maxGasForMatching The maximum amount of gas to consume within a matching engine loop.
    function supplyLogic(
        address _poolTokenAddress,
        address _supplier,
        address _onBehalf,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) external {
        if (_onBehalf == address(0)) revert AddressIsZero();
        if (_amount == 0) revert AmountIsZero();
        _updateIndexes(_poolTokenAddress);

        _enterMarketIfNeeded(_poolTokenAddress, _onBehalf);
        ERC20 underlyingToken = ERC20(IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS());
        underlyingToken.safeTransferFrom(_supplier, address(this), _amount);

        Types.Delta storage delta = deltas[_poolTokenAddress];
        SupplyVars memory vars;
        vars.poolBorrowIndex = poolIndexes[_poolTokenAddress].poolBorrowIndex;
        vars.remainingToSupply = _amount;

        /// Supply in peer-to-peer ///

        // Match borrow peer-to-peer delta first if any.
        if (delta.p2pBorrowDelta > 0) {
            uint256 matchedDelta = Math.min(
                delta.p2pBorrowDelta.rayMul(vars.poolBorrowIndex),
                vars.remainingToSupply
            );

            vars.toRepay += matchedDelta;
            vars.remainingToSupply -= matchedDelta;
            delta.p2pBorrowDelta -= matchedDelta.rayDiv(vars.poolBorrowIndex);
            emit P2PBorrowDeltaUpdated(_poolTokenAddress, delta.p2pBorrowDelta);
        }

        // Match pool borrowers if any.
        if (
            vars.remainingToSupply > 0 &&
            !p2pDisabled[_poolTokenAddress] &&
            borrowersOnPool[_poolTokenAddress].getHead() != address(0)
        ) {
            (uint256 matched, ) = _matchBorrowers(
                _poolTokenAddress,
                vars.remainingToSupply,
                _maxGasForMatching
            ); // In underlying.

            if (matched > 0) {
                vars.toRepay += matched;
                vars.remainingToSupply -= matched;
                delta.p2pBorrowAmount += matched.rayDiv(p2pBorrowIndex[_poolTokenAddress]);
            }
        }

        if (vars.toRepay > 0) {
            uint256 toAddInP2P = vars.toRepay.rayDiv(p2pSupplyIndex[_poolTokenAddress]);

            delta.p2pSupplyAmount += toAddInP2P;
            supplyBalanceInOf[_poolTokenAddress][_onBehalf].inP2P += toAddInP2P;
            _repayToPool(underlyingToken, vars.toRepay, vars.poolBorrowIndex); // Reverts on error.

            emit P2PAmountsUpdated(_poolTokenAddress, delta.p2pSupplyAmount, delta.p2pBorrowAmount);
        }

        /// Supply on pool ///

        if (vars.remainingToSupply > 0) {
            supplyBalanceInOf[_poolTokenAddress][_onBehalf].onPool += vars.remainingToSupply.rayDiv(
                poolIndexes[_poolTokenAddress].poolSupplyIndex
            ); // In scaled balance.
            _supplyToPool(underlyingToken, vars.remainingToSupply); // Reverts on error.
        }

        _updateSupplierInDS(_poolTokenAddress, _onBehalf);

        emit Supplied(
            _supplier,
            _onBehalf,
            _poolTokenAddress,
            _amount,
            supplyBalanceInOf[_poolTokenAddress][_onBehalf].onPool,
            supplyBalanceInOf[_poolTokenAddress][_onBehalf].inP2P
        );
    }

    /// @dev Implements borrow logic.
    /// @param _poolTokenAddress The address of the market the user wants to interact with.
    /// @param _amount The amount of token (in underlying).
    /// @param _maxGasForMatching The maximum amount of gas to consume within a matching engine loop.
    function borrowLogic(
        address _poolTokenAddress,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) external {
        if (_amount == 0) revert AmountIsZero();
        _updateIndexes(_poolTokenAddress);

        _enterMarketIfNeeded(_poolTokenAddress, msg.sender);
        if (!_borrowAllowed(msg.sender, _poolTokenAddress, _amount)) revert UnauthorisedBorrow();

        ERC20 underlyingToken = ERC20(IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS());
        uint256 remainingToBorrow = _amount;
        uint256 toWithdraw;
        Types.Delta storage delta = deltas[_poolTokenAddress];
        uint256 poolSupplyIndex = poolIndexes[_poolTokenAddress].poolSupplyIndex;
        uint256 withdrawable = IAToken(_poolTokenAddress).balanceOf(address(this)); // The balance on pool.

        /// Borrow in peer-to-peer ///

        // Match supply peer-to-peer delta first if any.
        if (delta.p2pSupplyDelta > 0) {
            uint256 matchedDelta = Math.min(
                delta.p2pSupplyDelta.rayMul(poolSupplyIndex),
                remainingToBorrow,
                withdrawable
            );

            toWithdraw += matchedDelta;
            remainingToBorrow -= matchedDelta;
            delta.p2pSupplyDelta -= matchedDelta.rayDiv(poolSupplyIndex);
            emit P2PSupplyDeltaUpdated(_poolTokenAddress, delta.p2pSupplyDelta);
        }

        // Match pool suppliers if any.
        if (
            remainingToBorrow > 0 &&
            !p2pDisabled[_poolTokenAddress] &&
            suppliersOnPool[_poolTokenAddress].getHead() != address(0)
        ) {
            (uint256 matched, ) = _matchSuppliers(
                _poolTokenAddress,
                Math.min(remainingToBorrow, withdrawable - toWithdraw),
                _maxGasForMatching
            ); // In underlying.

            if (matched > 0) {
                toWithdraw += matched;
                remainingToBorrow -= matched;
                deltas[_poolTokenAddress].p2pSupplyAmount += matched.rayDiv(
                    p2pSupplyIndex[_poolTokenAddress]
                );
            }
        }

        if (toWithdraw > 0) {
            uint256 toAddInP2P = toWithdraw.rayDiv(p2pBorrowIndex[_poolTokenAddress]); // In peer-to-peer unit.

            deltas[_poolTokenAddress].p2pBorrowAmount += toAddInP2P;
            borrowBalanceInOf[_poolTokenAddress][msg.sender].inP2P += toAddInP2P;
            emit P2PAmountsUpdated(_poolTokenAddress, delta.p2pSupplyAmount, delta.p2pBorrowAmount);

            if (toWithdraw > 0) _withdrawFromPool(underlyingToken, toWithdraw); // Reverts on error.
        }

        /// Borrow on pool ///

        if (remainingToBorrow > 0) {
            borrowBalanceInOf[_poolTokenAddress][msg.sender].onPool += remainingToBorrow.rayDiv(
                poolIndexes[_poolTokenAddress].poolBorrowIndex
            ); // In adUnit.
            _borrowFromPool(underlyingToken, remainingToBorrow);
        }

        _updateBorrowerInDS(_poolTokenAddress, msg.sender);
        underlyingToken.safeTransfer(msg.sender, _amount);

        emit Borrowed(
            msg.sender,
            _poolTokenAddress,
            _amount,
            borrowBalanceInOf[_poolTokenAddress][msg.sender].onPool,
            borrowBalanceInOf[_poolTokenAddress][msg.sender].inP2P
        );
    }

    /// @dev Checks whether the user can borrow or not.
    /// @param _user The user to determine liquidity for.
    /// @param _poolTokenAddress The market to hypothetically borrow in.
    /// @param _borrowedAmount The amount of tokens to hypothetically borrow (in underlying).
    /// @return Whether the borrow is allowed or not.
    function _borrowAllowed(
        address _user,
        address _poolTokenAddress,
        uint256 _borrowedAmount
    ) internal returns (bool) {
        IPriceOracleGetter oracle = IPriceOracleGetter(addressesProvider.getPriceOracle());
        uint256 numberOfEnteredMarkets = enteredMarkets[_user].length;

        Types.AssetLiquidityData memory assetData;
        Types.LiquidityData memory liquidityData;

        for (uint256 i; i < numberOfEnteredMarkets; ) {
            address poolTokenEntered = enteredMarkets[_user][i];

            if (poolTokenEntered != _poolTokenAddress) _updateIndexes(poolTokenEntered);

            address underlyingAddress = IAToken(poolTokenEntered).UNDERLYING_ASSET_ADDRESS();
            assetData.underlyingPrice = oracle.getAssetPrice(underlyingAddress); // In ETH.
            (assetData.ltv, , , assetData.reserveDecimals, , ) = pool
            .getConfiguration(underlyingAddress)
            .getParams();

            assetData.tokenUnit = 10**assetData.reserveDecimals;
            assetData.collateralValue =
                (_getUserSupplyBalanceInOf(poolTokenEntered, _user) * assetData.underlyingPrice) /
                assetData.tokenUnit;
            liquidityData.debtValue +=
                (_getUserBorrowBalanceInOf(poolTokenEntered, _user) * assetData.underlyingPrice) /
                assetData.tokenUnit;
            liquidityData.maxLoanToValue += assetData.collateralValue.percentMul(assetData.ltv);

            if (_poolTokenAddress == poolTokenEntered && _borrowedAmount > 0) {
                liquidityData.debtValue +=
                    (_borrowedAmount * assetData.underlyingPrice) /
                    assetData.tokenUnit;
            }

            unchecked {
                ++i;
            }
        }

        return liquidityData.debtValue <= liquidityData.maxLoanToValue;
    }

    /// @dev Enters the user into the market if not already there.
    /// @param _user The address of the user to update.
    /// @param _poolTokenAddress The address of the market to check.
    function _enterMarketIfNeeded(address _poolTokenAddress, address _user) internal {
        if (!userMembership[_poolTokenAddress][_user]) {
            userMembership[_poolTokenAddress][_user] = true;
            enteredMarkets[_user].push(_poolTokenAddress);
        }
    }
}
