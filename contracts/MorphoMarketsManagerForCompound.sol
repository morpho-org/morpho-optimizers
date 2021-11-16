// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "prb-math/contracts/PRBMathUD60x18.sol";
import "./libraries/CompoundMath.sol";

import {ICErc20, IComptroller} from "./interfaces/compound/ICompound.sol";
import "./interfaces/IPositionsManagerForCompound.sol";
import "./interfaces/IMarketsManagerForCompound.sol";

/**
 *  @title MorphoMarketsManagerForCompound
 *  @dev Smart contract managing the markets used by MorphoPositionsManagerForX, an other contract interacting with X: Compound or a fork of Compound.
 */
contract MorphoMarketsManagerForCompound is Ownable {
    using CompoundMath for uint256;
    using Math for uint256;

    /* Storage */

    bool public isPositionsManagerSet; // Whether or not the positions manager is set.
    mapping(address => bool) public isCreated; // Whether or not this market is created.
    mapping(address => uint256) public p2pBPY; // Block Percentage Yield ("midrate").
    mapping(address => uint256) public p2pUnitExchangeRate; // current exchange rate from p2pUnit to underlying.
    mapping(address => uint256) public lastUpdateBlockNumber; // Last time p2pUnitExchangeRate was updated.

    IPositionsManagerForCompound public positionsManagerForCompound;

    /* Events */

    /** @dev Emitted when a new market is created.
     *  @param _marketAddress The address of the market that has been created.
     */
    event MarketCreated(address _marketAddress);

    /** @dev Emitted when the comptroller is set on the `compoundPositionsManager`.
     *  @param _comptrollerAddress The address of the comptroller proxy.
     */
    event ComptrollerSet(address _comptrollerAddress);

    /** @dev Emitted when the `positionsManagerForCompound` is set.
     *  @param _positionsManagerForCompound The address of the `positionsManagerForCompound`.
     */
    event PositionsManagerForCompoundSet(address _positionsManagerForCompound);

    /** @dev Emitted when the p2pBPY of a market is updated.
     *  @param _marketAddress The address of the market to update.
     *  @param _newValue The new value of the p2pBPY.
     */
    event BPYUpdated(address _marketAddress, uint256 _newValue);

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

    /** @dev Emitted the maximum number of users to have in the data structure is updated.
     *  @param _newValue The new value of the maximum number of users to have in the data structure.
     */
    event MaxNumberUpdated(uint16 _newValue);

    /* Modifiers */

    /** @dev Prevents to update a market not created yet.
     */
    modifier isMarketCreated(address _marketAddress) {
        require(isCreated[_marketAddress], "0");
        _;
    }

    /* External */

    /** @dev Sets the `positionsManagerForCompound` to interact with Compound.
     *  @param _positionsManagerForCompound The address of compound module.
     */
    function setPositionsManagerForCompound(address _positionsManagerForCompound)
        external
        onlyOwner
    {
        require(!isPositionsManagerSet, "1");
        isPositionsManagerSet = true;
        positionsManagerForCompound = IPositionsManagerForCompound(_positionsManagerForCompound);
        emit PositionsManagerForCompoundSet(_positionsManagerForCompound);
    }

    /** @dev Sets the comptroller address.
     *  @param _proxyComptrollerAddress The address of Compound's comptroller.
     */
    function setComptroller(address _proxyComptrollerAddress) external onlyOwner {
        positionsManagerForCompound.setComptroller(_proxyComptrollerAddress);
        emit ComptrollerSet(_proxyComptrollerAddress);
    }

    /** @dev Sets the maximum number of users in data structure.
     *  @param _newMaxNumber The maximum number of users to have in the data structure.
     */
    function setMaxNumberOfUsersInDataStructure(uint16 _newMaxNumber) external onlyOwner {
        require(_newMaxNumber > 1, "2");
        positionsManagerForCompound.setMaxNumberOfUsersInDataStructure(_newMaxNumber);
        emit MaxNumberUpdated(_newMaxNumber);
    }

    /** @dev Creates a new market to borrow/supply.
     *  @param _marketAddress The addresses of the markets to add (cToken).
     */
    function createMarket(address _marketAddress) external onlyOwner {
        require(!isCreated[_marketAddress], "3");
        uint256[] memory results = positionsManagerForCompound.createMarket(_marketAddress);
        require(results[0] == 0, "4");
        positionsManagerForCompound.setThreshold(_marketAddress, 1e18);
        lastUpdateBlockNumber[_marketAddress] = block.number;
        p2pUnitExchangeRate[_marketAddress] = 1e18;
        isCreated[_marketAddress] = true;
        updateBPY(_marketAddress);
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
        require(_newThreshold > 0, "5");
        positionsManagerForCompound.setThreshold(_marketAddress, _newThreshold);
        emit ThresholdUpdated(_marketAddress, _newThreshold);
    }

    /* Public */

    /** @dev Updates the Block Percentage Yield (`p2pBPY`) and calculates the current exchange rate (`p2pUnitExchangeRate`).
     *  @param _marketAddress The address of the market we want to update.
     */
    function updateBPY(address _marketAddress) public isMarketCreated(_marketAddress) {
        ICErc20 cErc20Token = ICErc20(_marketAddress);

        // Update p2pBPY
        uint256 supplyBPY = cErc20Token.supplyRatePerBlock();
        uint256 borrowBPY = cErc20Token.borrowRatePerBlock();
        p2pBPY[_marketAddress] = Math.average(supplyBPY, borrowBPY);

        emit BPYUpdated(_marketAddress, p2pBPY[_marketAddress]);

        // Update p2pUnitExchangeRate
        updateP2pUnitExchangeRate(_marketAddress);
    }

    /** @dev Updates the current exchange rate, taking into account the block percentage yield (p2pBPY) since the last time it has been updated.
     *  @param _marketAddress The address of the market we want to update.
     *  @return currentExchangeRate to convert from p2pUnit to underlying or from underlying to p2pUnit.
     */
    function updateP2pUnitExchangeRate(address _marketAddress)
        public
        isMarketCreated(_marketAddress)
        returns (uint256)
    {
        uint256 currentBlock = block.number;

        if (lastUpdateBlockNumber[_marketAddress] == currentBlock) {
            return p2pUnitExchangeRate[_marketAddress];
        } else {
            uint256 numberOfBlocksSinceLastUpdate = currentBlock -
                lastUpdateBlockNumber[_marketAddress];
            // Update lastUpdateBlockNumber
            lastUpdateBlockNumber[_marketAddress] = currentBlock;

            uint256 newP2pUnitExchangeRate = p2pUnitExchangeRate[_marketAddress].mul(
                PRBMathUD60x18.pow(
                    1e18 + p2pBPY[_marketAddress],
                    PRBMathUD60x18.fromUint(numberOfBlocksSinceLastUpdate)
                )
            );

            // Update currentExchangeRate
            p2pUnitExchangeRate[_marketAddress] = newP2pUnitExchangeRate;
            emit P2PUnitExchangeRateUpdated(_marketAddress, newP2pUnitExchangeRate);
            return newP2pUnitExchangeRate;
        }
    }
}
