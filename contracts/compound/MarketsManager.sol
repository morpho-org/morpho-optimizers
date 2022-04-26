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
        uint256 lastSupplyPoolIndex; // Last pool supply index.
        uint256 lastBorrowPoolIndex; // Last pool borrow index.
    }

    /// STORAGE ///

    uint256 public constant WAD = 1e18;
    uint16 public constant MAX_BASIS_POINTS = 10_000; // 100% (in basis point).
    address[] public marketsCreated; // Keeps track of the created markets.
    mapping(address => bool) public override isCreated; // Whether or not this market is created.
    mapping(address => uint256) public reserveFactor; // Proportion of the interest earned by users sent to the DAO for each market, in basis point (100% = 10000). The default value is 0.
    mapping(address => uint256) public override p2pSupplyIndex; // Current index from supply p2pUnit to underlying (in wad).
    mapping(address => uint256) public override p2pBorrowIndex; // Current index from borrow p2pUnit to underlying (in wad).
    mapping(address => uint256) public override lastUpdateBlockNumber; // The last time the P2P indexes were updated.
    mapping(address => LastPoolIndexes) public lastPoolIndexes; // Last pool index stored.
    mapping(address => bool) public override noP2P; // Whether to put users on pool or not for the given market.

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

    /// @notice Emitted when a `noP2P` variable is set.
    /// @param _poolTokenAddress The address of the market to set.
    /// @param _noP2P The new value of `_noP2P` adopted.
    event NoP2PSet(address indexed _poolTokenAddress, bool _noP2P);

    /// @notice Emitted when the P2P BPYs of a market are updated.
    /// @param _poolTokenAddress The address of the market updated.
    /// @param _newSupplyP2PBPY The new value of the supply  P2P BPY.
    /// @param _newBorrowP2PBPY The new value of the borrow P2P BPY.
    event P2PBPYsUpdated(
        address indexed _poolTokenAddress,
        uint256 _newSupplyP2PBPY,
        uint256 _newBorrowP2PBPY
    );

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

    /// ERRORS ///

    /// @notice Thrown when the creation of a market failed on Compound.
    error MarketCreationFailedOnCompound();

    /// @notice Thrown when the market is not listed on Compound.
    error MarketIsNotListedOnCompound();

    /// @notice Thrown when the positionsManager is already set.
    error PositionsManagerAlreadySet();

    /// @notice Thrown when the market is already created.
    error MarketAlreadyCreated();

    /// @notice Thrown when only the positions manager can call the function.
    error OnlyPositionsManager();

    /// @notice Thrown when the market is not created yet.
    error MarketNotCreated();

    /// MODIFIERS ///

    /// @notice Prevents to update a market not created yet.
    /// @param _poolTokenAddress The address of the market to check.
    modifier isMarketCreated(address _poolTokenAddress) {
        if (!isCreated[_poolTokenAddress]) revert MarketNotCreated();
        _;
    }

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
        reserveFactor[_poolTokenAddress] = CompoundMath.min(MAX_BASIS_POINTS, _newReserveFactor);
        emit ReserveFactorSet(_poolTokenAddress, reserveFactor[_poolTokenAddress]);
    }

    /// @notice Creates a new market to borrow/supply in.
    /// @param _poolTokenAddress The pool token address of the given market.
    function createMarket(address _poolTokenAddress) external onlyOwner {
        address[] memory marketToEnter = new address[](1);
        marketToEnter[0] = _poolTokenAddress;
        uint256[] memory results = positionsManager.createMarket(_poolTokenAddress);
        if (results[0] != 0) revert MarketCreationFailedOnCompound();

        if (isCreated[_poolTokenAddress]) revert MarketAlreadyCreated();
        isCreated[_poolTokenAddress] = true;

        ICToken poolToken = ICToken(_poolTokenAddress);
        lastUpdateBlockNumber[_poolTokenAddress] = block.number;

        // Same initial index as Compound.
        uint256 initialIndex;
        if (_poolTokenAddress == positionsManager.cEth()) initialIndex = 2e26;
        else initialIndex = 2 * 10**(16 + IERC20Metadata(poolToken.underlying()).decimals() - 8);
        p2pSupplyIndex[_poolTokenAddress] = initialIndex;
        p2pBorrowIndex[_poolTokenAddress] = initialIndex;

        LastPoolIndexes storage poolIndexes = lastPoolIndexes[_poolTokenAddress];

        poolIndexes.lastSupplyPoolIndex = poolToken.exchangeRateCurrent();
        poolIndexes.lastBorrowPoolIndex = poolToken.borrowIndex();

        marketsCreated.push(_poolTokenAddress);
        emit MarketCreated(_poolTokenAddress);
    }

    /// @notice Sets whether to match people P2P or not.
    /// @param _poolTokenAddress The address of the market.
    /// @param _noP2P Whether to match people P2P or not.
    function setNoP2P(address _poolTokenAddress, bool _noP2P)
        external
        onlyOwner
        isMarketCreated(_poolTokenAddress)
    {
        noP2P[_poolTokenAddress] = _noP2P;
        emit NoP2PSet(_poolTokenAddress, _noP2P);
    }

    /// @notice Returns all created markets.
    /// @return marketsCreated_ The list of market adresses.
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
            uint256 lastUpdateBlockNumber_,
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
        lastUpdateBlockNumber_ = lastUpdateBlockNumber[_poolTokenAddress];
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
        isCreated_ = isCreated[_poolTokenAddress];
        noP2P_ = noP2P[_poolTokenAddress];
        (isPaused_, isPartiallyPaused_) = positionsManager.pauseStatuses(_poolTokenAddress);
        reserveFactor_ = reserveFactor[_poolTokenAddress];
    }

    /// @notice Returns the updated P2P indexes.
    /// @param _poolTokenAddress The address of the market to update.
    /// @return newP2PSupplyIndex The peer-to-peer supply index after udpate.
    /// @return newP2PBorrowIndex The peer-to-peer supply index after udpate.
    function getUpdatedP2PIndexes(address _poolTokenAddress)
        external
        view
        override
        returns (uint256 newP2PSupplyIndex, uint256 newP2PBorrowIndex)
    {
        if (block.timestamp == lastUpdateBlockNumber[_poolTokenAddress]) {
            newP2PSupplyIndex = p2pSupplyIndex[_poolTokenAddress];
            newP2PBorrowIndex = p2pBorrowIndex[_poolTokenAddress];
        } else {
            ICToken poolToken = ICToken(_poolTokenAddress);
            LastPoolIndexes storage poolIndexes = lastPoolIndexes[_poolTokenAddress];

            Types.Params memory params = Types.Params(
                p2pSupplyIndex[_poolTokenAddress],
                p2pBorrowIndex[_poolTokenAddress],
                poolToken.exchangeRateStored(),
                poolToken.borrowIndex(),
                poolIndexes.lastSupplyPoolIndex,
                poolIndexes.lastBorrowPoolIndex,
                reserveFactor[_poolTokenAddress],
                positionsManager.deltas(_poolTokenAddress)
            );

            (newP2PSupplyIndex, newP2PBorrowIndex) = interestRates.computeP2PIndexes(params);
        }
    }

    /// @notice Returns the updated peer-to-peer supply index.
    /// @param _poolTokenAddress The address of the market to update.
    /// @return newP2PSupplyIndex The peer-to-peer supply index after udpate.
    function getUpdatedp2pSupplyIndex(address _poolTokenAddress) external view returns (uint256) {
        if (block.timestamp == lastUpdateBlockNumber[_poolTokenAddress])
            return p2pSupplyIndex[_poolTokenAddress];
        else {
            ICToken poolToken = ICToken(_poolTokenAddress);
            LastPoolIndexes storage poolIndexes = lastPoolIndexes[_poolTokenAddress];

            Types.Params memory params = Types.Params(
                p2pSupplyIndex[_poolTokenAddress],
                p2pBorrowIndex[_poolTokenAddress],
                poolToken.exchangeRateStored(),
                poolToken.borrowIndex(),
                poolIndexes.lastSupplyPoolIndex,
                poolIndexes.lastBorrowPoolIndex,
                reserveFactor[_poolTokenAddress],
                positionsManager.deltas(_poolTokenAddress)
            );

            return interestRates.computeP2PSupplyIndex(params);
        }
    }

    /// @notice Returns the updated peer-to-peer borrow index.
    /// @param _poolTokenAddress The address of the market to update.
    /// @return newP2PSupplyIndex The peer-to-peer borrow index after udpate.
    function getUpdatedp2pBorrowIndex(address _poolTokenAddress) external view returns (uint256) {
        if (block.timestamp == lastUpdateBlockNumber[_poolTokenAddress])
            return p2pBorrowIndex[_poolTokenAddress];
        else {
            ICToken poolToken = ICToken(_poolTokenAddress);
            LastPoolIndexes storage poolIndexes = lastPoolIndexes[_poolTokenAddress];

            Types.Params memory params = Types.Params(
                p2pSupplyIndex[_poolTokenAddress],
                p2pBorrowIndex[_poolTokenAddress],
                poolToken.exchangeRateStored(),
                poolToken.borrowIndex(),
                poolIndexes.lastSupplyPoolIndex,
                poolIndexes.lastBorrowPoolIndex,
                reserveFactor[_poolTokenAddress],
                positionsManager.deltas(_poolTokenAddress)
            );

            return interestRates.computeP2PBorrowIndex(params);
        }
    }

    /// PUBLIC ///

    /// @notice Updates the P2P indexes, taking into account the Second Percentage Yield values.
    /// @param _poolTokenAddress The address of the market to update.
    function updateP2PIndexes(address _poolTokenAddress) public {
        if (block.timestamp > lastUpdateBlockNumber[_poolTokenAddress]) {
            ICToken poolToken = ICToken(_poolTokenAddress);
            lastUpdateBlockNumber[_poolTokenAddress] = block.timestamp;
            LastPoolIndexes storage poolIndexes = lastPoolIndexes[_poolTokenAddress];

            uint256 poolSupplyIndex = poolToken.exchangeRateCurrent();
            uint256 poolBorrowIndex = poolToken.borrowIndex();

            Types.Params memory params = Types.Params(
                p2pSupplyIndex[_poolTokenAddress],
                p2pBorrowIndex[_poolTokenAddress],
                poolSupplyIndex,
                poolBorrowIndex,
                poolIndexes.lastSupplyPoolIndex,
                poolIndexes.lastBorrowPoolIndex,
                reserveFactor[_poolTokenAddress],
                positionsManager.deltas(_poolTokenAddress)
            );

            (uint256 newP2PSupplyIndex, uint256 newP2PBorrowIndex) = interestRates
            .computeP2PIndexes(params);

            p2pSupplyIndex[_poolTokenAddress] = newP2PSupplyIndex;
            p2pBorrowIndex[_poolTokenAddress] = newP2PBorrowIndex;
            poolIndexes.lastSupplyPoolIndex = poolSupplyIndex;
            poolIndexes.lastBorrowPoolIndex = poolBorrowIndex;

            emit P2PIndexesUpdated(_poolTokenAddress, newP2PSupplyIndex, newP2PBorrowIndex);
        }
    }
}
