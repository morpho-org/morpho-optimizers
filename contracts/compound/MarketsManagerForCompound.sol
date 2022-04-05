// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import {ICToken, IComptroller} from "./interfaces/compound/ICompound.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./interfaces/IPositionsManagerForCompound.sol";
import "./interfaces/IMarketsManagerForCompound.sol";
import "./interfaces/IInterestRates.sol";

import "./libraries/CompoundMath.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/// @title MarketsManagerForCompound.
/// @notice Smart contract managing the markets used by a MorphoPositionsManagerForCompound contract, an other contract interacting with Compound or a fork of Compound.
contract MarketsManagerForCompound is IMarketsManagerForCompound, OwnableUpgradeable {
    using CompoundMath for uint256;

    /// STRUCTS ///

    struct LastPoolIndexes {
        uint256 lastSupplyPoolIndex; // Last supply pool index (current exchange rate) stored.
        uint256 lastBorrowPoolIndex; // Last borrow pool index (borrow index) stored.
    }

    /// STORAGE ///

    uint256 public constant WAD = 1e18;
    uint16 public constant MAX_BASIS_POINTS = 10_000; // 100% (in basis point).
    address[] public marketsCreated; // Keeps track of the created markets.
    mapping(address => bool) public override isCreated; // Whether or not this market is created.
    mapping(address => uint256) public reserveFactor; // Proportion of the interest earned by users sent to the DAO for each market, in basis point (100% = 10000). The default value is 0.
    mapping(address => uint256) public override supplyP2PBPY; // Supply Percentage Yield per block (in wad).
    mapping(address => uint256) public override borrowP2PBPY; // Borrow Percentage Yield per block (in wad).
    mapping(address => uint256) public override supplyP2PExchangeRate; // Current exchange rate from supply p2pUnit to underlying (in wad).
    mapping(address => uint256) public override borrowP2PExchangeRate; // Current exchange rate from borrow p2pUnit to underlying (in wad).
    mapping(address => uint256) public override lastUpdateBlockNumber; // The last time the P2P exchange rates were updated.
    mapping(address => LastPoolIndexes) public lastPoolIndexes; // Last pool index stored.
    mapping(address => bool) public override noP2P; // Whether to put users on pool or not for the given market.

    IPositionsManagerForCompound public positionsManager;
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

    /// @notice Emitted when the p2p exchange rates of a market are updated.
    /// @param _poolTokenAddress The address of the market updated.
    /// @param _newSupplyP2PExchangeRate The new value of the supply exchange rate from p2pUnit to underlying.
    /// @param _newBorrowP2PExchangeRate The new value of the borrow exchange rate from p2pUnit to underlying.
    event P2PExchangeRatesUpdated(
        address indexed _poolTokenAddress,
        uint256 _newSupplyP2PExchangeRate,
        uint256 _newBorrowP2PExchangeRate
    );

    /// @notice Emitted when the `reserveFactor` is set.
    /// @param _poolTokenAddress The address of the market set.
    /// @param _newValue The new value of the `reserveFactor`.
    event ReserveFactorSet(address indexed _poolTokenAddress, uint256 _newValue);

    /// ERRORS ///

    /// @notice Thrown when the market is not created yet.
    error MarketNotCreated();

    /// @notice Thrown when the market is not listed on Compound.
    error MarketIsNotListedOnCompound();

    /// @notice Thrown when the market is already created.
    error MarketAlreadyCreated();

    /// @notice Thrown when the positionsManager is already set.
    error PositionsManagerAlreadySet();

    /// @notice Thrown when only the positions manager can call the function.
    error OnlyPositionsManager();

    /// @notice Thrown when the creation of a market failed on Compound.
    error MarketCreationFailedOnCompound();

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

    /// @notice Initializes the MarketsManagerForCompound contract.
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
        positionsManager = IPositionsManagerForCompound(_positionsManager);
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
        reserveFactor[_poolTokenAddress] = CompoundMath.min(MAX_BASIS_POINTS, _newReserveFactor);
        updateRates(_poolTokenAddress);
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

        // Same initial exchange rate as Compound.
        uint256 initialExchangeRate = 2 *
            10**(16 + IERC20Metadata(poolToken.underlying()).decimals() - 8);
        supplyP2PExchangeRate[_poolTokenAddress] = initialExchangeRate;
        borrowP2PExchangeRate[_poolTokenAddress] = initialExchangeRate;

        LastPoolIndexes storage poolIndexes = lastPoolIndexes[_poolTokenAddress];

        poolIndexes.lastSupplyPoolIndex = poolToken.exchangeRateCurrent();
        poolIndexes.lastBorrowPoolIndex = poolToken.borrowIndex();

        _updateBPYs(_poolTokenAddress);
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

    /// @notice Updates the P2P exchange rates, taking into account the Block Percentage Yield values.
    /// @param _poolTokenAddress The address of the market to update.
    function updateP2PExchangeRates(address _poolTokenAddress)
        external
        override
        onlyPositionsManager
    {
        _updateP2PExchangeRates(_poolTokenAddress);
    }

    /// @notice Updates the P2P Block Percentage Yield of supply and borrow.
    /// @param _poolTokenAddress The address of the market to update.
    function updateBPYs(address _poolTokenAddress) external override onlyPositionsManager {
        _updateBPYs(_poolTokenAddress);
    }

    /// @notice Returns all created markets.
    /// @return marketsCreated_ The list of market adresses.
    function getAllMarkets() external view returns (address[] memory marketsCreated_) {
        marketsCreated_ = marketsCreated;
    }

    /// @notice Returns market's data.
    /// @return supplyP2PBPY_ The supply P2P BPY of the market.
    /// @return borrowP2PBPY_ The borrow P2P BPY of the market.
    /// @return supplyP2PExchangeRate_ The supply P2P exchange rate of the market.
    /// @return borrowP2PExchangeRate_ The borrow P2P exchange rate of the market.
    /// @return lastUpdateBlockNumber_ The last block number when P2P exchange rates where updated.
    /// @return supplyP2PDelta_ The supply P2P delta (in scaled balance).
    /// @return borrowP2PDelta_ The borrow P2P delta (in cdUnit).
    /// @return supplyP2PAmount_ The supply P2P amount (in P2P unit).
    /// @return borrowP2PAmount_ The borrow P2P amount (in P2P unit).
    function getMarketData(address _poolTokenAddress)
        external
        view
        returns (
            uint256 supplyP2PBPY_,
            uint256 borrowP2PBPY_,
            uint256 supplyP2PExchangeRate_,
            uint256 borrowP2PExchangeRate_,
            uint256 lastUpdateBlockNumber_,
            uint256 supplyP2PDelta_,
            uint256 borrowP2PDelta_,
            uint256 supplyP2PAmount_,
            uint256 borrowP2PAmount_
        )
    {
        {
            IPositionsManagerForCompound.Delta memory delta = positionsManager.deltas(
                _poolTokenAddress
            );
            supplyP2PDelta_ = delta.supplyP2PDelta;
            borrowP2PDelta_ = delta.borrowP2PDelta;
            supplyP2PAmount_ = delta.supplyP2PAmount;
            borrowP2PAmount_ = delta.borrowP2PAmount;
        }

        supplyP2PBPY_ = supplyP2PBPY[_poolTokenAddress];
        borrowP2PBPY_ = borrowP2PBPY[_poolTokenAddress];
        supplyP2PExchangeRate_ = supplyP2PExchangeRate[_poolTokenAddress];
        borrowP2PExchangeRate_ = borrowP2PExchangeRate[_poolTokenAddress];
        lastUpdateBlockNumber_ = lastUpdateBlockNumber[_poolTokenAddress];
    }

    /// @notice Returns market's configuration.
    /// @return isCreated_ Whether the market is created or not.
    /// @return noP2P_ Whether user are put in P2P or not.
    function getMarketConfiguration(address _poolTokenAddress)
        external
        view
        returns (bool isCreated_, bool noP2P_)
    {
        isCreated_ = isCreated[_poolTokenAddress];
        noP2P_ = noP2P[_poolTokenAddress];
    }

    /// PUBLIC ///

    /// @notice Updates the P2P Second Percentage Yield and the current P2P exchange rates.
    /// @param _poolTokenAddress The address of the market we want to update.
    function updateRates(address _poolTokenAddress)
        public
        override
        isMarketCreated(_poolTokenAddress)
    {
        _updateP2PExchangeRates(_poolTokenAddress);
        _updateBPYs(_poolTokenAddress);
    }

    /// @notice Returns the updated supply P2P exchange rate.
    /// @param _poolTokenAddress The address of the market to update.
    /// @return updatedSupplyP2P_ The supply P2P exchange rate after udpate.
    function getUpdatedSupplyP2PExchangeRate(address _poolTokenAddress)
        external
        view
        override
        returns (uint256 updatedSupplyP2P_)
    {
        uint256 blockDifference = block.number - lastUpdateBlockNumber[_poolTokenAddress];

        if (blockDifference == 0) return supplyP2PExchangeRate[_poolTokenAddress];
        else {
            ICToken poolToken = ICToken(_poolTokenAddress);
            IPositionsManagerForCompound.Delta memory delta = positionsManager.deltas(
                _poolTokenAddress
            );

            updatedSupplyP2P_ = _computeNewP2PExchangeRate(
                delta.supplyP2PDelta,
                delta.supplyP2PAmount,
                supplyP2PExchangeRate[_poolTokenAddress],
                supplyP2PBPY[_poolTokenAddress],
                poolToken.exchangeRateStored(),
                lastPoolIndexes[_poolTokenAddress].lastSupplyPoolIndex,
                blockDifference
            );
        }
    }

    /// @notice Returns the updated borrow P2P exchange rate.
    /// @param _poolTokenAddress The address of the market to update.
    /// @return updatedBorrowP2P_ The borrow P2P exchange rate after udpate.
    function getUpdatedBorrowP2PExchangeRate(address _poolTokenAddress)
        external
        view
        override
        returns (uint256 updatedBorrowP2P_)
    {
        uint256 blockDifference = block.number - lastUpdateBlockNumber[_poolTokenAddress];

        if (blockDifference == 0) return borrowP2PExchangeRate[_poolTokenAddress];
        else {
            ICToken poolToken = ICToken(_poolTokenAddress);
            IPositionsManagerForCompound.Delta memory delta = positionsManager.deltas(
                _poolTokenAddress
            );

            updatedBorrowP2P_ = _computeNewP2PExchangeRate(
                delta.borrowP2PDelta,
                delta.borrowP2PAmount,
                borrowP2PExchangeRate[_poolTokenAddress],
                borrowP2PBPY[_poolTokenAddress],
                poolToken.borrowIndex(),
                lastPoolIndexes[_poolTokenAddress].lastBorrowPoolIndex,
                blockDifference
            );
        }
    }

    /// INTERNAL ///

    /// @notice Updates the P2P exchange rates, taking into account the Block Percentage Yield values.
    /// @param _poolTokenAddress The address of the market to update.
    function _updateP2PExchangeRates(address _poolTokenAddress) internal {
        ICToken poolToken = ICToken(_poolTokenAddress);

        uint256 blockDifference = block.number - lastUpdateBlockNumber[_poolTokenAddress];
        lastUpdateBlockNumber[_poolTokenAddress] = block.number;
        LastPoolIndexes storage poolIndexes = lastPoolIndexes[_poolTokenAddress];
        IPositionsManagerForCompound.Delta memory delta = positionsManager.deltas(
            _poolTokenAddress
        );

        uint256 supplyPoolIndex = poolToken.exchangeRateCurrent();
        supplyP2PExchangeRate[_poolTokenAddress] = _computeNewP2PExchangeRate(
            delta.supplyP2PDelta,
            delta.supplyP2PAmount,
            supplyP2PExchangeRate[_poolTokenAddress],
            supplyP2PBPY[_poolTokenAddress],
            supplyPoolIndex,
            poolIndexes.lastSupplyPoolIndex,
            blockDifference
        );
        poolIndexes.lastSupplyPoolIndex = supplyPoolIndex;

        uint256 borrowPoolIndex = poolToken.borrowIndex();
        borrowP2PExchangeRate[_poolTokenAddress] = _computeNewP2PExchangeRate(
            delta.borrowP2PDelta,
            delta.borrowP2PAmount,
            borrowP2PExchangeRate[_poolTokenAddress],
            borrowP2PBPY[_poolTokenAddress],
            borrowPoolIndex,
            poolIndexes.lastBorrowPoolIndex,
            blockDifference
        );
        poolIndexes.lastBorrowPoolIndex = borrowPoolIndex;

        emit P2PExchangeRatesUpdated(
            _poolTokenAddress,
            supplyP2PExchangeRate[_poolTokenAddress],
            borrowP2PExchangeRate[_poolTokenAddress]
        );
    }

    /// @notice Updates the P2P Block Percentage Yield of supply and borrow.
    /// @param _poolTokenAddress The address of the market to update.
    function _updateBPYs(address _poolTokenAddress) internal {
        ICToken cToken = ICToken(_poolTokenAddress);
        uint256 supplyBPY = cToken.supplyRatePerBlock();
        uint256 borrowBPY = cToken.borrowRatePerBlock();

        (uint256 newSupplyP2PBPY, uint256 newBorrowP2PBPY) = interestRates.computeRates(
            supplyBPY,
            borrowBPY,
            reserveFactor[_poolTokenAddress]
        );

        supplyP2PBPY[_poolTokenAddress] = newSupplyP2PBPY;
        borrowP2PBPY[_poolTokenAddress] = newBorrowP2PBPY;

        emit P2PBPYsUpdated(_poolTokenAddress, newSupplyP2PBPY, newBorrowP2PBPY);
    }

    /// @notice Computes the new P2P exchange rate from arguments.
    /// @param _p2pDelta The P2P delta.
    /// @param _p2pAmount The P2P amount.
    /// @param _p2pRate The P2P exchange rate.
    /// @param _p2pBPY The P2P BPY.
    /// @param _poolIndex The pool index (normalized income for supply) or (normalized debt variable for borrow) of the market.
    /// @param _lastPoolIndex The last pool index (normalized income for supply) or (normalized debt variable for borrow) of the market.
    /// @param _blockDifference The time difference since the last update.
    /// @return The new P2P exchange rate.
    function _computeNewP2PExchangeRate(
        uint256 _p2pDelta,
        uint256 _p2pAmount,
        uint256 _p2pRate,
        uint256 _p2pBPY,
        uint256 _poolIndex,
        uint256 _lastPoolIndex,
        uint256 _blockDifference
    ) internal pure returns (uint256) {
        if (_p2pAmount == 0 || _p2pDelta == 0)
            return _p2pRate.mul(_computeCompoundedInterest(_p2pBPY, _blockDifference));
        else {
            uint256 shareOfTheDelta = _p2pDelta.mul(_poolIndex).div(_p2pRate).div(_p2pAmount);

            return
                _p2pRate.mul(
                    _computeCompoundedInterest(_p2pBPY, _blockDifference).mul(
                        1e18 - shareOfTheDelta
                    ) + shareOfTheDelta.mul(_poolIndex).div(_lastPoolIndex)
                );
        }
    }

    /// @dev Computes the compounded interest over a number of blocks.
    ///   To avoid expensive exponentiation, the calculation is performed using a binomial approximation:
    ///   (1+x)^n = 1+n*x+[n/2*(n-1)]*x^2+[n/6*(n-1)*(n-2)*x^3...
    /// @param _rate The BPY to use in the computation.
    /// @param _elapsedBlocks The number of blocks passed since te last computation.
    /// @return The result in wad.
    function _computeCompoundedInterest(uint256 _rate, uint256 _elapsedBlocks)
        internal
        pure
        returns (uint256)
    {
        if (_elapsedBlocks == 0) return WAD;
        if (_elapsedBlocks == 1) return WAD + _rate;

        uint256 ratePowerTwo = _rate.mul(_rate);
        uint256 ratePowerThree = ratePowerTwo.mul(_rate);

        return
            WAD +
            _rate *
            _elapsedBlocks +
            (_elapsedBlocks * (_elapsedBlocks - 1) * ratePowerTwo) /
            2 +
            (_elapsedBlocks * (_elapsedBlocks - 1) * (_elapsedBlocks - 2) * ratePowerThree) /
            6;
    }
}
