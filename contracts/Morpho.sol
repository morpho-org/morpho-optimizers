// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "prb-math/contracts/PRBMathUD60x18.sol";

import {ICErc20, IComptroller} from "./interfaces/ICompound.sol";
import "./interfaces/ICompoundModule.sol";
import "./interfaces/IMorpho.sol";

/**
 *  @title CompoundModule
 *  @dev Smart contracts interacting with Compound to enable real P2P lending with cERC20 tokens as lending/borrowing assets.
 */
contract Morpho is Ownable {
    using PRBMathUD60x18 for uint256;
    using Math for uint256;

    enum Threshold {
        Underlying,
        CToken,
        MUnit,
        CdUnit
    }

    /* Storage */

    mapping(address => bool) public isListed; // Whether or not this market is listed.
    mapping(address => uint256) public BPY; // Block Percentage Yield ("midrate").
    mapping(address => uint256) public mUnitExchangeRate; // current exchange rate from mUnit to underlying.
    mapping(address => uint256) public lastUpdateBlockNumber; // Last time mUnitExchangeRate was updated.
    mapping(address => mapping(Threshold => uint256)) public thresholds; // Thresholds below the ones we remove lenders and borrowers from the lists. 0 -> Underlying, 1 -> cToken, 2 -> mUnit

    IComptroller public comptroller;
    ICompoundModule public compoundModule;

    /* Events */

    /** @dev Emitted when a new market is created.
     *  @param _marketAddress The address of the market that has been created.
     */
    event CreateMarket(address _marketAddress);

    /** @dev Emitted when the BPY of a market is updated.
     *  @param _marketAddress The address of the market to update.
     *  @param _newValue The new value of the BPY.
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
     *  @param _thresholdType The threshold type to update.
     *  @param _newValue The new value of the threshold.
     */
    event UpdateThreshold(address _marketAddress, Threshold _thresholdType, uint256 _newValue);

    /* Constructor */

    constructor(address _proxyComptrollerAddress) {
        comptroller = IComptroller(_proxyComptrollerAddress);
    }

    /* External */

    /** @dev Sets the compound module to interact with Compound.
     *  @param _compoundModule The address of compound module.
     */
    function setCompoundModule(ICompoundModule _compoundModule) external onlyOwner {
        compoundModule = _compoundModule;
    }

    /** @dev Sets the comptroller address.
     *  @param _proxyComptrollerAddress The address of Compound's comptroller.
     */
    function setComptroller(address _proxyComptrollerAddress) external onlyOwner {
        comptroller = IComptroller(_proxyComptrollerAddress);
        compoundModule.setComptroller(_proxyComptrollerAddress);
    }

    /** @dev Creates new market to borrow/lend.
     *  @param _marketAddresses The addresses of the markets to add.
     */
    function createMarkets(address[] calldata _marketAddresses) external onlyOwner {
        uint256[] memory results = compoundModule.enterMarkets(_marketAddresses);
        for (uint256 i; i < _marketAddresses.length; i++) {
            require(results[i] == 0, "createMarkets: enter market failed on Compound");
            address _marketAddress = _marketAddresses[i];
            require(
                lastUpdateBlockNumber[_marketAddress] == 0,
                "createMarkets: market already created"
            );
            mUnitExchangeRate[_marketAddress] = 1e18;
            lastUpdateBlockNumber[_marketAddress] = block.number;
            thresholds[_marketAddress][Threshold.Underlying] = 1e18;
            thresholds[_marketAddress][Threshold.CToken] = 1e7;
            thresholds[_marketAddress][Threshold.MUnit] = 1e18;
            thresholds[_marketAddress][Threshold.CdUnit] = 1e16;
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

    /** @dev Updates thresholds below the ones lenders and borrowers are removed from lists.
     *  @param _marketAddress The address of the market to change the threshold.
     *  @param _thresholdType Which threshold must be updated.
     *  @param _newThreshold The new threshold to set.
     */
    function updateThreshold(
        address _marketAddress,
        Threshold _thresholdType,
        uint256 _newThreshold
    ) external onlyOwner {
        require(_newThreshold > 0, "morpho: new THRESHOLD must be strictly positive.");
        thresholds[_marketAddress][_thresholdType] = _newThreshold;
        emit UpdateThreshold(_marketAddress, _thresholdType, _newThreshold);
    }

    /* Public */

    /** @dev Updates the Block Percentage Yield (`BPY`) and calculate the current exchange rate (`mUnitExchangeRate`).
     *  @param _marketAddress The address of the market we want to update.
     */
    function updateBPY(address _marketAddress) public {
        ICErc20 cErc20Token = ICErc20(_marketAddress);

        // Update BPY
        uint256 lendBPY = cErc20Token.supplyRatePerBlock();
        uint256 borrowBPY = cErc20Token.borrowRatePerBlock();
        BPY[_marketAddress] = Math.average(lendBPY, borrowBPY);

        emit UpdateBPY(_marketAddress, BPY[_marketAddress]);

        // Update mUnitExhangeRate
        updateMUnitExchangeRate(_marketAddress);
    }

    /** @dev Updates the current exchange rate, taking into account the block percentage yield (BPY) since the last time it has been updated.
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
                (1e18 + BPY[_marketAddress]).pow(
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
