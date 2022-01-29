// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "./interfaces/aave/ILendingPoolAddressesProvider.sol";
import "./interfaces/aave/ILendingPool.sol";
import "./interfaces/aave/DataTypes.sol";
import {IAToken} from "./interfaces/aave/IAToken.sol";
import "./interfaces/IPositionsManagerForAave.sol";

import "./libraries/aave/WadRayMath.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

/// @title MarketsManagerForAave
/// @dev Smart contract managing the markets used by a MorphoPositionsManagerForAave contract, an other contract interacting with Aave or a fork of Aave.
contract MarketsManagerForAave is Ownable {
    using WadRayMath for uint256;

    /// Storage ///

    uint16 public constant MAX_BASIS_POINTS = 10000; // 100% in basis point.
    uint16 public constant HALF_MAX_BASIS_POINTS = 5000; // 50% in basis point.
    uint16 public reserveFactor; // Proportion of the interest earned by users sent to the DAO, in basis point (100% = 10000). The default value is 0.
    uint256 public constant SECONDS_PER_YEAR = 365 days; // The number of seconds in one year.

    mapping(address => bool) public isCreated; // Whether or not this market is created.
    mapping(address => uint256) public supplyP2PSPY; // Supply Percentage Yield per second, in ray.
    mapping(address => uint256) public borrowP2PSPY; // Borrow Percentage Yield per second, in ray.
    mapping(address => uint256) public supplyP2PExchangeRate; // Current exchange rate from supply p2pUnit to underlying.
    mapping(address => uint256) public borrowP2PExchangeRate; // Current exchange rate from borrow p2pUnit to underlying.
    mapping(address => uint256) public exchangeRatesLastUpdateTimestamp; // The last time the P2P exchange rates were updated.
    mapping(address => bool) public noP2P; // Whether to put users on pool or not for the given market.

    IPositionsManagerForAave public positionsManagerForAave;
    ILendingPoolAddressesProvider public addressesProvider;
    ILendingPool public lendingPool;

    /// Events ///

    /// @dev Emitted when a new market is created.
    /// @param _marketAddress The address of the market that has been created.
    event MarketCreated(address _marketAddress);

    /// @dev Emitted when the lendingPool is updated on the `positionsManagerForAave`.
    /// @param _lendingPoolAddress The address of the lending pool.
    event LendingPoolUpdated(address _lendingPoolAddress);

    /// @dev Emitted when the `positionsManagerForAave` is set.
    /// @param _positionsManagerForAave The address of the `positionsManagerForAave`.
    event PositionsManagerSet(address _positionsManagerForAave);

    /// @dev Emitted when a threshold of a market is set.
    /// @param _marketAddress The address of the market to set.
    /// @param _newValue The new value of the threshold.
    event ThresholdSet(address _marketAddress, uint256 _newValue);

    /// @dev Emitted when a cap value of a market is set.
    /// @param _marketAddress The address of the market to set.
    /// @param _newValue The new value of the cap.
    event CapValueSet(address _marketAddress, uint256 _newValue);

    /// @dev Emitted when a `noP2P` variable is set.
    /// @param _marketAddress The address of the market to set.
    /// @param _noP2P The new value of `_noP2P` adopted.
    event NoP2PSet(address _marketAddress, bool _noP2P);

    /// @dev Emitted when the P2P SPYs of a market are updated.
    /// @param _marketAddress The address of the market updated.
    /// @param _newSupplyP2PSPY The new value of the supply  P2P SPY.
    /// @param _newBorrowP2PSPY The new value of the borrow P2P SPY.
    event P2PSPYsUpdated(
        address _marketAddress,
        uint256 _newSupplyP2PSPY,
        uint256 _newBorrowP2PSPY
    );

    /// @dev Emitted when the p2p exchange rates of a market are updated.
    /// @param _marketAddress The address of the market updated.
    /// @param _newSupplyP2PExchangeRate The new value of the supply exchange rate from p2pUnit to underlying.
    /// @param _newBorrowP2PExchangeRate The new value of the borrow exchange rate from p2pUnit to underlying.
    event P2PExchangeRatesUpdated(
        address _marketAddress,
        uint256 _newSupplyP2PExchangeRate,
        uint256 _newBorrowP2PExchangeRate
    );

    /// @dev Emitted when a cap value of a market is updated.
    /// @param _marketAddress The address of the market updated.
    /// @param _newValue The new value of the cap.
    event CapValueUpdated(address _marketAddress, uint256 _newValue);

    /// @dev Emitted when the `reserveFactor` is set.
    /// @param _newValue The new value of the `reserveFactor`.
    event ReserveFactorSet(uint16 _newValue);

    /// Errors ///

    /// @notice Thrown when the market is not created yet.
    error MarketNotCreated();

    /// @notice Thrown when the market is already created.
    error MarketAlreadyCreated();

    /// @notice Thrown when the positionsManager is already set.
    error PositionsManagerAlreadySet();

    /// Modifiers ///

    /// @dev Prevents to update a market not created yet.
    modifier isMarketCreated(address _marketAddress) {
        if (!isCreated[_marketAddress]) revert MarketNotCreated();
        _;
    }

    /// Constructor ///

    /// @dev Constructs the MarketsManagerForAave contract.
    /// @param _lendingPoolAddressesProvider The address of the lending pool addresses provider.
    constructor(address _lendingPoolAddressesProvider) {
        addressesProvider = ILendingPoolAddressesProvider(_lendingPoolAddressesProvider);
        lendingPool = ILendingPool(addressesProvider.getLendingPool());
        emit LendingPoolUpdated(address(lendingPool));
    }

    /// External ///

    /// @dev Sets the `positionsManagerForAave` to interact with Aave.
    /// @param _positionsManagerForAave The address of the `positionsManagerForAave`.
    function setPositionsManager(address _positionsManagerForAave) external onlyOwner {
        if (address(positionsManagerForAave) != address(0)) revert PositionsManagerAlreadySet();
        positionsManagerForAave = IPositionsManagerForAave(_positionsManagerForAave);
        emit PositionsManagerSet(_positionsManagerForAave);
    }

    /// @dev Updates the lending pool.
    function updateLendingPool() external onlyOwner {
        lendingPool = ILendingPool(addressesProvider.getLendingPool());
        emit LendingPoolUpdated(address(lendingPool));
    }

    /// @dev Sets the `reserveFactor`.
    /// @param _newReserveFactor The proportion of the interest earned by users sent to the DAO, in basis point.
    function setReserveFactor(uint16 _newReserveFactor) external onlyOwner {
        reserveFactor = HALF_MAX_BASIS_POINTS <= _newReserveFactor
            ? HALF_MAX_BASIS_POINTS
            : _newReserveFactor;
        emit ReserveFactorSet(reserveFactor);
    }

    /// @dev Creates a new market to borrow/supply in.
    /// @param _marketAddress The addresses of the markets to add (aToken).
    /// @param _threshold The threshold to set for the market.
    /// @param _capValue The cap value to set for the market.
    function createMarket(
        address _marketAddress,
        uint256 _threshold,
        uint256 _capValue
    ) external onlyOwner {
        if (isCreated[_marketAddress]) revert MarketAlreadyCreated();

        isCreated[_marketAddress] = true;
        exchangeRatesLastUpdateTimestamp[_marketAddress] = block.timestamp;
        supplyP2PExchangeRate[_marketAddress] = WadRayMath.ray();
        borrowP2PExchangeRate[_marketAddress] = WadRayMath.ray();

        positionsManagerForAave.setThreshold(_marketAddress, _threshold);
        positionsManagerForAave.setCapValue(_marketAddress, _capValue);

        _updateSPYs(_marketAddress);
        emit MarketCreated(_marketAddress);
    }

    /// @dev Sets the threshold below which suppliers and borrowers cannot join a given market.
    /// @param _marketAddress The address of the market to change the threshold.
    /// @param _newThreshold The new threshold to set.
    function setThreshold(address _marketAddress, uint256 _newThreshold)
        external
        onlyOwner
        isMarketCreated(_marketAddress)
    {
        positionsManagerForAave.setThreshold(_marketAddress, _newThreshold);
        emit ThresholdSet(_marketAddress, _newThreshold);
    }

    /// @dev Sets the cap value above which suppliers cannot supply more tokens.
    /// @param _marketAddress The address of the market to change the max cap.
    /// @param _newCapValue The new max cap to set.
    function setCapValue(address _marketAddress, uint256 _newCapValue)
        external
        onlyOwner
        isMarketCreated(_marketAddress)
    {
        positionsManagerForAave.setCapValue(_marketAddress, _newCapValue);
        emit CapValueSet(_marketAddress, _newCapValue);
    }

    /// @dev Sets whether to put everyone on pool or not.
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

    /// Public ///

    /// @dev Updates the P2P Second Percentage Yield and the current P2P exchange rates.
    /// @param _marketAddress The address of the market we want to update.
    function updateRates(address _marketAddress) public isMarketCreated(_marketAddress) {
        if (exchangeRatesLastUpdateTimestamp[_marketAddress] != block.timestamp) {
            _updateP2PExchangeRates(_marketAddress);
            _updateSPYs(_marketAddress);
        }
    }

    /// Internal ///

    /// @dev Updates the P2P exchange rate, taking into account the Second Percentage Yield values.
    /// @param _marketAddress The address of the market to update.
    function _updateP2PExchangeRates(address _marketAddress) internal {
        uint256 timeDifference = block.timestamp - exchangeRatesLastUpdateTimestamp[_marketAddress];
        exchangeRatesLastUpdateTimestamp[_marketAddress] = block.timestamp;

        uint256 newSupplyP2PExchangeRate = supplyP2PExchangeRate[_marketAddress].rayMul(
            (WadRayMath.ray() + supplyP2PSPY[_marketAddress]).rayPow(timeDifference)
        ); // In ray
        supplyP2PExchangeRate[_marketAddress] = newSupplyP2PExchangeRate;

        uint256 newBorrowP2PExchangeRate = borrowP2PExchangeRate[_marketAddress].rayMul(
            (WadRayMath.ray() + borrowP2PSPY[_marketAddress]).rayPow(timeDifference)
        ); // In ray
        borrowP2PExchangeRate[_marketAddress] = newBorrowP2PExchangeRate;

        emit P2PExchangeRatesUpdated(
            _marketAddress,
            newSupplyP2PExchangeRate,
            newBorrowP2PExchangeRate
        );
    }

    /// @dev Updates the P2P Second Percentage Yield of supply and borrow.
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
}
