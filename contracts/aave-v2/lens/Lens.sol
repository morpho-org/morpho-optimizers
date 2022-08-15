// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./MarketsLens.sol";

/// @title Lens.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice This contract exposes an API to query on-chain data related to the Morpho Protocol, its markets and its users.
contract Lens is MarketsLens {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using WadRayMath for uint256;

    function initialize(address _morphoAddress) external initializer {
        morpho = IMorpho(_morphoAddress);
        addressesProvider = ILendingPoolAddressesProvider(morpho.addressesProvider());
        pool = ILendingPool(morpho.pool());
    }

    /// @notice Computes and returns the total distribution of supply through Morpho, using virtually updated indexes.
    /// @return p2pSupplyAmount The total supplied amount matched peer-to-peer, subtracting the supply delta (in ETH).
    /// @return poolSupplyAmount The total supplied amount on the underlying pool, adding the supply delta (in ETH).
    /// @return totalSupplyAmount The total amount supplied through Morpho (in ETH).
    function getTotalSupply()
        external
        view
        returns (
            uint256 p2pSupplyAmount,
            uint256 poolSupplyAmount,
            uint256 totalSupplyAmount
        )
    {
        address[] memory markets = morpho.getMarketsCreated();
        IPriceOracleGetter oracle = IPriceOracleGetter(addressesProvider.getPriceOracle());

        uint256 nbMarkets = markets.length;
        for (uint256 i; i < nbMarkets; ) {
            address _poolTokenAddress = markets[i];

            (uint256 marketP2PSupplyAmount, uint256 marketPoolSupplyAmount) = getTotalMarketSupply(
                _poolTokenAddress
            );

            address underlyingAddress = IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS();
            uint256 underlyingPrice = oracle.getAssetPrice(underlyingAddress);
            (, , , uint256 reserveDecimals, ) = pool
            .getConfiguration(underlyingAddress)
            .getParamsMemory();

            uint256 tokenUnit = 10**reserveDecimals;
            p2pSupplyAmount += (marketP2PSupplyAmount * underlyingPrice) / tokenUnit;
            poolSupplyAmount += (marketPoolSupplyAmount * underlyingPrice) / tokenUnit;

            unchecked {
                ++i;
            }
        }

        totalSupplyAmount = p2pSupplyAmount + poolSupplyAmount;
    }

    /// @notice Computes and returns the total distribution of borrows through Morpho, using virtually updated indexes.
    /// @return p2pBorrowAmount The total borrowed amount matched peer-to-peer, subtracting the borrow delta (in ETH).
    /// @return poolBorrowAmount The total borrowed amount on the underlying pool, adding the borrow delta (in ETH).
    /// @return totalBorrowAmount The total amount borrowed through Morpho (in ETH).
    function getTotalBorrow()
        external
        view
        returns (
            uint256 p2pBorrowAmount,
            uint256 poolBorrowAmount,
            uint256 totalBorrowAmount
        )
    {
        address[] memory markets = morpho.getMarketsCreated();
        IPriceOracleGetter oracle = IPriceOracleGetter(addressesProvider.getPriceOracle());

        uint256 nbMarkets = markets.length;
        for (uint256 i; i < nbMarkets; ) {
            address _poolTokenAddress = markets[i];

            (uint256 marketP2PBorrowAmount, uint256 marketPoolBorrowAmount) = getTotalMarketBorrow(
                _poolTokenAddress
            );

            address underlyingAddress = IAToken(_poolTokenAddress).UNDERLYING_ASSET_ADDRESS();
            uint256 underlyingPrice = oracle.getAssetPrice(underlyingAddress);
            (, , , uint256 reserveDecimals, ) = pool
            .getConfiguration(underlyingAddress)
            .getParamsMemory();

            uint256 tokenUnit = 10**reserveDecimals;
            p2pBorrowAmount += (marketP2PBorrowAmount * underlyingPrice) / tokenUnit;
            poolBorrowAmount += (marketPoolBorrowAmount * underlyingPrice) / tokenUnit;

            unchecked {
                ++i;
            }
        }

        totalBorrowAmount = p2pBorrowAmount + poolBorrowAmount;
    }
}
