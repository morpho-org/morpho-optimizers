// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../interfaces/compound/ICompound.sol";

import {LibStorage, MarketsStorage, PositionsStorage} from "./LibStorage.sol";
import "./LibInterestRates.sol";
import "./CompoundMath.sol";
import "./Types.sol";

library LibMarketsManager {
    using CompoundMath for uint256;

    /// EVENTS ///

    /// @notice Emitted when a new market is created.
    /// @param _poolTokenAddress The address of the market that has been created.
    event MarketCreated(address _poolTokenAddress);

    /// @notice Emitted when the p2p exchange rates of a market are updated.
    /// @param _poolTokenAddress The address of the market updated.
    /// @param _newSupplyP2PExchangeRate The new value of the supply exchange rate from p2pUnit to underlying.
    /// @param _newBorrowP2PExchangeRate The new value of the borrow exchange rate from p2pUnit to underlying.
    event P2PExchangeRatesUpdated(
        address indexed _poolTokenAddress,
        uint256 _newSupplyP2PExchangeRate,
        uint256 _newBorrowP2PExchangeRate
    );

    /// ERRORS ///

    /// @notice Thrown when the market is already created.
    error MarketAlreadyCreated();

    /// @notice Thrown when the creation of a market failed on Compound.
    error MarketCreationFailedOnCompound();

    /// STORAGE GETTERS ///

    function ms() internal pure returns (MarketsStorage storage) {
        return LibStorage.marketsStorage();
    }

    function ps() internal pure returns (PositionsStorage storage) {
        return LibStorage.positionsStorage();
    }

    /// INTERNAL ///

    /// @dev Creates a new market to borrow/supply in.
    /// @param _poolTokenAddress The pool token address of the given market.
    function createMarket(address _poolTokenAddress) internal {
        MarketsStorage storage m = ms();
        address[] memory marketToEnter = new address[](1);
        marketToEnter[0] = _poolTokenAddress;
        uint256[] memory results = m.comptroller.enterMarkets(marketToEnter);
        if (results[0] != 0) revert MarketCreationFailedOnCompound();

        if (m.isCreated[_poolTokenAddress]) revert MarketAlreadyCreated();
        m.isCreated[_poolTokenAddress] = true;

        ICToken poolToken = ICToken(_poolTokenAddress);
        m.lastUpdateBlockNumber[_poolTokenAddress] = block.number;

        // Same initial exchange rate as Compound.
        uint256 initialExchangeRate;
        if (_poolTokenAddress == ps().cEth) initialExchangeRate = 2e26;
        else
            initialExchangeRate =
                2 *
                10**(16 + IERC20Metadata(poolToken.underlying()).decimals() - 8);
        m.supplyP2PExchangeRate[_poolTokenAddress] = initialExchangeRate;
        m.borrowP2PExchangeRate[_poolTokenAddress] = initialExchangeRate;

        Types.LastPoolIndexes storage poolIndexes = m.lastPoolIndexes[_poolTokenAddress];

        poolIndexes.lastSupplyPoolIndex = poolToken.exchangeRateCurrent();
        poolIndexes.lastBorrowPoolIndex = poolToken.borrowIndex();

        m.marketsCreated.push(_poolTokenAddress);
        emit MarketCreated(_poolTokenAddress);
    }

    /// @dev Returns the updated P2P exchange rates.
    /// @param _poolTokenAddress The address of the market to update.
    /// @return newSupplyP2PExchangeRate The supply P2P exchange rate after udpate.
    /// @return newBorrowP2PExchangeRate The supply P2P exchange rate after udpate.
    function getUpdatedP2PExchangeRates(address _poolTokenAddress)
        internal
        view
        returns (uint256 newSupplyP2PExchangeRate, uint256 newBorrowP2PExchangeRate)
    {
        MarketsStorage storage m = ms();
        if (block.timestamp == m.lastUpdateBlockNumber[_poolTokenAddress]) {
            newSupplyP2PExchangeRate = m.supplyP2PExchangeRate[_poolTokenAddress];
            newBorrowP2PExchangeRate = m.borrowP2PExchangeRate[_poolTokenAddress];
        } else {
            ICToken poolToken = ICToken(_poolTokenAddress);
            Types.LastPoolIndexes storage poolIndexes = m.lastPoolIndexes[_poolTokenAddress];

            Types.Params memory params = Types.Params(
                m.supplyP2PExchangeRate[_poolTokenAddress],
                m.borrowP2PExchangeRate[_poolTokenAddress],
                poolToken.exchangeRateStored(),
                poolToken.borrowIndex(),
                poolIndexes.lastSupplyPoolIndex,
                poolIndexes.lastBorrowPoolIndex,
                m.reserveFactor[_poolTokenAddress],
                ps().deltas[_poolTokenAddress]
            );

            (newSupplyP2PExchangeRate, newBorrowP2PExchangeRate) = LibInterestRates
            .computeP2PExchangeRates(params);
        }
    }

    /// @dev Returns the updated supply P2P exchange rate.
    /// @param _poolTokenAddress The address of the market to update.
    /// @return newSupplyP2PExchangeRate The supply P2P exchange rate after udpate.
    function getUpdatedSupplyP2PExchangeRate(address _poolTokenAddress)
        internal
        view
        returns (uint256 newSupplyP2PExchangeRate)
    {
        MarketsStorage storage m = ms();
        if (block.timestamp == m.lastUpdateBlockNumber[_poolTokenAddress])
            newSupplyP2PExchangeRate = m.supplyP2PExchangeRate[_poolTokenAddress];
        else {
            ICToken poolToken = ICToken(_poolTokenAddress);
            Types.LastPoolIndexes storage poolIndexes = m.lastPoolIndexes[_poolTokenAddress];

            Types.Params memory params = Types.Params(
                m.supplyP2PExchangeRate[_poolTokenAddress],
                m.borrowP2PExchangeRate[_poolTokenAddress],
                poolToken.exchangeRateStored(),
                poolToken.borrowIndex(),
                poolIndexes.lastSupplyPoolIndex,
                poolIndexes.lastBorrowPoolIndex,
                m.reserveFactor[_poolTokenAddress],
                ps().deltas[_poolTokenAddress]
            );

            newSupplyP2PExchangeRate = LibInterestRates.computeSupplyP2PExchangeRate(params);
        }
    }

    /// @dev Returns the updated borrow P2P exchange rate.
    /// @param _poolTokenAddress The address of the market to update.
    /// @return newBorrowP2PExchangeRate The borrow P2P exchange rate after udpate.
    function getUpdatedBorrowP2PExchangeRate(address _poolTokenAddress)
        internal
        view
        returns (uint256 newBorrowP2PExchangeRate)
    {
        MarketsStorage storage m = ms();
        if (block.timestamp == m.lastUpdateBlockNumber[_poolTokenAddress])
            newBorrowP2PExchangeRate = m.borrowP2PExchangeRate[_poolTokenAddress];
        else {
            ICToken poolToken = ICToken(_poolTokenAddress);
            Types.LastPoolIndexes storage poolIndexes = m.lastPoolIndexes[_poolTokenAddress];

            Types.Params memory params = Types.Params(
                m.supplyP2PExchangeRate[_poolTokenAddress],
                m.borrowP2PExchangeRate[_poolTokenAddress],
                poolToken.exchangeRateStored(),
                poolToken.borrowIndex(),
                poolIndexes.lastSupplyPoolIndex,
                poolIndexes.lastBorrowPoolIndex,
                m.reserveFactor[_poolTokenAddress],
                ps().deltas[_poolTokenAddress]
            );

            newBorrowP2PExchangeRate = LibInterestRates.computeBorrowP2PExchangeRate(params);
        }
    }

    /// @dev Updates the P2P exchange rates, taking into account the Second Percentage Yield values.
    /// @param _poolTokenAddress The address of the market to update.
    function updateP2PExchangeRates(address _poolTokenAddress) internal {
        MarketsStorage storage m = ms();
        if (block.timestamp > m.lastUpdateBlockNumber[_poolTokenAddress]) {
            ICToken poolToken = ICToken(_poolTokenAddress);
            m.lastUpdateBlockNumber[_poolTokenAddress] = block.timestamp;
            Types.LastPoolIndexes storage poolIndexes = m.lastPoolIndexes[_poolTokenAddress];

            uint256 poolSupplyExchangeRate = poolToken.exchangeRateCurrent();
            uint256 poolBorrowExchangeRate = poolToken.borrowIndex();

            Types.Params memory params = Types.Params(
                m.supplyP2PExchangeRate[_poolTokenAddress],
                m.borrowP2PExchangeRate[_poolTokenAddress],
                poolSupplyExchangeRate,
                poolBorrowExchangeRate,
                poolIndexes.lastSupplyPoolIndex,
                poolIndexes.lastBorrowPoolIndex,
                m.reserveFactor[_poolTokenAddress],
                ps().deltas[_poolTokenAddress]
            );

            (uint256 newSupplyP2PExchangeRate, uint256 newBorrowP2PExchangeRate) = LibInterestRates
            .computeP2PExchangeRates(params);

            m.supplyP2PExchangeRate[_poolTokenAddress] = newSupplyP2PExchangeRate;
            m.borrowP2PExchangeRate[_poolTokenAddress] = newBorrowP2PExchangeRate;
            poolIndexes.lastSupplyPoolIndex = poolSupplyExchangeRate;
            poolIndexes.lastBorrowPoolIndex = poolBorrowExchangeRate;

            emit P2PExchangeRatesUpdated(
                _poolTokenAddress,
                newSupplyP2PExchangeRate,
                newBorrowP2PExchangeRate
            );
        }
    }
}
