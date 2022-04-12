// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import {IAToken} from "./interfaces/aave/IAToken.sol";
import "./interfaces/aave/ILendingPool.sol";
import "./interfaces/IPositionsManagerForAave.sol";
import "./interfaces/IMarketsManagerForAave.sol";
import "./interfaces/IInterestRates.sol";

import {ReserveConfiguration} from "./libraries/aave/ReserveConfiguration.sol";
import "./libraries/Math.sol";

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

    /// STORAGE ///

    uint16 public constant MAX_BASIS_POINTS = 10_000; // 100% (in basis point).
    uint256 public constant SECONDS_PER_YEAR = 365 days; // The number of seconds in one year.
    address[] public marketsCreated; // Keeps track of the created markets.
    mapping(address => bool) public override isCreated; // Whether or not this market is created.
    mapping(address => uint256) public reserveFactor; // Proportion of the interest earned by users sent to the DAO for each market, in basis point (100% = 10000). The default value is 0.
    mapping(address => uint256) public override supplyP2PSPY; // Supply Percentage Yield per second (in ray).
    mapping(address => uint256) public override borrowP2PSPY; // Borrow Percentage Yield per second (in ray).
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

    /// @notice Emitted when the P2P SPYs of a market are updated.
    /// @param _marketAddress The address of the market updated.
    /// @param _newSupplyP2PSPY The new value of the supply  P2P SPY.
    /// @param _newBorrowP2PSPY The new value of the borrow P2P SPY.
    event P2PSPYsUpdated(
        address indexed _marketAddress,
        uint256 _newSupplyP2PSPY,
        uint256 _newBorrowP2PSPY
    );

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
        updateRates(_marketAddress);
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

    /// @notice Updates the P2P exchange rates, taking into account the Second Percentage Yield values.
    /// @param _marketAddress The address of the market to update.
    function updateP2PExchangeRates(address _marketAddress) external override onlyPositionsManager {
        _updateP2PExchangeRates(_marketAddress);
    }

    /// @notice Returns all created markets.
    /// @return marketsCreated_ The list of market adresses.
    function getAllMarkets() external view returns (address[] memory marketsCreated_) {
        marketsCreated_ = marketsCreated;
    }

    /// @notice Returns market's data.
    /// @return supplyP2PSPY_ The supply P2P SPY of the market.
    /// @return borrowP2PSPY_ The borrow P2P SPY of the market.
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
            uint256 supplyP2PSPY_,
            uint256 borrowP2PSPY_,
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
            IPositionsManagerForAave.Delta memory delta = positionsManager.deltas(_marketAddress);
            supplyP2PDelta_ = delta.supplyP2PDelta;
            borrowP2PDelta_ = delta.borrowP2PDelta;
            supplyP2PAmount_ = delta.supplyP2PAmount;
            borrowP2PAmount_ = delta.borrowP2PAmount;
        }

        supplyP2PSPY_ = supplyP2PSPY[_marketAddress];
        borrowP2PSPY_ = borrowP2PSPY[_marketAddress];
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

    /// @notice Updates the P2P Second Percentage Yield and the current P2P exchange rates.
    /// @param _marketAddress The address of the market we want to update.
    function updateRates(address _marketAddress) public override isMarketCreated(_marketAddress) {
        _updateP2PExchangeRates(_marketAddress);
    }

    /// @notice Returns the updated supply P2P exchange rate.
    /// @param _marketAddress The address of the market to update.
    /// @return newSupplyP2PExchangeRate The supply P2P exchange rate after udpate.
    function getUpdatedSupplyP2PExchangeRate(address _marketAddress)
        external
        view
        override
        returns (uint256 newSupplyP2PExchangeRate)
    {
        if (block.timestamp == exchangeRatesLastUpdateTimestamp[_marketAddress])
            newSupplyP2PExchangeRate = supplyP2PExchangeRate[_marketAddress];
        else {
            address underlyingTokenAddress = IAToken(_marketAddress).UNDERLYING_ASSET_ADDRESS();
            LastPoolIndexes storage poolIndexes = lastPoolIndexes[_marketAddress];

            uint256 poolSupplyExchangeRate = lendingPool.getReserveNormalizedIncome(
                underlyingTokenAddress
            );
            uint256 poolBorrowExchangeRate = lendingPool.getReserveNormalizedVariableDebt(
                underlyingTokenAddress
            );

            newSupplyP2PExchangeRate = computeSupplyP2PExchangeRate(
                _marketAddress,
                supplyP2PExchangeRate[_marketAddress],
                poolSupplyExchangeRate,
                poolBorrowExchangeRate,
                poolIndexes.lastSupplyPoolIndex,
                poolIndexes.lastBorrowPoolIndex
            );
        }
    }

    /// @notice Returns the updated borrow P2P exchange rate.
    /// @param _marketAddress The address of the market to update.
    /// @return newBorrowP2PExchangeRate The borrow P2P exchange rate after udpate.
    function getUpdatedBorrowP2PExchangeRate(address _marketAddress)
        external
        view
        override
        returns (uint256 newBorrowP2PExchangeRate)
    {
        if (block.timestamp == exchangeRatesLastUpdateTimestamp[_marketAddress])
            newBorrowP2PExchangeRate = borrowP2PExchangeRate[_marketAddress];
        else {
            address underlyingTokenAddress = IAToken(_marketAddress).UNDERLYING_ASSET_ADDRESS();
            LastPoolIndexes storage poolIndexes = lastPoolIndexes[_marketAddress];

            uint256 poolSupplyExchangeRate = lendingPool.getReserveNormalizedIncome(
                underlyingTokenAddress
            );
            uint256 poolBorrowExchangeRate = lendingPool.getReserveNormalizedVariableDebt(
                underlyingTokenAddress
            );

            newBorrowP2PExchangeRate = computeBorrowP2PExchangeRate(
                _marketAddress,
                borrowP2PExchangeRate[_marketAddress],
                poolSupplyExchangeRate,
                poolBorrowExchangeRate,
                poolIndexes.lastSupplyPoolIndex,
                poolIndexes.lastBorrowPoolIndex
            );
        }
    }

    /// INTERNAL ///

    /// @notice Updates the P2P exchange rates, taking into account the Second Percentage Yield values.
    /// @param _marketAddress The address of the market to update.
    function _updateP2PExchangeRates(address _marketAddress) internal {
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

            uint256 newSupplyP2PExchangeRate = computeSupplyP2PExchangeRate(
                _marketAddress,
                supplyP2PExchangeRate[_marketAddress],
                poolSupplyExchangeRate,
                poolBorrowExchangeRate,
                poolIndexes.lastSupplyPoolIndex,
                poolIndexes.lastBorrowPoolIndex
            );

            uint256 newBorrowP2PExchangeRate = computeBorrowP2PExchangeRate(
                _marketAddress,
                borrowP2PExchangeRate[_marketAddress],
                poolSupplyExchangeRate,
                poolBorrowExchangeRate,
                poolIndexes.lastSupplyPoolIndex,
                poolIndexes.lastBorrowPoolIndex
            );

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

    struct Vars {
        uint256 shareOfTheDelta;
        uint256 poolIncrease;
        IPositionsManagerForAave.Delta delta;
    }

    function computeSupplyP2PExchangeRate(
        address _poolTokenAddress,
        uint256 _supplyP2pExchangeRate,
        uint256 _poolSupplyExchangeRate,
        uint256 _poolBorrowExchangeRate,
        uint256 _lastPoolSupplyExchangeRate,
        uint256 _lastPoolBorrowExchangeRate
    ) public view returns (uint256 newSupplyP2PExchangeRate) {
        Vars memory vars;
        vars.delta = positionsManager.deltas(_poolTokenAddress);

        vars.poolIncrease = computeSupplyPoolIncrease(
            _poolSupplyExchangeRate,
            _poolBorrowExchangeRate,
            _lastPoolSupplyExchangeRate,
            _lastPoolBorrowExchangeRate,
            reserveFactor[_poolTokenAddress]
        );

        if (vars.delta.supplyP2PAmount == 0 || vars.delta.supplyP2PDelta == 0) {
            newSupplyP2PExchangeRate = _supplyP2pExchangeRate.rayMul(vars.poolIncrease);
        } else {
            vars.shareOfTheDelta = Math.min(
                vars
                .delta
                .supplyP2PDelta
                .wadToRay()
                .rayMul(_poolSupplyExchangeRate)
                .rayDiv(_supplyP2pExchangeRate)
                .rayDiv(vars.delta.supplyP2PAmount.wadToRay()),
                Math.ray() // To avoid shareOfTheDelta > 1 with rounding errors.
            );

            newSupplyP2PExchangeRate = _supplyP2pExchangeRate.rayMul(
                (Math.ray() - vars.shareOfTheDelta).rayMul(vars.poolIncrease) +
                    vars.shareOfTheDelta.rayMul(_poolSupplyExchangeRate).rayDiv(
                        _lastPoolSupplyExchangeRate
                    )
            );
        }
    }

    function computeBorrowP2PExchangeRate(
        address _poolTokenAddress,
        uint256 _borrowP2pExchangeRate,
        uint256 _poolSupplyExchangeRate,
        uint256 _poolBorrowExchangeRate,
        uint256 _lastPoolSupplyExchangeRate,
        uint256 _lastPoolBorrowExchangeRate
    ) public view returns (uint256 newBorrowP2PExchangeRate) {
        Vars memory vars;
        vars.delta = positionsManager.deltas(_poolTokenAddress);

        vars.poolIncrease = computeBorrowPoolIncrease(
            _poolSupplyExchangeRate,
            _poolBorrowExchangeRate,
            _lastPoolSupplyExchangeRate,
            _lastPoolBorrowExchangeRate,
            reserveFactor[_poolTokenAddress]
        );

        if (vars.delta.borrowP2PAmount == 0 || vars.delta.borrowP2PDelta == 0) {
            newBorrowP2PExchangeRate = _borrowP2pExchangeRate.rayMul(vars.poolIncrease);
        } else {
            vars.shareOfTheDelta = Math.min(
                vars
                .delta
                .borrowP2PDelta
                .wadToRay()
                .rayMul(_poolBorrowExchangeRate)
                .rayDiv(_borrowP2pExchangeRate)
                .rayDiv(vars.delta.borrowP2PAmount.wadToRay()),
                Math.ray() // To avoid shareOfTheDelta > 1 with rounding errors.
            );

            newBorrowP2PExchangeRate = _borrowP2pExchangeRate.rayMul(
                (Math.ray() - vars.shareOfTheDelta).rayMul(vars.poolIncrease) +
                    vars.shareOfTheDelta.rayMul(_poolBorrowExchangeRate).rayDiv(
                        _lastPoolBorrowExchangeRate
                    )
            );
        }
    }

    function computeSupplyPoolIncrease(
        uint256 _poolSupplyExchangeRate,
        uint256 _poolBorrowExchangeRate,
        uint256 _lastPoolSupplyExchangeRate,
        uint256 _lastPoolBorrowExchangeRate,
        uint256 _reserveFactor
    ) internal pure returns (uint256) {
        return
            ((MAX_BASIS_POINTS - _reserveFactor) *
                (2 *
                    _poolSupplyExchangeRate.rayDiv(_lastPoolSupplyExchangeRate) +
                    _poolBorrowExchangeRate.rayDiv(_lastPoolBorrowExchangeRate))) /
            MAX_BASIS_POINTS /
            3 -
            (_reserveFactor * _poolSupplyExchangeRate.rayDiv(_lastPoolSupplyExchangeRate)) /
            MAX_BASIS_POINTS;
    }

    function computeBorrowPoolIncrease(
        uint256 _poolSupplyExchangeRate,
        uint256 _poolBorrowExchangeRate,
        uint256 _lastPoolSupplyExchangeRate,
        uint256 _lastPoolBorrowExchangeRate,
        uint256 _reserveFactor
    ) internal pure returns (uint256) {
        return
            ((MAX_BASIS_POINTS - _reserveFactor) *
                (2 *
                    _poolSupplyExchangeRate.rayDiv(_lastPoolSupplyExchangeRate) +
                    _poolBorrowExchangeRate.rayDiv(_lastPoolBorrowExchangeRate))) /
            MAX_BASIS_POINTS /
            3 +
            (_reserveFactor * _poolBorrowExchangeRate.rayDiv(_lastPoolBorrowExchangeRate)) /
            MAX_BASIS_POINTS;
    }
}
