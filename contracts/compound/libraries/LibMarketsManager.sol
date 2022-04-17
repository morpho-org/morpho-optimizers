pragma solidity 0.8.13;
import {LibStorage, MarketsStorage, LastPoolIndexes} from "./LibStorage.sol";
import "./Types.sol";
import "../interfaces/compound/ICompound.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

library LibMarketsManager {
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

    /// @notice Thrown when the market is already created.
    error MarketAlreadyCreated();

    /// @notice Thrown when the creation of a market failed on Compound.
    error MarketCreationFailedOnCompound();

    function ms() internal pure returns (MarketsStorage storage) {
        return LibStorage.marketsStorage();
    }

    /// @notice Creates a new market to borrow/supply in.
    /// @param _poolTokenAddress The pool token address of the given market.
    function createMarket(address _poolTokenAddress) internal {
        MarketsStorage storage s = ms();
        address[] memory marketToEnter = new address[](1);
        marketToEnter[0] = _poolTokenAddress;
        uint256[] memory results = ms().positionsManager.createMarket(_poolTokenAddress);
        if (results[0] != 0) revert MarketCreationFailedOnCompound();

        if (s.isCreated[_poolTokenAddress]) revert MarketAlreadyCreated();
        ms().isCreated[_poolTokenAddress] = true;

        ICToken poolToken = ICToken(_poolTokenAddress);
        ms().lastUpdateBlockNumber[_poolTokenAddress] = block.number;

        // Same initial exchange rate as Compound.
        uint256 initialExchangeRate;
        if (_poolTokenAddress == ms().positionsManager.cEth()) initialExchangeRate = 2e26;
        else
            initialExchangeRate =
                2 *
                10**(16 + IERC20Metadata(poolToken.underlying()).decimals() - 8);
        ms().supplyP2PExchangeRate[_poolTokenAddress] = initialExchangeRate;
        ms().borrowP2PExchangeRate[_poolTokenAddress] = initialExchangeRate;

        LastPoolIndexes storage poolIndexes = ms().lastPoolIndexes[_poolTokenAddress];

        poolIndexes.lastSupplyPoolIndex = poolToken.exchangeRateCurrent();
        poolIndexes.lastBorrowPoolIndex = poolToken.borrowIndex();

        ms().marketsCreated.push(_poolTokenAddress);
        emit MarketCreated(_poolTokenAddress);
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
        if (block.timestamp == ms().lastUpdateBlockNumber[_poolTokenAddress]) {
            newSupplyP2PExchangeRate = ms().supplyP2PExchangeRate[_poolTokenAddress];
            newBorrowP2PExchangeRate = ms().borrowP2PExchangeRate[_poolTokenAddress];
        } else {
            ICToken poolToken = ICToken(_poolTokenAddress);
            LastPoolIndexes storage poolIndexes = ms().lastPoolIndexes[_poolTokenAddress];

            Types.Params memory params = Types.Params(
                ms().supplyP2PExchangeRate[_poolTokenAddress],
                ms().borrowP2PExchangeRate[_poolTokenAddress],
                poolToken.exchangeRateStored(),
                poolToken.borrowIndex(),
                poolIndexes.lastSupplyPoolIndex,
                poolIndexes.lastBorrowPoolIndex,
                ms().reserveFactor[_poolTokenAddress],
                ms().positionsManager.deltas(_poolTokenAddress)
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
        if (block.timestamp > ms().lastUpdateBlockNumber[_poolTokenAddress]) {
            ICToken poolToken = ICToken(_poolTokenAddress);
            ms().lastUpdateBlockNumber[_poolTokenAddress] = block.timestamp;
            LastPoolIndexes storage poolIndexes = ms().lastPoolIndexes[_poolTokenAddress];

            uint256 poolSupplyExchangeRate = poolToken.exchangeRateCurrent();
            uint256 poolBorrowExchangeRate = poolToken.borrowIndex();

            Types.Params memory params = Types.Params(
                ms().supplyP2PExchangeRate[_poolTokenAddress],
                ms().borrowP2PExchangeRate[_poolTokenAddress],
                poolSupplyExchangeRate,
                poolBorrowExchangeRate,
                poolIndexes.lastSupplyPoolIndex,
                poolIndexes.lastBorrowPoolIndex,
                ms().reserveFactor[_poolTokenAddress],
                ms().positionsManager.deltas(_poolTokenAddress)
            );

            (uint256 newSupplyP2PExchangeRate, uint256 newBorrowP2PExchangeRate) = s
            .interestRates
            .computeP2PExchangeRates(params);

            ms().supplyP2PExchangeRate[_poolTokenAddress] = newSupplyP2PExchangeRate;
            ms().borrowP2PExchangeRate[_poolTokenAddress] = newBorrowP2PExchangeRate;
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
