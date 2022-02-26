// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

<<<<<<< HEAD
=======
import "./interfaces/aave/ILendingPoolAddressesProvider.sol";
import "./interfaces/aave/ILendingPool.sol";
>>>>>>> cdaa64a (⚡️ (data-provider) remove data provider from markets manager)
import {IAToken} from "./interfaces/aave/IAToken.sol";
import "./interfaces/aave/ILendingPool.sol";
import "./interfaces/IPositionsManagerForAave.sol";

import {ReserveConfiguration} from "./libraries/aave/ReserveConfiguration.sol";
import "./libraries/aave/WadRayMath.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

/// @title MarketsManagerForAave
/// @notice Smart contract managing the markets used by a MorphoPositionsManagerForAave contract, an other contract interacting with Aave or a fork of Aave.
contract MarketsManagerForAave is Ownable {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using WadRayMath for uint256;

    /// Structs ///

    struct LastPoolIndexes {
        uint256 lastSupplyPoolIndex; // Last supply pool index (normalized income) stored.
        uint256 lastBorrowPoolIndex; // Last borrow pool index (normalized variable debt) stored.
    }

    /// Storage ///

    uint16 public reserveFactor; // Proportion of the interest earned by users sent to the DAO, in basis point (100% = 10000). The default value is 0.
    uint16 public constant MAX_BASIS_POINTS = 10000; // 100% in basis point.
    uint16 public constant HALF_MAX_BASIS_POINTS = 5000; // 50% in basis point.
    uint256 public constant SECONDS_PER_YEAR = 365 days; // The number of seconds in one year.
    bytes32 public constant DATA_PROVIDER_ID =
        0x0100000000000000000000000000000000000000000000000000000000000000; // Id of the data provider.
    address[] public marketsCreated; // Keeps track of the created markets.
    mapping(address => bool) public isCreated; // Whether or not this market is created.
    mapping(address => uint256) public supplyP2PSPY; // Supply Percentage Yield per second (in ray).
    mapping(address => uint256) public borrowP2PSPY; // Borrow Percentage Yield per second (in ray).
    mapping(address => uint256) public supplyP2PExchangeRate; // Current exchange rate from supply p2pUnit to underlying (in ray).
    mapping(address => uint256) public borrowP2PExchangeRate; // Current exchange rate from borrow p2pUnit to underlying (in ray).
    mapping(address => uint256) public exchangeRatesLastUpdateTimestamp; // The last time the P2P exchange rates were updated.
    mapping(address => LastPoolIndexes) public lastPoolIndexes; // Last pool index stored.
    mapping(address => bool) public noP2P; // Whether to put users on pool or not for the given market.

    IPositionsManagerForAave public positionsManager;
    ILendingPool public lendingPool;

    /// Events ///

    /// @notice Emitted when a new market is created.
    /// @param _marketAddress The address of the market that has been created.
    event MarketCreated(address _marketAddress);

    /// @notice Emitted when the `positionsManager` is set.
    /// @param _positionsManager The address of the `positionsManager`.
    event PositionsManagerSet(address _positionsManager);

    /// @notice Emitted when a threshold of a market is set.
    /// @param _marketAddress The address of the market to set.
    /// @param _newValue The new value of the threshold.
    event ThresholdSet(address _marketAddress, uint256 _newValue);

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
    /// @param _newValue The new value of the `reserveFactor`.
    event ReserveFactorSet(uint16 _newValue);

    /// Errors ///

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

    /// Modifiers ///

    /// @notice Prevents to update a market not created yet.
    /// @param _marketAddress The address of the market to check.
    modifier isMarketCreated(address _marketAddress) {
        if (!isCreated[_marketAddress]) revert MarketNotCreated();
        _;
    }

    /// @dev Prevents a user to call function only allowed for `positionsManager` owner.
    modifier onlyPositionsManager() {
        if (msg.sender != address(positionsManager)) revert OnlyPositionsManager();
        _;
    }

    /// Constructor ///

    /// @notice Constructs the MarketsManagerForAave contract.
    /// @param _lendingPool The lending pool.
    constructor(ILendingPool _lendingPool) {
        lendingPool = ILendingPool(_lendingPool);
    }

    /// External ///

    /// @notice Sets the `positionsManager` to interact with Aave.
    /// @param _positionsManager The address of the `positionsManager`.
    function setPositionsManager(address _positionsManager) external onlyOwner {
        if (address(positionsManager) != address(0)) revert PositionsManagerAlreadySet();
        positionsManager = IPositionsManagerForAave(_positionsManager);
        emit PositionsManagerSet(_positionsManager);
    }

    /// @notice Sets the `reserveFactor`.
    /// @param _newReserveFactor The proportion of the interest earned by users sent to the DAO, in basis point.
    function setReserveFactor(uint16 _newReserveFactor) external onlyOwner {
        reserveFactor = HALF_MAX_BASIS_POINTS <= _newReserveFactor
            ? HALF_MAX_BASIS_POINTS
            : _newReserveFactor;
        for (uint256 i; i < marketsCreated.length; i++) {
            updateRates(marketsCreated[i]);
        }
        emit ReserveFactorSet(reserveFactor);
    }

    /// @notice Creates a new market to borrow/supply in.
    /// @param _underlyingTokenAddress The underlying address of the given market.
    /// @param _threshold The threshold to set for the market.
    function createMarket(address _underlyingTokenAddress, uint256 _threshold) external onlyOwner {
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

        positionsManager.setThreshold(poolTokenAddress, _threshold);

        _updateSPYs(poolTokenAddress);
        marketsCreated.push(poolTokenAddress);
        emit MarketCreated(poolTokenAddress);
    }

    /// @notice Sets the threshold below which suppliers and borrowers cannot join a given market.
    /// @param _marketAddress The address of the market to change the threshold.
    /// @param _newThreshold The new threshold to set.
    function setThreshold(address _marketAddress, uint256 _newThreshold)
        external
        onlyOwner
        isMarketCreated(_marketAddress)
    {
        positionsManager.setThreshold(_marketAddress, _newThreshold);
        emit ThresholdSet(_marketAddress, _newThreshold);
    }

    /// @notice Sets whether to put everyone on pool or not.
    /// @param _marketAddress The address of the market.
    /// @param _noP2P Whether to put everyone on pool or not.
    function setNoP2P(address _marketAddress, bool _noP2P)
        external
        onlyOwner
        isMarketCreated(_marketAddress)
    {
        noP2P[_marketAddress] = _noP2P;
        emit NoP2PSet(_marketAddress, _noP2P);
    }

    /// @notice Updates the P2P exchange rate, taking into account the Second Percentage Yield values.
    /// @param _marketAddress The address of the market to update.
    function updateP2PExchangeRates(address _marketAddress) external onlyPositionsManager {
        _updateP2PExchangeRates(_marketAddress);
    }

    /// @notice Updates the P2P Second Percentage Yield of supply and borrow.
    /// @param _marketAddress The address of the market to update.
    function updateSPYs(address _marketAddress) external onlyPositionsManager {
        _updateSPYs(_marketAddress);
    }

    /// @notice Returns all created markets.
    /// @return The list of market adresses.
    function getAllMarkets() external view returns (address[] memory) {
        return marketsCreated;
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
    /// @return Whether the market is created or not.
    /// @return Whether user are put in P2P or not.
    /// @return The threshold of the market.
    function getMarketConfiguration(address _marketAddress)
        external
        view
        returns (
            bool,
            bool,
            uint256
        )
    {
        return (
            isCreated[_marketAddress],
            noP2P[_marketAddress],
            positionsManager.threshold(_marketAddress)
        );
    }

    /// Public ///

    /// @notice Updates the P2P Second Percentage Yield and the current P2P exchange rates.
    /// @param _marketAddress The address of the market we want to update.
    function updateRates(address _marketAddress) public isMarketCreated(_marketAddress) {
        if (exchangeRatesLastUpdateTimestamp[_marketAddress] != block.timestamp) {
            _updateP2PExchangeRates(_marketAddress);
            _updateSPYs(_marketAddress);
        }
    }

    /// @notice Returns the updated supply P2P exchange rate.
    /// @param _marketAddress The address of the market to update.
    /// @return The supply P2P exchange rate after udpate.
    function getUpdatedSupplyP2PExchangeRate(address _marketAddress)
        external
        view
        returns (uint256)
    {
        address underlyingTokenAddress = IAToken(_marketAddress).UNDERLYING_ASSET_ADDRESS();
        IPositionsManagerForAave.Delta memory delta = positionsManager.deltas(_marketAddress);
        uint256 timeDifference = block.timestamp - exchangeRatesLastUpdateTimestamp[_marketAddress];

        return
            _computeNewP2PExchangeRate(
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
    /// @return The borrow P2P exchange rate after udpate.
    function getUpdatedBorrowP2PExchangeRate(address _marketAddress)
        external
        view
        returns (uint256)
    {
        address underlyingTokenAddress = IAToken(_marketAddress).UNDERLYING_ASSET_ADDRESS();
        IPositionsManagerForAave.Delta memory delta = positionsManager.deltas(_marketAddress);
        uint256 timeDifference = block.timestamp - exchangeRatesLastUpdateTimestamp[_marketAddress];

        return
            _computeNewP2PExchangeRate(
                delta.borrowP2PDelta,
                delta.borrowP2PAmount,
                borrowP2PExchangeRate[_marketAddress],
                borrowP2PSPY[_marketAddress],
                lendingPool.getReserveNormalizedVariableDebt(underlyingTokenAddress),
                lastPoolIndexes[_marketAddress].lastBorrowPoolIndex,
                timeDifference
            );
    }

    /// Internal ///

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
    function _updateSPYs(address _marketAddress) internal {
        DataTypes.ReserveData memory reserveData = lendingPool.getReserveData(
            IAToken(_marketAddress).UNDERLYING_ASSET_ADDRESS()
        );

        uint256 meanSPY = Math.average(
            reserveData.currentLiquidityRate,
            reserveData.currentVariableBorrowRate
        ) / SECONDS_PER_YEAR; // In ray

        supplyP2PSPY[_marketAddress] =
            (meanSPY * (MAX_BASIS_POINTS - reserveFactor)) /
            MAX_BASIS_POINTS;
        borrowP2PSPY[_marketAddress] =
            (meanSPY * (MAX_BASIS_POINTS + reserveFactor)) /
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
            return _p2pRate.rayMul((WadRayMath.ray() + _p2pSPY).rayPow(_timeDifference));
        else {
            uint256 shareOfTheDelta = _p2pDelta
            .wadToRay()
            .rayMul(_p2pRate)
            .rayDiv(_poolIndex)
            .rayDiv(_p2pAmount.wadToRay());

            return
                _p2pRate.rayMul(
                    (
                        (WadRayMath.ray() + _p2pSPY).rayPow(_timeDifference).rayMul(
                            WadRayMath.ray() - shareOfTheDelta
                        )
                    ) + (shareOfTheDelta.rayMul(_poolIndex).rayDiv(_lastPoolIndex))
                );
        }
    }
}
