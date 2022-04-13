// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import {IAToken} from "./interfaces/aave/IAToken.sol";
import "./interfaces/aave/ILendingPool.sol";
import "./interfaces/IPositionsManagerForAave.sol";
import "./interfaces/IMarketsManagerForAave.sol";
import "./interfaces/IInterestRates.sol";

import {ReserveConfiguration} from "./libraries/aave/ReserveConfiguration.sol";
import "./libraries/Math.sol";
import "./libraries/Types.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/// @title MarketsManagerForAave
/// @notice Smart contract managing the markets used by a MorphoPositionsManagerForAave contract, an other contract interacting with Aave or a fork of Aave.
contract MarketsManagerForAave is IMarketsManagerForAave, OwnableUpgradeable {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using Math for uint256;

    /// STRUCTS ///

    struct LastPoolIndexes {
        uint256 lastSupplyPoolIndex; // Last supply pool index (normalized income) stored.
        uint256 lastBorrowPoolIndex; // Last borrow pool index (normalized variable debt) stored.
    }

    struct Vars {
        uint256 shareOfTheDelta;
        uint256 poolIncrease;
        Types.Delta delta;
    }

    /// STORAGE ///

    uint16 public constant MAX_BASIS_POINTS = 10_000; // 100% (in basis point).
    uint256 public constant SECONDS_PER_YEAR = 365 days; // The number of seconds in one year.
    address[] public marketsCreated; // Keeps track of the created markets.
    mapping(address => bool) public override isCreated; // Whether or not this market is created.
    mapping(address => uint256) public reserveFactor; // Proportion of the interest earned by users sent to the DAO for each market, in basis point (100% = 10000). The default value is 0.
    mapping(address => uint256) public override supplyP2PExchangeRate; // Current exchange rate from supply p2pUnit to underlying (in ray).
    mapping(address => uint256) public override borrowP2PExchangeRate; // Current exchange rate from borrow p2pUnit to underlying (in ray).
    mapping(address => uint256) public override exchangeRatesLastUpdateTimestamp; // The last time the P2P exchange rates were updated.
    mapping(address => LastPoolIndexes) public lastPoolIndexes; // Last pool index stored.
    mapping(address => bool) public override noP2P; // Whether to put users on pool or not for the given market.

    IPositionsManagerForAave public positionsManager;
    IInterestRates public interestRates;
    ILendingPool public lendingPool;

    /// EVENTS ///

    /// @notice Emitted when a new market is created.
    /// @param _marketAddress The address of the market that has been created.
    event MarketCreated(address indexed _marketAddress);

    /// @notice Emitted when the `positionsManager` is set.
    /// @param _positionsManager The address of the `positionsManager`.
    event PositionsManagerSet(address indexed _positionsManager);

    /// @notice Emitted when the `interestRates` is set.
    /// @param _interestRates The address of the `interestRates`.
    event InterestRatesSet(address _interestRates);

    /// @notice Emitted when a `noP2P` variable is set.
    /// @param _marketAddress The address of the market to set.
    /// @param _noP2P The new value of `_noP2P` adopted.
    event NoP2PSet(address indexed _marketAddress, bool _noP2P);

    /// @notice Emitted when the p2p exchange rates of a market are updated.
    /// @param _marketAddress The address of the market updated.
    /// @param _newSupplyP2PExchangeRate The new value of the supply exchange rate from p2pUnit to underlying.
    /// @param _newBorrowP2PExchangeRate The new value of the borrow exchange rate from p2pUnit to underlying.
    event P2PExchangeRatesUpdated(
        address indexed _marketAddress,
        uint256 _newSupplyP2PExchangeRate,
        uint256 _newBorrowP2PExchangeRate
    );

    /// @notice Emitted when the `reserveFactor` is set.
    /// @param _marketAddress The address of the market set.
    /// @param _newValue The new value of the `reserveFactor`.
    event ReserveFactorSet(address indexed _marketAddress, uint256 _newValue);

    /// ERRORS ///

    /// @notice Thrown when the market is not created yet.
    error MarketNotCreated();

    /// @notice Thrown when the market is not listed on Aave.
    error MarketIsNotListedOnAave();

    /// @notice Thrown when the market is already created.
    error MarketAlreadyCreated();

    /// @notice Thrown when the positionsManager is already set.
    error PositionsManagerAlreadySet();

    /// @notice Thrown when only the positions manager can call the function.
    error OnlyPositionsManager();

    /// MODIFIERS ///

    /// @notice Prevents to update a market not created yet.
    /// @param _marketAddress The address of the market to check.
    modifier isMarketCreated(address _marketAddress) {
        if (!isCreated[_marketAddress]) revert MarketNotCreated();
        _;
    }

    /// @notice Prevents a user to call function only allowed for `positionsManager` owner.
    modifier onlyPositionsManager() {
        if (msg.sender != address(positionsManager)) revert OnlyPositionsManager();
        _;
    }

    /// UPGRADE ///

    /// @notice Initializes the MarketsManagerForAave contract.
    /// @param _lendingPool The `lendingPool`.
    /// @param _interestRates The `interestRates`.
    function initialize(ILendingPool _lendingPool, IInterestRates _interestRates)
        external
        initializer
    {
        __Ownable_init();

        lendingPool = _lendingPool;
        interestRates = _interestRates;
    }

    /// EXTERNAL ///

    /// @notice Sets the `positionsManager` to interact with Aave.
    /// @param _positionsManager The address of the `positionsManager`.
    function setPositionsManager(address _positionsManager) external onlyOwner {
        if (address(positionsManager) != address(0)) revert PositionsManagerAlreadySet();
        positionsManager = IPositionsManagerForAave(_positionsManager);
        emit PositionsManagerSet(_positionsManager);
    }

    /// @notice Sets the `intersRates`.
    /// @param _interestRates The new `interestRates` contract.
    function setInterestRates(IInterestRates _interestRates) external onlyOwner {
        interestRates = _interestRates;
        emit InterestRatesSet(address(_interestRates));
    }

    /// @notice Sets the `reserveFactor`.
    /// @param _marketAddress The market on which to set the `_newReserveFactor`.
    /// @param _newReserveFactor The proportion of the interest earned by users sent to the DAO, (in basis point).
    function setReserveFactor(address _marketAddress, uint256 _newReserveFactor)
        external
        onlyOwner
    {
        reserveFactor[_marketAddress] = Math.min(MAX_BASIS_POINTS, _newReserveFactor);
        updateP2PExchangeRates(_marketAddress);
        emit ReserveFactorSet(_marketAddress, reserveFactor[_marketAddress]);
    }

    /// @notice Creates a new market to borrow/supply in.
    /// @param _underlyingTokenAddress The underlying address of the given market.
    function createMarket(address _underlyingTokenAddress) external onlyOwner {
        DataTypes.ReserveConfigurationMap memory configuration = lendingPool.getConfiguration(
            _underlyingTokenAddress
        );
        (bool isActive, , , ) = configuration.getFlagsMemory();
        if (!isActive) revert MarketIsNotListedOnAave();

        address poolTokenAddress = lendingPool
        .getReserveData(_underlyingTokenAddress)
        .aTokenAddress;

        if (isCreated[poolTokenAddress]) revert MarketAlreadyCreated();
        isCreated[poolTokenAddress] = true;

        exchangeRatesLastUpdateTimestamp[poolTokenAddress] = block.timestamp;
        supplyP2PExchangeRate[poolTokenAddress] = Math.ray();
        borrowP2PExchangeRate[poolTokenAddress] = Math.ray();

        LastPoolIndexes storage poolIndexes = lastPoolIndexes[poolTokenAddress];
        poolIndexes.lastSupplyPoolIndex = lendingPool.getReserveNormalizedIncome(
            _underlyingTokenAddress
        );
        poolIndexes.lastBorrowPoolIndex = lendingPool.getReserveNormalizedVariableDebt(
            _underlyingTokenAddress
        );

        marketsCreated.push(poolTokenAddress);
        emit MarketCreated(poolTokenAddress);
    }

    /// @notice Sets whether to match people P2P or not.
    /// @param _marketAddress The address of the market.
    /// @param _noP2P Whether to match people P2P or not.
    function setNoP2P(address _marketAddress, bool _noP2P)
        external
        onlyOwner
        isMarketCreated(_marketAddress)
    {
        noP2P[_marketAddress] = _noP2P;
        emit NoP2PSet(_marketAddress, _noP2P);
    }

    /// @notice Returns all created markets.
    /// @return marketsCreated_ The list of market adresses.
    function getAllMarkets() external view returns (address[] memory marketsCreated_) {
        marketsCreated_ = marketsCreated;
    }

    /// @notice Returns market's data.
    /// @return supplyP2PExchangeRate_ The supply P2P exchange rate of the market.
    /// @return borrowP2PExchangeRate_ The borrow P2P exchange rate of the market.
    /// @return exchangeRatesLastUpdateTimestamp_ The last timestamp when P2P exchange rates where updated.
    /// @return supplyP2PDelta_ The supply P2P delta (in scaled balance).
    /// @return borrowP2PDelta_ The borrow P2P delta (in adUnit).
    /// @return supplyP2PAmount_ The supply P2P amount (in P2P unit).
    /// @return borrowP2PAmount_ The borrow P2P amount (in P2P unit).
    function getMarketData(address _marketAddress)
        external
        view
        returns (
            uint256 supplyP2PExchangeRate_,
            uint256 borrowP2PExchangeRate_,
            uint256 exchangeRatesLastUpdateTimestamp_,
            uint256 supplyP2PDelta_,
            uint256 borrowP2PDelta_,
            uint256 supplyP2PAmount_,
            uint256 borrowP2PAmount_
        )
    {
        {
            Types.Delta memory delta = positionsManager.deltas(_marketAddress);
            supplyP2PDelta_ = delta.supplyP2PDelta;
            borrowP2PDelta_ = delta.borrowP2PDelta;
            supplyP2PAmount_ = delta.supplyP2PAmount;
            borrowP2PAmount_ = delta.borrowP2PAmount;
        }

        supplyP2PExchangeRate_ = supplyP2PExchangeRate[_marketAddress];
        borrowP2PExchangeRate_ = borrowP2PExchangeRate[_marketAddress];
        exchangeRatesLastUpdateTimestamp_ = exchangeRatesLastUpdateTimestamp[_marketAddress];
    }

    /// @notice Returns market's configuration.
    /// @return isCreated_ Whether the market is created or not.
    /// @return noP2P_ Whether user are put in P2P or not.
    function getMarketConfiguration(address _marketAddress)
        external
        view
        returns (bool isCreated_, bool noP2P_)
    {
        isCreated_ = isCreated[_marketAddress];
        noP2P_ = noP2P[_marketAddress];
    }

    /// PUBLIC ///

    /// @notice Returns the updated P2P exchange rates.
    /// @param _marketAddress The address of the market to update.
    /// @return newSupplyP2PExchangeRate The supply P2P exchange rate after udpate.
    /// @return newBorrowP2PExchangeRate The supply P2P exchange rate after udpate.
    function getUpdatedP2PExchangeRates(address _marketAddress)
        external
        view
        override
        returns (uint256 newSupplyP2PExchangeRate, uint256 newBorrowP2PExchangeRate)
    {
        if (block.timestamp == exchangeRatesLastUpdateTimestamp[_marketAddress]) {
            newSupplyP2PExchangeRate = supplyP2PExchangeRate[_marketAddress];
            newBorrowP2PExchangeRate = borrowP2PExchangeRate[_marketAddress];
        } else {
            address underlyingTokenAddress = IAToken(_marketAddress).UNDERLYING_ASSET_ADDRESS();
            LastPoolIndexes storage poolIndexes = lastPoolIndexes[_marketAddress];

            uint256 poolSupplyExchangeRate = lendingPool.getReserveNormalizedIncome(
                underlyingTokenAddress
            );
            uint256 poolBorrowExchangeRate = lendingPool.getReserveNormalizedVariableDebt(
                underlyingTokenAddress
            );

            Types.Params memory params = Types.Params(
                supplyP2PExchangeRate[_marketAddress],
                borrowP2PExchangeRate[_marketAddress],
                poolSupplyExchangeRate,
                poolBorrowExchangeRate,
                poolIndexes.lastSupplyPoolIndex,
                poolIndexes.lastBorrowPoolIndex,
                reserveFactor[_marketAddress],
                positionsManager.deltas(_marketAddress)
            );

            (newSupplyP2PExchangeRate, newBorrowP2PExchangeRate) = interestRates
            .computeP2PExchangeRates(params);
        }
    }

    /// @notice Updates the P2P exchange rates, taking into account the Second Percentage Yield values.
    /// @param _marketAddress The address of the market to update.
    function updateP2PExchangeRates(address _marketAddress) public {
        uint256 timeDifference = block.timestamp - exchangeRatesLastUpdateTimestamp[_marketAddress];

        if (timeDifference > 0) {
            address underlyingTokenAddress = IAToken(_marketAddress).UNDERLYING_ASSET_ADDRESS();
            exchangeRatesLastUpdateTimestamp[_marketAddress] = block.timestamp;
            LastPoolIndexes storage poolIndexes = lastPoolIndexes[_marketAddress];

            uint256 poolSupplyExchangeRate = lendingPool.getReserveNormalizedIncome(
                underlyingTokenAddress
            );
            uint256 poolBorrowExchangeRate = lendingPool.getReserveNormalizedVariableDebt(
                underlyingTokenAddress
            );

            Types.Params memory params = Types.Params(
                supplyP2PExchangeRate[_marketAddress],
                borrowP2PExchangeRate[_marketAddress],
                poolSupplyExchangeRate,
                poolBorrowExchangeRate,
                poolIndexes.lastSupplyPoolIndex,
                poolIndexes.lastBorrowPoolIndex,
                reserveFactor[_marketAddress],
                positionsManager.deltas(_marketAddress)
            );

            (uint256 newSupplyP2PExchangeRate, uint256 newBorrowP2PExchangeRate) = interestRates
            .computeP2PExchangeRates(params);

            supplyP2PExchangeRate[_marketAddress] = newSupplyP2PExchangeRate;
            borrowP2PExchangeRate[_marketAddress] = newBorrowP2PExchangeRate;
            poolIndexes.lastSupplyPoolIndex = poolSupplyExchangeRate;
            poolIndexes.lastBorrowPoolIndex = poolBorrowExchangeRate;

            emit P2PExchangeRatesUpdated(
                _marketAddress,
                newSupplyP2PExchangeRate,
                newBorrowP2PExchangeRate
            );
        }
    }
}
