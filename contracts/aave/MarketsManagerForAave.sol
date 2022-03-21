// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import {IAToken} from "./interfaces/aave/IAToken.sol";
import "./interfaces/aave/ILendingPool.sol";
import "./interfaces/IPositionsManagerForAave.sol";
import "./interfaces/IMarketsManagerForAave.sol";

import {ReserveConfiguration} from "./libraries/aave/ReserveConfiguration.sol";
import "./libraries/aave/WadRayMath.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/// @title MarketsManagerForAave
/// @notice Smart contract managing the markets used by a MorphoPositionsManagerForAave contract, an other contract interacting with Aave or a fork of Aave.
contract MarketsManagerForAave is IMarketsManagerForAave, OwnableUpgradeable {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using WadRayMath for uint256;

    /// STRUCTS ///

    struct LastPoolIndexes {
        uint256 lastSupplyPoolIndex; // Last supply pool index (normalized income) stored.
        uint256 lastBorrowPoolIndex; // Last borrow pool index (normalized variable debt) stored.
    }

    /// STORAGE ///

    uint16 public constant MAX_BASIS_POINTS = 10000; // 100% in basis point.
    uint16 public constant HALF_MAX_BASIS_POINTS = 5000; // 50% in basis point.
    uint256 public constant SECONDS_PER_YEAR = 365 days; // The number of seconds in one year.
    address[] public marketsCreated; // Keeps track of the created markets.
    mapping(address => bool) public override isCreated; // Whether or not this market is created.
    mapping(address => uint16) public reserveFactor; // Proportion of the interest earned by users sent to the DAO for each market, in basis point (100% = 10000). The default value is 0.
    mapping(address => uint256) public override supplyP2PSPY; // Supply Percentage Yield per second (in ray).
    mapping(address => uint256) public override borrowP2PSPY; // Borrow Percentage Yield per second (in ray).
    mapping(address => uint256) public override supplyP2PExchangeRate; // Current exchange rate from supply p2pUnit to underlying (in ray).
    mapping(address => uint256) public override borrowP2PExchangeRate; // Current exchange rate from borrow p2pUnit to underlying (in ray).
    mapping(address => uint256) public override exchangeRatesLastUpdateTimestamp; // The last time the P2P exchange rates were updated.
    mapping(address => LastPoolIndexes) public lastPoolIndexes; // Last pool index stored.
    mapping(address => bool) public override noP2P; // Whether to put users on pool or not for the given market.

    IPositionsManagerForAave public positionsManager;
    ILendingPool public lendingPool;

    /// EVENTS ///

    /// @notice Emitted when a new market is created.
    /// @param _marketAddress The address of the market that has been created.
    event MarketCreated(address _marketAddress);

    /// @notice Emitted when the `positionsManager` is set.
    /// @param _positionsManager The address of the `positionsManager`.
    event PositionsManagerSet(address _positionsManager);

    /// @notice Emitted when a `noP2P` variable is set.
    /// @param _marketAddress The address of the market to set.
    /// @param _noP2P The new value of `_noP2P` adopted.
    event NoP2PSet(address _marketAddress, bool _noP2P);

    /// @notice Emitted when the P2P SPYs of a market are updated.
    /// @param _marketAddress The address of the market updated.
    /// @param _newSupplyP2PSPY The new value of the supply  P2P SPY.
    /// @param _newBorrowP2PSPY The new value of the borrow P2P SPY.
    event P2PSPYsUpdated(
        address _marketAddress,
        uint256 _newSupplyP2PSPY,
        uint256 _newBorrowP2PSPY
    );

    /// @notice Emitted when the p2p exchange rates of a market are updated.
    /// @param _marketAddress The address of the market updated.
    /// @param _newSupplyP2PExchangeRate The new value of the supply exchange rate from p2pUnit to underlying.
    /// @param _newBorrowP2PExchangeRate The new value of the borrow exchange rate from p2pUnit to underlying.
    event P2PExchangeRatesUpdated(
        address _marketAddress,
        uint256 _newSupplyP2PExchangeRate,
        uint256 _newBorrowP2PExchangeRate
    );

    /// @notice Emitted when the `reserveFactor` is set.
    /// @param _marketAddress The address of the market set.
    /// @param _newValue The new value of the `reserveFactor`.
    event ReserveFactorSet(address _marketAddress, uint16 _newValue);

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
    /// @param _lendingPool The lending pool.
    function initialize(ILendingPool _lendingPool) external initializer {
        __Ownable_init();

        lendingPool = ILendingPool(_lendingPool);
    }

    /// EXTERNAL ///

    /// @notice Sets the `positionsManager` to interact with Aave.
    /// @param _positionsManager The address of the `positionsManager`.
    function setPositionsManager(address _positionsManager) external onlyOwner {
        if (address(positionsManager) != address(0)) revert PositionsManagerAlreadySet();
        positionsManager = IPositionsManagerForAave(_positionsManager);
        emit PositionsManagerSet(_positionsManager);
    }

    /// @notice Sets the `reserveFactor`.
    /// @param _marketAddress The market on which to set the `_newReserveFactor`.
    /// @param _newReserveFactor The proportion of the interest earned by users sent to the DAO, in basis point.
    function setReserveFactor(address _marketAddress, uint16 _newReserveFactor) external onlyOwner {
        reserveFactor[_marketAddress] = HALF_MAX_BASIS_POINTS <= _newReserveFactor
            ? HALF_MAX_BASIS_POINTS
            : _newReserveFactor;

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
        supplyP2PExchangeRate[poolTokenAddress] = WadRayMath.ray();
        borrowP2PExchangeRate[poolTokenAddress] = WadRayMath.ray();

        LastPoolIndexes storage poolIndexes = lastPoolIndexes[poolTokenAddress];
        poolIndexes.lastSupplyPoolIndex = lendingPool.getReserveNormalizedIncome(
            _underlyingTokenAddress
        );
        poolIndexes.lastBorrowPoolIndex = lendingPool.getReserveNormalizedVariableDebt(
            _underlyingTokenAddress
        );

        _updateSPYs(poolTokenAddress);
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
        if (exchangeRatesLastUpdateTimestamp[_marketAddress] != block.timestamp)
            _updateP2PExchangeRates(_marketAddress);
    }

    /// @notice Updates the P2P Second Percentage Yield of supply and borrow.
    /// @param _marketAddress The address of the market to update.
    function updateSPYs(address _marketAddress) external override onlyPositionsManager {
        _updateSPYs(_marketAddress);
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
        if (exchangeRatesLastUpdateTimestamp[_marketAddress] != block.timestamp)
            _updateP2PExchangeRates(_marketAddress);
        _updateSPYs(_marketAddress);
    }

    /// @notice Returns the updated supply P2P exchange rate.
    /// @param _marketAddress The address of the market to update.
    /// @return updatedSupplyP2P_ The supply P2P exchange rate after udpate.
    function getUpdatedSupplyP2PExchangeRate(address _marketAddress)
        external
        view
        returns (uint256 updatedSupplyP2P_)
    {
        address underlyingTokenAddress = IAToken(_marketAddress).UNDERLYING_ASSET_ADDRESS();
        IPositionsManagerForAave.Delta memory delta = positionsManager.deltas(_marketAddress);
        uint256 timeDifference = block.timestamp - exchangeRatesLastUpdateTimestamp[_marketAddress];

        updatedSupplyP2P_ = _computeNewP2PExchangeRate(
            delta.supplyP2PDelta,
            delta.supplyP2PAmount,
            supplyP2PExchangeRate[_marketAddress],
            supplyP2PSPY[_marketAddress],
            lendingPool.getReserveNormalizedIncome(underlyingTokenAddress),
            lastPoolIndexes[_marketAddress].lastSupplyPoolIndex,
            timeDifference
        );
    }

    /// @notice Returns the updated borrow P2P exchange rate.
    /// @param _marketAddress The address of the market to update.
    /// @return updatedBorrowP2P_ The borrow P2P exchange rate after udpate.
    function getUpdatedBorrowP2PExchangeRate(address _marketAddress)
        external
        view
        returns (uint256 updatedBorrowP2P_)
    {
        address underlyingTokenAddress = IAToken(_marketAddress).UNDERLYING_ASSET_ADDRESS();
        IPositionsManagerForAave.Delta memory delta = positionsManager.deltas(_marketAddress);
        uint256 timeDifference = block.timestamp - exchangeRatesLastUpdateTimestamp[_marketAddress];

        updatedBorrowP2P_ = _computeNewP2PExchangeRate(
            delta.borrowP2PDelta,
            delta.borrowP2PAmount,
            borrowP2PExchangeRate[_marketAddress],
            borrowP2PSPY[_marketAddress],
            lendingPool.getReserveNormalizedVariableDebt(underlyingTokenAddress),
            lastPoolIndexes[_marketAddress].lastBorrowPoolIndex,
            timeDifference
        );
    }

    /// INTERNAL ///

    /// @dev calculates compounded interest over a period of time.
    ///   To avoid expensive exponentiation, the calculation is performed using a binomial approximation:
    ///   (1+x)^n = 1+n*x+[n/2*(n-1)]*x^2+[n/6*(n-1)*(n-2)*x^3...
    /// @param _rate The SPY to use in the computation.
    /// @param _elapsedTime The amount of time during to get the interest for.
    /// @return results in ray.
    function _computeCompoundedInterest(uint256 _rate, uint256 _elapsedTime)
        internal
        pure
        returns (uint256)
    {
        if (_elapsedTime == 0) {
            return WadRayMath.ray();
        }

        if (_elapsedTime == 1) {
            return WadRayMath.ray() + _rate;
        }

        uint256 ratePowerTwo = _rate.rayMul(_rate);
        uint256 ratePowerThree = ratePowerTwo.rayMul(_rate);

        return
            WadRayMath.ray() +
            _rate *
            _elapsedTime +
            (_elapsedTime * (_elapsedTime - 1) * ratePowerTwo) /
            2 +
            (_elapsedTime * (_elapsedTime - 1) * (_elapsedTime - 2) * ratePowerThree) /
            6;
    }

    /// @notice Updates the P2P exchange rates, taking into account the Second Percentage Yield values.
    /// @param _marketAddress The address of the market to update.
    function _updateP2PExchangeRates(address _marketAddress) internal {
        address underlyingTokenAddress = IAToken(_marketAddress).UNDERLYING_ASSET_ADDRESS();
        uint256 timeDifference = block.timestamp - exchangeRatesLastUpdateTimestamp[_marketAddress];
        exchangeRatesLastUpdateTimestamp[_marketAddress] = block.timestamp;
        LastPoolIndexes storage poolIndexes = lastPoolIndexes[_marketAddress];
        IPositionsManagerForAave.Delta memory delta = positionsManager.deltas(_marketAddress);

        uint256 normalizedIncome = lendingPool.getReserveNormalizedIncome(underlyingTokenAddress);
        supplyP2PExchangeRate[_marketAddress] = _computeNewP2PExchangeRate(
            delta.supplyP2PDelta,
            delta.supplyP2PAmount,
            supplyP2PExchangeRate[_marketAddress],
            supplyP2PSPY[_marketAddress],
            normalizedIncome,
            poolIndexes.lastSupplyPoolIndex,
            timeDifference
        );
        poolIndexes.lastSupplyPoolIndex = normalizedIncome;

        uint256 normalizedVariableDebt = lendingPool.getReserveNormalizedVariableDebt(
            underlyingTokenAddress
        );
        borrowP2PExchangeRate[_marketAddress] = _computeNewP2PExchangeRate(
            delta.borrowP2PDelta,
            delta.borrowP2PAmount,
            borrowP2PExchangeRate[_marketAddress],
            borrowP2PSPY[_marketAddress],
            normalizedVariableDebt,
            poolIndexes.lastBorrowPoolIndex,
            timeDifference
        );
        poolIndexes.lastBorrowPoolIndex = normalizedVariableDebt;

        emit P2PExchangeRatesUpdated(
            _marketAddress,
            supplyP2PExchangeRate[_marketAddress],
            borrowP2PExchangeRate[_marketAddress]
        );
    }

    /// @notice Updates the P2P Second Percentage Yield of supply and borrow.
    /// @param _marketAddress The address of the market to update.
    /// @dev Note: that the exchange rate must have been updated in the same block before calling this.
    function _updateSPYs(address _marketAddress) internal {
        DataTypes.ReserveData memory reserveData = lendingPool.getReserveData(
            IAToken(_marketAddress).UNDERLYING_ASSET_ADDRESS()
        );

        uint256 meanSPY;
        unchecked {
            meanSPY =
                (reserveData.currentLiquidityRate + reserveData.currentVariableBorrowRate) /
                (2 * SECONDS_PER_YEAR);
        }

        supplyP2PSPY[_marketAddress] =
            (meanSPY * (MAX_BASIS_POINTS - reserveFactor[_marketAddress])) /
            MAX_BASIS_POINTS;
        borrowP2PSPY[_marketAddress] =
            (meanSPY * (MAX_BASIS_POINTS + reserveFactor[_marketAddress])) /
            MAX_BASIS_POINTS;

        emit P2PSPYsUpdated(
            _marketAddress,
            supplyP2PSPY[_marketAddress],
            borrowP2PSPY[_marketAddress]
        );
    }

    /// @notice Computes the new P2P exchange rate from arguments.
    /// @param _p2pDelta The P2P delta.
    /// @param _p2pAmount The P2P amount.
    /// @param _p2pRate The P2P exchange rate.
    /// @param _p2pSPY The P2P SPY.
    /// @param _poolIndex The pool index (normalized income for supply) or (normalized debt variable for borrow) of the market.
    /// @param _lastPoolIndex The last pool index (normalized income for supply) or (normalized debt variable for borrow) of the market.
    /// @param _timeDifference The time difference since the last update.
    /// @return The new P2P exchange rate.
    function _computeNewP2PExchangeRate(
        uint256 _p2pDelta,
        uint256 _p2pAmount,
        uint256 _p2pRate,
        uint256 _p2pSPY,
        uint256 _poolIndex,
        uint256 _lastPoolIndex,
        uint256 _timeDifference
    ) internal pure returns (uint256) {
        if (_p2pDelta == 0)
            return _p2pRate.rayMul(_computeCompoundedInterest(_p2pSPY, _timeDifference));
        else {
            uint256 shareOfTheDelta = _p2pDelta
            .wadToRay()
            .rayMul(_p2pRate)
            .rayDiv(_poolIndex)
            .rayDiv(_p2pAmount.wadToRay());

            return
                _p2pRate.rayMul(
                    (
                        _computeCompoundedInterest(_p2pSPY, _timeDifference).rayMul(
                            WadRayMath.ray() - shareOfTheDelta
                        )
                    ) + (shareOfTheDelta.rayMul(_poolIndex).rayDiv(_lastPoolIndex))
                );
        }
    }
}
