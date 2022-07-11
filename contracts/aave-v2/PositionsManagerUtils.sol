// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import {IVariableDebtToken} from "./interfaces/aave/IVariableDebtToken.sol";

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
    using PercentageMath for uint256;

    /// COMMON EVENTS ///

    /// @notice Emitted when the peer-to-peer borrow delta is updated.
    /// @param _poolTokenAddress The address of the market.
    /// @param _p2pBorrowDelta The peer-to-peer borrow delta after update.
    event P2PBorrowDeltaUpdated(address indexed _poolTokenAddress, uint256 _p2pBorrowDelta);

    /// @notice Emitted when the peer-to-peer supply delta is updated.
    /// @param _poolTokenAddress The address of the market.
    /// @param _p2pSupplyDelta The peer-to-peer supply delta after update.
    event P2PSupplyDeltaUpdated(address indexed _poolTokenAddress, uint256 _p2pSupplyDelta);

    /// @notice Emitted when the supply and peer-to-peer borrow amounts are updated.
    /// @param _poolTokenAddress The address of the market.
    /// @param _p2pSupplyAmount The peer-to-peer supply amount after update.
    /// @param _p2pBorrowAmount The peer-to-peer borrow amount after update.
    event P2PAmountsUpdated(
        address indexed _poolTokenAddress,
        uint256 _p2pSupplyAmount,
        uint256 _p2pBorrowAmount
    );

    /// COMMON ERRORS ///

    /// @notice Thrown when the address is zero.
    error AddressIsZero();

    /// @notice Thrown when the amount is equal to 0.
    error AmountIsZero();

    /// POOL INTERACTION ///

    /// @dev Supplies underlying tokens to Aave.
    /// @param _underlyingToken The underlying token of the market to supply to.
    /// @param _amount The amount of token (in underlying).
    function _supplyToPool(ERC20 _underlyingToken, uint256 _amount) internal {
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
    function _repayToPool(ERC20 _underlyingToken, uint256 _amount) internal {
        if (
            _amount == 0 ||
            IVariableDebtToken(
                pool.getReserveData(address(_underlyingToken)).variableDebtTokenAddress
            ).scaledBalanceOf(address(this)) ==
            0
        ) return;

        pool.repay(address(_underlyingToken), _amount, VARIABLE_INTEREST_MODE, address(this)); // Reverts if debt is 0.
    }

    /// @dev Gets all markets of the user.
    /// @param _user The user address.
    /// @return markets The markets the user is participating in.
    function _userMarkets(address _user) internal view returns (address[] memory markets) {
        markets = new address[](marketsCreated.length);
        uint256 marketLength;
        for (uint256 i; i < markets.length; i++) {
            if (_isSupplyingOrBorrowing(_user, marketsCreated[i])) {
                markets[marketLength] = marketsCreated[i];
                ++marketLength;
            }
        }

        // Resize the array for return
        assembly {
            mstore(markets, marketLength)
        }
    }

    /// @dev Calculates the total value of the collateral, debt, and LTV/LT value depending on the calculation type.
    /// @param _user The user address.
    /// @param _poolTokens The pool tokens to calculate the values for.
    /// @param _poolTokenAddress The pool token that is being borrowed or withdrawn.
    /// @param _amount The amount that is being borrowed or withdrawn.
    /// @param _calculationType The calculation type to use.
    /// @return collateralValue The total value of the collateral.
    /// @return debtValue The total value of the debt.
    /// @return calculatedMax The max value of the LTV/LT or none depending on the calculation type.
    function _collateralAndDebtValues(
        address _user,
        address[] memory _poolTokens,
        address _poolTokenAddress,
        uint256 _amount,
        Types.LoanCalculationType _calculationType
    )
        internal
        view
        returns (
            uint256 collateralValue,
            uint256 debtValue,
            uint256 calculatedMax
        )
    {
        IPriceOracleGetter oracle = IPriceOracleGetter(addressesProvider.getPriceOracle());
        address[] memory underlyings = new address[](_poolTokens.length);
        uint256[] memory underlyingPrices = new uint256[](_poolTokens.length);

        for (uint256 i; i < _poolTokens.length; i++) {
            underlyings[i] = IAToken(_poolTokens[i]).UNDERLYING_ASSET_ADDRESS();
            underlyingPrices[i] = oracle.getAssetPrice(underlyings[i]);
        }

        Types.AssetLiquidityData memory assetData;

        for (uint256 i; i < _poolTokens.length; i++) {
            (assetData.ltv, assetData.liquidationThreshold, , assetData.reserveDecimals, ) = pool
            .getConfiguration(underlyings[i])
            .getParamsMemory();

            assetData.tokenUnit = 10**assetData.reserveDecimals;

            debtValue += _debtValue(
                _poolTokens[i],
                _user,
                underlyingPrices[i],
                assetData.tokenUnit
            );

            // Cache current asset collateral value
            uint256 assetCollateralValue = _collateralValue(
                _poolTokens[i],
                _user,
                underlyingPrices[i],
                assetData.tokenUnit
            );
            collateralValue += assetCollateralValue;

            // Calculate LTV for borrow
            if (_calculationType == Types.LoanCalculationType.LOAN_TO_VALUE) {
                calculatedMax += assetCollateralValue.percentMul(assetData.ltv);
                // Add debt value for borrowed token
                if (_poolTokenAddress == _poolTokens[i])
                    debtValue += (_amount * underlyingPrices[i]) / assetData.tokenUnit;
            }
            // Calculate LT for withdraw
            else if (_calculationType == Types.LoanCalculationType.LIQUIDATION_THRESHOLD) {
                calculatedMax += assetCollateralValue.percentMul(assetData.liquidationThreshold);
                // Subtract from liquidation threshold value for withdrawn token
                if (_poolTokenAddress == _poolTokens[i])
                    calculatedMax -= ((_amount * underlyingPrices[i]) / assetData.tokenUnit)
                    .percentMul(assetData.liquidationThreshold);
            }
        }
    }

    /// @dev Calculates the value of the collateral.
    /// @param _poolToken The pool token to calculate the value for.
    /// @param _user The user address.
    /// @param _underlyingPrice The underlying price.
    /// @param _tokenUnit The token unit.
    function _collateralValue(
        address _poolToken,
        address _user,
        uint256 _underlyingPrice,
        uint256 _tokenUnit
    ) internal view returns (uint256 collateralValue) {
        if (_isSupplying(_user, _poolToken))
            collateralValue =
                (_getUserSupplyBalanceInOf(_poolToken, _user) * _underlyingPrice) /
                _tokenUnit;
    }

    /// @dev Calculates the value of the debt.
    /// @param _poolToken The pool token to calculate the value for.
    /// @param _user The user address.
    /// @param _underlyingPrice The underlying price.
    /// @param _tokenUnit The token unit.
    function _debtValue(
        address _poolToken,
        address _user,
        uint256 _underlyingPrice,
        uint256 _tokenUnit
    ) internal view returns (uint256 debtValue) {
        if (_isBorrowing(_user, _poolToken))
            debtValue =
                (_getUserBorrowBalanceInOf(_poolToken, _user) * _underlyingPrice) /
                _tokenUnit;
    }
}
