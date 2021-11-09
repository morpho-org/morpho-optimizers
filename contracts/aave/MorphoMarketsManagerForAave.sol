// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "./libraries/aave/WadRayMath.sol";
import "./interfaces/aave/ILendingPoolAddressesProvider.sol";
import "./interfaces/aave/IProtocolDataProvider.sol";
import "./interfaces/aave/ILendingPool.sol";
import "./interfaces/aave/DataTypes.sol";
import {IAToken} from "./interfaces/aave/IAToken.sol";
import "./interfaces/IPositionsManagerForAave.sol";
import "./interfaces/IMarketsManagerForAave.sol";

/**
 *  @title MorphoMarketsManagerForAave
 *  @dev Smart contract managing the markets used by MorphoPositionsManagerForX, an other contract interacting with X: Compound or a fork of Compound.
 */
contract MorphoMarketsManagerForAave is Ownable {
    using WadRayMath for uint256;
    using SafeMath for uint256;
    using Math for uint256;

    /* Storage */

    uint256 internal constant SECONDS_PER_YEAR = 365 days;
    bool public isPositionsManagerSet; // Whether or not the positions manager is set.
    mapping(address => bool) public isCreated; // Whether or not this market is created.
    mapping(address => uint256) public p2pSPY; // Second Percentage Yield ("midrate").
    mapping(address => uint256) public p2pUnitExchangeRate; // current exchange rate from p2pUnit to underlying.
    mapping(address => uint256) public lastUpdateTimestamp; // Last time p2pUnitExchangeRate was updated.

    IPositionsManagerForAave public positionsManagerForAave;
    ILendingPoolAddressesProvider public addressesProvider;
    ILendingPool public lendingPool;

    /* Events */

    /** @dev Emitted when a new market is created.
     *  @param _marketAddress The address of the market that has been created.
     */
    event MarketCreated(address _marketAddress);

    /** @dev Emitted when the lendingPool is set on the `positionsManagerForAave`.
     *  @param _lendingPoolAddress The address of the lending pool.
     */
    event LendingPoolSet(address _lendingPoolAddress);

    /** @dev Emitted when the `positionsManagerForAave` is set.
     *  @param _positionsManagerForAave The address of the `positionsManagerForAave`.
     */
    event PositionsManagerForAaveSet(address _positionsManagerForAave);

    /** @dev Emitted when the p2pSPY of a market is updated.
     *  @param _marketAddress The address of the market to update.
     *  @param _newValue The new value of the p2pSPY.
     */
    event P2PSPYUpdated(address _marketAddress, uint256 _newValue);

    /** @dev Emitted when the p2pUnitExchangeRate of a market is updated.
     *  @param _marketAddress The address of the market to update.
     *  @param _newValue The new value of the p2pUnitExchangeRate.
     */
    event P2PUnitExchangeRateUpdated(address _marketAddress, uint256 _newValue);

    /** @dev Emitted when a threshold of a market is updated.
     *  @param _marketAddress The address of the market to update.
     *  @param _newValue The new value of the threshold.
     */
    event ThresholdUpdated(address _marketAddress, uint256 _newValue);

    /* Modifiers */

    /** @dev Prevents to update a market not created yet.
     */
    modifier isMarketCreated(address _marketAddress) {
        require(isCreated[_marketAddress], "mkt-not-created");
        _;
    }

    /* Constructor */

    /** @dev Sets the lending pool addresses provider.
     * _lendingPoolAddressesProvider The address of the lending pool addresses provider.
     */
    constructor(address _lendingPoolAddressesProvider) {
        addressesProvider = ILendingPoolAddressesProvider(_lendingPoolAddressesProvider);
    }

    /* External */

    /** @dev Sets the `positionsManagerForAave` to interact with Compound.
     *  @param _positionsManagerForAave The address of compound module.
     */
    function setPositionsManager(address _positionsManagerForAave) external onlyOwner {
        require(!isPositionsManagerSet, "positions-manager-already-set");
        isPositionsManagerSet = true;
        positionsManagerForAave = IPositionsManagerForAave(_positionsManagerForAave);
        emit PositionsManagerForAaveSet(_positionsManagerForAave);
    }

    /** @dev Sets the lending pool.
     */
    function setLendingPool() external onlyOwner {
        lendingPool = ILendingPool(addressesProvider.getLendingPool());
        emit LendingPoolSet(address(lendingPool));
    }

    /** @dev Creates a new market to borrow/supply.
     *  @param _marketAddress The addresses of the markets to add (aToken).
     */
    function createMarket(address _marketAddress) external onlyOwner {
        require(!isCreated[_marketAddress], "createMarket:mkt-already-created");
        positionsManagerForAave.setThreshold(_marketAddress, 1e18);
        lastUpdateTimestamp[_marketAddress] = block.timestamp;
        p2pUnitExchangeRate[_marketAddress] = WadRayMath.ray();
        isCreated[_marketAddress] = true;
        updateP2PSPY(_marketAddress);
        emit MarketCreated(_marketAddress);
    }

    /** @dev Updates the threshold below which suppliers and borrowers cannot join a given market.
     *  @param _marketAddress The address of the market to change the threshold.
     *  @param _newThreshold The new threshold to set.
     */
    function updateThreshold(address _marketAddress, uint256 _newThreshold)
        external
        onlyOwner
        isMarketCreated(_marketAddress)
    {
        require(_newThreshold > 0, "updateThreshold:threshold!=0");
        positionsManagerForAave.setThreshold(_marketAddress, _newThreshold);
        emit ThresholdUpdated(_marketAddress, _newThreshold);
    }

    /* Public */

    /** @dev Updates the Second Percentage Yield (`p2pSPY`) and calculates the current exchange rate (`p2pUnitExchangeRate`).
     *  @param _marketAddress The address of the market we want to update.
     */
    function updateP2PSPY(address _marketAddress) public isMarketCreated(_marketAddress) {
        DataTypes.ReserveData memory reserveData = lendingPool.getReserveData(
            IAToken(_marketAddress).UNDERLYING_ASSET_ADDRESS()
        );

        // Update p2pSPY
        p2pSPY[_marketAddress] = Math
            .average(reserveData.currentLiquidityRate, reserveData.currentVariableBorrowRate)
            .div(SECONDS_PER_YEAR); // In ray

        emit P2PSPYUpdated(_marketAddress, p2pSPY[_marketAddress]);

        // Update p2pUnitExhangeRate
        updateP2PUnitExchangeRate(_marketAddress);
    }

    /** @dev Updates the current exchange rate, taking into account the Second Percentage Yield (p2pSPY) since the last time it has been updated.
     *  @param _marketAddress The address of the market we want to update.
     *  @return currentExchangeRate to convert from p2pUnit to underlying or from underlying to p2pUnit.
     */
    function updateP2PUnitExchangeRate(address _marketAddress)
        public
        isMarketCreated(_marketAddress)
        returns (uint256)
    {
        uint256 currentTimestamp = block.timestamp;

        if (lastUpdateTimestamp[_marketAddress] == currentTimestamp) {
            return p2pUnitExchangeRate[_marketAddress];
        } else {
            uint256 timeDifference = currentTimestamp - lastUpdateTimestamp[_marketAddress];

            // Update lastUpdateTimestamp
            lastUpdateTimestamp[_marketAddress] = currentTimestamp;

            uint256 newP2PUnitExchangeRate = p2pUnitExchangeRate[_marketAddress].rayMul(
                (WadRayMath.ray() + p2pSPY[_marketAddress]).rayPow(timeDifference)
            ); // In ray

            // Update currentExchangeRate
            p2pUnitExchangeRate[_marketAddress] = newP2PUnitExchangeRate;
            emit P2PUnitExchangeRateUpdated(_marketAddress, newP2PUnitExchangeRate);
            return newP2PUnitExchangeRate;
        }
    }
}
