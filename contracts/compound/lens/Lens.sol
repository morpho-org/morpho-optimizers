// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./RewardsLens.sol";

/// @title Lens.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice This contract exposes an API to query on-chain data related to the Morpho Protocol, its markets and its users.
contract Lens is RewardsLens {
    using CompoundMath for uint256;

    function initialize(address _morphoAddress) external initializer {
        morpho = IMorpho(_morphoAddress);
        comptroller = IComptroller(morpho.comptroller());
        rewardsManager = IRewardsManager(morpho.rewardsManager());
    }

    /// @notice Computes and returns the total distribution of supply through Morpho, using virtually updated indexes.
    /// @return p2pSupplyAmount The total supplied amount matched peer-to-peer, without the supply delta (in USD, 18 decimals).
    /// @return poolSupplyAmount The total supplied amount on the underlying pool, including the supply delta (in USD, 18 decimals).
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
            address _poolTokenAddress = markets[i];

            (uint256 marketP2PSupplyAmount, uint256 marketPoolSupplyAmount) = getTotalMarketSupply(
                _poolTokenAddress,
                true
            );

            uint256 underlyingPrice = oracle.getUnderlyingPrice(_poolTokenAddress);
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
    /// @return p2pBorrowAmount The total borrowed amount matched peer-to-peer, without the borrow delta (in USD, 18 decimals).
    /// @return poolBorrowAmount The total borrowed amount on the underlying pool, including the borrow delta (in USD, 18 decimals).
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
            address _poolTokenAddress = markets[i];

            (uint256 marketP2PBorrowAmount, uint256 marketPoolBorrowAmount) = getTotalMarketBorrow(
                _poolTokenAddress,
                true
            );

            uint256 underlyingPrice = oracle.getUnderlyingPrice(_poolTokenAddress);
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
