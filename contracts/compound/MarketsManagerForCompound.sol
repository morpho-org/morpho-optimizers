// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.10;

import {ICErc20, IComptroller} from "./interfaces/compound/ICompound.sol";
import "./interfaces/IPositionsManagerForCompound.sol";

import "./libraries/CompoundMath.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "prb-math/contracts/PRBMathUD60x18.sol";

/// @title MarketsManagerForCompound.
/// @dev Smart contract managing the markets used by MorphoPositionsManagerForX, an other contract interacting with X: Compound or a fork of Compound.
contract MarketsManagerForCompound is Ownable {
    using CompoundMath for uint256;
    using Math for uint256;

    /// Storage ///

    mapping(address => bool) public isCreated; // Whether or not this market is created.
    mapping(address => uint256) public p2pBPY; // Block Percentage Yield ("midrate").
    mapping(address => uint256) public p2pExchangeRate; // Current exchange rate from p2pUnit to underlying.
    mapping(address => uint256) public lastUpdateBlockNumber; // Last time p2pExchangeRate was updated.

    IPositionsManagerForCompound public positionsManagerForCompound;

    /// Events ///

    /// @dev Emitted when a new market is created.
    /// @param _marketAddress The address of the market that has been created.
    event MarketCreated(address _marketAddress);

    /// @dev Emitted when the `positionsManagerForCompound` is set.
    /// @param _positionsManagerForCompound The address of the `positionsManagerForCompound`.
    event PositionsManagerForCompoundSet(address _positionsManagerForCompound);

    /// @dev Emitted when the p2pBPY of a market is updated.
    /// @param _marketAddress The address of the market to update.
    /// @param _newValue The new value of the p2pBPY.
    event BPYUpdated(address _marketAddress, uint256 _newValue);

    /// @dev Emitted when the p2pExchangeRate of a market is updated.
    /// @param _marketAddress The address of the market to update.
    /// @param _newValue The new value of the p2pExchangeRate.
    event P2PExchangeRateUpdated(address _marketAddress, uint256 _newValue);

    /// @dev Emitted when a threshold of a market is updated.
    /// @param _marketAddress The address of the market to update.
    /// @param _newValue The new value of the threshold.
    event ThresholdUpdated(address _marketAddress, uint256 _newValue);

    /// @dev Emitted the maximum number of users to have in the tree is updated.
    /// @param _newValue The new value of the maximum number of users to have in the tree.
    event MaxNumberUpdated(uint16 _newValue);

    /// Errors ///

    /// @notice Emitted when the market is not created yet.
    error MarketNotCreated();

    /// @notice Emitted when the market is already created.
    error MarketAlreadyCreated();

    /// @notice Emitted when the positionsManager is already set.
    error PositionsManagerAlreadySet();

    /// @notice Emitted when the creation of a market failed on Compound.
    error MarketCreationFailedOnCompound();

    /// Modifiers ///

    /// @dev Prevents to update a market not created yet.
    modifier isMarketCreated(address _marketAddress) {
        if (!isCreated[_marketAddress]) revert MarketNotCreated();
        _;
    }

    /// External ///

    /// @dev Sets the `positionsManagerForCompound` to interact with Compound.
    /// @param _positionsManagerForCompound The address of compound module.
    function setPositionsManager(address _positionsManagerForCompound) external onlyOwner {
        if (address(positionsManagerForCompound) != address(0)) revert PositionsManagerAlreadySet();
        positionsManagerForCompound = IPositionsManagerForCompound(_positionsManagerForCompound);
        emit PositionsManagerForCompoundSet(_positionsManagerForCompound);
    }

    /// @dev Sets the maximum number of users in tree.
    /// @param _newMaxNumber The maximum number of users to have in the tree.
    function setNMAX(uint16 _newMaxNumber) external onlyOwner {
        positionsManagerForCompound.setNMAX(_newMaxNumber);
        emit MaxNumberUpdated(_newMaxNumber);
    }

    /// @dev Creates a new market to borrow/supply.
    /// @param _marketAddress The addresses of the markets to add (cToken).
    /// @param _threshold The threshold to set for the market.
    function createMarket(address _marketAddress, uint256 _threshold) external onlyOwner {
        if (isCreated[_marketAddress]) revert MarketAlreadyCreated();
        uint256[] memory results = positionsManagerForCompound.createMarket(_marketAddress);
        if (results[0] != 0) revert MarketCreationFailedOnCompound();
        positionsManagerForCompound.setThreshold(_marketAddress, _threshold);
        lastUpdateBlockNumber[_marketAddress] = block.number;
        p2pExchangeRate[_marketAddress] = 1e18;
        isCreated[_marketAddress] = true;
        _updateBPY(_marketAddress);
        emit MarketCreated(_marketAddress);
    }

    /// @dev Updates the threshold below which suppliers and borrowers cannot join a given market.
    /// @param _marketAddress The address of the market to change the threshold.
    /// @param _newThreshold The new threshold to set.
    function updateThreshold(address _marketAddress, uint256 _newThreshold)
        external
        onlyOwner
        isMarketCreated(_marketAddress)
    {
        positionsManagerForCompound.setThreshold(_marketAddress, _newThreshold);
        emit ThresholdUpdated(_marketAddress, _newThreshold);
    }

    /// Public ///

    /// @dev Updates the Block Percentage Yield (`p2pBPY`) and calculates the current exchange rate (`p2pExchangeRate`).
    /// @param _marketAddress The address of the market we want to update.
    function updateRates(address _marketAddress) public isMarketCreated(_marketAddress) {
        if (lastUpdateBlockNumber[_marketAddress] != block.number) {
            _updateP2PExchangeRate(_marketAddress);
            _updateBPY(_marketAddress);
            lastUpdateBlockNumber[_marketAddress] = block.number;
        }
    }

    /// Internal ///

    /// @dev Updates the current exchange rate, taking into account the block percentage yield (`p2pBPY`) since the last time it has been updated.
    /// @param _marketAddress The address of the market to update.
    function _updateP2PExchangeRate(address _marketAddress) internal {
        uint256 numberOfBlocksSinceLastUpdate = block.number -
            lastUpdateBlockNumber[_marketAddress];
        uint256 newP2pUnitExchangeRate = p2pExchangeRate[_marketAddress].mul(
            PRBMathUD60x18.pow(
                1e18 + p2pBPY[_marketAddress],
                PRBMathUD60x18.fromUint(numberOfBlocksSinceLastUpdate)
            )
        );

        p2pExchangeRate[_marketAddress] = newP2pUnitExchangeRate;
        emit P2PExchangeRateUpdated(_marketAddress, newP2pUnitExchangeRate);
    }

    /// @dev Updates the Block Percentage Yield (`p2pBPY`).
    /// @param _marketAddress The address of the market to update.
    function _updateBPY(address _marketAddress) internal {
        ICErc20 cErc20Token = ICErc20(_marketAddress);
        uint256 supplyBPY = cErc20Token.supplyRatePerBlock();
        uint256 borrowBPY = cErc20Token.borrowRatePerBlock();

        p2pBPY[_marketAddress] = Math.average(supplyBPY, borrowBPY);
        emit BPYUpdated(_marketAddress, p2pBPY[_marketAddress]);
    }
}
