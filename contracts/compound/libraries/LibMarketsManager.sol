pragma solidity 0.8.13;
import {LibStorage, MarketsStorage, LastPoolIndexes} from "./LibStorage.sol";
import "./Types.sol";
import "../interfaces/compound/ICompound.sol";

library LibMarketsManager {
    /// @notice Emitted when the p2p exchange rates of a market are updated.
    /// @param _poolTokenAddress The address of the market updated.
    /// @param _newSupplyP2PExchangeRate The new value of the supply exchange rate from p2pUnit to underlying.
    /// @param _newBorrowP2PExchangeRate The new value of the borrow exchange rate from p2pUnit to underlying.
    event P2PExchangeRatesUpdated(
        address indexed _poolTokenAddress,
        uint256 _newSupplyP2PExchangeRate,
        uint256 _newBorrowP2PExchangeRate
    );

    function ms() internal pure returns (MarketsStorage storage) {
        return LibStorage.marketsStorage();
    }

    /// @notice Returns the updated P2P exchange rates.
    /// @param _poolTokenAddress The address of the market to update.
    /// @return newSupplyP2PExchangeRate The supply P2P exchange rate after udpate.
    /// @return newBorrowP2PExchangeRate The supply P2P exchange rate after udpate.
    function getUpdatedP2PExchangeRates(address _poolTokenAddress)
        internal
        view
        returns (uint256 newSupplyP2PExchangeRate, uint256 newBorrowP2PExchangeRate)
    {
        MarketsStorage storage s = ms();
        if (block.timestamp == s.lastUpdateBlockNumber[_poolTokenAddress]) {
            newSupplyP2PExchangeRate = s.supplyP2PExchangeRate[_poolTokenAddress];
            newBorrowP2PExchangeRate = s.borrowP2PExchangeRate[_poolTokenAddress];
        } else {
            ICToken poolToken = ICToken(_poolTokenAddress);
            LastPoolIndexes storage poolIndexes = s.lastPoolIndexes[_poolTokenAddress];

            Types.Params memory params = Types.Params(
                s.supplyP2PExchangeRate[_poolTokenAddress],
                s.borrowP2PExchangeRate[_poolTokenAddress],
                poolToken.exchangeRateStored(),
                poolToken.borrowIndex(),
                poolIndexes.lastSupplyPoolIndex,
                poolIndexes.lastBorrowPoolIndex,
                s.reserveFactor[_poolTokenAddress],
                s.positionsManager.deltas(_poolTokenAddress)
            );

            (newSupplyP2PExchangeRate, newBorrowP2PExchangeRate) = s
            .interestRates
            .computeP2PExchangeRates(params);
        }
    }

    /// @notice Updates the P2P exchange rates, taking into account the Second Percentage Yield values.
    /// @param _poolTokenAddress The address of the market to update.
    function updateP2PExchangeRates(address _poolTokenAddress) internal {
        MarketsStorage storage s = ms();
        if (block.timestamp > s.lastUpdateBlockNumber[_poolTokenAddress]) {
            ICToken poolToken = ICToken(_poolTokenAddress);
            s.lastUpdateBlockNumber[_poolTokenAddress] = block.timestamp;
            LastPoolIndexes storage poolIndexes = s.lastPoolIndexes[_poolTokenAddress];

            uint256 poolSupplyExchangeRate = poolToken.exchangeRateCurrent();
            uint256 poolBorrowExchangeRate = poolToken.borrowIndex();

            Types.Params memory params = Types.Params(
                s.supplyP2PExchangeRate[_poolTokenAddress],
                s.borrowP2PExchangeRate[_poolTokenAddress],
                poolSupplyExchangeRate,
                poolBorrowExchangeRate,
                poolIndexes.lastSupplyPoolIndex,
                poolIndexes.lastBorrowPoolIndex,
                s.reserveFactor[_poolTokenAddress],
                s.positionsManager.deltas(_poolTokenAddress)
            );

            (uint256 newSupplyP2PExchangeRate, uint256 newBorrowP2PExchangeRate) = s
            .interestRates
            .computeP2PExchangeRates(params);

            s.supplyP2PExchangeRate[_poolTokenAddress] = newSupplyP2PExchangeRate;
            s.borrowP2PExchangeRate[_poolTokenAddress] = newBorrowP2PExchangeRate;
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
