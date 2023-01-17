// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.13;

import "./RewardsLens.sol";

/// @title Lens.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice This contract exposes an API to query on-chain data related to the Morpho Protocol, its markets and its users.
contract Lens is RewardsLens {
    using CompoundMath for uint256;

    /// CONSTRUCTOR ///

    /// @notice Constructs the contract.
    /// @param _lensExtension The address of the Lens extension.
    constructor(address _lensExtension) LensStorage(_lensExtension) {}

    /// EXTERNAL ///

    /// @notice Computes and returns the total distribution of supply through Morpho, using virtually updated indexes.
    /// @return p2pSupplyAmount The total supplied amount matched peer-to-peer, subtracting the supply delta (in USD, 18 decimals).
    /// @return poolSupplyAmount The total supplied amount on the underlying pool, adding the supply delta (in USD, 18 decimals).
    /// @return totalSupplyAmount The total amount supplied through Morpho (in USD, 18 decimals).
    function getTotalSupply()
        external
        view
        returns (
            uint256 p2pSupplyAmount,
            uint256 poolSupplyAmount,
            uint256 totalSupplyAmount
        )
    {
        address[] memory markets = morpho.getAllMarkets();
        ICompoundOracle oracle = ICompoundOracle(comptroller.oracle());

        uint256 nbMarkets = markets.length;
        for (uint256 i; i < nbMarkets; ) {
            address _poolToken = markets[i];

            (uint256 marketP2PSupplyAmount, uint256 marketPoolSupplyAmount) = getTotalMarketSupply(
                _poolToken
            );

            uint256 underlyingPrice = oracle.getUnderlyingPrice(_poolToken);
            if (underlyingPrice == 0) revert CompoundOracleFailed();

            p2pSupplyAmount += marketP2PSupplyAmount.mul(underlyingPrice);
            poolSupplyAmount += marketPoolSupplyAmount.mul(underlyingPrice);

            unchecked {
                ++i;
            }
        }

        totalSupplyAmount = p2pSupplyAmount + poolSupplyAmount;
    }

    /// @notice Computes and returns the total distribution of borrows through Morpho, using virtually updated indexes.
    /// @return p2pBorrowAmount The total borrowed amount matched peer-to-peer, subtracting the borrow delta (in USD, 18 decimals).
    /// @return poolBorrowAmount The total borrowed amount on the underlying pool, adding the borrow delta (in USD, 18 decimals).
    /// @return totalBorrowAmount The total amount borrowed through Morpho (in USD, 18 decimals).
    function getTotalBorrow()
        external
        view
        returns (
            uint256 p2pBorrowAmount,
            uint256 poolBorrowAmount,
            uint256 totalBorrowAmount
        )
    {
        address[] memory markets = morpho.getAllMarkets();
        ICompoundOracle oracle = ICompoundOracle(comptroller.oracle());

        uint256 nbMarkets = markets.length;
        for (uint256 i; i < nbMarkets; ) {
            address _poolToken = markets[i];

            (uint256 marketP2PBorrowAmount, uint256 marketPoolBorrowAmount) = getTotalMarketBorrow(
                _poolToken
            );

            uint256 underlyingPrice = oracle.getUnderlyingPrice(_poolToken);
            if (underlyingPrice == 0) revert CompoundOracleFailed();

            p2pBorrowAmount += marketP2PBorrowAmount.mul(underlyingPrice);
            poolBorrowAmount += marketPoolBorrowAmount.mul(underlyingPrice);

            unchecked {
                ++i;
            }
        }

        totalBorrowAmount = p2pBorrowAmount + poolBorrowAmount;
    }
}
