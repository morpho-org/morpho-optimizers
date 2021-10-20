// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import "./libraries/aave/WadRayMath.sol";
import "./interfaces/aave/ILendingPoolAddressesProvider.sol";
import "./interfaces/aave/ILendingPool.sol";
import "./interfaces/aave/DataTypes.sol";
import "./interfaces/IPositionsManagerForAave.sol";
import "./interfaces/IMarketsManagerForAave.sol";

/**
 *  @title MorphoMarketsManagerForAave
 *  @dev Smart contract managing the markets used by MorphoPositionsManagerForX, an other contract interacting with X: Compound or a fork of Compound.
 */
contract MorphoMarketsManagerForAave is Ownable {
    using WadRayMath for uint256;
    using Math for uint256;

    /* Storage */

    bool public isPositionsManagerSet; // Whether or not the positions manager is set.
    mapping(address => bool) public isCreated; // Whether or not this market is created.
    mapping(address => uint256) public p2pBPY; // Block Percentage Yield ("midrate").
    mapping(address => uint256) public mUnitExchangeRate; // current exchange rate from mUnit to underlying.
    mapping(address => uint256) public lastUpdateBlockNumber; // Last time mUnitExchangeRate was updated.

    IPositionsManagerForAave public positionsManagerForAave;
    ILendingPoolAddressesProvider public provider;
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

    /** @dev Emitted when the p2pBPY of a market is updated.
     *  @param _marketAddress The address of the market to update.
     *  @param _newValue The new value of the p2pBPY.
     */
    event BPYUpdated(address _marketAddress, uint256 _newValue);

    /** @dev Emitted when the mUnitExchangeRate of a market is updated.
     *  @param _marketAddress The address of the market to update.
     *  @param _newValue The new value of the mUnitExchangeRate.
     */
    event MUnitExchangeRateUpdated(address _marketAddress, uint256 _newValue);

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

    /* External */

    /** @dev Sets the `positionsManagerForAave` to interact with Compound.
     *  @param _positionsManagerForAave The address of compound module.
     */
    function setPositionsManagerForAave(address _positionsManagerForAave) external onlyOwner {
        require(!isPositionsManagerSet, "positions-manager-already-set");
        isPositionsManagerSet = true;
        positionsManagerForAave = IPositionsManagerForAave(_positionsManagerForAave);
        emit PositionsManagerForAaveSet(_positionsManagerForAave);
    }

    /** @dev Sets the lending pool address.
     *  @param _lendingPoolAddressesProvider The address of Aaves's lending pool addresses provider.
     */
    function setLendingPool(address _lendingPoolAddressesProvider) external onlyOwner {
        provider = ILendingPoolAddressesProvider(_lendingPoolAddressesProvider);
        lendingPool = ILendingPool(provider.getLendingPool());
        // positionsManagerForAave(provider.getLendingPool());
        emit LendingPoolSet(_lendingPoolAddressesProvider);
    }

    /** @dev Creates a new market to borrow/supply.
     *  @param _marketAddress The addresses of the markets to add (aToken).
     */
    function createMarket(address _marketAddress) external onlyOwner {
        require(!isCreated[_marketAddress], "createMarket:mkt-already-created");
        positionsManagerForAave.setThreshold(_marketAddress, 1e18);
        lastUpdateBlockNumber[_marketAddress] = block.number;
        mUnitExchangeRate[_marketAddress] = WadRayMath.ray();
        isCreated[_marketAddress] = true;
        updateBPY(_marketAddress);
        emit MarketCreated(_marketAddress);
    }

    /** @dev Updates the threshold below which suppliers and borrowers cannot join a given market.
     *  @param _marketAddress The address of the market to change the threshold.
     *  @param _newThreshold The new threshold to set.
     */
    function updateThreshold(address _marketAddress, uint256 _newThreshold) external onlyOwner {
        require(_newThreshold > 0, "updateThreshold:threshold!=0");
        positionsManagerForAave.setThreshold(_marketAddress, _newThreshold);
        emit ThresholdUpdated(_marketAddress, _newThreshold);
    }

    /* Public */

    /** @dev Updates the Block Percentage Yield (`p2pBPY`) and calculates the current exchange rate (`mUnitExchangeRate`).
     *  @param _marketAddress The address of the market we want to update.
     */
    function updateBPY(address _marketAddress) public isMarketCreated(_marketAddress) {
        DataTypes.ReserveData memory reserveData = lendingPool.getReserveData(_marketAddress);

        // Update p2pBPY
        p2pBPY[_marketAddress] = Math.average(
            reserveData.currentLiquidityRate,
            reserveData.currentVariableBorrowRate
        ); // In ray

        emit BPYUpdated(_marketAddress, p2pBPY[_marketAddress]);

        // Update mUnitExhangeRate
        updateMUnitExchangeRate(_marketAddress);
    }

    /** @dev Updates the current exchange rate, taking into account the block percentage yield (p2pBPY) since the last time it has been updated.
     *  @param _marketAddress The address of the market we want to update.
     *  @return currentExchangeRate to convert from mUnit to underlying or from underlying to mUnit.
     */
    function updateMUnitExchangeRate(address _marketAddress)
        public
        isMarketCreated(_marketAddress)
        returns (uint256)
    {
        uint256 currentBlock = block.number;

        if (lastUpdateBlockNumber[_marketAddress] == currentBlock) {
            return mUnitExchangeRate[_marketAddress];
        } else {
            uint256 numberOfBlocksSinceLastUpdate = currentBlock -
                lastUpdateBlockNumber[_marketAddress];
            // Update lastUpdateBlockNumber
            lastUpdateBlockNumber[_marketAddress] = currentBlock;

            uint256 newMUnitExchangeRate = mUnitExchangeRate[_marketAddress].rayMul(
                (WadRayMath.ray() + p2pBPY[_marketAddress]).rayPow(numberOfBlocksSinceLastUpdate)
            ); // In ray

            // Update currentExchangeRate
            mUnitExchangeRate[_marketAddress] = newMUnitExchangeRate;
            emit MUnitExchangeRateUpdated(_marketAddress, newMUnitExchangeRate);
            return newMUnitExchangeRate;
        }
    }
}
