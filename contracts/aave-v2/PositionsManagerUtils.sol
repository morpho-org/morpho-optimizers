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

    /// LIQUIDITY COMPUTATION

    /// @dev Returns the liquidity data of a user.
    /// @param _user The user to determine the position.
    /// @param _poolTokenAddress The market to hypothetically borrow and withdraw from.
    /// @param _borrowedAmount The amount of tokens to hypothetically borrow (in underlying).
    /// @param _withdrawnAmount The number of tokens to hypothetically withdraw (in underlying).
    /// @return liquidityData The liquidaty data of the user after borrow and withdraw.
    function _getUserLiquidityData(
        address _user,
        address _poolTokenAddress,
        uint256 _borrowedAmount,
        uint256 _withdrawnAmount
    ) internal returns (Types.LiquidityData memory liquidityData) {
        IPriceOracleGetter oracle = IPriceOracleGetter(addressesProvider.getPriceOracle());
        uint256 numberOfMarketsCreated = marketsCreated.length;
        Types.AssetLiquidityData memory assetData;

        for (uint256 i; i < numberOfMarketsCreated; ) {
            address poolToken = marketsCreated[i];

            if (_isSupplyingOrBorrowing(_user, poolToken)) {
                if (poolToken != _poolTokenAddress) _updateIndexes(poolToken);

                address underlyingAddress = IAToken(poolToken).UNDERLYING_ASSET_ADDRESS();
                assetData.underlyingPrice = oracle.getAssetPrice(underlyingAddress); // In ETH.
                (
                    assetData.ltv,
                    assetData.liquidationThreshold,
                    ,
                    assetData.reserveDecimals,

                ) = pool.getConfiguration(underlyingAddress).getParamsMemory();
                assetData.tokenUnit = 10**assetData.reserveDecimals;

                if (_isBorrowing(_user, poolToken))
                    liquidityData.debtValue +=
                        (_getUserBorrowBalanceInOf(poolToken, _user) * assetData.underlyingPrice) /
                        assetData.tokenUnit;

                if (_isSupplying(_user, poolToken)) {
                    assetData.collateralValue =
                        (_getUserSupplyBalanceInOf(poolToken, _user) * assetData.underlyingPrice) /
                        assetData.tokenUnit;

                    liquidityData.collateralValue += assetData.collateralValue;

                    liquidityData.liquidationThresholdValue += assetData.collateralValue.percentMul(
                        assetData.liquidationThreshold
                    );

                    liquidityData.maxLoanToValue += assetData.collateralValue.percentMul(
                        assetData.ltv
                    );
                }

                if (_poolTokenAddress == poolToken && _borrowedAmount > 0)
                    liquidityData.debtValue +=
                        (_borrowedAmount * assetData.underlyingPrice) /
                        assetData.tokenUnit;

                if (_poolTokenAddress == poolToken && _withdrawnAmount > 0)
                    liquidityData.liquidationThresholdValue -= ((_withdrawnAmount *
                        assetData.underlyingPrice) / assetData.tokenUnit)
                    .percentMul(assetData.liquidationThreshold);
            }

            unchecked {
                ++i;
            }
        }
    }
}
