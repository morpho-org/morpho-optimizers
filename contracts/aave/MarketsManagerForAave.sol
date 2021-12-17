// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "./libraries/aave/WadRayMath.sol";
import "./libraries/ErrorsForAave.sol";
import "./interfaces/aave/ILendingPoolAddressesProvider.sol";
import "./interfaces/aave/IProtocolDataProvider.sol";
import "./interfaces/aave/ILendingPool.sol";
import "./interfaces/aave/DataTypes.sol";
import {IAToken} from "./interfaces/aave/IAToken.sol";
import "./interfaces/IMarketsManagerForAave.sol";
import "../common/interfaces/IPositionsManager.sol";

/**
 *  @title MarketsManagerForAave
 *  @dev Smart contract managing the markets used by a MorphoPositionsManagerForAave contract, an other contract interacting with Aave or a fork of Aave.
 */
contract MarketsManagerForAave is Ownable {
    using WadRayMath for uint256;
    using SafeMath for uint256;
    using Math for uint256;

    /* Storage */

    uint256 internal constant SECONDS_PER_YEAR = 365 days;
    mapping(address => bool) public isCreated; // Whether or not this market is created.
    mapping(address => uint256) public p2pSPY; // Second Percentage Yield ("midrate").
    mapping(address => uint256) public p2pExchangeRate; // Current exchange rate from p2pUnit to underlying.
    mapping(address => uint256) public lastUpdateTimestamp; // Last time p2pExchangeRate was updated.

    IPositionsManager public positionsManagerForAave;
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

    /** @dev Emitted when the p2pExchangeRate of a market is updated.
     *  @param _marketAddress The address of the market to update.
     *  @param _newValue The new value of the p2pExchangeRate.
     */
    event P2PExchangeRateUpdated(address _marketAddress, uint256 _newValue);

    /** @dev Emitted when a threshold of a market is updated.
     *  @param _marketAddress The address of the market to update.
     *  @param _newValue The new value of the threshold.
     */
    event ThresholdUpdated(address _marketAddress, uint256 _newValue);

    /** @dev Emitted when a cap value of a market is updated.
     *  @param _marketAddress The address of the market to update.
     *  @param _newValue The new value of the cap.
     */
    event CapValueUpdated(address _marketAddress, uint256 _newValue);

    /** @dev Emitted the maximum number of users to have in the tree is updated.
     *  @param _newValue The new value of the maximum number of users to have in the tree.
     */
    event MaxNumberUpdated(uint16 _newValue);

    /* Modifiers */

    /** @dev Prevents to update a market not created yet.
     */
    modifier isMarketCreated(address _marketAddress) {
        require(isCreated[_marketAddress], Errors.MM_MARKET_NOT_CREATED);
        _;
    }

    /* Constructor */

    /** @dev Constructs the MarketsManagerForAave contract.
     *  @param _lendingPoolAddressesProvider The address of the lending pool addresses provider.
     */
    constructor(address _lendingPoolAddressesProvider) {
        addressesProvider = ILendingPoolAddressesProvider(_lendingPoolAddressesProvider);
    }

    /* External */

    /** @dev Sets the `positionsManagerForAave` to interact with Aave.
     *  @param _positionsManagerForAave The address of compound module.
     */
    function setPositionsManager(address _positionsManagerForAave) external onlyOwner {
        require(address(positionsManagerForAave) == address(0), Errors.MM_POSITIONS_MANAGER_SET);
        positionsManagerForAave = IPositionsManager(_positionsManagerForAave);
        emit PositionsManagerForAaveSet(_positionsManagerForAave);
    }

    /** @dev Updates the lending pool.
     */
    function updateLendingPool() external onlyOwner {
        lendingPool = ILendingPool(addressesProvider.getLendingPool());
        emit LendingPoolSet(address(lendingPool));
    }

    /** @dev Sets the maximum number of users in tree.
     *  @param _maxIterations The maximum number of users to have in the tree.
     */
    function updateMaxIterations(uint16 _maxIterations) external onlyOwner {
        positionsManagerForAave.updateMaxIterations(_maxIterations);
        emit MaxNumberUpdated(_maxIterations);
    }

    function updatePositionsUpdatorLogic(address _positionsUpdatorLogic) external onlyOwner {
        positionsManagerForAave.updatePositionsUpdatorLogic(_positionsUpdatorLogic);
    }

    /** @dev Creates a new market to borrow/supply.
     *  @param _marketAddress The addresses of the markets to add (aToken).
     *  @param _threshold The threshold to set for the market.
     *  @param _capValue The cap value to set for the market.
     */
    function createMarket(
        address _marketAddress,
        uint256 _threshold,
        uint256 _capValue
    ) external onlyOwner {
        require(!isCreated[_marketAddress], Errors.MM_MARKET_ALREADY_CREATED);
        positionsManagerForAave.setThreshold(_marketAddress, _threshold);
        positionsManagerForAave.setCapValue(_marketAddress, _capValue);
        lastUpdateTimestamp[_marketAddress] = block.timestamp;
        p2pExchangeRate[_marketAddress] = WadRayMath.ray();
        isCreated[_marketAddress] = true;
        _updateSPY(_marketAddress);
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
        positionsManagerForAave.setThreshold(_marketAddress, _newThreshold);
        emit ThresholdUpdated(_marketAddress, _newThreshold);
    }

    /** @dev Updates the cap value above which suppliers cannot supply more tokens.
     *  @param _marketAddress The address of the market to change the max cap.
     *  @param _newCapValue The new max cap to set.
     */
    function updateCapValue(address _marketAddress, uint256 _newCapValue)
        external
        onlyOwner
        isMarketCreated(_marketAddress)
    {
        positionsManagerForAave.setCapValue(_marketAddress, _newCapValue);
        emit CapValueUpdated(_marketAddress, _newCapValue);
    }

    /* Public */

    /** @dev Updates the Second Percentage Yield (`p2pSPY`) and calculates the current exchange rate (`p2pExchangeRate`).
     *  @param _marketAddress The address of the market we want to update.
     */
    function updateRates(address _marketAddress) public isMarketCreated(_marketAddress) {
        if (lastUpdateTimestamp[_marketAddress] != block.timestamp) {
            _updateP2PExchangeRate(_marketAddress);
            _updateSPY(_marketAddress);
            lastUpdateTimestamp[_marketAddress] = block.timestamp;
        }
    }

    /* Internal */

    /** @dev Updates the P2P exchange rate, taking into account the Second Percentage Yield (`p2pSPY`) since the last time it has been updated.
     *  @param _marketAddress The address of the market to update.
     */
    function _updateP2PExchangeRate(address _marketAddress) internal {
        uint256 timeDifference = block.timestamp - lastUpdateTimestamp[_marketAddress];
        uint256 newP2PExchangeRate = p2pExchangeRate[_marketAddress].rayMul(
            (WadRayMath.ray() + p2pSPY[_marketAddress]).rayPow(timeDifference)
        ); // In ray

        p2pExchangeRate[_marketAddress] = newP2PExchangeRate;
        emit P2PExchangeRateUpdated(_marketAddress, newP2PExchangeRate);
    }

    /** @dev Updates the Second Percentage Yield (`p2pSPY`).
     *  @param _marketAddress The address of the market to update.
     */
    function _updateSPY(address _marketAddress) internal {
        DataTypes.ReserveData memory reserveData = lendingPool.getReserveData(
            IAToken(_marketAddress).UNDERLYING_ASSET_ADDRESS()
        );

        p2pSPY[_marketAddress] = Math
            .average(reserveData.currentLiquidityRate, reserveData.currentVariableBorrowRate)
            .div(SECONDS_PER_YEAR); // In ray
        emit P2PSPYUpdated(_marketAddress, p2pSPY[_marketAddress]);
    }
}
