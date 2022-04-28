// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./interfaces/compound/ICompound.sol";
import "./interfaces/IPositionsManager.sol";
import "./interfaces/IMarketsManager.sol";
import "./interfaces/IInterestRates.sol";

import "./libraries/CompoundMath.sol";
import "./libraries/Types.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/// @title MarketsManager.
/// @notice Smart contract managing the markets used by a MorphoPositionsManager contract, an other contract interacting with Compound or a fork of Compound.
contract MarketsManager is IMarketsManager, OwnableUpgradeable {
    using CompoundMath for uint256;

    /// STRUCTS ///

    struct LastPoolIndexes {
        uint32 lastUpdateBlockNumber; // The last time the P2P indexes were updated.
        uint112 lastSupplyPoolIndex; // Last pool supply index.
        uint112 lastBorrowPoolIndex; // Last pool borrow index.
    }

    struct MarketParameters {
        uint16 reserveFactor; // Proportion of the interest earned by users sent to the DAO for each market, in basis point (100% = 10000). The default value is 0.
        uint16 p2pIndexCursor; // Position of the peer-to-peer rate in the pool's spread. Determine the weights of the weighted arithmetic average in the indexes computations ((1 - p2pIndexCursor) * r^S + p2pIndexCursor * r^B) (in basis point).
    }

    struct MarketStatuses {
        bool isCreated; // Whether or not this market is created.
        bool isPaused; // Whether the market is paused or not (all entry points on Morpho are frozen; supply, borrow, withdraw, repay and liquidate).
        bool isPartiallyPaused; // Whether the market is partially paused or not (only supply and borrow are frozen).
    }

    /// STORAGE ///

    uint256 public constant WAD = 1e18;
    uint16 public constant MAX_BASIS_POINTS = 10_000; // 100% (in basis point).
    address[] public marketsCreated; // Keeps track of the created markets.
    mapping(address => MarketParameters) public marketParameters; // Market parameters.
    mapping(address => uint256) public override p2pSupplyIndex; // Current index from supply p2pUnit to underlying (in wad).
    mapping(address => uint256) public override p2pBorrowIndex; // Current index from borrow p2pUnit to underlying (in wad).
    mapping(address => LastPoolIndexes) public lastPoolIndexes; // Last pool index stored.
    mapping(address => MarketStatuses) public override marketStatuses; // Whether a market is paused or partially paused or not.

    /// EVENTS ///

    IPositionsManager public positionsManager;
    IInterestRates public interestRates;
    IComptroller public comptroller;

    /// EVENTS ///

    /// @notice Emitted when a new market is created.
    /// @param _poolTokenAddress The address of the market that has been created.
    event MarketCreated(address _poolTokenAddress);

    /// @notice Emitted when the `positionsManager` is set.
    /// @param _positionsManager The address of the `positionsManager`.
    event PositionsManagerSet(address _positionsManager);

    /// @notice Emitted when the `interestRates` is set.
    /// @param _interestRates The address of the `interestRates`.
    event InterestRatesSet(address _interestRates);

    /// @notice Emitted when the p2p indexes of a market are updated.
    /// @param _poolTokenAddress The address of the market updated.
    /// @param _newP2PSupplyIndex The new value of the supply index from p2pUnit to underlying.
    /// @param _newP2PBorrowIndex The new value of the borrow index from p2pUnit to underlying.
    event P2PIndexesUpdated(
        address indexed _poolTokenAddress,
        uint256 _newP2PSupplyIndex,
        uint256 _newP2PBorrowIndex
    );

    /// @notice Emitted when the `reserveFactor` is set.
    /// @param _poolTokenAddress The address of the market set.
    /// @param _newValue The new value of the `reserveFactor`.
    event ReserveFactorSet(address indexed _poolTokenAddress, uint256 _newValue);

    /// @notice Emitted when the `p2pIndexCursor` is set.
    /// @param _poolTokenAddress The address of the market set.
    /// @param _newValue The new value of the `p2pIndexCursor`.
    event P2PIndexCursorSet(address indexed _poolTokenAddress, uint256 _newValue);

    /// @notice Emitted when a market is paused or unpaused.
    /// @param _poolTokenAddress The address of the pool token concerned.
    /// @param _newStatus The new pause status of the market.
    event PauseStatusChanged(address indexed _poolTokenAddress, bool _newStatus);

    /// @notice Emitted when a market is partially paused or unpaused.
    /// @param _poolTokenAddress The address of the pool token concerned.
    /// @param _newStatus The new partial pause status of the market.
    event PartialPauseStatusChanged(address indexed _poolTokenAddress, bool _newStatus);

    /// ERRORS ///

    /// @notice Thrown when the creation of a market failed on Compound.
    error MarketCreationFailedOnCompound();

    /// @notice Thrown when the positionsManager is already set.
    error PositionsManagerAlreadySet();

    /// @notice Thrown when the market is already created.
    error MarketAlreadyCreated();

    /// @notice Thrown when only the positions manager can call the function.
    error OnlyPositionsManager();

    /// @notice Thrown when the market is not created yet.
    error MarketNotCreated();

    /// @notice Thrown when the market is paused.
    error MarketPaused();

    /// MODIFIERS ///

    /// @notice Prevents a user to call function only allowed for `positionsManager`.
    modifier onlyPositionsManager() {
        if (msg.sender != address(positionsManager)) revert OnlyPositionsManager();
        _;
    }

    /// UPGRADE ///

    /// @notice Initializes the MarketsManager contract.
    /// @param _comptroller The comptroller.
    /// @param _interestRates The `interestRates`.
    function initialize(IComptroller _comptroller, IInterestRates _interestRates)
        external
        initializer
    {
        __Ownable_init();

        comptroller = _comptroller;
        interestRates = _interestRates;
    }

    /// EXTERNAL ///

    /// @notice Sets the `positionsManager` to interact with Compound.
    /// @param _positionsManager The address of the `positionsManager`.
    function setPositionsManager(address _positionsManager) external onlyOwner {
        if (address(positionsManager) != address(0)) revert PositionsManagerAlreadySet();
        positionsManager = IPositionsManager(_positionsManager);
        emit PositionsManagerSet(_positionsManager);
    }

    /// @notice Sets the `intersRates`.
    /// @param _interestRates The new `interestRates` contract.
    function setInterestRates(IInterestRates _interestRates) external onlyOwner {
        interestRates = _interestRates;
        emit InterestRatesSet(address(_interestRates));
    }

    /// @notice Sets the `reserveFactor`.
    /// @param _poolTokenAddress The market on which to set the `_newReserveFactor`.
    /// @param _newReserveFactor The proportion of the interest earned by users sent to the DAO, in basis point.
    function setReserveFactor(address _poolTokenAddress, uint256 _newReserveFactor)
        external
        onlyOwner
    {
        updateP2PIndexes(_poolTokenAddress);
        marketParameters[_poolTokenAddress].reserveFactor = uint16(
            CompoundMath.min(MAX_BASIS_POINTS, _newReserveFactor)
        );
        emit ReserveFactorSet(_poolTokenAddress, marketParameters[_poolTokenAddress].reserveFactor);
    }

    /// @notice Creates a new market to borrow/supply in.
    /// @param _poolTokenAddress The pool token address of the given market.
    function createMarket(address _poolTokenAddress) external onlyOwner {
        address[] memory marketToEnter = new address[](1);
        marketToEnter[0] = _poolTokenAddress;
        uint256[] memory results = positionsManager.createMarket(_poolTokenAddress);
        if (results[0] != 0) revert MarketCreationFailedOnCompound();

        if (marketStatuses[_poolTokenAddress].isCreated) revert MarketAlreadyCreated();
        marketStatuses[_poolTokenAddress].isCreated = true;

        ICToken poolToken = ICToken(_poolTokenAddress);

        // Same initial index as Compound.
        uint256 initialIndex;
        if (_poolTokenAddress == positionsManager.cEth()) initialIndex = 2e26;
        else initialIndex = 2 * 10**(16 + IERC20Metadata(poolToken.underlying()).decimals() - 8);
        p2pSupplyIndex[_poolTokenAddress] = initialIndex;
        p2pBorrowIndex[_poolTokenAddress] = initialIndex;

        LastPoolIndexes storage poolIndexes = lastPoolIndexes[_poolTokenAddress];

        poolIndexes.lastUpdateBlockNumber = uint32(block.number);
        poolIndexes.lastSupplyPoolIndex = uint112(poolToken.exchangeRateCurrent());
        poolIndexes.lastBorrowPoolIndex = uint112(poolToken.borrowIndex());

        marketsCreated.push(_poolTokenAddress);
        emit MarketCreated(_poolTokenAddress);
    }

    /// @notice Returns all created markets.
    /// @return marketsCreated_ The list of market addresses.
    function getAllMarkets() external view returns (address[] memory marketsCreated_) {
        marketsCreated_ = marketsCreated;
    }

    /// @notice Returns market's data.
    /// @return p2pSupplyIndex_ The peer-to-peer supply index of the market.
    /// @return p2pBorrowIndex_ The peer-to-peer borrow index of the market.
    /// @return lastUpdateBlockNumber_ The last block number when P2P indexes where updated.
    /// @return supplyP2PDelta_ The supply P2P delta (in scaled balance).
    /// @return borrowP2PDelta_ The borrow P2P delta (in cdUnit).
    /// @return supplyP2PAmount_ The supply P2P amount (in P2P unit).
    /// @return borrowP2PAmount_ The borrow P2P amount (in P2P unit).
    function getMarketData(address _poolTokenAddress)
        external
        view
        returns (
            uint256 p2pSupplyIndex_,
            uint256 p2pBorrowIndex_,
            uint32 lastUpdateBlockNumber_,
            uint256 supplyP2PDelta_,
            uint256 borrowP2PDelta_,
            uint256 supplyP2PAmount_,
            uint256 borrowP2PAmount_
        )
    {
        {
            Types.Delta memory delta = positionsManager.deltas(_poolTokenAddress);
            supplyP2PDelta_ = delta.supplyP2PDelta;
            borrowP2PDelta_ = delta.borrowP2PDelta;
            supplyP2PAmount_ = delta.supplyP2PAmount;
            borrowP2PAmount_ = delta.borrowP2PAmount;
        }
        p2pSupplyIndex_ = p2pSupplyIndex[_poolTokenAddress];
        p2pBorrowIndex_ = p2pBorrowIndex[_poolTokenAddress];
        lastUpdateBlockNumber_ = lastPoolIndexes[_poolTokenAddress].lastUpdateBlockNumber;
    }

    /// @notice Returns market's configuration.
    /// @return isCreated_ Whether the market is created or not.
    /// @return noP2P_ Whether user are put in P2P or not.
    /// @return isPaused_ Whether the market is paused or not (all entry points on Morpho are frozen; supply, borrow, withdraw, repay and liquidate).
    /// @return isPartiallyPaused_ Whether the market is partially paused or not (only supply and borrow are frozen).
    /// @return reserveFactor_ The reserve actor applied to this market.
    function getMarketConfiguration(address _poolTokenAddress)
        external
        view
        returns (
            bool isCreated_,
            bool noP2P_,
            bool isPaused_,
            bool isPartiallyPaused_,
            uint256 reserveFactor_
        )
    {
        MarketStatuses memory marketStatuses_ = marketStatuses[_poolTokenAddress];
        isCreated_ = marketStatuses_.isCreated;
        noP2P_ = positionsManager.noP2P(_poolTokenAddress);
        isPaused_ = marketStatuses_.isPaused;
        isPartiallyPaused_ = marketStatuses_.isPartiallyPaused;
        reserveFactor_ = marketParameters[_poolTokenAddress].reserveFactor;
    }

    /// @notice Returns the updated P2P indexes.
    /// @param _poolTokenAddress The address of the market to update.
    /// @return newP2PSupplyIndex The peer-to-peer supply index after update.
    /// @return newP2PBorrowIndex The peer-to-peer supply index after update.
    function getUpdatedP2PIndexes(address _poolTokenAddress)
        external
        view
        override
        returns (uint256 newP2PSupplyIndex, uint256 newP2PBorrowIndex)
    {
        if (block.timestamp == lastPoolIndexes[_poolTokenAddress].lastUpdateBlockNumber) {
            newP2PSupplyIndex = p2pSupplyIndex[_poolTokenAddress];
            newP2PBorrowIndex = p2pBorrowIndex[_poolTokenAddress];
        } else {
            ICToken poolToken = ICToken(_poolTokenAddress);
            LastPoolIndexes storage poolIndexes = lastPoolIndexes[_poolTokenAddress];
            MarketParameters storage marketParams = marketParameters[_poolTokenAddress];

            Types.Params memory params = Types.Params(
                p2pSupplyIndex[_poolTokenAddress],
                p2pBorrowIndex[_poolTokenAddress],
                poolToken.exchangeRateStored(),
                poolToken.borrowIndex(),
                poolIndexes.lastSupplyPoolIndex,
                poolIndexes.lastBorrowPoolIndex,
                marketParams.reserveFactor,
                marketParams.p2pIndexCursor,
                positionsManager.deltas(_poolTokenAddress)
            );

            (newP2PSupplyIndex, newP2PBorrowIndex) = interestRates.computeP2PIndexes(params);
        }
    }

    /// @notice Returns the updated peer-to-peer supply index.
    /// @param _poolTokenAddress The address of the market to update.
    /// @return newP2PSupplyIndex The peer-to-peer supply index after update.
    function getUpdatedp2pSupplyIndex(address _poolTokenAddress) external view returns (uint256) {
        if (block.timestamp == lastPoolIndexes[_poolTokenAddress].lastUpdateBlockNumber)
            return p2pSupplyIndex[_poolTokenAddress];
        else {
            ICToken poolToken = ICToken(_poolTokenAddress);
            LastPoolIndexes storage poolIndexes = lastPoolIndexes[_poolTokenAddress];
            MarketParameters storage marketParams = marketParameters[_poolTokenAddress];

            Types.Params memory params = Types.Params(
                p2pSupplyIndex[_poolTokenAddress],
                p2pBorrowIndex[_poolTokenAddress],
                poolToken.exchangeRateStored(),
                poolToken.borrowIndex(),
                poolIndexes.lastSupplyPoolIndex,
                poolIndexes.lastBorrowPoolIndex,
                marketParams.reserveFactor,
                marketParams.p2pIndexCursor,
                positionsManager.deltas(_poolTokenAddress)
            );

            return interestRates.computeP2PSupplyIndex(params);
        }
    }

    /// @notice Returns the updated peer-to-peer borrow index.
    /// @param _poolTokenAddress The address of the market to update.
    /// @return newP2PSupplyIndex The peer-to-peer borrow index after update.
    function getUpdatedp2pBorrowIndex(address _poolTokenAddress) external view returns (uint256) {
        if (block.timestamp == lastPoolIndexes[_poolTokenAddress].lastUpdateBlockNumber)
            return p2pBorrowIndex[_poolTokenAddress];
        else {
            ICToken poolToken = ICToken(_poolTokenAddress);
            LastPoolIndexes storage poolIndexes = lastPoolIndexes[_poolTokenAddress];
            MarketParameters storage marketParams = marketParameters[_poolTokenAddress];

            Types.Params memory params = Types.Params(
                p2pSupplyIndex[_poolTokenAddress],
                p2pBorrowIndex[_poolTokenAddress],
                poolToken.exchangeRateStored(),
                poolToken.borrowIndex(),
                poolIndexes.lastSupplyPoolIndex,
                poolIndexes.lastBorrowPoolIndex,
                marketParams.reserveFactor,
                marketParams.p2pIndexCursor,
                positionsManager.deltas(_poolTokenAddress)
            );

            return interestRates.computeP2PBorrowIndex(params);
        }
    }

    /// @notice Sets a new peer-to-peer cursor.
    /// @param _p2pIndexCursor The new peer-to-peer cursor.
    function setP2PIndexCursor(address _poolTokenAddress, uint16 _p2pIndexCursor)
        external
        onlyOwner
    {
        marketParameters[_poolTokenAddress].p2pIndexCursor = _p2pIndexCursor;
        emit P2PIndexCursorSet(_poolTokenAddress, _p2pIndexCursor);
    }

    /// @notice Prevents to update a market not created yet.
    /// @param _poolTokenAddress The address of the market to check.
    function isMarketCreated(address _poolTokenAddress) external view {
        if (!marketStatuses[_poolTokenAddress].isCreated) revert MarketNotCreated();
    }

    /// @notice Prevents a user to trigger a function when market is not created or paused.
    /// @param _poolTokenAddress The address of the market to check.
    function isMarketCreatedAndNotPaused(address _poolTokenAddress) external view {
        MarketStatuses memory marketStatuses_ = marketStatuses[_poolTokenAddress];
        if (!marketStatuses_.isCreated) revert MarketNotCreated();
        if (marketStatuses_.isPaused) revert MarketPaused();
    }

    /// @notice Prevents a user to trigger a function when market is not created or paused or partial paused.
    /// @param _poolTokenAddress The address of the market to check.
    function isMarketCreatedAndNotPausedOrPartiallyPaused(address _poolTokenAddress) external view {
        MarketStatuses memory marketStatuses_ = marketStatuses[_poolTokenAddress];
        if (!marketStatuses_.isCreated) revert MarketNotCreated();
        if (marketStatuses_.isPaused || marketStatuses_.isPartiallyPaused) revert MarketPaused();
    }

    /// @notice Toggles the pause status on a specific market in case of emergency.
    /// @param _poolTokenAddress The address of the market to pause/unpause.
    function togglePauseStatus(address _poolTokenAddress) external onlyOwner {
        MarketStatuses storage marketStatuses_ = marketStatuses[_poolTokenAddress];
        bool newPauseStatus = !marketStatuses_.isPaused;
        marketStatuses_.isPaused = newPauseStatus;
        emit PauseStatusChanged(_poolTokenAddress, newPauseStatus);
    }

    /// @notice Toggles the pause status on a specific market in case of emergency.
    /// @param _poolTokenAddress The address of the market to partially pause/unpause.
    function togglePartialPauseStatus(address _poolTokenAddress) external onlyOwner {
        MarketStatuses storage marketStatuses_ = marketStatuses[_poolTokenAddress];
        bool newPauseStatus = !marketStatuses_.isPartiallyPaused;
        marketStatuses_.isPartiallyPaused = newPauseStatus;
        emit PartialPauseStatusChanged(_poolTokenAddress, newPauseStatus);
    }

    /// PUBLIC ///

    /// @notice Updates the P2P indexes, taking into account the Second Percentage Yield values.
    /// @param _poolTokenAddress The address of the market to update.
    function updateP2PIndexes(address _poolTokenAddress) public {
        if (block.timestamp > lastPoolIndexes[_poolTokenAddress].lastUpdateBlockNumber) {
            ICToken poolToken = ICToken(_poolTokenAddress);
            LastPoolIndexes storage poolIndexes = lastPoolIndexes[_poolTokenAddress];
            MarketParameters storage marketParams = marketParameters[_poolTokenAddress];

            uint256 poolSupplyIndex = poolToken.exchangeRateCurrent();
            uint256 poolBorrowIndex = poolToken.borrowIndex();

            Types.Params memory params = Types.Params(
                p2pSupplyIndex[_poolTokenAddress],
                p2pBorrowIndex[_poolTokenAddress],
                poolSupplyIndex,
                poolBorrowIndex,
                poolIndexes.lastSupplyPoolIndex,
                poolIndexes.lastBorrowPoolIndex,
                marketParams.reserveFactor,
                marketParams.p2pIndexCursor,
                positionsManager.deltas(_poolTokenAddress)
            );

            (uint256 newP2PSupplyIndex, uint256 newP2PBorrowIndex) = interestRates
            .computeP2PIndexes(params);

            p2pSupplyIndex[_poolTokenAddress] = newP2PSupplyIndex;
            p2pBorrowIndex[_poolTokenAddress] = newP2PBorrowIndex;

            poolIndexes.lastUpdateBlockNumber = uint32(block.timestamp);
            poolIndexes.lastSupplyPoolIndex = uint112(poolSupplyIndex);
            poolIndexes.lastBorrowPoolIndex = uint112(poolBorrowIndex);

            emit P2PIndexesUpdated(_poolTokenAddress, newP2PSupplyIndex, newP2PBorrowIndex);
        }
    }
}
