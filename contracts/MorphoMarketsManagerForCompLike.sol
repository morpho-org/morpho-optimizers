// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "prb-math/contracts/PRBMathUD60x18.sol";

import {ICErc20, IComptroller} from "./interfaces/compound/ICompound.sol";
import "./interfaces/IPositionsManagerForCompLike.sol";
import "./interfaces/IMarketsManagerForCompLike.sol";

/**
 *  @title MorphoMarketsManagerForCompLike
 *  @dev Smart contract managing the markets used by MorphoPositionsManagerForX, an other contract interacting with X: Compound or a fork of Compound.
 */
contract MorphoMarketsManagerForCompLike is Ownable {
    using PRBMathUD60x18 for uint256;
    using Math for uint256;

    /* Storage */

    bool public isPositionsManagerSet; // Whether or not the positions manager is set.
    mapping(address => bool) public isCreated; // Whether or not this market is created.
    mapping(address => uint256) public p2pBPY; // Block Percentage Yield ("midrate").
    mapping(address => uint256) public mUnitExchangeRate; // current exchange rate from mUnit to underlying.
    mapping(address => uint256) public lastUpdateBlockNumber; // Last time mUnitExchangeRate was updated.

    IPositionsManagerForCompLike public positionsManagerForCompLike;

    /* Events */

    /** @dev Emitted when a new market is created.
     *  @param _marketAddress The address of the market that has been created.
     */
    event MarketCreated(address _marketAddress);

    /** @dev Emitted when the comptroller is set on the `compLikePositionsManager`.
     *  @param _comptrollerAddress The address of the comptroller proxy.
     */
    event ComptrollerSet(address _comptrollerAddress);

    /** @dev Emitted when the `positionsManagerForCompLike` is set.
     *  @param _positionsManagerForCompLike The address of the `positionsManagerForCompLike`.
     */
    event PositionsManagerForCompLikeSet(address _positionsManagerForCompLike);

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

    /** @dev Sets the `positionsManagerForCompLike` to interact with Compound.
     *  @param _positionsManagerForCompLike The address of compound module.
     */
    function setPositionsManagerForCompLike(address _positionsManagerForCompLike)
        external
        onlyOwner
    {
        require(!isPositionsManagerSet, "positions-manager-already-set");
        isPositionsManagerSet = true;
        positionsManagerForCompLike = IPositionsManagerForCompLike(_positionsManagerForCompLike);
        emit PositionsManagerForCompLikeSet(_positionsManagerForCompLike);
    }

    /** @dev Sets the comptroller address.
     *  @param _proxyComptrollerAddress The address of Compound's comptroller.
     */
    function setComptroller(address _proxyComptrollerAddress) external onlyOwner {
        positionsManagerForCompLike.setComptroller(_proxyComptrollerAddress);
        emit ComptrollerSet(_proxyComptrollerAddress);
    }

    /** @dev Creates a new market to borrow/supply.
     *  @param _marketAddress The addresses of the markets to add (cToken).
     */
    function createMarket(address _marketAddress) external onlyOwner {
        require(!isCreated[_marketAddress], "createMarket:mkt-already-created");
        uint256[] memory results = positionsManagerForCompLike.createMarket(_marketAddress);
        require(results[0] == 0, "createMarket:enter-mkt-fail");
        positionsManagerForCompLike.setThreshold(_marketAddress, 1e18);
        lastUpdateBlockNumber[_marketAddress] = block.number;
        mUnitExchangeRate[_marketAddress] = 1e18;
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
        positionsManagerForCompLike.setThreshold(_marketAddress, _newThreshold);
        emit ThresholdUpdated(_marketAddress, _newThreshold);
    }

    /* Public */

    /** @dev Updates the Block Percentage Yield (`p2pBPY`) and calculates the current exchange rate (`mUnitExchangeRate`).
     *  @param _marketAddress The address of the market we want to update.
     */
    function updateBPY(address _marketAddress) public isMarketCreated(_marketAddress) {
        ICErc20 cErc20Token = ICErc20(_marketAddress);

        // Update p2pBPY
        uint256 supplyBPY = cErc20Token.supplyRatePerBlock();
        uint256 borrowBPY = cErc20Token.borrowRatePerBlock();
        p2pBPY[_marketAddress] = Math.average(supplyBPY, borrowBPY);

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

            uint256 newMUnitExchangeRate = mUnitExchangeRate[_marketAddress].mul(
                (1e18 + p2pBPY[_marketAddress]).pow(
                    PRBMathUD60x18.fromUint(numberOfBlocksSinceLastUpdate)
                )
            );

            // Update currentExchangeRate
            mUnitExchangeRate[_marketAddress] = newMUnitExchangeRate;
            emit MUnitExchangeRateUpdated(_marketAddress, newMUnitExchangeRate);
            return newMUnitExchangeRate;
        }
    }
}
