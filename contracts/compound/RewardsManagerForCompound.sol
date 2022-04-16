// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "hardhat/console.sol";

import "./interfaces/IPositionsManagerForCompound.sol";
import "./interfaces/IRewardsManagerForCompound.sol";
import "./interfaces/compound/ICompound.sol";

import "./libraries/CompoundMath.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

contract RewardsManagerForCompound is IRewardsManagerForCompound, Ownable {
    using CompoundMath for uint256;

    /// STORAGE ///

    uint224 public constant COMP_INITIAL_INDEX = 1e36;
    uint256 public constant COMP_CLAIM_THRESHOLD = 0.001e18;

    mapping(address => uint256) public userUnclaimedCompRewards; // The unclaimed rewards of the user.
    mapping(address => mapping(address => uint256)) public compSupplierIndex;
    mapping(address => mapping(address => uint256)) public compBorrowerIndex;
    mapping(address => IComptroller.CompMarketState) public localCompSupplyState;
    mapping(address => IComptroller.CompMarketState) public localCompBorrowState;

    IPositionsManagerForCompound public immutable positionsManager;
    IComptroller public immutable comptroller;

    /// EVENTS ///

    // TODO: Add events.

    /// ERRORS ///

    /// @notice Thrown when only the positions manager can call the function.
    error OnlyPositionsManager();

    /// @notice Thrown when an invalid asset is passed to accrue rewards.
    error InvalidAsset();

    /// MODIFIERS ///

    /// @notice Prevents a user to call function allowed for the positions manager only.
    modifier onlyPositionsManager() {
        if (msg.sender != address(positionsManager)) revert OnlyPositionsManager();
        _;
    }

    /// CONSTRUCTOR ///

    /// @notice Constructs the RewardsManager contract.
    /// @param _positionsManager The `positionsManager`.
    /// @param _comptroller The `comptroller`.
    constructor(address _positionsManager, IComptroller _comptroller) {
        positionsManager = IPositionsManagerForCompound(_positionsManager);
        comptroller = _comptroller;
    }

    /// EXTERNAL ///

    /// @notice Accrues unclaimed rewards for the given assets and returns the total unclaimed rewards.
    /// @param _cTokenAddresses The assets for which to accrue rewards (aToken or variable debt token).
    /// @param _user The address of the user.
    function claimRewards(address[] calldata _cTokenAddresses, address _user)
        external
        onlyPositionsManager
        returns (uint256 amountToClaim)
    {
        amountToClaim = accrueUserUnclaimedRewards(_cTokenAddresses, _user);
        if (amountToClaim > 0) userUnclaimedCompRewards[_user] = 0;
    }

    function getLocalCompSupplyState(address _cTokenAddress)
        external
        view
        override
        returns (IComptroller.CompMarketState memory)
    {
        return localCompSupplyState[_cTokenAddress];
    }

    function getLocalCompBorrowState(address _cTokenAddress)
        external
        view
        override
        returns (IComptroller.CompMarketState memory)
    {
        return localCompBorrowState[_cTokenAddress];
    }

    function getUserUnclaimedRewards(address[] calldata _cTokenAddresses, address _user)
        external
        view
        returns (uint256 unclaimedRewards)
    {
        unclaimedRewards = userUnclaimedCompRewards[_user];

        for (uint256 i; i < _cTokenAddresses.length; i++) {
            address cTokenAddress = _cTokenAddresses[i];

            unclaimedRewards += getAccruedSupplierComp(
                _user,
                cTokenAddress,
                positionsManager.supplyBalanceInOf(cTokenAddress, _user).onPool
            );
            unclaimedRewards += getAccruedBorrowerComp(
                _user,
                cTokenAddress,
                positionsManager.borrowBalanceInOf(cTokenAddress, _user).onPool
            );
        }
    }

    /// @notice Updates the unclaimed rewards of an user.
    /// @param _user The address of the user.
    /// @param _cTokenAddress The address of the reference asset of the distribution (aToken or variable debt token).
    /// @param _userBalance The user balance of tokens in the distribution.
    function accrueUserSupplyUnclaimedRewards(
        address _user,
        address _cTokenAddress,
        uint256 _userBalance
    ) external onlyPositionsManager {
        _updateSupplyIndex(_cTokenAddress);
        userUnclaimedCompRewards[_user] += _accrueSupplierComp(_user, _cTokenAddress, _userBalance);
    }

    /// @notice Updates the unclaimed rewards of an user.
    /// @param _user The address of the user.
    /// @param _cTokenAddress The address of the reference asset of the distribution (aToken or variable debt token).
    /// @param _userBalance The user balance of tokens in the distribution.
    function accrueUserBorrowUnclaimedRewards(
        address _user,
        address _cTokenAddress,
        uint256 _userBalance
    ) external onlyPositionsManager {
        _updateBorrowIndex(_cTokenAddress);
        userUnclaimedCompRewards[_user] += _accrueBorrowerComp(_user, _cTokenAddress, _userBalance);
    }

    /// PUBLIC ///

    /// @notice Accrues unclaimed rewards for the given assets and returns the total unclaimed rewards.
    /// @param _cTokenAddresses The assets for which to accrue rewards (aToken or variable debt token).
    /// @param _user The address of the user.
    /// @return unclaimedRewards The user unclaimed rewards.
    function accrueUserUnclaimedRewards(address[] calldata _cTokenAddresses, address _user)
        public
        returns (uint256 unclaimedRewards)
    {
        unclaimedRewards = userUnclaimedCompRewards[_user];

        for (uint256 i; i < _cTokenAddresses.length; i++) {
            address cTokenAddress = _cTokenAddresses[i];

            // TODO: isListed on Compound
            if (!ICToken(cTokenAddress).isCToken()) revert InvalidAsset();

            _updateSupplyIndex(cTokenAddress);
            unclaimedRewards += _accrueSupplierComp(
                _user,
                cTokenAddress,
                positionsManager.supplyBalanceInOf(cTokenAddress, _user).onPool
            );

            _updateBorrowIndex(cTokenAddress);
            unclaimedRewards += _accrueBorrowerComp(
                _user,
                cTokenAddress,
                positionsManager.borrowBalanceInOf(cTokenAddress, _user).onPool
            );
        }

        userUnclaimedCompRewards[_user] = unclaimedRewards;
    }

    /// INTERNAL ///

    function getUpdatedSupplyIndex(address _cTokenAddress) public view returns (uint256) {
        IComptroller.CompMarketState memory localSupplyState = localCompSupplyState[_cTokenAddress];
        uint256 blockNumber = block.number;

        if (localSupplyState.block == blockNumber) return localSupplyState.index;
        else {
            IComptroller.CompMarketState memory supplyState = comptroller.compSupplyState(
                _cTokenAddress
            );

            if (supplyState.block == blockNumber) return supplyState.index;
            else {
                uint256 deltaBlocks = localSupplyState.block == 0
                    ? blockNumber - supplyState.block
                    : blockNumber - localSupplyState.block;
                uint256 supplySpeed = comptroller.compSupplySpeeds(_cTokenAddress);

                if (supplySpeed > 0) {
                    uint256 supplyTokens = ICToken(_cTokenAddress).totalSupply();
                    uint256 compAccrued = deltaBlocks * supplySpeed;
                    uint256 ratio = supplyTokens > 0 ? (compAccrued * 1e36) / supplyTokens : 0;
                    uint256 formerIndex = localSupplyState.index == 0
                        ? supplyState.index
                        : localSupplyState.index;
                    return formerIndex + ratio;
                } else return supplyState.index;
            }
        }
    }

    function getUpdatedBorrowIndex(address _cTokenAddress) public view returns (uint256) {
        IComptroller.CompMarketState memory localBorrowState = localCompBorrowState[_cTokenAddress];
        uint256 blockNumber = block.number;

        if (localBorrowState.block == blockNumber) return localBorrowState.index;
        else {
            IComptroller.CompMarketState memory borrowState = comptroller.compBorrowState(
                _cTokenAddress
            );

            if (borrowState.block == blockNumber) return borrowState.index;
            else {
                uint256 deltaBlocks = localBorrowState.block == 0
                    ? blockNumber - borrowState.block
                    : blockNumber - localBorrowState.block;
                uint256 borrowSpeed = comptroller.compBorrowSpeeds(_cTokenAddress);

                if (borrowSpeed > 0) {
                    uint256 borrowAmount = ICToken(_cTokenAddress).totalBorrows().div(
                        ICToken(_cTokenAddress).borrowIndex()
                    );
                    uint256 compAccrued = deltaBlocks * borrowSpeed;
                    uint256 ratio = borrowAmount > 0 ? (compAccrued * 1e36) / borrowAmount : 0;
                    uint256 formerIndex = localBorrowState.index == 0
                        ? borrowState.index
                        : localBorrowState.index;
                    return formerIndex + ratio;
                } else return borrowState.index;
            }
        }
    }

    function _updateSupplyIndex(address _cTokenAddress) internal {
        IComptroller.CompMarketState storage localSupplyState = localCompSupplyState[
            _cTokenAddress
        ];
        uint256 blockNumber = block.number;

        if (localSupplyState.block == blockNumber) return;
        else {
            IComptroller.CompMarketState memory supplyState = comptroller.compSupplyState(
                _cTokenAddress
            );

            if (supplyState.block == blockNumber) {
                localSupplyState.block = supplyState.block;
                localSupplyState.index = supplyState.index;
            } else {
                uint256 deltaBlocks = localSupplyState.block == 0
                    ? blockNumber - supplyState.block
                    : blockNumber - localSupplyState.block;
                uint256 supplySpeed = comptroller.compSupplySpeeds(_cTokenAddress);

                if (supplySpeed > 0) {
                    uint256 supplyTokens = ICToken(_cTokenAddress).totalSupply();
                    uint256 compAccrued = deltaBlocks * supplySpeed;
                    uint256 ratio = supplyTokens > 0 ? (compAccrued * 1e36) / supplyTokens : 0;
                    uint256 formerIndex = localSupplyState.index == 0
                        ? supplyState.index
                        : localSupplyState.index;
                    uint256 index = formerIndex + ratio;
                    localCompSupplyState[_cTokenAddress] = IComptroller.CompMarketState({
                        index: CompoundMath.safe224(index, "new index exceeds 224 bits"),
                        block: CompoundMath.safe32(blockNumber, "block number exceeds 32 bits")
                    });
                } else
                    localSupplyState.block = CompoundMath.safe32(
                        blockNumber,
                        "block number exceeds 32 bits"
                    );
            }
        }
    }

    function _updateBorrowIndex(address _cTokenAddress) internal {
        IComptroller.CompMarketState storage localBorrowState = localCompBorrowState[
            _cTokenAddress
        ];
        uint256 blockNumber = block.number;

        if (localBorrowState.block == blockNumber) return;
        else {
            IComptroller.CompMarketState memory borrowState = comptroller.compBorrowState(
                _cTokenAddress
            );

            if (borrowState.block == blockNumber) {
                localBorrowState.block = borrowState.block;
                localBorrowState.index = borrowState.index;
            } else {
                uint256 deltaBlocks = localBorrowState.block == 0
                    ? blockNumber - borrowState.block
                    : blockNumber - localBorrowState.block;
                uint256 borrowSpeed = comptroller.compBorrowSpeeds(_cTokenAddress);

                if (borrowSpeed > 0) {
                    uint256 borrowAmount = ICToken(_cTokenAddress).totalBorrows().div(
                        ICToken(_cTokenAddress).borrowIndex()
                    );
                    uint256 compAccrued = deltaBlocks * borrowSpeed;
                    uint256 ratio = borrowAmount > 0 ? (compAccrued * 1e36) / borrowAmount : 0;
                    uint256 formerIndex = localBorrowState.index == 0
                        ? borrowState.index
                        : localBorrowState.index;
                    uint256 index = formerIndex + ratio;
                    localBorrowState.index = CompoundMath.safe224(
                        index,
                        "new index exceeds 224 bits"
                    );
                    localBorrowState.block = CompoundMath.safe32(
                        blockNumber,
                        "block number exceeds 32 bits"
                    );
                } else
                    localBorrowState.block = CompoundMath.safe32(
                        blockNumber,
                        "block number exceeds 32 bits"
                    );
            }
        }
    }

    function getAccruedSupplierComp(
        address _supplier,
        address _cTokenAddress,
        uint256 _balance
    ) public view returns (uint256) {
        uint256 supplyIndex = getUpdatedSupplyIndex(_cTokenAddress);
        uint256 supplierIndex = compSupplierIndex[_cTokenAddress][_supplier];

        if (supplierIndex == 0) return 0;
        return (_balance * (supplyIndex - supplierIndex)) / 1e36;
    }

    function _accrueSupplierComp(
        address _supplier,
        address _cTokenAddress,
        uint256 _balance
    ) internal returns (uint256) {
        uint256 supplyIndex = localCompSupplyState[_cTokenAddress].index;
        uint256 supplierIndex = compSupplierIndex[_cTokenAddress][_supplier];
        compSupplierIndex[_cTokenAddress][_supplier] = supplyIndex;

        if (supplierIndex == 0) return 0;
        return (_balance * (supplyIndex - supplierIndex)) / 1e36;
    }

    function getAccruedBorrowerComp(
        address _borrower,
        address _cTokenAddress,
        uint256 _balance
    ) public view returns (uint256) {
        uint256 borrowIndex = getUpdatedBorrowIndex(_cTokenAddress);
        uint256 borrowerIndex = compBorrowerIndex[_cTokenAddress][_borrower];

        if (borrowerIndex == 0) return 0;
        return (_balance * (borrowIndex - borrowerIndex)) / 1e36;
    }

    function _accrueBorrowerComp(
        address _borrower,
        address _cTokenAddress,
        uint256 _balance
    ) internal returns (uint256) {
        uint256 borrowIndex = localCompBorrowState[_cTokenAddress].index;
        uint256 borrowerIndex = compBorrowerIndex[_cTokenAddress][_borrower];
        compBorrowerIndex[_cTokenAddress][_borrower] = borrowIndex;

        if (borrowerIndex == 0) return 0;
        return (_balance * (borrowIndex - borrowerIndex)) / 1e36;
    }
}
