// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "../interfaces/compound/ICompound.sol";
import "../interfaces/IRewardsManager.sol";
import "../interfaces/IMorpho.sol";

import "../libraries/CompoundMath.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

/// @title RewardsManager.
/// @notice This contract is used to manage the COMP rewards from the Compound protocol.
contract RewardsManager is IRewardsManager, Ownable {
    using CompoundMath for uint256;

    /// STORAGE ///

    uint224 public constant COMP_INITIAL_INDEX = 1e36;

    mapping(address => uint256) public userUnclaimedCompRewards; // The unclaimed rewards of the user.
    mapping(address => mapping(address => uint256)) public compSupplierIndex; // The supply index of the user for a specific cToken. cToken -> user -> index.
    mapping(address => mapping(address => uint256)) public compBorrowerIndex; // The borrow index of the user for a specific cToken. cToken -> user -> index.
    mapping(address => IComptroller.CompMarketState) public localCompSupplyState; // The local supply state for a specific cToken.
    mapping(address => IComptroller.CompMarketState) public localCompBorrowState; // The local borrow state for a specific cToken.

    IMorpho public immutable morpho;
    IComptroller public immutable comptroller;

    /// ERRORS ///

    /// @notice Thrown when only Morpho can call the function.
    error OnlyMorpho();

    /// @notice Thrown when an invalid cToken address is passed to accrue rewards.
    error InvalidCToken();

    /// MODIFIERS ///

    /// @notice Prevents a user to call function allowed for the Morpho only.
    modifier onlyMorpho() {
        if (msg.sender != address(morpho)) revert OnlyMorpho();
        _;
    }

    /// CONSTRUCTOR ///

    /// @notice Constructs the RewardsManager contract.
    /// @param _morpho The `morpho`.
    constructor(address _morpho) {
        morpho = IMorpho(_morpho);
        comptroller = IComptroller(morpho.comptroller());
    }

    /// EXTERNAL ///

    /// @notice Accrues unclaimed COMP rewards for the given cToken addresses and returns the total COMP unclaimed rewards.
    /// @dev This function is called by the `morpho` to accrue COMP rewards and reset them to 0.
    /// @dev The transfer of tokens is done in the `morpho`.
    /// @param _cTokenAddresses The cToken addresses for which to claim rewards.
    /// @param _user The address of the user.
    function claimRewards(address[] calldata _cTokenAddresses, address _user)
        external
        onlyMorpho
        returns (uint256 totalUnclaimedRewards)
    {
        totalUnclaimedRewards = accrueUserUnclaimedRewards(_cTokenAddresses, _user);
        if (totalUnclaimedRewards > 0) userUnclaimedCompRewards[_user] = 0;
    }

    /// @notice Updates the unclaimed COMP rewards of the user.
    /// @param _user The address of the user.
    /// @param _cTokenAddress The cToken address.
    /// @param _userBalance The user balance of tokens in the distribution.
    function accrueUserSupplyUnclaimedRewards(
        address _user,
        address _cTokenAddress,
        uint256 _userBalance
    ) external onlyMorpho {
        _updateSupplyIndex(_cTokenAddress);
        userUnclaimedCompRewards[_user] += _accrueSupplierComp(_user, _cTokenAddress, _userBalance);
    }

    /// @notice Updates the unclaimed COMP rewards of the user.
    /// @param _user The address of the user.
    /// @param _cTokenAddress The cToken address.
    /// @param _userBalance The user balance of tokens in the distribution.
    function accrueUserBorrowUnclaimedRewards(
        address _user,
        address _cTokenAddress,
        uint256 _userBalance
    ) external onlyMorpho {
        _updateBorrowIndex(_cTokenAddress);
        userUnclaimedCompRewards[_user] += _accrueBorrowerComp(_user, _cTokenAddress, _userBalance);
    }

    /// @notice Returns the unclaimed COMP rewards for the given cToken addresses.
    /// @param _cTokenAddresses The cToken addresses for which to compute the rewards.
    /// @param _user The address of the user.
    function getUserUnclaimedRewards(address[] calldata _cTokenAddresses, address _user)
        external
        view
        returns (uint256 unclaimedRewards)
    {
        unclaimedRewards = userUnclaimedCompRewards[_user];

        for (uint256 i; i < _cTokenAddresses.length; i++) {
            address cTokenAddress = _cTokenAddresses[i];

            (bool isListed, , ) = comptroller.markets(cTokenAddress);
            if (!isListed) revert InvalidCToken();

            unclaimedRewards += getAccruedSupplierComp(
                _user,
                cTokenAddress,
                morpho.supplyBalanceInOf(cTokenAddress, _user).onPool
            );
            unclaimedRewards += getAccruedBorrowerComp(
                _user,
                cTokenAddress,
                morpho.borrowBalanceInOf(cTokenAddress, _user).onPool
            );
        }
    }

    /// @notice Returns the local COMP supply state.
    /// @param _cTokenAddress The cToken address.
    /// @return The local COMP supply state.
    function getLocalCompSupplyState(address _cTokenAddress)
        external
        view
        override
        returns (IComptroller.CompMarketState memory)
    {
        return localCompSupplyState[_cTokenAddress];
    }

    /// @notice Returns the local COMP borrow state.
    /// @param _cTokenAddress The cToken address.
    /// @return The local COMP borrow state.
    function getLocalCompBorrowState(address _cTokenAddress)
        external
        view
        override
        returns (IComptroller.CompMarketState memory)
    {
        return localCompBorrowState[_cTokenAddress];
    }

    /// PUBLIC ///

    /// @notice Accrues unclaimed COMP rewards for the cToken addresses and returns the total unclaimed COMP rewards.
    /// @param _cTokenAddresses The cToken addresses for which to accrue rewards.
    /// @param _user The address of the user.
    /// @return unclaimedRewards The user unclaimed rewards.
    function accrueUserUnclaimedRewards(address[] calldata _cTokenAddresses, address _user)
        public
        returns (uint256 unclaimedRewards)
    {
        unclaimedRewards = userUnclaimedCompRewards[_user];

        for (uint256 i; i < _cTokenAddresses.length; i++) {
            address cTokenAddress = _cTokenAddresses[i];

            (bool isListed, , ) = comptroller.markets(cTokenAddress);
            if (!isListed) revert InvalidCToken();

            _updateSupplyIndex(cTokenAddress);
            unclaimedRewards += _accrueSupplierComp(
                _user,
                cTokenAddress,
                morpho.supplyBalanceInOf(cTokenAddress, _user).onPool
            );

            _updateBorrowIndex(cTokenAddress);
            unclaimedRewards += _accrueBorrowerComp(
                _user,
                cTokenAddress,
                morpho.borrowBalanceInOf(cTokenAddress, _user).onPool
            );
        }

        userUnclaimedCompRewards[_user] = unclaimedRewards;
    }

    /// @notice Returns the accrued COMP rewards of a user since the last update.
    /// @param _supplier The address of the supplier.
    /// @param _cTokenAddress The cToken address.
    /// @param _balance The user balance of tokens in the distribution.
    /// @return The accrued COMP rewards.
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

    /// @notice Returns the accrued COMP rewards of a user since the last update.
    /// @param _borrower The address of the borrower.
    /// @param _cTokenAddress The cToken address.
    /// @param _balance The user balance of tokens in the distribution.
    /// @return The accrued COMP rewards.
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

    /// @notice Returns the updated COMP supply index.
    /// @param _cTokenAddress The cToken address.
    /// @return The updated COMP supply index.
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

    /// @notice Returns the updated COMP borrow index.
    /// @param _cTokenAddress The cToken address.
    /// @return The updated COMP borrow index.
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

    /// INTERNAL ///

    /// @notice Updates supplier index and returns the accrued COMP rewards of the supplier since the last update.
    /// @param _supplier The address of the supplier.
    /// @param _cTokenAddress The cToken address.
    /// @param _balance The user balance of tokens in the distribution.
    /// @return The accrued COMP rewards.
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

    /// @notice Updates borrower index and returns the accrued COMP rewards of the borrower since the last update.
    /// @param _borrower The address of the borrower.
    /// @param _cTokenAddress The cToken address.
    /// @param _balance The user balance of tokens in the distribution.
    /// @return The accrued COMP rewards.
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

    /// @notice Updates the COMP supply index.
    /// @param _cTokenAddress The cToken address.
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
                        index: CompoundMath.safe224(index),
                        block: CompoundMath.safe32(blockNumber)
                    });
                } else localSupplyState.block = CompoundMath.safe32(blockNumber);
            }
        }
    }

    /// @notice Updates the COMP borrow index.
    /// @param _cTokenAddress The cToken address.
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
                    localBorrowState.index = CompoundMath.safe224(index);
                    localBorrowState.block = CompoundMath.safe32(blockNumber);
                } else localBorrowState.block = CompoundMath.safe32(blockNumber);
            }
        }
    }
}
