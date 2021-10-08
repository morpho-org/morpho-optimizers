// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "prb-math/contracts/PRBMathUD60x18.sol";

import {ICErc20, IComptroller} from "./interfaces/ICompound.sol";
import "./interfaces/ICompPositionsManager.sol";
import "./interfaces/ICompMarketsManager.sol";

/**
 *  @title CompPositionsManager
 *  @dev Smart contracts interacting with Compound to enable real P2P lending with cERC20 tokens as lending/borrowing assets.
 */
contract CompMarketsManager is Ownable {
    using PRBMathUD60x18 for uint256;
    using Math for uint256;

    /* Storage */

    mapping(address => bool) public isListed; // Whether or not this market is listed.
    mapping(address => bool) public isEntered; // Whether or not this market is entered.
    mapping(address => uint256) public p2pBPY; // Block Percentage Yield ("midrate").
    mapping(address => uint256) public mUnitExchangeRate; // current exchange rate from mUnit to underlying.
    mapping(address => uint256) public lastUpdateBlockNumber; // Last time mUnitExchangeRate was updated.
    mapping(address => uint256) public thresholds; // Thresholds below the ones suppliers and borrowers cannot enter markets.

    IComptroller public comptroller;
    ICompPositionsManager public compPositionsManager;

    /* Events */

    /** @dev Emitted when a new market is created.
     *  @param _marketAddress The address of the market that has been created.
     */
    event CreateMarket(address _marketAddress);

    /** @dev Emitted when the p2pBPY of a market is updated.
     *  @param _marketAddress The address of the market to update.
     *  @param _newValue The new value of the p2pBPY.
     */
    event UpdateBPY(address _marketAddress, uint256 _newValue);

    /** @dev Emitted when the collateral factor of a market is updated.
     *  @param _marketAddress The address of the market to update.
     *  @param _newValue The new value of the collateral factor.
     */
    event UpdateCollateralFactor(address _marketAddress, uint256 _newValue);

    /** @dev Emitted when the mUnitExchangeRate of a market is updated.
     *  @param _marketAddress The address of the market to update.
     *  @param _newValue The new value of the mUnitExchangeRate.
     */
    event UpdateMUnitExchangeRate(address _marketAddress, uint256 _newValue);

    /** @dev Emitted when a threshold of a market is updated.
     *  @param _marketAddress The address of the market to update.
     *  @param _newValue The new value of the threshold.
     */
    event UpdateThreshold(address _marketAddress, uint256 _newValue);

    /* Constructor */

    constructor(address _proxyComptrollerAddress) {
        comptroller = IComptroller(_proxyComptrollerAddress);
    }

    /* External */

    /** @dev Sets the `compPositionsManager` to interact with Compound.
     *  @param _compPositionsManager The address of compound module.
     */
    function setCompPositionsManager(ICompPositionsManager _compPositionsManager)
        external
        onlyOwner
    {
        compPositionsManager = _compPositionsManager;
    }

    /** @dev Sets the comptroller address.
     *  @param _proxyComptrollerAddress The address of Compound's comptroller.
     */
    function setComptroller(address _proxyComptrollerAddress) external onlyOwner {
        comptroller = IComptroller(_proxyComptrollerAddress);
        compPositionsManager.setComptroller(_proxyComptrollerAddress);
    }

    /** @dev Creates new market to borrow/lend.
     *  @param _marketAddresses The addresses of the markets to add.
     */
    function createMarkets(address[] calldata _marketAddresses) external onlyOwner {
        uint256[] memory results = compPositionsManager.enterMarkets(_marketAddresses);
        for (uint256 i; i < _marketAddresses.length; i++) {
            require(results[i] == 0, "createMarkets: enter market failed on Compound");
            address _marketAddress = _marketAddresses[i];
            require(!isEntered[_marketAddress], "createMarkets: market already entered");
            isEntered[_marketAddress] = true;
            mUnitExchangeRate[_marketAddress] = 1e18;
            lastUpdateBlockNumber[_marketAddress] = block.number;
            thresholds[_marketAddress] = 1e18;
            updateBPY(_marketAddress);
            emit CreateMarket(_marketAddress);
        }
    }

    /** @dev Sets a market as listed.
     *  @param _marketAddress The address of the market to list.
     */
    function listMarket(address _marketAddress) external onlyOwner {
        isListed[_marketAddress] = true;
    }

    /** @dev Sets a market as unlisted.
     *  @param _marketAddress The address of the market to unlist.
     */
    function unlistMarket(address _marketAddress) external onlyOwner {
        isListed[_marketAddress] = false;
    }

    /** @dev Updates thresholds below the ones suppliers and borrowers cannot enter markets.
     *  @param _marketAddress The address of the market to change the threshold.
     *  @param _newThreshold The new threshold to set.
     */
    function updateThreshold(address _marketAddress, uint256 _newThreshold) external onlyOwner {
        require(_newThreshold > 0, "morpho: new THRESHOLD must be strictly positive.");
        thresholds[_marketAddress] = _newThreshold;
        emit UpdateThreshold(_marketAddress, _newThreshold);
    }

    /* Public */

    /** @dev Updates the Block Percentage Yield (`p2pBPY`) and calculate the current exchange rate (`mUnitExchangeRate`).
     *  @param _marketAddress The address of the market we want to update.
     */
    function updateBPY(address _marketAddress) public {
        ICErc20 cErc20Token = ICErc20(_marketAddress);

        // Update p2pBPY
        uint256 supplyBPY = cErc20Token.supplyRatePerBlock();
        uint256 borrowBPY = cErc20Token.borrowRatePerBlock();
        p2pBPY[_marketAddress] = Math.average(supplyBPY, borrowBPY);

        emit UpdateBPY(_marketAddress, p2pBPY[_marketAddress]);

        // Update mUnitExhangeRate
        updateMUnitExchangeRate(_marketAddress);
    }

    /** @dev Updates the current exchange rate, taking into account the block percentage yield (p2pBPY) since the last time it has been updated.
     *  @param _marketAddress The address of the market we want to update.
     *  @return currentExchangeRate to convert from mUnit to underlying or from underlying to mUnit.
     */
    function updateMUnitExchangeRate(address _marketAddress) public returns (uint256) {
        uint256 currentBlock = block.number;

        if (lastUpdateBlockNumber[_marketAddress] == currentBlock) {
            return mUnitExchangeRate[_marketAddress];
        } else {
            uint256 numberOfBlocksSinceLastUpdate = currentBlock -
                lastUpdateBlockNumber[_marketAddress];

            uint256 newMUnitExchangeRate = mUnitExchangeRate[_marketAddress].mul(
                (1e18 + p2pBPY[_marketAddress]).pow(
                    PRBMathUD60x18.fromUint(numberOfBlocksSinceLastUpdate)
                )
            );

            emit UpdateMUnitExchangeRate(_marketAddress, newMUnitExchangeRate);

            // Update currentExchangeRate
            mUnitExchangeRate[_marketAddress] = newMUnitExchangeRate;

            // Update lastUpdateBlockNumber
            lastUpdateBlockNumber[_marketAddress] = currentBlock;

            return newMUnitExchangeRate;
        }
    }
}
