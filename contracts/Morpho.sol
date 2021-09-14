// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "prb-math/contracts/PRBMathUD60x18.sol";

import {ICErc20, IComptroller, ICompoundOracle} from "./interfaces/ICompound.sol";
import "./interfaces/ICompoundModule.sol";

/**
 *  @title CompoundModule
 *  @dev Smart contracts interacting with Compound to enable real P2P lending with cERC20 tokens as lending/borrowing assets.
 */
contract Morpho is Ownable {
    using PRBMathUD60x18 for uint256;
    using Math for uint256;

    /* Storage */

    uint256 public liquidationIncentive = 1.1e18; // Incentive for liquidators in percentage (110%).

    mapping(address => bool) public isListed; // Whether or not this market is listed.
    mapping(address => uint256) public BPY; // Block Percentage Yield ("midrate").
    mapping(address => uint256) public collateralFactor; // Multiplier representing the most one can borrow against their collateral in this market (0.9 => borrow 90% of collateral value max). Between 0 and 1.
    mapping(address => uint256) public mUnitExchangeRate; // current exchange rate from mUnit to underlying.
    mapping(address => uint256) public lastUpdateBlockNumber; // Last time mUnitExchangeRate was updated.
    mapping(address => mapping(uint256 => uint256)) public thresholds; // Thresholds below the ones we remove lenders and borrowers from the lists. 0 -> Underlying, 1 -> cToken, 2 -> mUnit

    IComptroller public comptroller;
    ICompoundModule public compoundModule;
    ICompoundOracle public compoundOracle;

    /* Events */

    event CreateMarket(address _cErc20Address);
    event UpdateBPY(address _cErc20Address, uint256 _newValue);
    event UpdateMUnitExchangeRate(address _cErc20Address, uint256 _newValue);
    event UpdateThreshold(
        address _cErc20Address,
        uint256 _thresholdType,
        uint256 _newValue
    );

    /* Constructor */

    constructor(address _proxyComptrollerAddress) {
        comptroller = IComptroller(_proxyComptrollerAddress);
        address compoundOracleAddress = comptroller.oracle();
        compoundOracle = ICompoundOracle(compoundOracleAddress);
    }

    /* External */

    /** @dev Sets the compound module to interact with Compound.
     *  @param _compoundModule The address of compound module.
     */
    function setCompoundModule(ICompoundModule _compoundModule)
        external
        onlyOwner
    {
        compoundModule = _compoundModule;
    }

    /** @dev Creates new market to borrow/lend.
     *  @param _cTokensAddresses The addresses of the markets to add.
     */
    function createMarkets(address[] calldata _cTokensAddresses)
        external
        onlyOwner
    {
        uint256[] memory results = compoundModule.enterMarkets(
            _cTokensAddresses
        );
        for (uint256 i; i < _cTokensAddresses.length; i++) {
            require(results[i] == 0, "Enter market failed on Compound");
            address cTokenAddress = _cTokensAddresses[i];
            mUnitExchangeRate[cTokenAddress] = 1e18;
            lastUpdateBlockNumber[cTokenAddress] = block.number;
            thresholds[cTokenAddress][0] = 1e18;
            thresholds[cTokenAddress][1] = 1e7;
            thresholds[cTokenAddress][2] = 1e18;
            updateBPY(cTokenAddress);
            updateCollateralFactor(cTokenAddress);
        }
    }

    /** @dev Sets a market as listed.
     *  @param _cTokenAddress The address of the market to list.
     */
    function listMarket(address _cTokenAddress) external onlyOwner {
        isListed[_cTokenAddress] = true;
    }

    /** @dev Sets a market as unlisted.
     *  @param _cTokenAddress The address of the market to unlist.
     */
    function unlistMarket(address _cTokenAddress) external onlyOwner {
        isListed[_cTokenAddress] = false;
    }

    /** @dev Updates thresholds below the ones lenders and borrowers are removed from lists.
     *  @param _thresholdType Which threshold must be updated. 0 -> Underlying, 1 -> cToken, 2 -> mUnit
     *  @param _newThreshold The new threshold to set.
     */
    function updateThreshold(
        address _cErc20Address,
        uint256 _thresholdType,
        uint256 _newThreshold
    ) external onlyOwner {
        require(_newThreshold > 0, "New THRESHOLD must be strictly positive.");
        thresholds[_cErc20Address][_thresholdType] = _newThreshold;
    }

    /* Public */

    /** @dev Updates the collateral factor related to cToken.
     *  @param _cErc20Address The address of the market we want to update.
     */
    function updateCollateralFactor(address _cErc20Address) public {
        (, uint256 collateralFactorMantissa, ) = comptroller.markets(
            _cErc20Address
        );
        collateralFactor[_cErc20Address] = collateralFactorMantissa;
    }

    /** @dev Updates the Block Percentage Yield (`BPY`) and calculate the current exchange rate (`currentExchangeRate`).
     *  @param _cErc20Address The address of the market we want to update.
     */
    function updateBPY(address _cErc20Address) public {
        ICErc20 cErc20Token = ICErc20(_cErc20Address);

        // Update BPY
        uint256 lendBPY = cErc20Token.supplyRatePerBlock();
        uint256 borrowBPY = cErc20Token.borrowRatePerBlock();
        BPY[_cErc20Address] = Math.average(lendBPY, borrowBPY);

        emit UpdateBPY(_cErc20Address, BPY[_cErc20Address]);

        // Update currentExchangeRate
        updateMUnitExchangeRate(_cErc20Address);
    }

    /** @dev Updates the current exchange rate, taking into account the block percentage yield (BPY) since the last time it has been updated.
     *  @param _cErc20Address The address of the market we want to update.
     *  @return currentExchangeRate to convert from mUnit to underlying or from underlying to mUnit.
     */
    function updateMUnitExchangeRate(address _cErc20Address)
        public
        returns (uint256)
    {
        uint256 currentBlock = block.number;

        if (lastUpdateBlockNumber[_cErc20Address] == currentBlock) {
            return mUnitExchangeRate[_cErc20Address];
        } else {
            uint256 numberOfBlocksSinceLastUpdate = currentBlock -
                lastUpdateBlockNumber[_cErc20Address];

            uint256 newMUnitExchangeRate = mUnitExchangeRate[_cErc20Address]
                .mul(
                    (1e18 + BPY[_cErc20Address]).pow(
                        PRBMathUD60x18.fromUint(numberOfBlocksSinceLastUpdate)
                    )
                );

            emit UpdateMUnitExchangeRate(_cErc20Address, newMUnitExchangeRate);

            // Update currentExchangeRate
            mUnitExchangeRate[_cErc20Address] = newMUnitExchangeRate;

            // Update lastUpdateBlockNumber
            lastUpdateBlockNumber[_cErc20Address] = currentBlock;

            return newMUnitExchangeRate;
        }
    }
}
